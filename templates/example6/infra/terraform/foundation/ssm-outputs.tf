locals {
  published_strings = {
    kms_key_arn              = module.kms.key_arn
    alarm_topic_arn          = module.alarm_topic.topic_arn
    api_secret_arn           = module.secret["api_key"].arn
    origin_verify_secret_arn = module.secret["origin_verify"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "foundation"
  strings    = local.published_strings
}
