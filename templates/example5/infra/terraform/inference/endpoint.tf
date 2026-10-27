locals {
  enabled = var.model_package_arn != null

  # Naming rule: the rollback alarms need the endpoint name in their dimensions before the endpoint exists, and the
  # endpoint needs the alarm names, so both take the name from here. sagemaker-endpoint names its variant "primary".
  endpoint_name = "${local.name_prefix}-inference"
  variant_name  = "primary"

  alarm_metric = { namespace = "AWS/SageMaker", dimensions = { EndpointName = local.endpoint_name, VariantName = local.variant_name } }

  # Thresholds are starting points, not tuned against real traffic. ModelLatency is in microseconds.
  alarms = {
    endpoint_5xx_errors = {
      description = "The inference endpoint returns 5XX errors. During a blue/green update this rolls the endpoint back."
      threshold   = 1
      metric      = merge(local.alarm_metric, { metric_name = "Invocation5XXErrors", statistic = "Sum", period = 60 })
    }
    endpoint_model_latency = {
      description = "The model takes over a second per request on average. During a blue/green update this rolls the endpoint back."
      threshold   = 1000000
      metric      = merge(local.alarm_metric, { metric_name = "ModelLatency", statistic = "Average", period = 60 })
    }
  }

  ml_bucket_name = module.in.strings["ml_bucket_name"]

  # Instance variant: in the VPC, without outbound network, capturing requests (design K19). Serverless supports none
  # of those three.
  endpoint = !local.enabled ? null : {
    name               = local.endpoint_name
    model_package_arn  = var.model_package_arn
    execution_role_arn = module.in.strings["role_sagemaker_endpoint_arn"]
    variant = {
      instance   = var.serverless == null ? { instance_type = "ml.m5.large", initial_instance_count = 1 } : null
      serverless = var.serverless
    }
    vpc = var.serverless != null ? null : {
      subnet_ids         = module.in.lists["subnet_ids_data"]
      security_group_ids = [module.in.strings["sg_sagemaker_id"]]
    }
    enable_network_isolation = var.serverless == null
    data_capture             = var.serverless != null ? null : { destination_s3_uri = "s3://${local.ml_bucket_name}/capture/", sampling_percentage = 20 }
    deployment = {
      blue_green           = { traffic = "ALL_AT_ONCE", wait_interval_in_seconds = 600 }
      rollback_alarm_names = [for k in sort(keys(local.alarms)) : module.alarms[0].alarm_names[k]]
    }
  }
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"
  count   = local.enabled ? 1 : 0

  name_prefix    = local.name_prefix
  alarms         = local.alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}

module "endpoint" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sagemaker-endpoint/aws"
  version = "~> 0.1.0"
  count   = local.enabled ? 1 : 0

  name                     = local.endpoint.name
  model_package_arn        = local.endpoint.model_package_arn
  execution_role_arn       = local.endpoint.execution_role_arn
  kms_key_arn              = module.in.strings["kms_key_arn"]
  variant                  = local.endpoint.variant
  vpc                      = local.endpoint.vpc
  enable_network_isolation = local.endpoint.enable_network_isolation
  data_capture             = local.endpoint.data_capture
  deployment               = local.endpoint.deployment
}
