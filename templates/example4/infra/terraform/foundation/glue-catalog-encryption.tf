# Account and region level: a second project in the same account sets glue_catalog_encryption = null (design D13).
locals {
  glue_catalog_encryption = var.glue_catalog_encryption == null ? null : {
    kms_key_arn = coalesce(var.glue_catalog_encryption.kms_key_arn, module.kms.key_arn)
  }
}

module "glue_catalog_encryption" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/glue-catalog-encryption/aws"
  version = "~> 0.1.0"
  count   = local.glue_catalog_encryption == null ? 0 : 1

  kms_key_arn = local.glue_catalog_encryption.kms_key_arn
}
