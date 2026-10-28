locals {
  secrets = {
    signing_public_key  = { name = "${local.name_prefix}/app-signing-public-key", description = "Public key that verifies the tokens the application issues." }
    signing_private_key = { name = "${local.name_prefix}/app-signing-private-key", description = "Private key that signs the tokens the application issues." }
  }

  # No project key in this template, so the secrets keep the AWS managed Secrets Manager key (K2). A deleted secret
  # can be restored for a week; 0 would delete it at once and free the name for reuse.
  secret_kms_key_arn             = null
  secret_recovery_window_in_days = 7
}

# Containers only. The values are written by a person or a rotation process, never by Terraform, so they stay out of
# tfvars, SSM and state.
module "secrets" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/secrets-manager-secret/aws"
  version  = "~> 0.1.0"
  for_each = local.secrets

  name                    = each.value.name
  description             = "${each.value.description} The value is written outside Terraform."
  kms_key_arn             = local.secret_kms_key_arn
  recovery_window_in_days = local.secret_recovery_window_in_days
}

moved {
  from = aws_secretsmanager_secret.this["signing_public_key"]
  to   = module.secrets["signing_public_key"].aws_secretsmanager_secret.this
}

moved {
  from = aws_secretsmanager_secret.this["signing_private_key"]
  to   = module.secrets["signing_private_key"].aws_secretsmanager_secret.this
}
