terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "web" {
  source = "../.."

  name                  = "alpha-dev-web"
  subnet_ids            = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-web"
  instance_types        = ["t4g.small", "t4g.medium"]

  min_size         = 2
  desired_capacity = 2
  max_size         = 6

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOT

  target_group_arns = ["arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"]
  cpu_target        = 60

  tags = {
    Project = "alpha"
  }
}

output "asg_name" {
  value = module.web.asg_name
}
