locals {
  published_strings = {
    firehose_s3_arn         = module.firehose_s3.arn
    firehose_opensearch_arn = module.firehose_opensearch.arn
  }
  published_lists = {
    rule_names = module.rules.rule_names
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "ingest"
  strings    = local.published_strings
  lists      = local.published_lists
}
