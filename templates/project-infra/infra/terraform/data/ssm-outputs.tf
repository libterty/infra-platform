locals {
  # No conditional between two object types: each branch is already a JSON string.
  # deployment and name come from the rds outputs, so the JSON describes what the module built.
  database = var.db == null ? jsonencode({ enabled = false }) : jsonencode({
    enabled             = true
    deployment          = module.db[0].deployment
    port                = module.db[0].port
    name                = module.db[0].database_name
    secret_arn          = module.db[0].master_user_secret_arn
    app_endpoint        = module.db[0].app_endpoint
    app_reader_endpoint = module.db[0].app_reader_endpoint
    writer_endpoint     = module.db[0].writer_endpoint
    reader_endpoint     = module.db[0].reader_endpoint
    proxy_endpoint      = module.db[0].proxy_endpoint
    has_reader          = module.db[0].has_reader
    # The knowledge base in the agent stack and its role in iam-app need the cluster; a single instance has none.
    cluster_arn = module.db[0].deployment == "rds" ? null : module.db[0].arn
    data_api    = local.data_api
  })

  published_strings = {
    database = local.database
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "data"
  strings    = local.published_strings
}
