# Container only. The value is written by a person or a rotation process, never by Terraform,
# so it stays out of tfvars, SSM and state (design section 8.2).
resource "aws_secretsmanager_secret" "app" {
  name        = "${local.name_prefix}/app"
  description = "Application secret of ${local.name_prefix}. The value is written outside Terraform."
  kms_key_id  = module.kms.key_arn
}
