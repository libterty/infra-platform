mock_provider "aws" {}

variables {
  delegated_admin_account_id = "333333333333"
  services                   = ["guardduty", "securityhub", "inspector", "config", "access-analyzer"]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "five_services" {
  command = plan

  assert {
    condition = toset(keys(aws_organizations_aws_service_access.this)) == toset([
      "guardduty.amazonaws.com",
      "malware-protection.guardduty.amazonaws.com",
      "securityhub.amazonaws.com",
      "inspector2.amazonaws.com",
      "config.amazonaws.com",
      "config-multiaccountsetup.amazonaws.com",
      "access-analyzer.amazonaws.com",
    ])
    error_message = "Every selected service must get trusted access for each of its service principals"
  }

  assert {
    condition     = alltrue([for p, r in aws_organizations_aws_service_access.this : r.service_principal == p])
    error_message = "The trusted access resource key must be its service principal"
  }

  assert {
    condition = toset(keys(aws_organizations_delegated_administrator.this)) == toset([
      "config.amazonaws.com",
      "config-multiaccountsetup.amazonaws.com",
      "access-analyzer.amazonaws.com",
    ])
    error_message = "Only Config and Access Analyzer are registered through Organizations; GuardDuty, Security Hub and Inspector register themselves"
  }

  assert {
    condition     = alltrue([for p, r in aws_organizations_delegated_administrator.this : r.account_id == "333333333333" && r.service_principal == p])
    error_message = "Organizations delegated administrators must be the security account"
  }

  assert {
    condition     = length(aws_guardduty_organization_admin_account.this) == 1 && aws_guardduty_organization_admin_account.this["provider"].admin_account_id == "333333333333"
    error_message = "GuardDuty must be delegated with its own API in the provider region"
  }

  assert {
    condition     = length(aws_securityhub_organization_admin_account.this) == 1 && aws_securityhub_organization_admin_account.this["provider"].admin_account_id == "333333333333"
    error_message = "Security Hub must be delegated with its own API in the provider region"
  }

  assert {
    condition     = length(aws_inspector2_delegated_admin_account.this) == 1 && aws_inspector2_delegated_admin_account.this["provider"].account_id == "333333333333"
    error_message = "Inspector must be delegated with its own API in the provider region"
  }

  assert {
    condition     = length(aws_cloudtrail_organization_delegated_admin_account.this) == 0
    error_message = "CloudTrail must not be delegated when not selected"
  }
}

run "cloudtrail_uses_its_own_api" {
  command = plan

  variables {
    services = ["cloudtrail"]
  }

  assert {
    condition     = keys(aws_organizations_aws_service_access.this) == ["cloudtrail.amazonaws.com"]
    error_message = "CloudTrail needs trusted access for cloudtrail.amazonaws.com"
  }

  assert {
    condition     = length(aws_cloudtrail_organization_delegated_admin_account.this) == 1 && aws_cloudtrail_organization_delegated_admin_account.this[0].account_id == "333333333333"
    error_message = "CloudTrail must be delegated with the CloudTrail API"
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.this) == 0
    error_message = "CloudTrail must not also be registered through Organizations"
  }

  assert {
    condition     = length(aws_guardduty_organization_admin_account.this) == 0 && length(aws_securityhub_organization_admin_account.this) == 0 && length(aws_inspector2_delegated_admin_account.this) == 0
    error_message = "Unselected regional services must not be delegated"
  }
}

run "regional_services_in_several_regions" {
  command = plan

  variables {
    regions = ["ap-northeast-1", "us-east-1"]
  }

  assert {
    condition     = toset(keys(aws_guardduty_organization_admin_account.this)) == toset(["ap-northeast-1", "us-east-1"]) && aws_guardduty_organization_admin_account.this["us-east-1"].region == "us-east-1"
    error_message = "GuardDuty must be delegated once per region"
  }

  assert {
    condition     = toset(keys(aws_securityhub_organization_admin_account.this)) == toset(["ap-northeast-1", "us-east-1"]) && aws_securityhub_organization_admin_account.this["us-east-1"].region == "us-east-1"
    error_message = "Security Hub must be delegated once per region"
  }

  assert {
    condition     = toset(keys(aws_inspector2_delegated_admin_account.this)) == toset(["ap-northeast-1", "us-east-1"]) && aws_inspector2_delegated_admin_account.this["ap-northeast-1"].region == "ap-northeast-1"
    error_message = "Inspector must be delegated once per region"
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) == 7 && length(aws_organizations_delegated_administrator.this) == 3
    error_message = "Organization-wide settings must be created once regardless of the number of regions"
  }
}

run "global_services_only" {
  command = plan

  variables {
    services = ["config", "access-analyzer"]
    regions  = ["ap-northeast-1", "us-east-1"]
  }

  assert {
    condition     = length(aws_guardduty_organization_admin_account.this) == 0 && length(aws_securityhub_organization_admin_account.this) == 0 && length(aws_inspector2_delegated_admin_account.this) == 0
    error_message = "regions must not create anything for Organizations-registered services"
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.this) == 3
    error_message = "Config needs two registrations and Access Analyzer one"
  }
}

run "outputs_after_apply" {
  command = apply

  variables {
    services = ["guardduty", "securityhub", "inspector", "config", "access-analyzer", "cloudtrail"]
  }

  assert {
    condition     = length(output.trusted_service_principals) == 8 && contains(output.trusted_service_principals, "cloudtrail.amazonaws.com")
    error_message = "trusted_service_principals must list every principal given trusted access"
  }

  assert {
    condition     = output.delegated_admin_account_id == "333333333333"
    error_message = "delegated_admin_account_id must echo the input"
  }
}
