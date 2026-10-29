# Detection services of this region. GuardDuty keeps the module defaults (design K7: runtime monitoring off), Security
# Hub subscribes FSBP and CIS, Inspector scans EC2, ECR and Lambda packages (design K8: Lambda code scanning off).
locals {
  securityhub_standards    = ["fsbp", "cis"]
  inspector_resource_types = ["EC2", "ECR", "LAMBDA"]
}

module "guardduty" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/guardduty/aws"
  version = "~> 0.1.0"
}

module "securityhub" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/securityhub/aws"
  version = "~> 0.1.0"

  standards = local.securityhub_standards
}

module "inspector" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/inspector/aws"
  version = "~> 0.1.0"

  resource_types = local.inspector_resource_types
}
