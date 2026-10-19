locals {
  published_strings = {
    alarm_topic_arn     = module.alarm_topic.topic_arn
    kms_key_arn         = module.kms.key_arn
    app_secret_arn      = aws_secretsmanager_secret.app.arn
    flow_log_bucket_arn = module.log_bucket["flow_log"].arn
    alb_log_bucket_name = module.log_bucket["alb_log"].bucket_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "foundation"
  strings    = local.published_strings
}
