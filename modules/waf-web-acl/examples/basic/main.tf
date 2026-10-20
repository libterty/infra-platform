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

module "waf" {
  source = "../.."

  name = "alpha-dev-waf"

  # Observe first; switch to block when the site must be shut for everyone.
  kill_switch = {
    action        = "count"
    response_json = null
  }

  rate_limit = {
    limit           = 2000
    allowlist_cidrs = ["10.10.0.0/16"]
  }

  managed_rule_groups = [
    {
      name            = "AWSManagedRulesCommonRuleSet"
      count_overrides = ["SizeRestrictions_BODY"]
    },
    { name = "AWSManagedRulesKnownBadInputsRuleSet" },
  ]

  # Needs SizeRestrictions_BODY counted above; every other path keeps the 8 KB body limit.
  body_size_exempt_path_prefixes = ["/api/upload"]

  logging = {
    retention_days   = 30
    redacted_headers = ["authorization", "cookie", "X-Origin-Verify"]
  }

  tags = {
    Project = "alpha"
  }
}

# Associate it with the load balancer through the alb module: web_acl_arn = module.waf.web_acl_arn.
output "web_acl_arn" {
  value = module.waf.web_acl_arn
}
