mock_provider "aws" {}

variables {
  project             = "baseline"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/config_bucket_name"]
  values = { insecure_value = "baseline-dev-config-111111111111" }
}

run "reads_only_the_foundation_keys_it_needs" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn        = "foundation/kms_key_arn"
      config_bucket_name = "foundation/config_bucket_name"
    } && local.ssm_input_lists == {}
    error_message = "iam may read only the foundation key and config bucket (design 8.2)"
  }
}

# The audit stack names the log group exactly like this; its tests pin the same string.
run "naming_rule_of_the_trail_log_group" {
  command = plan

  assert {
    condition     = local.trail_log_group_name == "/aws/cloudtrail/baseline-dev"
    error_message = "The trail log group must be named /aws/cloudtrail/<name_prefix>"
  }

  assert {
    condition     = local.trail_log_group_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev"
    error_message = "The log group ARN must be built from the naming rule"
  }
}

run "each_role_trusts_one_service_of_this_account" {
  command = plan

  assert {
    condition = {
      for k, r in local.service_roles : k => { name = r.name, service = r.service }
      } == {
      config     = { name = "baseline-dev-config-recorder", service = "config.amazonaws.com" }
      backup     = { name = "baseline-dev-backup", service = "backup.amazonaws.com" }
      trail_logs = { name = "baseline-dev-trail-logs", service = "cloudtrail.amazonaws.com" }
    }
    error_message = "There must be exactly the Config, Backup and CloudTrail log roles, each trusting its own service (design K4)"
  }

  assert {
    condition     = length(regexall("source_account = var\\.expected_account_id", file("${path.module}/roles.tf"))) == 1
    error_message = "Every role must trust its service only with aws:SourceAccount of this account (design section 4)"
  }

  assert {
    condition     = module.role["config"].name == "baseline-dev-config-recorder"
    error_message = "iam-role must create the roles with those names"
  }
}

run "managed_policies_are_the_documented_ones" {
  command = plan

  assert {
    condition     = local.service_roles.config.managed_policy_arns == ["arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"]
    error_message = "The Config role must carry AWS_ConfigRole"
  }

  assert {
    condition = toset(local.service_roles.backup.managed_policy_arns) == toset([
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    ])
    error_message = "The Backup role must carry the backup and restore service role policies"
  }

  assert {
    condition     = local.service_roles.trail_logs.managed_policy_arns == []
    error_message = "The CloudTrail log role gets only its inline policy"
  }
}

run "policies_are_attached_to_their_roles" {
  command = plan

  assert {
    condition     = toset(keys(local.role_policies)) == toset(["config", "trail_logs"]) && alltrue([for p in values(local.role_policies) : keys(p) == ["permissions"]])
    error_message = "Config and the CloudTrail log role each get one inline policy named permissions; Backup gets none"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*role_arn\\s*=\\s*module\\.role\\[each\\.key\\]\\.arn\\s*$", file("${path.module}/policies.tf"))) == 1
    error_message = "Each policy must be attached to the role with the same key"
  }
}

run "config_writes_only_its_own_path_of_the_config_bucket" {
  command = plan

  assert {
    condition = (
      local.config_statements["CheckBucketAcl"].Action == ["s3:GetBucketAcl"] &&
      local.config_statements["CheckBucketAcl"].Resource == ["arn:aws:s3:::baseline-dev-config-111111111111"]
    )
    error_message = "Config may read the ACL of the config bucket only"
  }

  assert {
    condition = (
      toset(local.config_statements["DeliverToConfigBucket"].Action) == toset(["s3:PutObject", "s3:PutObjectAcl"]) &&
      local.config_statements["DeliverToConfigBucket"].Resource == ["arn:aws:s3:::baseline-dev-config-111111111111/AWSLogs/111111111111/Config/*"] &&
      local.config_statements["DeliverToConfigBucket"].Condition == { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
    )
    error_message = "Config writes only under AWSLogs/<account>/Config/ of the config bucket, with bucket-owner-full-control"
  }

  assert {
    condition = (
      toset(local.config_statements["EncryptWithGovernanceKey"].Action) == toset(["kms:Decrypt", "kms:GenerateDataKey"]) &&
      local.config_statements["EncryptWithGovernanceKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
    )
    error_message = "Config uses the governance key only to encrypt its deliveries"
  }

  assert {
    condition     = length(local.config_statements) == 3
    error_message = "The Config policy has exactly these three statements"
  }
}

run "trail_logs_writes_only_the_trail_log_group" {
  command = plan

  assert {
    condition = (
      length(local.trail_logs_statements) == 1 &&
      toset(local.trail_logs_statements["WriteTrailLogs"].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      local.trail_logs_statements["WriteTrailLogs"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev:log-stream:*"]
    )
    error_message = "The CloudTrail log role may only create streams and put events in the trail log group"
  }
}

run "publishes_exactly_the_three_role_arns" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      config_role_arn     = "/baseline/dev/iam/config_role_arn"
      backup_role_arn     = "/baseline/dev/iam/backup_role_arn"
      trail_logs_role_arn = "/baseline/dev/iam/trail_logs_role_arn"
    }
    error_message = "ssm-publish must write exactly the three role ARNs under the iam stack path (design 8.2)"
  }

  assert {
    condition     = length(regexall("depends_on = \\[module\\.policy\\]", file("${path.module}/ssm-outputs.tf"))) == 1
    error_message = "The role ARNs must be published only after the inline policies are attached"
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
