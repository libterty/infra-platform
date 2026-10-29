mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "baseline"
  env                 = "dev"
  expected_account_id = "111111111111"
  alert_emails        = ["security@example.com"]
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
    target = module.log_bucket["trail"]
    outputs = {
      bucket_name = "baseline-dev-trail-111111111111"
    }
  }

  override_module {
    target = module.log_bucket["config"]
    outputs = {
      bucket_name = "baseline-dev-config-111111111111"
    }
  }

  override_module {
    target = module.alert_topic
    outputs = {
      topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts"
    }
  }

  assert {
    condition = local.published_strings == {
      kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      trail_bucket_name  = "baseline-dev-trail-111111111111"
      config_bucket_name = "baseline-dev-config-111111111111"
      alert_topic_arn    = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts"
    }
    error_message = "Each published key must come from the matching module output, and there must be exactly four (design 8.2)"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      kms_key_arn        = "/baseline/dev/foundation/kms_key_arn"
      trail_bucket_name  = "/baseline/dev/foundation/trail_bucket_name"
      config_bucket_name = "/baseline/dev/foundation/config_bucket_name"
      alert_topic_arn    = "/baseline/dev/foundation/alert_topic_arn"
    }
    error_message = "ssm-publish must write exactly the four foundation keys under the foundation stack path"
  }
}

run "kms_service_principals" {
  command = plan

  assert {
    condition = toset(keys(local.kms_service_principals)) == toset([
      "cloudtrail.amazonaws.com",
      "config.amazonaws.com",
      "backup.amazonaws.com",
      "budgets.amazonaws.com",
      "events.amazonaws.com",
      "cloudwatch.amazonaws.com",
      "logs.ap-northeast-1.amazonaws.com",
    ])
    error_message = "The key must serve CloudTrail, Config, Backup, the alert topic publishers and CloudWatch Logs, and nothing else"
  }

  assert {
    condition     = module.kms.alias_name == "alias/baseline-dev-governance"
    error_message = "The key must be aliased <name_prefix>-governance"
  }
}

run "cloudtrail_key_use_is_bound_to_trails_of_this_account" {
  command = plan

  assert {
    condition     = toset(local.kms_service_principals["cloudtrail.amazonaws.com"].actions) == toset(["kms:GenerateDataKey*", "kms:DescribeKey"])
    error_message = "CloudTrail only generates data keys and describes the key; it never decrypts"
  }

  assert {
    condition = toset(local.kms_service_principals["cloudtrail.amazonaws.com"].conditions) == toset([
      {
        test     = "StringLikeIfExists"
        variable = "kms:EncryptionContext:aws:cloudtrail:arn"
        values   = ["arn:aws:cloudtrail:*:111111111111:trail/*"]
      },
      {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:aws:cloudtrail:*:111111111111:trail/*"]
      },
    ])
    error_message = "CloudTrail must be limited by the trail encryption context and aws:SourceArn to trails of this account (design section 4)"
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

run "log_buckets_keep_audit_evidence" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition = (
      local.log_buckets.trail.name == "baseline-dev-trail-111111111111" &&
      local.log_buckets.config.name == "baseline-dev-config-111111111111"
    )
    error_message = "The log buckets must be named <name_prefix>-trail-<account> and <name_prefix>-config-<account>"
  }

  assert {
    condition     = local.log_buckets.trail.log_delivery == ["cloudtrail"] && local.log_buckets.config.log_delivery == ["config"]
    error_message = "The trail bucket must accept CloudTrail only and the config bucket Config only"
  }

  assert {
    condition = (
      local.log_bucket_settings.expiration_days == 365 &&
      local.log_bucket_settings.versioning.noncurrent_expiration_days == 365 &&
      local.log_bucket_settings.force_destroy == false
    )
    error_message = "Audit evidence is kept 365 days with versioning and is never force-destroyed (design 4.1)"
  }

  assert {
    condition     = local.log_bucket_settings.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Both log buckets must be encrypted with the governance key"
  }

  assert {
    condition     = module.log_bucket["trail"].bucket_name == "baseline-dev-trail-111111111111"
    error_message = "s3-bucket must create the trail bucket with that name"
  }
}

run "alert_topic_takes_service_publishers_and_the_key" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.alert_topic.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The alert topic must be encrypted with the governance key"
  }

  assert {
    condition     = toset(local.alert_topic.service_publishers) == toset(["budgets.amazonaws.com", "backup.amazonaws.com", "events.amazonaws.com"])
    error_message = "Budgets, Backup and EventBridge must be the only service publishers of the alert topic"
  }

  assert {
    condition     = local.alert_topic.name == "baseline-dev-alerts" && local.alert_topic.email_subscriptions == tolist(["security@example.com"])
    error_message = "The topic must be named <name_prefix>-alerts and subscribe the configured emails"
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
