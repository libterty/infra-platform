locals {
  # Must match iam/naming.tf: the api-deploy role's UpdateService permission is built from this name.
  cluster_name = local.name_prefix
}

module "cluster" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-cluster/aws"
  version = "~> 0.1.1"

  name               = local.cluster_name
  log_retention_days = var.log_retention_days
  log_kms_key_arn    = module.in.strings["kms_key_arn"]
}
