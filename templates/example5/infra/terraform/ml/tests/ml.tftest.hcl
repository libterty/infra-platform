mock_provider "aws" {}

variables {
  project                 = "example"
  env                     = "dev"
  expected_account_id     = "111111111111"
  training_schedule_state = "DISABLED"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_name"]
  values = { insecure_value = "example-dev-ml-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/model_approved_queue_arn"]
  values = { insecure_value = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_sagemaker_pipeline_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-sagemaker-pipeline" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_scheduler_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-scheduler" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                 = "foundation/kms_key_arn"
      ml_bucket_name              = "storage/ml_bucket_name"
      model_approved_queue_arn    = "storage/model_approved_queue_arn"
      role_sagemaker_pipeline_arn = "iam-base/role_sagemaker_pipeline_arn"
      role_scheduler_arn          = "iam-base/role_scheduler_arn"
    } && local.ssm_input_lists == {}
    error_message = "ml must read exactly the keys of earlier stacks it needs"
  }
}

# The names below are pinned in iam-base (naming.tf) and storage (queues.tf); the strings are written out so a change
# on either side has to change a test.
run "names_follow_the_iam_base_and_storage_naming_rules" {
  command = plan

  assert {
    condition     = module.registry.name == "example-dev-models" && local.pipeline.name == "example-dev-training"
    error_message = "The model package group is <name_prefix>-models and the pipeline <name_prefix>-training (iam-base naming rules)"
  }

  assert {
    condition     = local.approved_rule.name == "example-dev-model-approved"
    error_message = "The rule is <name_prefix>-model-approved: the model-approved queue policy of storage allows exactly this rule"
  }
}

run "pipeline_definition_comes_from_the_template_file" {
  command = plan

  assert {
    condition     = [for s in jsondecode(local.pipeline.definition).Steps : s.Type] == ["Processing", "Training", "RegisterModel"]
    error_message = "The pipeline preprocesses, trains and registers the model"
  }

  assert {
    condition = (
      jsondecode(local.pipeline.definition).Steps[2].Arguments.ModelPackageGroupName == "example-dev-models" &&
      one([for p in jsondecode(local.pipeline.definition).Parameters : p.DefaultValue if p.Name == "ModelApprovalStatus"]) == "PendingManualApproval"
    )
    error_message = "Models are registered to the group as PendingManualApproval; approval is a human step (design section 7.4)"
  }

  assert {
    condition = (
      jsondecode(local.pipeline.definition).Steps[1].Arguments.OutputDataConfig.S3OutputPath == "s3://example-dev-ml-artifacts-111111111111/models/training/" &&
      alltrue([for s in slice(jsondecode(local.pipeline.definition).Steps, 0, 2) : s.Arguments.RoleArn == "arn:aws:iam::111111111111:role/example-dev-sagemaker-pipeline"])
    )
    error_message = "Jobs run as the iam-base pipeline role, and models land under models/ of the ml bucket, where the endpoint role reads"
  }

  assert {
    condition     = local.pipeline.role_arn == "arn:aws:iam::111111111111:role/example-dev-sagemaker-pipeline" && !strcontains(local.pipeline.definition, "$${")
    error_message = "The pipeline runs as the iam-base role and every placeholder of the template is filled"
  }
}

run "weekly_schedule_starts_the_pipeline" {
  command = plan

  override_module {
    target  = module.pipeline
    outputs = { pipeline_name = "example-dev-training", pipeline_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/example-dev-training" }
  }

  assert {
    condition = local.schedules == {
      "example-dev-weekly-training" = {
        expression = "cron(0 3 ? * MON *)"
        timezone   = "Asia/Taipei"
        state      = "DISABLED"
        target     = { arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/example-dev-training", role_arn = "arn:aws:iam::111111111111:role/example-dev-scheduler" }
      }
    }
    error_message = "One weekly schedule starts the training pipeline with the iam-base scheduler role; its state comes from tfvars"
  }
}

run "schedule_state_rejected" {
  command = plan

  variables {
    training_schedule_state = "PAUSED"
  }

  expect_failures = [var.training_schedule_state]
}

run "approved_rule_matches_one_group_and_sends_to_the_queue" {
  command = plan

  assert {
    condition = local.approved_rule.event_pattern == {
      source        = ["aws.sagemaker"]
      "detail-type" = ["SageMaker Model Package State Change"]
      detail        = { ModelPackageGroupName = ["example-dev-models"], ModelApprovalStatus = ["Approved"] }
    }
    error_message = "The rule matches approvals of the single model package group (design K22)"
  }

  assert {
    condition     = local.approved_rule.targets == { model-approved = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved" } }
    error_message = "The only target is the model-approved queue, without a role (its queue policy allows the rule)"
  }
}

run "publishes_exactly_the_ml_keys" {
  command = plan

  override_module {
    target  = module.registry
    outputs = { name = "example-dev-models", arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/example-dev-models" }
  }

  override_module {
    target  = module.pipeline
    outputs = { pipeline_name = "example-dev-training", pipeline_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/example-dev-training" }
  }

  assert {
    condition = local.published_strings == {
      model_package_group_arn  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/example-dev-models"
      model_package_group_name = "example-dev-models"
      pipeline_name            = "example-dev-training"
    }
    error_message = "ml publishes exactly the three keys of design section 7.2"
  }

  assert {
    condition     = module.ssm_publish.names == { for k in keys(local.published_strings) : k => "/example/dev/ml/${k}" }
    error_message = "ssm-publish must write the contract keys under the ml stack path"
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
