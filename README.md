# Scaled-Infrastructure-Using-Shared-Storage-s3
AWS Infrastructure with Remote State Backend
This project deploys a high-availability web cluster using Terraform, featuring a professional-grade remote backend for state management.

# Architecture
Networking: Custom VPC with Public Subnets across multiple Availability Zones.

Load Balancing: An Application Load Balancer (ALB) serving as the single public entry point.

Auto Scaling: An Auto Scaling Group (ASG) managing a fleet of EC2 instances running Apache.

Security: Tiered Security Groups ensuring instances only accept traffic from the ALB.

# Remote State Management
To support team collaboration and prevent state corruption, this project uses:

Amazon S3: Stores the terraform.tfstate file with versioning and encryption enabled.

DynamoDB: Handles State Locking to prevent concurrent executions from corrupting the infrastructure map.