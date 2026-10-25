locals {
  published_strings = {
    telemetry_bucket_arn             = module.bucket["telemetry"].arn
    greengrass_artifacts_bucket_arn  = module.bucket["greengrass_artifacts"].arn
    greengrass_artifacts_bucket_name = module.bucket["greengrass_artifacts"].bucket_name
    ota_bucket_arn                   = module.bucket["ota"].arn
    ml_bucket_arn                    = module.bucket["ml"].arn
    ml_bucket_name                   = module.bucket["ml"].bucket_name
    stream_arn                       = module.stream.arn
    rule_errors_queue_arn            = module.queue["rule_errors"].queue_arn
    rule_errors_queue_url            = module.queue["rule_errors"].queue_url
    model_approved_queue_arn         = module.queue["model_approved"].queue_arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "storage"
  strings    = local.published_strings
}
