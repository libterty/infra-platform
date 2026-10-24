locals {
  published_strings = {
    role_firehose_arn       = module.role["firehose"].arn
    role_firehose_name      = module.role["firehose"].name
    role_glue_crawler_arn   = module.role["glue_crawler"].arn
    role_glue_job_arn       = module.role["glue_job"].arn
    role_glue_events_arn    = module.role["glue_events"].arn
    role_redshift_arn       = module.role["redshift"].arn
    role_quicksight_vpc_arn = module.role["quicksight_vpc"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-base"
  strings    = local.published_strings
}
