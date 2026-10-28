locals {
  # The recovery window was the AWS default (30 days) before the container moved into the module; keep it.
  app_secret = {
    name                    = "${local.name_prefix}/app"
    description             = "Application secret of ${local.name_prefix}. The value is written outside Terraform."
    kms_key_arn             = module.kms.key_arn
    recovery_window_in_days = 30
  }
}

# Container only. The value is written by a person or a rotation process, never by Terraform,
# so it stays out of tfvars, SSM and state (design section 8.2).
module "app_secret" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/secrets-manager-secret/aws"
  version = "~> 0.1.0"

  name                    = local.app_secret.name
  description             = local.app_secret.description
  kms_key_arn             = local.app_secret.kms_key_arn
  recovery_window_in_days = local.app_secret.recovery_window_in_days
}

moved {
  from = aws_secretsmanager_secret.app
  to   = module.app_secret.aws_secretsmanager_secret.this
}
