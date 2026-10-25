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

run "both_variants_rejected" {
  command = plan

  variables {
    variant = {
      instance   = { instance_type = "ml.m5.large" }
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
    }
  }

  expect_failures = [var.variant]
}

run "no_variant_rejected" {
  command = plan

  variables {
    variant = {}
  }

  expect_failures = [var.variant]
}

run "instance_type_without_ml_prefix_rejected" {
  command = plan

  variables {
    variant = {
      instance = { instance_type = "m5.large" }
    }
  }

  expect_failures = [var.variant]
}

run "zero_instances_rejected" {
  command = plan

  variables {
    variant = {
      instance = { instance_type = "ml.m5.large", initial_instance_count = 0 }
    }
  }

  expect_failures = [var.variant]
}

run "serverless_memory_below_range_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 512, max_concurrency = 5 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.variant]
}

run "serverless_memory_above_range_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 7168, max_concurrency = 5 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.variant]
}

run "serverless_memory_not_multiple_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 1536, max_concurrency = 5 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.variant]
}

run "serverless_concurrency_above_200_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 201 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.variant]
}

run "provisioned_above_max_concurrency_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5, provisioned_concurrency = 6 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.variant]
}

run "instance_without_vpc_rejected" {
  command = plan

  variables {
    vpc = null
  }

  expect_failures = [var.vpc]
}

run "vpc_without_subnets_rejected" {
  command = plan

  variables {
    vpc = { subnet_ids = [], security_group_ids = ["sg-0aaaaaaaaaaaaaaa1"] }
  }

  expect_failures = [var.vpc]
}

run "serverless_with_vpc_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
    }
    deployment               = null
    enable_network_isolation = false
  }

  expect_failures = [var.vpc]
}

run "serverless_with_network_isolation_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
    }
    vpc        = null
    deployment = null
  }

  expect_failures = [var.enable_network_isolation]
}

run "serverless_with_data_capture_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
    }
    vpc                      = null
    deployment               = null
    enable_network_isolation = false
    data_capture = {
      destination_s3_uri  = "s3://alpha-dev-ml-artifacts/capture/"
      sampling_percentage = 20
    }
  }

  expect_failures = [var.data_capture]
}

run "data_capture_sampling_above_100_rejected" {
  command = plan

  variables {
    data_capture = {
      destination_s3_uri  = "s3://alpha-dev-ml-artifacts/capture/"
      sampling_percentage = 101
    }
  }

  expect_failures = [var.data_capture]
}

run "data_capture_destination_not_s3_rejected" {
  command = plan

  variables {
    data_capture = {
      destination_s3_uri  = "alpha-dev-ml-artifacts/capture/"
      sampling_percentage = 20
    }
  }

  expect_failures = [var.data_capture]
}

run "instance_without_deployment_rejected" {
  command = plan

  variables {
    deployment = null
  }

  expect_failures = [var.deployment]
}

run "deployment_without_alarms_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green           = { traffic = "ALL_AT_ONCE" }
      rollback_alarm_names = []
    }
  }

  expect_failures = [var.deployment]
}

run "deployment_with_eleven_alarms_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green           = { traffic = "ALL_AT_ONCE" }
      rollback_alarm_names = [for i in range(11) : "alpha-dev-detector-${i}"]
    }
  }

  expect_failures = [var.deployment]
}

run "deployment_with_both_strategies_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green = { traffic = "ALL_AT_ONCE" }
      rolling = {
        maximum_batch_size = { type = "INSTANCE_COUNT", value = 1 }
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "deployment_without_strategy_rejected" {
  command = plan

  variables {
    deployment = {
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "unknown_traffic_type_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green           = { traffic = "SHADOW" }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "canary_without_size_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green           = { traffic = "CANARY" }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "all_at_once_with_canary_size_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green = {
        traffic     = "ALL_AT_ONCE"
        canary_size = { type = "CAPACITY_PERCENT", value = 10 }
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "linear_without_step_size_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green           = { traffic = "LINEAR" }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "unknown_size_type_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green = {
        traffic     = "CANARY"
        canary_size = { type = "PERCENT", value = 10 }
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "wait_interval_above_3600_rejected" {
  command = plan

  variables {
    deployment = {
      blue_green = {
        traffic                  = "ALL_AT_ONCE"
        wait_interval_in_seconds = 3601
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
  }

  expect_failures = [var.deployment]
}

run "serverless_rolling_rejected" {
  command = plan

  variables {
    variant = {
      serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
    }
    vpc = null
    deployment = {
      rolling = {
        maximum_batch_size = { type = "CAPACITY_PERCENT", value = 50 }
      }
      rollback_alarm_names = ["alpha-dev-detector-5xx"]
    }
    enable_network_isolation = false
  }

  expect_failures = [var.deployment]
}

run "model_package_arn_without_version_rejected" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector"
  }

  expect_failures = [var.model_package_arn]
}

run "model_package_group_arn_rejected" {
  command = plan

  variables {
    model_package_arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/alpha-dev-detector"
  }

  expect_failures = [var.model_package_arn]
}

run "execution_role_arn_format_rejected" {
  command = plan

  variables {
    execution_role_arn = "alpha-dev-sagemaker-endpoint"
  }

  expect_failures = [var.execution_role_arn]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "alpha-dev-detector-0123456789abcdefgh"
  }

  expect_failures = [var.name]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha_dev_detector"
  }

  expect_failures = [var.name]
}
