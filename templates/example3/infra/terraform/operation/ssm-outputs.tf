locals {
  published_strings = {
    import_bucket_name           = module.import_bucket.bucket_name
    import_extract_function_name = module.lambda["import-extract"].function_name
    import_load_function_name    = module.lambda["import-load"].function_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "operation"
  strings    = local.published_strings
}
