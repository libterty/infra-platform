mock_provider "aws" {}

override_resource {
  target          = aws_backup_plan.this
  override_during = plan
  values = {
    id  = "11111111-2222-3333-4444-555555555555"
    arn = "arn:aws:backup:ap-northeast-1:111111111111:backup-plan:11111111-2222-3333-4444-555555555555"
  }
}

override_resource {
  target          = aws_backup_selection.this
  override_during = plan
  values = {
    id = "66666666-7777-8888-9999-000000000000"
  }
}

variables {
  name       = "alpha-dev-daily"
  vault_name = "alpha-dev-backup"
  role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-backup"

  rules = {
    daily = {
      schedule                = "cron(0 18 * * ? *)"
      delete_after_days       = 120
      cold_storage_after_days = 30
    }
  }

  selection_tags = {
    backup = "daily"
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "daily_with_cold_storage" {
  command = plan

  assert {
    condition     = aws_backup_plan.this.name == "alpha-dev-daily" && length(aws_backup_plan.this.rule) == 1
    error_message = "The plan must keep the given name and have one rule"
  }

  assert {
    condition = one([for r in aws_backup_plan.this.rule : r.rule_name == "daily" &&
      r.target_vault_name == "alpha-dev-backup" &&
      r.schedule == "cron(0 18 * * ? *)" &&
      r.enable_continuous_backup == false
    ])
    error_message = "The rule must target the vault with the given schedule and no continuous backup"
  }

  assert {
    condition = one([for r in aws_backup_plan.this.rule :
      r.lifecycle[0].delete_after == 120 && r.lifecycle[0].cold_storage_after == 30
    ])
    error_message = "The lifecycle must move to cold storage after 30 days and delete after 120 days"
  }

  assert {
    condition     = one([for r in aws_backup_plan.this.rule : length(r.copy_action)]) == 0
    error_message = "No copy action without copy_to"
  }

  assert {
    condition     = aws_backup_plan.this.tags["Name"] == "alpha-dev-daily"
    error_message = "The plan must carry a Name tag"
  }
}

run "selection_by_tag" {
  command = plan

  assert {
    condition     = aws_backup_selection.this.name == "alpha-dev-daily" && aws_backup_selection.this.plan_id == "11111111-2222-3333-4444-555555555555"
    error_message = "The selection must belong to the plan"
  }

  assert {
    condition     = aws_backup_selection.this.iam_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-backup"
    error_message = "The selection must use the given role"
  }

  assert {
    condition     = aws_backup_selection.this.selection_tag == toset([{ type = "STRINGEQUALS", key = "backup", value = "daily" }])
    error_message = "The selection must pick resources tagged backup = daily"
  }

  assert {
    condition     = aws_backup_selection.this.resources == null || length(coalesce(aws_backup_selection.this.resources, [])) == 0
    error_message = "The selection must not list resources by ARN"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.plan_id == "11111111-2222-3333-4444-555555555555" &&
      output.plan_arn == "arn:aws:backup:ap-northeast-1:111111111111:backup-plan:11111111-2222-3333-4444-555555555555" &&
      output.selection_id == "66666666-7777-8888-9999-000000000000"
    )
    error_message = "Outputs must expose the plan and the selection"
  }
}

run "continuous_backup" {
  command = plan

  variables {
    rules = {
      pitr = {
        schedule                 = "cron(0 * * * ? *)"
        delete_after_days        = 35
        enable_continuous_backup = true
      }
    }
  }

  assert {
    condition = one([for r in aws_backup_plan.this.rule :
      r.enable_continuous_backup == true && r.lifecycle[0].delete_after == 35 && r.lifecycle[0].cold_storage_after == null
    ])
    error_message = "Continuous backup must be enabled with 35 days of retention"
  }
}

run "copy_to_another_vault" {
  command = plan

  variables {
    rules = {
      daily = {
        schedule                  = "cron(0 18 * * ? *)"
        start_window_minutes      = 60
        completion_window_minutes = 180
        delete_after_days         = 35
        copy_to = {
          vault_arn         = "arn:aws:backup:us-west-2:111111111111:backup-vault:alpha-dev-backup-copy"
          delete_after_days = 90
        }
      }
    }
  }

  assert {
    condition     = one([for r in aws_backup_plan.this.rule : r.start_window == 60 && r.completion_window == 180])
    error_message = "The start and completion windows must be passed through"
  }

  assert {
    condition = one([for r in aws_backup_plan.this.rule : [for c in r.copy_action : {
      destination_vault_arn = c.destination_vault_arn
      delete_after          = c.lifecycle[0].delete_after
    }]]) == [{ destination_vault_arn = "arn:aws:backup:us-west-2:111111111111:backup-vault:alpha-dev-backup-copy", delete_after = 90 }]
    error_message = "The copy action must target the other vault and keep copies for 90 days"
  }
}

run "region_on_every_resource" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = aws_backup_plan.this.region == "us-east-1" && aws_backup_selection.this.region == "us-east-1"
    error_message = "region must be set on every resource"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "no_selection_tag_rejected" {
  command = plan

  variables {
    selection_tags = {}
  }

  expect_failures = [var.selection_tags]
}

run "cold_storage_under_90_days_rejected" {
  command = plan

  variables {
    rules = {
      daily = {
        schedule                = "cron(0 18 * * ? *)"
        delete_after_days       = 119
        cold_storage_after_days = 30
      }
    }
  }

  expect_failures = [var.rules]
}

run "continuous_over_35_days_rejected" {
  command = plan

  variables {
    rules = {
      pitr = {
        schedule                 = "cron(0 * * * ? *)"
        delete_after_days        = 36
        enable_continuous_backup = true
      }
    }
  }

  expect_failures = [var.rules]
}

run "continuous_without_retention_rejected" {
  command = plan

  variables {
    rules = {
      pitr = {
        schedule                 = "cron(0 * * * ? *)"
        enable_continuous_backup = true
      }
    }
  }

  expect_failures = [var.rules]
}

run "continuous_with_cold_storage_rejected" {
  command = plan

  variables {
    rules = {
      pitr = {
        schedule                 = "cron(0 * * * ? *)"
        delete_after_days        = 35
        cold_storage_after_days  = 1
        enable_continuous_backup = true
      }
    }
  }

  expect_failures = [var.rules]
}

run "rate_schedule_rejected" {
  command = plan

  variables {
    rules = {
      daily = {
        schedule = "rate(1 day)"
      }
    }
  }

  expect_failures = [var.rules]
}

run "no_rules_rejected" {
  command = plan

  variables {
    rules = {}
  }

  expect_failures = [var.rules]
}

run "copy_vault_arn_format_rejected" {
  command = plan

  variables {
    rules = {
      daily = {
        schedule = "cron(0 18 * * ? *)"
        copy_to = {
          vault_arn = "alpha-dev-backup-copy"
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "role_arn_format_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:policy/alpha-dev-backup"
  }

  expect_failures = [var.role_arn]
}

run "vault_name_format_rejected" {
  command = plan

  variables {
    vault_name = "arn:aws:backup:ap-northeast-1:111111111111:backup-vault:alpha-dev-backup"
  }

  expect_failures = [var.vault_name]
}

run "name_format_rejected" {
  command = plan

  variables {
    name = "alpha dev daily"
  }

  expect_failures = [var.name]
}

run "region_format_rejected" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
