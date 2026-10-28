locals {
  # The recovery window was the AWS default (30 days) before the container moved into the module; keep it.
  opensearch_master_secret = {
    name                    = "${local.name_prefix}/opensearch-master"
    description             = "OpenSearch master user of ${local.name_prefix} as JSON with username and password. The value is written outside Terraform."
    kms_key_arn             = module.kms.key_arn
    recovery_window_in_days = 30
  }
}

# Container only. The value is written by a person or a rotation process, never by Terraform, so it stays out of
# tfvars, SSM and the foundation state; the search stack reads it (design section 4.1). Do not add a secret version here.
module "opensearch_master_secret" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/secrets-manager-secret/aws"
  version = "~> 0.1.0"

  name                    = local.opensearch_master_secret.name
  description             = local.opensearch_master_secret.description
  kms_key_arn             = local.opensearch_master_secret.kms_key_arn
  recovery_window_in_days = local.opensearch_master_secret.recovery_window_in_days
}

moved {
  from = aws_secretsmanager_secret.opensearch_master
  to   = module.opensearch_master_secret.aws_secretsmanager_secret.this
}
