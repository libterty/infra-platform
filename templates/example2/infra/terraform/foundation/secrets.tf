locals {
  secrets = {
    signing_public_key  = { name = "${local.name_prefix}/app-signing-public-key", description = "Public key that verifies the tokens the application issues." }
    signing_private_key = { name = "${local.name_prefix}/app-signing-private-key", description = "Private key that signs the tokens the application issues." }
  }
}

# Containers only. The values are written by a person or a rotation process, never by Terraform, so they stay out of
# tfvars, SSM and state.
resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  name        = each.value.name
  description = "${each.value.description} The value is written outside Terraform."

  # A deleted secret can be restored for a week; 0 would delete it at once and free the name for reuse.
  recovery_window_in_days = 7

  tags = { Name = each.value.name }
}
