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

module "app" {
  source = "../.."

  name                  = "alpha-dev-app"
  subnet_id             = "subnet-0123456789abcdef0"
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-app"
  instance_type         = "t4g.small"

  ebs_volumes = {
    data = { device_name = "/dev/sdf", size = 100 }
  }

  # Optional: with a topic, a StatusCheckFailed_System alarm recovers the instance and notifies it.
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  tags = {
    Project = "alpha"
  }
}

output "instance_id" {
  value = module.app.instance_id
}
