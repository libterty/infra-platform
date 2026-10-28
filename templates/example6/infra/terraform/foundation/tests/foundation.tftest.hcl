mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  alarm_emails        = ["ops@example.com"]
}

run "publishes_exactly_the_four_foundation_keys" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  override_module {
    target = module.alarm_topic
    outputs = {
      topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
    }
  }

  override_module {
    target = module.secret["api_key"]
    outputs = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf"
    }
  }

  override_module {
    target = module.secret["origin_verify"]
    outputs = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl"
    }
  }

  assert {
    condition = local.published_strings == {
      kms_key_arn              = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      alarm_topic_arn          = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      api_secret_arn           = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf"
      origin_verify_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl"
    }
    error_message = "Each published key must come from the matching module output, and there must be exactly four (design 8.2)"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      kms_key_arn              = "/example/dev/foundation/kms_key_arn"
      alarm_topic_arn          = "/example/dev/foundation/alarm_topic_arn"
      api_secret_arn           = "/example/dev/foundation/api_secret_arn"
      origin_verify_secret_arn = "/example/dev/foundation/origin_verify_secret_arn"
    }
    error_message = "ssm-publish must write exactly the four foundation keys under the foundation stack path"
  }
}

run "kms_service_principals" {
  command = plan

  assert {
    condition = toset(keys(local.kms_service_principals)) == toset([
      "logs.ap-northeast-1.amazonaws.com",
      "cloudwatch.amazonaws.com",
      "sns.amazonaws.com",
    ])
    error_message = "The key must serve CloudWatch Logs, CloudWatch and SNS, and nothing else"
  }

  assert {
    condition = (
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].test == "ArnLike" &&
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].variable == "kms:EncryptionContext:aws:logs:arn" &&
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].values == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"]
    )
    error_message = "CloudWatch Logs must be limited to log groups of this account and region with the EncryptionContext condition"
  }
}

run "topic_uses_project_key" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.alarm_topic.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The alarm topic must be encrypted with the key of this stack"
  }

  assert {
    condition     = local.alarm_topic.name == "example-dev-alarms" && local.alarm_topic.email_subscriptions == tolist(["ops@example.com"])
    error_message = "The topic must be named <name_prefix>-alarms and subscribe the configured emails"
  }
}

run "secrets_are_two_cmk_containers" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = toset(keys(module.secret)) == toset(["api_key", "origin_verify"])
    error_message = "foundation must create exactly the third-party API key and the origin verify containers"
  }

  assert {
    condition     = module.secret["api_key"].name == "example-dev/api-key" && module.secret["origin_verify"].name == "example-dev/origin-verify"
    error_message = "The containers must be named <name_prefix>/api-key and <name_prefix>/origin-verify"
  }

  assert {
    condition     = local.secret_settings.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Both secrets must be encrypted with the customer managed key of this stack"
  }

  assert {
    condition     = local.secret_settings.recovery_window_in_days == 7
    error_message = "Both secrets must keep a 7-day recovery window"
  }
}

# Terraform cannot list resource types in a test, so scan the stack files.
run "secret_has_no_value" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "aws_secretsmanager_secret_version")])
    error_message = "The stack must not write a secret value; it would end up in state"
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
