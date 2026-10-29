mock_provider "aws" {}

variables {
  project             = "baseline"
  env                 = "dev"
  expected_account_id = "111111111111"
  monthly_budget_usd  = 100
  budget_emails       = ["finops@example.com"]
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

run "reads_only_the_alert_topic" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { alert_topic_arn = "foundation/alert_topic_arn" } && local.ssm_input_lists == {}
    error_message = "budget may read only the alert topic (design 8.2)"
  }
}

run "one_monthly_cost_budget" {
  command = plan

  assert {
    condition     = keys(local.budgets) == ["baseline-dev-monthly"]
    error_message = "There must be exactly one budget, named <name_prefix>-monthly (design K12)"
  }

  assert {
    condition     = local.budgets["baseline-dev-monthly"].limit_amount == 100 && local.budgets["baseline-dev-monthly"].time_unit == "MONTHLY"
    error_message = "The dev budget is 100 USD a month (design 8.3)"
  }

  assert {
    condition     = keys(module.budgets.budget_arns) == ["baseline-dev-monthly"]
    error_message = "budgets must create the budget under that name"
  }
}

run "three_notifications_to_the_alert_topic_and_email" {
  command = plan

  assert {
    condition = toset([for n in local.budgets["baseline-dev-monthly"].notifications : "${n.type}:${n.threshold}"]) == toset([
      "ACTUAL:80", "ACTUAL:100", "FORECASTED:100",
    ]) && length(local.budgets["baseline-dev-monthly"].notifications) == 3
    error_message = "Notifications must be actual 80%, actual 100% and forecasted 100%, and nothing else (design K12)"
  }

  assert {
    condition = alltrue([for n in local.budgets["baseline-dev-monthly"].notifications :
      tolist(n.sns_topic_arns) == tolist(["arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts"]) &&
      tolist(n.emails) == tolist(["finops@example.com"]) &&
      n.threshold_type == "PERCENTAGE" && n.comparison == "GREATER_THAN"
    ])
    error_message = "Every notification must go to the alert topic and the budget emails, as a percentage over the limit"
  }
}

run "no_email_still_notifies_the_topic" {
  command = plan

  variables {
    budget_emails = []
  }

  assert {
    condition     = alltrue([for n in local.budgets["baseline-dev-monthly"].notifications : length(n.emails) == 0 && length(n.sns_topic_arns) == 1])
    error_message = "Without budget emails the notifications still go to the alert topic"
  }
}

run "zero_budget_rejected" {
  command = plan

  variables {
    monthly_budget_usd = 0
  }

  expect_failures = [var.monthly_budget_usd]
}

run "bad_email_rejected" {
  command = plan

  variables {
    budget_emails = ["finops"]
  }

  expect_failures = [var.budget_emails]
}

run "too_many_emails_rejected" {
  command = plan

  variables {
    budget_emails = [for i in range(11) : "user${i}@example.com"]
  }

  expect_failures = [var.budget_emails]
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
