mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::111122223333:root" }
  }
}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"
  alarm_emails        = ["ops@example.com"]
}

run "publishes_foundation_keys" {
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
      topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
    }
  }

  override_module {
    target = module.log_bucket["flow_log"]
    outputs = {
      arn = "arn:aws:s3:::alpha-dev-flow-logs-111111111111"
    }
  }

  override_module {
    target = module.log_bucket["alb_log"]
    outputs = {
      bucket_name = "alpha-dev-alb-logs-111111111111"
      arn         = "arn:aws:s3:::alpha-dev-alb-logs-111111111111"
    }
  }

  override_resource {
    target          = module.app_secret.aws_secretsmanager_secret.this
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
    }
  }

  assert {
    condition = local.published_strings == {
      alarm_topic_arn     = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      kms_key_arn         = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      app_secret_arn      = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
      flow_log_bucket_arn = "arn:aws:s3:::alpha-dev-flow-logs-111111111111"
      alb_log_bucket_arn  = "arn:aws:s3:::alpha-dev-alb-logs-111111111111"
    }
    error_message = "Each published key must come from the matching module output or secret"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      alarm_topic_arn     = "/alpha/dev/foundation/alarm_topic_arn"
      kms_key_arn         = "/alpha/dev/foundation/kms_key_arn"
      app_secret_arn      = "/alpha/dev/foundation/app_secret_arn"
      flow_log_bucket_arn = "/alpha/dev/foundation/flow_log_bucket_arn"
      alb_log_bucket_arn  = "/alpha/dev/foundation/alb_log_bucket_arn"
    }
    error_message = "ssm-publish must write exactly the five foundation keys under the foundation stack path"
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
    condition     = local.alarm_topic.kms_master_key_id == module.kms.key_arn && module.kms.key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The alarm topic must be encrypted with the key of this stack"
  }

  assert {
    condition     = local.alarm_topic.email_subscriptions == tolist(["ops@example.com"])
    error_message = "The topic must subscribe the configured emails"
  }
}

run "log_buckets_sse_s3" {
  command = plan

  assert {
    condition     = alltrue([for b in values(local.log_buckets) : b.kms_key_arn == null])
    error_message = "Both log buckets must use SSE-S3; ALB log delivery drops logs silently with a customer managed key"
  }

  assert {
    condition     = alltrue([for b in values(local.log_buckets) : b.expiration_days == 90])
    error_message = "Both log buckets must expire objects after 90 days"
  }
}

run "log_buckets_delivery" {
  command = plan

  assert {
    condition     = local.log_buckets["flow_log"].log_delivery == ["vpc_flow_logs"]
    error_message = "The flow log bucket must allow vpc_flow_logs delivery only"
  }

  assert {
    condition     = local.log_buckets["alb_log"].log_delivery == ["vended_logs"]
    error_message = "The ALB bucket must allow vended log delivery only"
  }

  assert {
    condition     = local.log_buckets["flow_log"].name == "alpha-dev-flow-logs-111111111111" && local.log_buckets["alb_log"].name == "alpha-dev-alb-logs-111111111111"
    error_message = "Bucket names must be <name_prefix>-<purpose>-<account id>"
  }
}

run "log_buckets_always_created" {
  command = plan

  assert {
    condition     = length(module.log_bucket) == 2
    error_message = "Both buckets must exist even when no environment uses flow logs or access logs"
  }
}

run "secret_container_only" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = module.app_secret.name == "alpha-dev/app"
    error_message = "The secret container must be named <name_prefix>/app"
  }

  assert {
    condition     = local.app_secret.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The secret must be encrypted with the customer managed key of this stack"
  }

  assert {
    condition     = local.app_secret.recovery_window_in_days == 30
    error_message = "The recovery window must stay at 30 days, the AWS default the secret had before it moved into the module"
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
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
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
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
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
