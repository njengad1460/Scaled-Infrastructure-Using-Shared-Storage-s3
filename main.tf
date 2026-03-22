# DATA SOURCES
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"] 
}

# NETWORKING
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr # referencing variable here
  enable_dns_hostnames = true
  tags = {
    Name   = var.vpc_name # referencing variable here
    Region = data.aws_region.current.name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnet_config # refencing  variable here
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 8, each.value)
  availability_zone       = tolist(data.aws_availability_zones.available.names)[each.value]
  map_public_ip_on_launch = true

  tags = { Name = each.key }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}



# EC2 COMPUTE & SECURITY groups
resource "aws_security_group" "web_traffic" {
  name   = "allow-http-from-web_traffic"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [ aws_security_group.alb_sg.id ] # web traffic for the ec2 is onlt allowed if it comes from the ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#ALB Security Group (public)

resource "aws_security_group" "alb_sg" {
  name = "alb_sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ] # This security group allow trafic from the internet ingress
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}


# Load Balancers and Target groups 

resource "aws_alb" "web_alb" {
  name = "web-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [ aws_security_group.alb_sg.id ]
  subnets = [ for s in aws_subnet.public_subnets : s.id ]
}

resource "aws_lb_target_group" "web_tg" {
  name = "web-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.web_alb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


# Lauch template & autoscaling group

resource "aws_launch_template" "web_lt" {
  name_prefix = "web-server-"
  image_id = data.aws_ami.ubuntu_22_04.id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [ aws_security_group.web_traffic.id ]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2
              systemctl start apache2
              systemctl enable apache2
              echo "<h1>Hello from ASG Instance: $(hostname -f )  </h1>" /var/www/html/index/html
              EOF
  )
}

resource "aws_autoscaling_group" "web_asg" {
  vpc_zone_identifier = [ for s in aws_subnet.public_subnets : s.id]
  target_group_arns = [ aws_lb_target_group.web_tg.arn ]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  # This skips the "graceful" wait time during destruction
  force_delete = true

  launch_template {
    id = aws_launch_template.web_lt.id
    version = "$Latest"
  }
}

output "alb_dns_name" {
  value = aws_alb.web_alb.dns_name
  description = "The domain name of the load balancer"
}