mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
  alarm_emails        = ["ops@example.com"]
}

run "reads_nothing" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "foundation needs nothing from containerimage and must not read SSM"
  }
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
    target = module.artifact_bucket
    outputs = {
      bucket_name = "cicd-dev-artifacts-111111111111"
    }
  }

  override_module {
    target = module.alert_topic
    outputs = {
      topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts"
    }
  }

  override_module {
    target = module.connection
    outputs = {
      arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition = local.published_strings == {
      kms_key_arn          = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      artifact_bucket_name = "cicd-dev-artifacts-111111111111"
      alert_topic_arn      = "arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts"
      connection_arn       = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    }
    error_message = "Each published key must come from the matching module output, and there must be exactly four (design 8.3; the web bucket belongs to the web stack)"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      kms_key_arn          = "/cicd/dev/foundation/kms_key_arn"
      artifact_bucket_name = "/cicd/dev/foundation/artifact_bucket_name"
      alert_topic_arn      = "/cicd/dev/foundation/alert_topic_arn"
      connection_arn       = "/cicd/dev/foundation/connection_arn"
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
      "events.amazonaws.com",
    ])
    error_message = "The key must serve CloudWatch Logs, CloudWatch, SNS and EventBridge, and nothing else"
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

run "artifact_bucket_is_cmk_encrypted_and_expires_in_30_days" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.artifact_bucket.name == "cicd-dev-artifacts-111111111111"
    error_message = "The artifact bucket must be named <name_prefix>-artifacts-<account>; iam builds its ARN from this name"
  }

  assert {
    condition     = local.artifact_bucket.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The artifact bucket must be encrypted with the key of this stack (design K8)"
  }

  assert {
    condition     = local.artifact_bucket.expiration_days == 30
    error_message = "Artifacts must expire after 30 days (design K8)"
  }
}

# The web bucket policy names the distribution, which only the web stack knows; see buckets.tf.
run "no_web_bucket_here" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "cloudfront_distribution_arns")])
    error_message = "foundation must not create the web bucket; its OAC read grant needs the distribution of the web stack"
  }
}

run "alert_topic_is_encrypted_and_open_to_eventbridge" {
  command = plan

  override_module {
    target = module.kms
    outputs = {
      key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.alert_topic.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The alert topic must be encrypted with the key of this stack"
  }

  assert {
    condition     = local.alert_topic.name == "cicd-dev-alerts" && local.alert_topic.email_subscriptions == tolist(["ops@example.com"])
    error_message = "The topic must be named <name_prefix>-alerts and subscribe the configured emails"
  }

  assert {
    condition     = local.alert_topic.service_publishers == ["events.amazonaws.com"]
    error_message = "Only EventBridge may publish as a service: the pipeline-failure rule of the pipeline stack (design K7)"
  }
}

run "one_github_connection" {
  command = plan

  assert {
    condition     = local.connection.name == "cicd-dev-github" && local.connection.provider_type == "GitHub"
    error_message = "The connection must be a GitHub connection named <name_prefix>-github (design D1)"
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
    condition     = local.name_prefix == "cicd-dev" && local.ssm_prefix == "/cicd/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Cicd"
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
    condition     = local.name_prefix == "cicd-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
