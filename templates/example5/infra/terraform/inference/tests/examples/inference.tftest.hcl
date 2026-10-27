# Run by scripts/validate.sh with each envs/examples/*.tfvars; it checks the examples that turn the endpoint on.
mock_provider "aws" {}

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

run "example_creates_the_endpoint_and_its_alarms" {
  command = plan

  assert {
    condition     = length(module.endpoint) == 1 && length(module.alarms) == 1 && length(local.endpoint.deployment.rollback_alarm_names) == 2
    error_message = "An example must create the endpoint with its two rollback alarms"
  }

  assert {
    condition     = startswith(var.model_package_arn, "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/")
    error_message = "The example deploys a version of the dev model package group"
  }
}

run "example_variant_settings" {
  command = plan

  assert {
    condition = var.serverless == null ? (
      local.endpoint.variant.instance.instance_type == "ml.m5.large" && local.endpoint.vpc != null && local.endpoint.enable_network_isolation
      ) : (
      local.endpoint.vpc == null && local.endpoint.data_capture == null && !local.endpoint.enable_network_isolation
    )
    error_message = "The instance example runs isolated in the VPC; the serverless example has no VPC or capture"
  }
}
