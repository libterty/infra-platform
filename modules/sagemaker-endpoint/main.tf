locals {
  instance   = var.variant.instance
  serverless = var.variant.serverless
  tags       = merge(var.tags, { Name = var.name })

  # Blue/green and rolling updates require the new endpoint configuration to keep the same variant name.
  variant_name = "primary"
}

resource "aws_sagemaker_model" "this" {
  # No fixed name: a replacement is created before the old model is destroyed, so the name must not collide.
  execution_role_arn       = var.execution_role_arn
  enable_network_isolation = var.enable_network_isolation

  primary_container {
    model_package_name = var.model_package_arn
  }

  dynamic "vpc_config" {
    for_each = var.vpc == null ? [] : [var.vpc]
    content {
      subnets            = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sagemaker_endpoint_configuration" "this" {
  name_prefix = "${var.name}-"
  kms_key_arn = var.kms_key_arn

  production_variants {
    variant_name           = local.variant_name
    model_name             = aws_sagemaker_model.this.name
    initial_variant_weight = 1
    instance_type          = try(local.instance.instance_type, null)
    initial_instance_count = try(local.instance.initial_instance_count, null)

    dynamic "serverless_config" {
      for_each = local.serverless == null ? [] : [local.serverless]
      content {
        memory_size_in_mb       = serverless_config.value.memory_size_in_mb
        max_concurrency         = serverless_config.value.max_concurrency
        provisioned_concurrency = serverless_config.value.provisioned_concurrency
      }
    }
  }

  dynamic "data_capture_config" {
    for_each = var.data_capture == null ? [] : [var.data_capture]
    content {
      enable_capture              = true
      destination_s3_uri          = data_capture_config.value.destination_s3_uri
      initial_sampling_percentage = data_capture_config.value.sampling_percentage
      kms_key_id                  = var.kms_key_arn

      capture_options {
        capture_mode = "Input"
      }

      capture_options {
        capture_mode = "Output"
      }
    }
  }

  tags = local.tags

  # Endpoint configurations are immutable; the endpoint switches to the new one before the old one is deleted.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_sagemaker_endpoint" "this" {
  name                 = var.name
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this.name

  dynamic "deployment_config" {
    for_each = var.deployment == null ? [] : [var.deployment]
    content {
      auto_rollback_configuration {
        dynamic "alarms" {
          for_each = toset(deployment_config.value.rollback_alarm_names)
          content {
            alarm_name = alarms.value
          }
        }
      }

      dynamic "blue_green_update_policy" {
        for_each = deployment_config.value.blue_green == null ? [] : [deployment_config.value.blue_green]
        content {
          termination_wait_in_seconds          = blue_green_update_policy.value.termination_wait_in_seconds
          maximum_execution_timeout_in_seconds = blue_green_update_policy.value.maximum_execution_timeout_in_seconds

          traffic_routing_configuration {
            type                     = blue_green_update_policy.value.traffic
            wait_interval_in_seconds = blue_green_update_policy.value.wait_interval_in_seconds

            dynamic "canary_size" {
              for_each = blue_green_update_policy.value.canary_size == null ? [] : [blue_green_update_policy.value.canary_size]
              content {
                type  = canary_size.value.type
                value = canary_size.value.value
              }
            }

            dynamic "linear_step_size" {
              for_each = blue_green_update_policy.value.linear_step_size == null ? [] : [blue_green_update_policy.value.linear_step_size]
              content {
                type  = linear_step_size.value.type
                value = linear_step_size.value.value
              }
            }
          }
        }
      }

      dynamic "rolling_update_policy" {
        for_each = deployment_config.value.rolling == null ? [] : [deployment_config.value.rolling]
        content {
          wait_interval_in_seconds             = rolling_update_policy.value.wait_interval_in_seconds
          maximum_execution_timeout_in_seconds = rolling_update_policy.value.maximum_execution_timeout_in_seconds

          maximum_batch_size {
            type  = rolling_update_policy.value.maximum_batch_size.type
            value = rolling_update_policy.value.maximum_batch_size.value
          }

          dynamic "rollback_maximum_batch_size" {
            for_each = rolling_update_policy.value.rollback_maximum_batch_size == null ? [] : [rolling_update_policy.value.rollback_maximum_batch_size]
            content {
              type  = rollback_maximum_batch_size.value.type
              value = rollback_maximum_batch_size.value.value
            }
          }
        }
      }
    }
  }

  tags = local.tags
}
