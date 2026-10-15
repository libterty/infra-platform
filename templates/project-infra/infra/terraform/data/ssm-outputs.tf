locals {
  # No conditional between two object types: each branch is already a JSON string.
  database = var.db == null ? jsonencode({ enabled = false }) : jsonencode({
    enabled             = true
    deployment          = var.db.deployment
    port                = module.db[0].port
    name                = var.db.database_name
    secret_arn          = module.db[0].master_user_secret_arn
    app_endpoint        = module.db[0].app_endpoint
    app_reader_endpoint = module.db[0].app_reader_endpoint
    writer_endpoint     = module.db[0].writer_endpoint
    reader_endpoint     = module.db[0].reader_endpoint
    proxy_endpoint      = module.db[0].proxy_endpoint
    has_reader          = module.db[0].has_reader
  })

  published_strings = {
    database = local.database
  }
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "data"
  strings    = local.published_strings
}
