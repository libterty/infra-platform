# SSM refuses an empty value and a missing key breaks readers, so a CA that is off publishes {"enabled":false}.
# certificate_pem is null for a SUBORDINATE CA until its certificate is installed.
locals {
  published_strings = {
    ca = var.ca == null ? jsonencode({ enabled = false }) : jsonencode({
      enabled         = true
      arn             = module.ca[0].ca_arn
      certificate_pem = module.ca[0].ca_certificate_pem
    })
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "pki"
  strings    = local.published_strings
}
