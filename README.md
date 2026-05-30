# aws-infra-componets

Overview
Reusable Terraform components and orchestration for AWS resources used by Roboshop.

Why this exists
To modularize infrastructure so teams can reuse VPC, SG, and service templates.

Workflows
- Select modules for environment
- Configure variables and backends
- terraform init && terraform apply

Actions (quick start)
1. Install Terraform and configure AWS CLI credentials.
2. Update variables in environment files.
3. terraform init && terraform apply

Key files
- 00-VPC..91-cdn, DOCUMENTATION.md, readme.MD

Notes
- Use remote state (S3 + DynamoDB) for collaboration.
