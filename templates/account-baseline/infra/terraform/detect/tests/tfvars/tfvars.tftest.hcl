# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
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

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["audit/config_recorder_name"]
  values = { insecure_value = "default" }
}

run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

run "tfvars_rule_names_follow_the_env" {
  command = plan

  assert {
    condition     = local.finding_rules.guardduty.name == "${var.project}-${var.env}-guardduty-findings" && local.finding_rules.securityhub.name == "${var.project}-${var.env}-securityhub-findings"
    error_message = "The finding rules must be named after the tfvars project and env"
  }
}
