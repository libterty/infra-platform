mock_provider "aws" {}

override_resource {
  target          = aws_budgets_budget.this["alpha-dev-monthly"]
  override_during = plan
  values = {
    arn = "arn:aws:budgets::111111111111:budget/alpha-dev-monthly"
  }
}

variables {
  budgets = {
    alpha-dev-monthly = {
      limit_amount = 100
      notifications = [
        {
          threshold      = 80
          type           = "ACTUAL"
          sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
          emails         = ["ops@example.com"]
        },
        {
          threshold      = 100
          type           = "ACTUAL"
          sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
          emails         = ["ops@example.com"]
        },
        {
          threshold      = 100
          type           = "FORECASTED"
          sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
          emails         = ["ops@example.com"]
        },
      ]
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "monthly_cost_budget_with_three_notifications" {
  command = plan

  assert {
    condition     = aws_budgets_budget.this["alpha-dev-monthly"].name == "alpha-dev-monthly"
    error_message = "The budget must be named after its key"
  }

  assert {
    condition     = aws_budgets_budget.this["alpha-dev-monthly"].budget_type == "COST" && aws_budgets_budget.this["alpha-dev-monthly"].limit_unit == "USD"
    error_message = "Budgets must be COST budgets in USD"
  }

  assert {
    condition     = tonumber(aws_budgets_budget.this["alpha-dev-monthly"].limit_amount) == 100 && aws_budgets_budget.this["alpha-dev-monthly"].time_unit == "MONTHLY"
    error_message = "The limit must be 100 USD per month"
  }

  assert {
    condition     = length(aws_budgets_budget.this["alpha-dev-monthly"].cost_filter) == 0
    error_message = "No cost filter without cost_filters"
  }

  assert {
    condition = aws_budgets_budget.this["alpha-dev-monthly"].notification == toset([
      for t in [["ACTUAL", 80], ["ACTUAL", 100], ["FORECASTED", 100]] : {
        comparison_operator        = "GREATER_THAN"
        notification_type          = t[0]
        threshold                  = t[1]
        threshold_type             = "PERCENTAGE"
        subscriber_sns_topic_arns  = toset(["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"])
        subscriber_email_addresses = toset(["ops@example.com"])
      }
    ])
    error_message = "The three notifications must be actual 80%, actual 100% and forecasted 100%, sent to SNS and email"
  }

  assert {
    condition     = aws_budgets_budget.this["alpha-dev-monthly"].tags["Name"] == "alpha-dev-monthly"
    error_message = "The budget must carry a Name tag"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.budget_arns == { alpha-dev-monthly = "arn:aws:budgets::111111111111:budget/alpha-dev-monthly" }
    error_message = "budget_arns must map budget names to ARNs"
  }
}

run "cost_filters_and_email_only" {
  command = plan

  variables {
    budgets = {
      alpha-sit-ec2 = {
        limit_amount = 50.5
        time_unit    = "QUARTERLY"
        cost_filters = {
          Service = ["Amazon Elastic Compute Cloud - Compute"]
        }
        notifications = [{
          threshold      = 50
          threshold_type = "ABSOLUTE_VALUE"
          comparison     = "GREATER_THAN"
          type           = "ACTUAL"
          emails         = ["ops@example.com"]
        }]
      }
    }
  }

  assert {
    condition     = aws_budgets_budget.this["alpha-sit-ec2"].cost_filter == toset([{ name = "Service", values = tolist(["Amazon Elastic Compute Cloud - Compute"]) }])
    error_message = "cost_filters must become cost_filter blocks"
  }

  assert {
    condition     = tonumber(aws_budgets_budget.this["alpha-sit-ec2"].limit_amount) == 50.5 && aws_budgets_budget.this["alpha-sit-ec2"].time_unit == "QUARTERLY"
    error_message = "The limit and time unit must be passed through"
  }

  assert {
    condition     = one(aws_budgets_budget.this["alpha-sit-ec2"].notification).threshold_type == "ABSOLUTE_VALUE" && length(one(aws_budgets_budget.this["alpha-sit-ec2"].notification).subscriber_sns_topic_arns) == 0
    error_message = "An email-only absolute notification must be passed through"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "notification_without_subscribers_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        notifications = [{ threshold = 80, type = "ACTUAL" }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "zero_limit_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 0
        notifications = [{ threshold = 80, type = "ACTUAL", emails = ["ops@example.com"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "percentage_threshold_over_1000_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        notifications = [{ threshold = 1001, type = "ACTUAL", emails = ["ops@example.com"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "unknown_notification_type_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        notifications = [{ threshold = 80, type = "PREDICTED", emails = ["ops@example.com"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "two_sns_topics_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount = 100
        notifications = [{
          threshold = 80
          type      = "ACTUAL"
          sns_topic_arns = [
            "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms",
            "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-security",
          ]
        }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "sns_arn_format_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        notifications = [{ threshold = 80, type = "ACTUAL", sns_topic_arns = ["alpha-dev-alarms"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "email_format_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        notifications = [{ threshold = 80, type = "ACTUAL", emails = ["ops"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "unknown_time_unit_rejected" {
  command = plan

  variables {
    budgets = {
      alpha-dev-monthly = {
        limit_amount  = 100
        time_unit     = "WEEKLY"
        notifications = [{ threshold = 80, type = "ACTUAL", emails = ["ops@example.com"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}

run "budget_name_with_colon_rejected" {
  command = plan

  variables {
    budgets = {
      "alpha:dev" = {
        limit_amount  = 100
        notifications = [{ threshold = 80, type = "ACTUAL", emails = ["ops@example.com"] }]
      }
    }
  }

  expect_failures = [var.budgets]
}
