locals {
  # For whoever starts the pipelines (people or a later automation): the names to pass to start-pipeline-execution.
  published_strings = {
    api_pipeline_name = module.pipeline["api"].name
    fn_pipeline_name  = module.pipeline["fn"].name
    web_pipeline_name = module.pipeline["web"].name
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
