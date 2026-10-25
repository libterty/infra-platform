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

module "iot_rules" {
  source = "../.."

  rules = {
    alpha_dev_telemetry = {
      sql = "SELECT *, topic(3) AS deviceId FROM 'alpha/dev/+/telemetry'"
      actions = {
        kinesis = [{
          stream_name   = "alpha-dev-telemetry"
          role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
          partition_key = "$${topic(3)}"
        }]
      }
    }
  }

  error_action = {
    sqs = {
      queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-iot-errors"
      role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
    }
  }

  tags = { Project = "alpha" }
}

output "rule_arns" {
  value = module.iot_rules.rule_arns
}
