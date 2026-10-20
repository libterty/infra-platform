locals {
  published_strings = {
    alb_arn_suffix = module.alb.alb_arn_suffix
    # SSM rejects a map, so this is JSON in a String: target group key => targetgroup/<name>/<id>.
    target_group_arn_suffixes = jsonencode(module.alb.target_group_arn_suffixes)
    waf_web_acl_name          = module.waf.web_acl_name
    # application registers the api service with the full ARN; a suffix is not enough.
    api_target_group_arn = module.alb.target_group_arns["api"]
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "loadbalancer"
  strings    = local.published_strings
}
