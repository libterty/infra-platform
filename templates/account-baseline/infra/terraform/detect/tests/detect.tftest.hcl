mock_provider "aws" {
  # The securityhub and inspector modules build the standards ARNs and the account list from these.
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "baseline"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["audit/config_recorder_name"]
  values = { insecure_value = "default" }
}

run "reads_the_alert_topic_and_waits_for_config" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      alert_topic_arn      = "foundation/alert_topic_arn"
      config_recorder_name = "audit/config_recorder_name"
    } && local.ssm_input_lists == {}
    error_message = "detect reads the alert topic and the recorder name of audit, so it plans only after Config is on (design 8.2)"
  }
}

run "guardduty_keeps_the_k7_defaults" {
  command = plan

  assert {
    condition     = length(regexall("(?s)module \"guardduty\" \\{[^}]*(features|organization)\\s*=", file("${path.module}/detectors.tf"))) == 0
    error_message = "GuardDuty must keep the module default features (design K7) and no organization settings"
  }
}

run "securityhub_subscribes_exactly_fsbp_and_cis" {
  command = plan

  assert {
    condition     = local.securityhub_standards == ["fsbp", "cis"]
    error_message = "Security Hub must subscribe exactly FSBP and CIS (design 8.3)"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*standards\\s*=\\s*local\\.securityhub_standards\\s*$", file("${path.module}/detectors.tf"))) == 1
    error_message = "securityhub must take its standards from securityhub_standards"
  }
}

run "inspector_scans_ec2_ecr_and_lambda_packages" {
  command = plan

  assert {
    condition     = local.inspector_resource_types == ["EC2", "ECR", "LAMBDA"]
    error_message = "Inspector must scan EC2, ECR and Lambda packages; Lambda code scanning stays off (design K8)"
  }

  assert {
    condition     = toset(module.inspector.enabled_resource_types) == toset(["EC2", "ECR", "LAMBDA"])
    error_message = "inspector must enable the listed scan types"
  }
}

run "only_high_and_critical_findings_reach_the_alert_topic" {
  command = plan

  assert {
    condition     = toset(keys(local.finding_rules)) == toset(["guardduty", "securityhub"])
    error_message = "There must be one rule for GuardDuty and one for Security Hub findings (design K13)"
  }

  assert {
    condition = local.finding_rules.guardduty.event_pattern == {
      source        = ["aws.guardduty"]
      "detail-type" = ["GuardDuty Finding"]
      detail        = { severity = [{ numeric = [">=", 7] }] }
    }
    error_message = "The GuardDuty rule must match severity 7 and above only (HIGH and CRITICAL)"
  }

  assert {
    condition     = local.finding_rules.securityhub.event_pattern.source == ["aws.securityhub"] && local.finding_rules.securityhub.event_pattern["detail-type"] == ["Security Hub Findings - Imported"] && local.finding_rules.securityhub.event_pattern.detail.findings.Severity == { Label = ["HIGH", "CRITICAL"] }
    error_message = "The Security Hub rule must match imported findings labelled HIGH or CRITICAL only"
  }

  assert {
    condition     = local.finding_targets == { alerts = { arn = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" } }
    error_message = "Both rules must target the alert topic of foundation and nothing else"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*targets\\s*=\\s*local\\.finding_targets\\s*$", file("${path.module}/findings.tf"))) == 1
    error_message = "eventbridge-rule must take its targets from finding_targets"
  }

  assert {
    condition = { for k, m in module.finding_rule : k => m.rule_name } == {
      guardduty   = "baseline-dev-guardduty-findings"
      securityhub = "baseline-dev-securityhub-findings"
    }
    error_message = "eventbridge-rule must create both rules"
  }
}

run "publishes_the_detector_id" {
  command = plan

  override_module {
    target  = module.guardduty
    outputs = { detector_id = "12abc34d567e8fa901bc2d34e56789f0" }
  }

  assert {
    condition     = local.published_strings == { guardduty_detector_id = "12abc34d567e8fa901bc2d34e56789f0" }
    error_message = "detect publishes the GuardDuty detector ID only (design 8.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { guardduty_detector_id = "/baseline/dev/detect/guardduty_detector_id" }
    error_message = "ssm-publish must write the key under the detect stack path"
  }
}

# The stack cannot see inside the modules, so these runs plan the same registry modules with the values the stack
# passes and pin what they decide: the GuardDuty default features and the two Security Hub subscriptions.
run "guardduty_module_defaults_follow_k7" {
  command = plan

  module {
    source  = "app.terraform.io/libterty/guardduty/aws"
    version = "~> 0.1.0"
  }

  assert {
    condition = { for k, f in aws_guardduty_detector_feature.this : k => f.status } == {
      S3_DATA_EVENTS         = "ENABLED"
      EKS_AUDIT_LOGS         = "ENABLED"
      EBS_MALWARE_PROTECTION = "ENABLED"
      RDS_LOGIN_EVENTS       = "ENABLED"
      LAMBDA_NETWORK_LOGS    = "ENABLED"
      RUNTIME_MONITORING     = "DISABLED"
    }
    error_message = "GuardDuty must turn on S3, EKS audit logs, EBS malware, RDS login and Lambda network logs, with runtime monitoring off (design K7)"
  }
}

run "securityhub_module_subscribes_two_standards" {
  command = plan

  module {
    source  = "app.terraform.io/libterty/securityhub/aws"
    version = "~> 0.1.0"
  }

  variables {
    standards = ["fsbp", "cis"]
    region    = "ap-northeast-1"
  }

  assert {
    condition = toset([for s in aws_securityhub_standards_subscription.this : s.standards_arn]) == toset([
      "arn:aws:securityhub:ap-northeast-1::standards/aws-foundational-security-best-practices/v/1.0.0",
      "arn:aws:securityhub:ap-northeast-1::standards/cis-aws-foundations-benchmark/v/5.0.0",
    ])
    error_message = "Security Hub must subscribe exactly FSBP v1.0.0 and CIS v5.0.0"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "baseline-dev" && local.ssm_prefix == "/baseline/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "baseline-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
