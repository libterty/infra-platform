# The API Lambda execution role. The role carries the trust policy only; iam-role-policy attaches the permissions.
locals {
  api_role = {
    name  = "${local.name_prefix}-api-lambda"
    trust = { service_principals = ["lambda.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
  }
}

module "api_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.4.1"

  name  = local.api_role.name
  trust = local.api_role.trust
}
