# Container only. The value is written by a person or a rotation process, never by Terraform, so it stays out of
# tfvars, SSM and the foundation state; the search stack reads it (design section 4.1). Do not add a secret version here.
resource "aws_secretsmanager_secret" "opensearch_master" {
  name        = "${local.name_prefix}/opensearch-master"
  description = "OpenSearch master user of ${local.name_prefix} as JSON with username and password. The value is written outside Terraform."
  kms_key_id  = module.kms.key_arn
}
