# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream value below stands in for what the foundation stack publishes.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
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

run "tfvars_budget_follows_the_env" {
  command = plan

  assert {
    condition     = var.monthly_budget_usd == (var.env == "dev" ? 100 : 300)
    error_message = "The placeholder budget is 100 USD a month in dev and 300 in sit (design 8.3)"
  }

  assert {
    condition     = keys(local.budgets) == ["${var.project}-${var.env}-monthly"] && length(var.budget_emails) >= 1
    error_message = "The budget name must be built from the tfvars project and env, and the tfvars must give a budget email"
  }
}
