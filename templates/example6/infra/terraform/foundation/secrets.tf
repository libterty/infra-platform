# Containers only. The values are written by a person or a rotation process, never by Terraform, so they stay out of
# tfvars, SSM and the foundation state. Do not add a secret version here.
#   api_key:       key of the third-party API the API Lambda calls.
#   origin_verify: the value CloudFront sends in the origin verify header; the API Lambda rejects requests without it
#                  (design K17). It must match TF_VAR_origin_verify_header_value of the web stack.
# "origin-verify" ends in "-" plus 6 characters, like the suffix AWS adds to secret ARNs, so it is always referenced by
# its full ARN (published to SSM), never by name or partial ARN.
locals {
  secrets = {
    api_key = {
      name        = "${local.name_prefix}/api-key"
      description = "Third-party API key of ${local.name_prefix}. The value is written outside Terraform."
    }
    origin_verify = {
      name        = "${local.name_prefix}/origin-verify"
      description = "Origin verify header value of ${local.name_prefix}, shared by CloudFront and the API Lambda. The value is written outside Terraform."
    }
  }
  secret_settings = {
    kms_key_arn             = module.kms.key_arn
    recovery_window_in_days = 7
  }
}

module "secret" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/secrets-manager-secret/aws"
  version  = "~> 0.1.0"
  for_each = local.secrets

  name                    = each.value.name
  description             = each.value.description
  kms_key_arn             = local.secret_settings.kms_key_arn
  recovery_window_in_days = local.secret_settings.recovery_window_in_days
}
