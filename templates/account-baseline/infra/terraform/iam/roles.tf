# Service roles the governance modules take as ARNs (design K4). Each trusts one service of this account only; the
# managed policies are the ones the AWS service documentation names, and iam-role-policy adds what they lack.
locals {
  service_roles = {
    config = {
      name                = "${local.name_prefix}-config-recorder"
      service             = "config.amazonaws.com"
      managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"]
    }
    backup = {
      name    = "${local.name_prefix}-backup"
      service = "backup.amazonaws.com"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
        "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
      ]
    }
    trail_logs = {
      name                = "${local.name_prefix}-trail-logs"
      service             = "cloudtrail.amazonaws.com"
      managed_policy_arns = []
    }
  }
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.5.0"
  for_each = local.service_roles

  name                = each.value.name
  trust               = { service_principals = [each.value.service], source_account = var.expected_account_id, source_arn = null }
  managed_policy_arns = each.value.managed_policy_arns
}
