mock_provider "aws" {}

variables {
  project                     = "example"
  env                         = "dev"
  expected_account_id         = "111111111111"
  point_in_time_recovery_days = 7
  deletion_protection         = false
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

run "reads_only_the_shared_key" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { kms_key_arn = "foundation/kms_key_arn" } && local.ssm_input_lists == {}
    error_message = "data may read only foundation/kms_key_arn (design 8.2)"
  }
}

run "table_is_on_demand_with_pk_sk_and_the_shared_key" {
  command = plan

  assert {
    condition = (
      local.table.name == "example-dev-app" &&
      local.table.hash_key == "PK" && local.table.range_key == "SK" &&
      local.table.attributes == { PK = "S", SK = "S" } &&
      local.table.billing_mode == "PAY_PER_REQUEST"
    )
    error_message = "The table must be <name_prefix>-app, on-demand, with string keys PK and SK"
  }

  assert {
    condition     = local.table.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The table must be encrypted with the shared key published by foundation"
  }

  assert {
    condition     = module.table.table_name == "example-dev-app"
    error_message = "dynamodb-table must create the table with that name"
  }
}

run "dev_keeps_7_days_of_pitr_without_deletion_protection" {
  command = plan

  assert {
    condition     = local.table.point_in_time_recovery_days == 7 && local.table.deletion_protection == false
    error_message = "PITR days and deletion protection must come from the tfvars"
  }
}

run "sit_keeps_35_days_of_pitr_with_deletion_protection" {
  command = plan

  variables {
    env                         = "sit"
    expected_account_id         = "222222222222"
    point_in_time_recovery_days = 35
    deletion_protection         = true
  }

  assert {
    condition     = local.table.name == "example-sit-app" && local.table.point_in_time_recovery_days == 35 && local.table.deletion_protection
    error_message = "sit must name the table after the env and pass PITR and deletion protection through"
  }
}

run "publishes_exactly_the_table_keys" {
  command = plan

  override_module {
    target = module.table
    outputs = {
      table_name = "example-dev-app"
      arn        = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-app"
    }
  }

  assert {
    condition = local.published_strings == {
      table_name = "example-dev-app"
      table_arn  = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-app"
    }
    error_message = "data must publish exactly table_name and table_arn (design 8.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { table_name = "/example/dev/data/table_name", table_arn = "/example/dev/data/table_arn" }
    error_message = "ssm-publish must write the keys under the data path"
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
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
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
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
