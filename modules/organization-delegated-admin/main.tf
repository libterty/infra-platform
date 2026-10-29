locals {
  service_principals = {
    guardduty         = ["guardduty.amazonaws.com", "malware-protection.guardduty.amazonaws.com"]
    securityhub       = ["securityhub.amazonaws.com"]
    inspector         = ["inspector2.amazonaws.com"]
    config            = ["config.amazonaws.com", "config-multiaccountsetup.amazonaws.com"]
    "access-analyzer" = ["access-analyzer.amazonaws.com"]
    cloudtrail        = ["cloudtrail.amazonaws.com"]
  }

  # GuardDuty, Security Hub and Inspector register the delegated administrator in Organizations
  # themselves; registering them here as well would conflict. CloudTrail has its own API too.
  organizations_registered = ["config", "access-analyzer"]

  trusted_principals = toset(flatten([for s in var.services : local.service_principals[s]]))

  registered_principals = toset(flatten([
    for s in var.services : local.service_principals[s] if contains(local.organizations_registered, s)
  ]))

  # Key "provider" means the provider's region (resource-level region left null).
  regions = length(var.regions) == 0 ? { provider = null } : { for r in var.regions : r => r }
}

resource "aws_organizations_aws_service_access" "this" {
  for_each = local.trusted_principals

  service_principal = each.value
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each = local.registered_principals

  account_id        = var.delegated_admin_account_id
  service_principal = each.value

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_guardduty_organization_admin_account" "this" {
  for_each = contains(var.services, "guardduty") ? local.regions : {}

  region           = each.value
  admin_account_id = var.delegated_admin_account_id

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_securityhub_organization_admin_account" "this" {
  for_each = contains(var.services, "securityhub") ? local.regions : {}

  region           = each.value
  admin_account_id = var.delegated_admin_account_id

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_inspector2_delegated_admin_account" "this" {
  for_each = contains(var.services, "inspector") ? local.regions : {}

  region     = each.value
  account_id = var.delegated_admin_account_id

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_cloudtrail_organization_delegated_admin_account" "this" {
  count = contains(var.services, "cloudtrail") ? 1 : 0

  account_id = var.delegated_admin_account_id

  depends_on = [aws_organizations_aws_service_access.this]
}
