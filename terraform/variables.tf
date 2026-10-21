variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for tagging"
  type        = string
  default     = "terraform-ansible-task"
}

variable "my_ip" {
  description = "Your public IP address for SSH access (e.g., 203.0.113.5/32)"
  type        = string
}

variable "key_name" {
  description = "Name of the existing AWS SSH key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (ARM64)"
  type        = string
  default     = "t4g.micro"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS ARM64 AMI ID"
  type        = string
  default     = "ami-0e1ab5c876cc030e8"
}