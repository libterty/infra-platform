mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_sagemaker_id"]
  values = { insecure_value = "sg-0aaaaaaa00000003" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_name"]
  values = { insecure_value = "example-dev-ml-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_sagemaker_endpoint_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-sagemaker-endpoint" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["ml/model_package_group_name"]
  values = { insecure_value = "example-dev-models" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                 = "foundation/kms_key_arn"
      alarm_topic_arn             = "foundation/alarm_topic_arn"
      sg_sagemaker_id             = "network/sg_sagemaker_id"
      ml_bucket_name              = "storage/ml_bucket_name"
      role_sagemaker_endpoint_arn = "iam-base/role_sagemaker_endpoint_arn"
      model_package_group_name    = "ml/model_package_group_name"
    } && local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    error_message = "inference must read exactly the keys of earlier stacks it needs"
  }
}

# Design K21 and section 7.5: no approved model, no endpoint.
run "defaults_create_nothing" {
  command = plan

  assert {
    condition     = var.model_package_arn == null && var.serverless == null && length(module.endpoint) == 0 && length(module.alarms) == 0
    error_message = "model_package_arn defaults to null, and then neither the endpoint nor its alarms may be created"
  }

  assert {
    condition     = local.published_strings == { endpoint = "{\"enabled\":false}" }
    error_message = "Without an endpoint, inference must publish {\"enabled\":false}"
  }

  assert {
    condition     = module.ssm_publish.names == { endpoint = "/example/dev/inference/endpoint" }
    error_message = "ssm-publish must write the endpoint key under the inference stack path"
  }
}

run "instance_endpoint_in_the_vpc_with_network_isolation" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/3"
  }

  assert {
    condition     = length(module.endpoint) == 1 && local.endpoint.name == "example-dev-inference" && local.endpoint.variant.instance.instance_type == "ml.m5.large" && local.endpoint.variant.instance.initial_instance_count == 1 && local.endpoint.variant.serverless == null
    error_message = "One ml.m5.large instance named <name_prefix>-inference"
  }

  assert {
    condition     = tolist(local.endpoint.vpc.subnet_ids) == tolist(["subnet-0dat1", "subnet-0dat2"]) && tolist(local.endpoint.vpc.security_group_ids) == tolist(["sg-0aaaaaaa00000003"]) && local.endpoint.enable_network_isolation
    error_message = "The instance variant runs in the data subnets with the SageMaker security group and network isolation (design K19)"
  }

  assert {
    condition     = local.endpoint.data_capture == { destination_s3_uri = "s3://example-dev-ml-artifacts-111111111111/capture/", sampling_percentage = 20 }
    error_message = "Requests and responses are captured to capture/ of the ml bucket"
  }

  assert {
    condition     = local.endpoint.execution_role_arn == "arn:aws:iam::111111111111:role/example-dev-sagemaker-endpoint" && local.endpoint.model_package_arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/3"
    error_message = "The endpoint uses the iam-base endpoint role and the given approved model package"
  }
}

# The alarms need the endpoint name before the endpoint exists, and the endpoint needs the alarm names: the endpoint
# name comes from the naming rule, so both sides use the same string.
run "rollback_alarms_watch_the_endpoint_by_its_naming_rule" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/3"
  }

  assert {
    condition = (
      toset(keys(local.alarms)) == toset(["endpoint_5xx_errors", "endpoint_model_latency"]) &&
      alltrue([for a in values(local.alarms) : a.metric.namespace == "AWS/SageMaker" && a.metric.dimensions == { EndpointName = "example-dev-inference", VariantName = "primary" }]) &&
      local.alarms["endpoint_5xx_errors"].metric.metric_name == "Invocation5XXErrors" &&
      local.alarms["endpoint_model_latency"].metric.metric_name == "ModelLatency"
    )
    error_message = "The rollback alarms watch 5XX errors and model latency of variant primary of <name_prefix>-inference"
  }

  assert {
    condition = local.endpoint.deployment == {
      blue_green           = { traffic = "ALL_AT_ONCE", wait_interval_in_seconds = 600 }
      rollback_alarm_names = ["example-dev-endpoint-5xx-errors", "example-dev-endpoint-model-latency"]
    }
    error_message = "Updates are blue/green all at once and roll back on either alarm (design K19)"
  }
}

run "serverless_endpoint_drops_vpc_and_capture" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/3"
    serverless        = { memory_size_in_mb = 2048, max_concurrency = 5 }
  }

  assert {
    condition = (
      local.endpoint.variant.instance == null && local.endpoint.variant.serverless.memory_size_in_mb == 2048 && local.endpoint.variant.serverless.max_concurrency == 5 &&
      local.endpoint.vpc == null && local.endpoint.data_capture == null && !local.endpoint.enable_network_isolation
    )
    error_message = "A serverless variant has no VPC, no data capture and no network isolation (not supported)"
  }
}

run "model_package_of_another_group_rejected" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/other-models/3"
  }

  expect_failures = [output.endpoint]
}

run "model_package_arn_format_rejected" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/example-dev-models"
  }

  expect_failures = [var.model_package_arn]
}

run "publishes_the_endpoint" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/3"
  }

  override_module {
    target  = module.endpoint
    outputs = { endpoint_name = "example-dev-inference", endpoint_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:endpoint/example-dev-inference" }
  }

  assert {
    condition     = jsondecode(local.published_strings["endpoint"]) == { enabled = true, name = "example-dev-inference", arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:endpoint/example-dev-inference" }
    error_message = "With an endpoint, inference publishes enabled = true with its name and ARN"
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
