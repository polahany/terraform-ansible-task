# Terraform infrastructure

This directory provisions the AWS network, public subnet, security groups,
application and database EC2 instances, and their dedicated EBS volumes. The
root [README](../README.md) is the canonical A-to-Z deployment guide.

Important variables are supplied through the ignored `terraform.tfvars` file:
`aws_region`, `project_name`, `my_ip`, `key_name`, `instance_type`, and
`ami_id`. Outputs consumed by Ansible are `app_public_ip`, `db_public_ip`, and
`db_private_ip`.
