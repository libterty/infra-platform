mock_provider "aws" {}

override_resource {
  target          = aws_sagemaker_endpoint.this
  override_during = plan
  values = {
    arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:endpoint/alpha-dev-detector"
  }
}

variables {
  name               = "alpha-dev-detector"
  model_package_arn  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector/3"
  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-endpoint"
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  variant = {
    instance = { instance_type = "ml.m5.large", initial_instance_count = 2 }
  }

  vpc = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
    security_group_ids = ["sg-0aaaaaaaaaaaaaaa1"]
  }

  deployment = {
    blue_green = {
      traffic     = "CANARY"
      canary_size = { type = "CAPACITY_PERCENT", value = 10 }
    }
    rollback_alarm_names = ["alpha-dev-detector-5xx", "alpha-dev-detector-latency"]
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "instance_in_vpc_with_canary_and_alarms" {
  command = plan

  assert {
    condition     = one(aws_sagemaker_model.this.primary_container).model_package_name == "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector/3"
    error_message = "The model must be built from the model package"
  }

  assert {
    condition     = one(aws_sagemaker_model.this.primary_container).image == null && length(aws_sagemaker_model.this.container) == 0
    error_message = "The model must not take an image"
  }

  assert {
    condition     = aws_sagemaker_model.this.enable_network_isolation == true
    error_message = "Network isolation must default to true"
  }

  assert {
    condition     = aws_sagemaker_model.this.execution_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-endpoint"
    error_message = "The execution role must be passed through"
  }

  assert {
    condition     = one(aws_sagemaker_model.this.vpc_config).subnets == toset(["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]) && one(aws_sagemaker_model.this.vpc_config).security_group_ids == toset(["sg-0aaaaaaaaaaaaaaa1"])
    error_message = "The instance variant must run in the given VPC"
  }

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The endpoint configuration must use the given key"
  }

  assert {
    condition     = length(aws_sagemaker_endpoint_configuration.this.production_variants) == 1
    error_message = "There must be exactly one variant"
  }

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.production_variants[0].variant_name == "primary"
    error_message = "The variant name must be fixed so blue/green updates keep the same name"
  }

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.production_variants[0].instance_type == "ml.m5.large" && aws_sagemaker_endpoint_configuration.this.production_variants[0].initial_instance_count == 2
    error_message = "The instance settings must be passed through"
  }

  assert {
    condition     = length(aws_sagemaker_endpoint_configuration.this.production_variants[0].serverless_config) == 0
    error_message = "An instance variant has no serverless config"
  }

  assert {
    condition     = length(aws_sagemaker_endpoint_configuration.this.data_capture_config) == 0
    error_message = "No data capture unless data_capture is given"
  }

  assert {
    condition     = one(one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).traffic_routing_configuration).type == "CANARY"
    error_message = "The traffic routing type must be passed through"
  }

  assert {
    condition     = one(one(one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).traffic_routing_configuration).canary_size).value == 10
    error_message = "The canary size must be passed through"
  }

  assert {
    condition     = one(one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).traffic_routing_configuration).wait_interval_in_seconds == 600
    error_message = "The bake time must default to 600 seconds"
  }

  assert {
    condition     = toset([for a in one(one(aws_sagemaker_endpoint.this.deployment_config).auto_rollback_configuration).alarms : a.alarm_name]) == toset(["alpha-dev-detector-5xx", "alpha-dev-detector-latency"])
    error_message = "The rollback alarms must be passed through"
  }

  assert {
    condition     = length(one(aws_sagemaker_endpoint.this.deployment_config).rolling_update_policy) == 0
    error_message = "Blue/green must not set a rolling policy"
  }

  assert {
    condition     = aws_sagemaker_endpoint.this.name == "alpha-dev-detector"
    error_message = "The endpoint name must be passed through"
  }
}

run "endpoint_configuration_uses_name_prefix" {
  command = plan

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.name_prefix == "alpha-dev-detector-"
    error_message = "The endpoint configuration must use a name prefix so it can be created before the old one is destroyed"
  }
}

run "linear_traffic" {
  command = plan

  variables {
    deployment = {
      blue_green = {
        traffic                     = "LINEAR"
        linear_step_size            = { type = "INSTANCE_COUNT", value = 1 }
        wait_interval_in_seconds    = 300
        termination_wait_in_seconds = 120
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  assert {
    condition     = one(one(one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).traffic_routing_configuration).linear_step_size).type == "INSTANCE_COUNT"
    error_message = "The linear step size must be passed through"
  }

  assert {
    condition     = one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).termination_wait_in_seconds == 120
    error_message = "termination_wait_in_seconds must be passed through"
  }
}

run "rolling_update" {
  command = plan

  variables {
    deployment = {
      rolling = {
        maximum_batch_size          = { type = "INSTANCE_COUNT", value = 1 }
        rollback_maximum_batch_size = { type = "CAPACITY_PERCENT", value = 100 }
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  assert {
    condition     = one(one(one(aws_sagemaker_endpoint.this.deployment_config).rolling_update_policy).maximum_batch_size).value == 1
    error_message = "The rolling batch size must be passed through"
  }

  assert {
    condition     = one(one(aws_sagemaker_endpoint.this.deployment_config).rolling_update_policy).wait_interval_in_seconds == 600
    error_message = "The rolling bake time must default to 600 seconds"
  }

  assert {
    condition     = length(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy) == 0
    error_message = "Rolling must not set a blue/green policy"
  }
}

run "data_capture" {
  command = plan

  variables {
    data_capture = {
      destination_s3_uri  = "s3://alpha-dev-ml-artifacts/capture/"
      sampling_percentage = 20
    }
  }

  assert {
    condition     = one(aws_sagemaker_endpoint_configuration.this.data_capture_config).destination_s3_uri == "s3://alpha-dev-ml-artifacts/capture/"
    error_message = "The capture destination must be passed through"
  }

  assert {
    condition     = one(aws_sagemaker_endpoint_configuration.this.data_capture_config).initial_sampling_percentage == 20
    error_message = "The sampling percentage must be passed through"
  }

  assert {
    condition     = one(aws_sagemaker_endpoint_configuration.this.data_capture_config).kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Captured data must be encrypted with the given key"
  }

  assert {
    condition     = toset([for o in one(aws_sagemaker_endpoint_configuration.this.data_capture_config).capture_options : o.capture_mode]) == toset(["Input", "Output"])
    error_message = "Both requests and responses must be captured"
  }
}

run "serverless" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5, provisioned_concurrency = 1 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  assert {
    condition     = one(aws_sagemaker_endpoint_configuration.this.production_variants[0].serverless_config).memory_size_in_mb == 2048
    error_message = "The serverless memory must be passed through"
  }

  assert {
    condition     = one(aws_sagemaker_endpoint_configuration.this.production_variants[0].serverless_config).max_concurrency == 5 && one(aws_sagemaker_endpoint_configuration.this.production_variants[0].serverless_config).provisioned_concurrency == 1
    error_message = "The serverless concurrency must be passed through"
  }

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.production_variants[0].instance_type == null && aws_sagemaker_endpoint_configuration.this.production_variants[0].initial_instance_count == null
    error_message = "A serverless variant has no instance settings"
  }

  assert {
    condition     = length(aws_sagemaker_model.this.vpc_config) == 0 && aws_sagemaker_model.this.enable_network_isolation == false
    error_message = "A serverless model has no VPC and no network isolation"
  }

  assert {
    condition     = length(aws_sagemaker_endpoint.this.deployment_config) == 0
    error_message = "No deployment config when deployment is null"
  }
}

run "serverless_with_blue_green" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 1024, max_concurrency = 5 }
    }
    vpc                      = null
    enable_network_isolation = false
    deployment = {
      blue_green           = { traffic = "ALL_AT_ONCE" }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  assert {
    condition     = one(one(one(aws_sagemaker_endpoint.this.deployment_config).blue_green_update_policy).traffic_routing_configuration).type == "ALL_AT_ONCE"
    error_message = "Blue/green is supported on serverless endpoints"
  }
}

run "tags" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition = alltrue([for t in [aws_sagemaker_model.this.tags, aws_sagemaker_endpoint_configuration.this.tags, aws_sagemaker_endpoint.this.tags] :
      t["Project"] == "alpha" && t["Name"] == "alpha-dev-detector"
    ])
    error_message = "Name must be merged into the given tags on every resource"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.endpoint_name == "alpha-dev-detector"
    error_message = "endpoint_name output must be the endpoint name"
  }

  assert {
    condition     = output.endpoint_arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:endpoint/alpha-dev-detector"
    error_message = "endpoint_arn output must be the endpoint ARN"
  }
}

run "apply_wires_generated_names" {
  command = apply

  # Plan-time mock values for the endpoint would be regenerated during apply; generate them once, at apply.
  override_resource {
    target          = aws_sagemaker_endpoint.this
    override_during = apply
    values = {
      arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:endpoint/alpha-dev-detector"
    }
  }

  assert {
    condition     = aws_sagemaker_endpoint_configuration.this.production_variants[0].model_name == aws_sagemaker_model.this.name
    error_message = "The variant must use the model created by the module"
  }

  assert {
    condition     = aws_sagemaker_endpoint.this.endpoint_config_name == aws_sagemaker_endpoint_configuration.this.name
    error_message = "The endpoint must use the endpoint configuration created by the module"
  }
}
