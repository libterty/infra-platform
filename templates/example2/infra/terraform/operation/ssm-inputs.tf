locals {
  shared_input_strings = {
    app_sg_id               = "infra/app_sg_id"
    bastion_sg_id           = "infra/bastion_sg_id"
    import_extract_role_arn = "infra/import_extract_role_arn"
    import_load_role_arn    = "infra/import_load_role_arn"
    db_proxy_endpoint       = "infra/db_proxy_endpoint"
    db_secret_arn           = "infra/db_secret_arn"
    ecr_repository_urls     = "infra/ecr_repository_urls"
  }

  shared_input_lists = {
    app_subnet_ids = "infra/app_subnet_ids"
  }
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
  lists      = local.shared_input_lists
}
