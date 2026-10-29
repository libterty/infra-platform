mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = { region = "ap-northeast-1" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_resource {
  target          = aws_securityhub_account.this
  override_during = plan
  values = {
    id = "111111111111"
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "fsbp_and_cis" {
  command = plan

  assert {
    condition     = aws_securityhub_account.this.enable_default_standards == false
    error_message = "Default standards must never be enabled; standards come only from var.standards"
  }

  assert {
    condition     = aws_securityhub_account.this.control_finding_generator == "SECURITY_CONTROL" && aws_securityhub_account.this.auto_enable_controls == true
    error_message = "Consolidated control findings and auto-enabled controls must be the defaults"
  }

  assert {
    condition = { for k, s in aws_securityhub_standards_subscription.this : k => s.standards_arn } == {
      fsbp = "arn:aws:securityhub:ap-northeast-1::standards/aws-foundational-security-best-practices/v/1.0.0"
      cis  = "arn:aws:securityhub:ap-northeast-1::standards/cis-aws-foundations-benchmark/v/5.0.0"
    }
    error_message = "fsbp and cis must map to the FSBP v1.0.0 and CIS v5.0.0 standards ARNs in the provider region"
  }

  assert {
    condition     = length(aws_securityhub_finding_aggregator.this) == 0 && length(aws_securityhub_organization_configuration.this) == 0
    error_message = "No aggregator or organization configuration unless given"
  }

  assert {
    condition     = output.account_id == "111111111111"
    error_message = "account_id output must be the Security Hub account id"
  }
}

run "standards_follow_region" {
  command = plan

  variables {
    region                    = "us-east-1"
    standards                 = ["cis"]
    control_finding_generator = "STANDARD_CONTROL"
    auto_enable_controls      = false
  }

  assert {
    condition     = keys(aws_securityhub_standards_subscription.this) == ["cis"]
    error_message = "Only the given standards must be subscribed"
  }

  assert {
    condition     = aws_securityhub_standards_subscription.this["cis"].standards_arn == "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/5.0.0"
    error_message = "The standards ARN must use var.region"
  }

  assert {
    condition     = aws_securityhub_account.this.region == "us-east-1" && aws_securityhub_standards_subscription.this["cis"].region == "us-east-1"
    error_message = "region must be set on the account and the subscriptions"
  }

  assert {
    condition     = aws_securityhub_account.this.control_finding_generator == "STANDARD_CONTROL" && aws_securityhub_account.this.auto_enable_controls == false
    error_message = "control_finding_generator and auto_enable_controls must be passed through"
  }
}

run "subscription_arns_output" {
  command = plan

  assert {
    condition     = keys(output.standards_subscription_arns) == ["cis", "fsbp"]
    error_message = "standards_subscription_arns must be keyed by short name"
  }
}

run "finding_aggregator" {
  command = plan

  variables {
    finding_aggregator = {
      linking_mode = "SPECIFIED_REGIONS"
      regions      = ["us-east-1", "us-west-2"]
    }
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].linking_mode == "SPECIFIED_REGIONS"
    error_message = "linking_mode must be passed through"
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].specified_regions == toset(["us-east-1", "us-west-2"])
    error_message = "regions must be passed through"
  }
}

run "finding_aggregator_all_regions" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "ALL_REGIONS" }
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].linking_mode == "ALL_REGIONS" && aws_securityhub_finding_aggregator.this[0].specified_regions == null
    error_message = "ALL_REGIONS must not pass regions"
  }
}

run "organization" {
  command = plan

  variables {
    organization = {
      auto_enable           = true
      auto_enable_standards = "NONE"
    }
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this[0].auto_enable == true && aws_securityhub_organization_configuration.this[0].auto_enable_standards == "NONE"
    error_message = "organization settings must be passed through"
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this[0].organization_configuration[0].configuration_type == "LOCAL"
    error_message = "The organization must use local configuration"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "unknown_standard_rejected" {
  command = plan

  variables {
    standards = ["fsbp", "pci"]
  }

  expect_failures = [var.standards]
}

run "invalid_control_finding_generator_rejected" {
  command = plan

  variables {
    control_finding_generator = "CONSOLIDATED"
  }

  expect_failures = [var.control_finding_generator]
}

run "invalid_linking_mode_rejected" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "SOME_REGIONS", regions = ["us-east-1"] }
  }

  expect_failures = [var.finding_aggregator]
}

run "specified_regions_without_regions_rejected" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "SPECIFIED_REGIONS" }
  }

  expect_failures = [var.finding_aggregator]
}

run "all_regions_with_regions_rejected" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "ALL_REGIONS", regions = ["us-east-1"] }
  }

  expect_failures = [var.finding_aggregator]
}

run "invalid_aggregator_region_rejected" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "SPECIFIED_REGIONS", regions = ["tokyo"] }
  }

  expect_failures = [var.finding_aggregator]
}

run "invalid_auto_enable_standards_rejected" {
  command = plan

  variables {
    organization = { auto_enable = true, auto_enable_standards = "ALL" }
  }

  expect_failures = [var.organization]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
