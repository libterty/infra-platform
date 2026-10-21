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

# The Lambda function itself (lambda-function) and its role (iam-role) are built by the caller;
# see the README for the full assembly. Placeholder values below.
module "breaker" {
  source = "../.."

  name                     = "dev-web"
  load_balancer_type       = "application"
  load_balancer_arn_suffix = "app/dev-web/0123456789abcdef"
  lambda_function_arn      = "arn:aws:lambda:ap-northeast-1:111111111111:function:dev-web-breaker"
  sns_topic_arns           = ["arn:aws:sns:ap-northeast-1:111111111111:dev-alarms"]

  breakers = {
    # Listener default action: new system gets part of the traffic, old system keeps the rest.
    api = {
      listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
      stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
      canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
    }

    # A listener rule, with a stricter threshold and an application metric.
    admin = {
      rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
      stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old-admin/3333333333333333"
      canary_target_group_arn_suffix = "targetgroup/dev-new-admin/4444444444444444"
      error_rate_percent             = 2
      min_requests                   = 20
      custom_metric = {
        namespace   = "Alpha/Admin"
        metric_name = "FailedLogins"
        statistic   = "Sum"
        threshold   = 50
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "alarm_names" {
  value = module.breaker.alarm_names
}

output "lambda_config_json" {
  value = module.breaker.lambda_config_json
}
