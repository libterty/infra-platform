locals {
  published_strings = {
    firehose_s3_arn         = module.firehose_s3.arn
    firehose_opensearch_arn = module.firehose_opensearch.arn
    glue_workflow_name      = module.etl.workflow_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "pipeline"
  strings    = local.published_strings
}
