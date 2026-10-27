locals {
  # No CRL and no OCSP (design K18): device certificates are revoked in the IoT registry. The fleet stack registers the
  # CA to IoT Core in SNI_ONLY mode.
  ca = var.ca == null ? null : {
    type           = var.ca.type
    usage_mode     = var.ca.usage_mode
    key_algorithm  = var.ca.key_algorithm
    subject        = merge(var.ca.subject, { common_name = "${local.name_prefix}-device-ca" })
    validity_years = var.ca.validity_years

    permanent_deletion_time_in_days = var.ca.permanent_deletion_time_in_days
    subordinate_certificate         = var.ca.subordinate_certificate
  }
}

module "ca" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/acm-pca/aws"
  version = "~> 0.1.0"
  count   = var.ca == null ? 0 : 1

  type                            = local.ca.type
  usage_mode                      = local.ca.usage_mode
  key_algorithm                   = local.ca.key_algorithm
  subject                         = local.ca.subject
  validity_years                  = local.ca.validity_years
  permanent_deletion_time_in_days = local.ca.permanent_deletion_time_in_days
  subordinate_certificate         = local.ca.subordinate_certificate
}
