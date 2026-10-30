locals {
  published_strings = {
    kms_key_arn          = module.kms.key_arn
    artifact_bucket_name = module.artifact_bucket.bucket_name
    alert_topic_arn      = module.alert_topic.topic_arn
    connection_arn       = module.connection.arn
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
