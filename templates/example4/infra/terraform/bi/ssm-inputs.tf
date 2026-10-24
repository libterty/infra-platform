locals {
  # Only keys of stacks that come earlier in ORDER. bi publishes nothing; warehouse's redshift_mode is deliberately not read.
  ssm_input_strings = {
    curated_database_name      = "storage/curated_database_name"
    athena_workgroup_name      = "analytics/athena_workgroup_name"
    role_quicksight_athena_arn = "iam-app/role_quicksight_athena_arn"
    role_quicksight_vpc_arn    = "iam-base/role_quicksight_vpc_arn"
    sg_quicksight_id           = "network/sg_quicksight_id"
    redshift_host              = "warehouse/redshift_host"
    redshift_port              = "warehouse/redshift_port"
    redshift_database          = "warehouse/redshift_database"
  }
  ssm_input_lists = {
    subnet_ids_data = "network/subnet_ids_data"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
