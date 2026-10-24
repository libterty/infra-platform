mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project                 = "example"
  env                     = "dev"
  expected_account_id     = "111111111111"
  alarm_emails            = ["ops@example.com"]
  glue_catalog_encryption = {}
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
    target = module.flow_log_bucket
    outputs = {
      arn = "arn:aws:s3:::example-dev-flow-logs-111111111111"
    }
  }

  override_resource {
    target          = aws_secretsmanager_secret.opensearch_master
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/opensearch-master-AbCdEf"
    }
  }

  assert {
    condition = local.published_strings == {
      kms_key_arn                  = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      alarm_topic_arn              = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      flow_log_bucket_arn          = "arn:aws:s3:::example-dev-flow-logs-111111111111"
      opensearch_master_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/opensearch-master-AbCdEf"
    }
    error_message = "Each published key must come from the matching module output or secret, and there must be exactly four"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      kms_key_arn                  = "/example/dev/foundation/kms_key_arn"
      alarm_topic_arn              = "/example/dev/foundation/alarm_topic_arn"
      flow_log_bucket_arn          = "/example/dev/foundation/flow_log_bucket_arn"
      opensearch_master_secret_arn = "/example/dev/foundation/opensearch_master_secret_arn"
    }
    error_message = "ssm-publish must write exactly the four foundation keys under the foundation stack path"
  }
}

run "kms_service_principals" {
  command = plan

  assert {
    condition = toset(keys(local.kms_service_principals)) == toset([
      "logs.ap-northeast-1.amazonaws.com",
      "delivery.logs.amazonaws.com",
      "cloudwatch.amazonaws.com",
      "sns.amazonaws.com",
    ])
    error_message = "The key must serve CloudWatch Logs, log delivery (flow logs), CloudWatch and SNS, and nothing else"
  }

  assert {
    condition = (
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].test == "ArnLike" &&
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].variable == "kms:EncryptionContext:aws:logs:arn" &&
      local.kms_service_principals["logs.ap-northeast-1.amazonaws.com"].conditions[0].values == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"]
    )
    error_message = "CloudWatch Logs must be limited to log groups of this account and region with the EncryptionContext condition"
  }

  assert {
    condition = (
      local.kms_service_principals["delivery.logs.amazonaws.com"].conditions[0].test == "StringEquals" &&
      local.kms_service_principals["delivery.logs.amazonaws.com"].conditions[0].variable == "aws:SourceAccount" &&
      local.kms_service_principals["delivery.logs.amazonaws.com"].conditions[0].values == ["111111111111"]
    )
    error_message = "Log delivery must be limited to this account with aws:SourceAccount"
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
    condition     = local.alarm_topic.kms_master_key_id == module.kms.key_arn && module.kms.key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The alarm topic must be encrypted with the key of this stack"
  }

  assert {
    condition     = local.alarm_topic.email_subscriptions == tolist(["ops@example.com"])
    error_message = "The topic must subscribe the configured emails"
  }
}

run "flow_log_bucket_is_sse_kms" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.flow_log_bucket.kms_key_arn == module.kms.key_arn && local.flow_log_bucket.kms_key_arn != null
    error_message = "The flow log bucket must be encrypted with the customer managed key of this stack (SSE-KMS)"
  }

  assert {
    condition     = local.flow_log_bucket.log_delivery == toset(["vpc_flow_logs"])
    error_message = "The flow log bucket must allow vpc_flow_logs delivery only"
  }

  assert {
    condition     = local.flow_log_bucket.name == "example-dev-flow-logs-111111111111" && local.flow_log_bucket.expiration_days == 90
    error_message = "The bucket must be named <name_prefix>-flow-logs-<account id> and expire objects after 90 days"
  }
}

run "opensearch_master_secret_uses_cmk" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.opensearch_master.name == "example-dev/opensearch-master"
    error_message = "The secret container must be named <name_prefix>/opensearch-master"
  }

  assert {
    condition     = aws_secretsmanager_secret.opensearch_master.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The secret must be encrypted with the customer managed key of this stack"
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

# ---- glue_catalog_encryption (design D13): null calls no module ----

run "glue_catalog_encryption_null_creates_no_module" {
  command = plan

  variables {
    glue_catalog_encryption = null
  }

  assert {
    condition     = length(module.glue_catalog_encryption) == 0
    error_message = "glue_catalog_encryption = null must not call the module (a second project in the same account sets null)"
  }

  assert {
    condition     = local.glue_catalog_encryption == null
    error_message = "The resolved setting must be null when the variable is null"
  }
}

run "glue_catalog_encryption_default_is_null" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"glue_catalog_encryption\" \\{.*?default\\s*=\\s*null", file("${path.module}/variables.tf"))) == 1
    error_message = "glue_catalog_encryption must default to null: the account-level setting is opt-in per stack"
  }
}

run "glue_catalog_encryption_empty_object_uses_stack_key" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = length(module.glue_catalog_encryption) == 1
    error_message = "An object value must call the module"
  }

  assert {
    condition     = local.glue_catalog_encryption.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Without kms_key_arn the catalog must be encrypted with the key of this stack"
  }
}

run "glue_catalog_encryption_given_key_is_used" {
  command = plan

  variables {
    glue_catalog_encryption = {
      kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = length(module.glue_catalog_encryption) == 1
    error_message = "An object value must call the module"
  }

  assert {
    condition     = local.glue_catalog_encryption.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "A given kms_key_arn must be used instead of the key of this stack"
  }
}

run "glue_catalog_encryption_alias_rejected" {
  command = plan

  variables {
    glue_catalog_encryption = {
      kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/shared"
    }
  }

  expect_failures = [var.glue_catalog_encryption]
}

run "glue_catalog_encryption_non_kms_arn_rejected" {
  command = plan

  variables {
    glue_catalog_encryption = {
      kms_key_arn = "arn:aws:s3:::example-dev-flow-logs-111111111111"
    }
  }

  expect_failures = [var.glue_catalog_encryption]
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
