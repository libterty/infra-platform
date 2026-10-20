# Test fixture: the Web ACL ARN is not known until apply, as when the module is
# called in the same configuration that creates the Web ACL.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

resource "aws_wafv2_web_acl" "this" {
  name  = "alpha-dev"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "alpha-dev"
    sampled_requests_enabled   = true
  }
}

module "alb" {
  source = "../../.."

  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  web_acl = { arn = aws_wafv2_web_acl.this.arn }
}

output "association_count" {
  value = length(module.alb.web_acl_association_ids)
}
