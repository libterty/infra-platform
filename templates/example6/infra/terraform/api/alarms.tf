locals {
  # Thresholds are starting points, not tuned against real traffic.
  alarms = {
    lambda_errors = {
      description = "The API Lambda returned errors. Check its log group /aws/lambda/${local.api_function.name}."
      threshold   = 1
      metric = {
        namespace   = "AWS/Lambda"
        metric_name = "Errors"
        dimensions  = { FunctionName = local.api_function.name }
        statistic   = "Sum"
        period      = 300
      }
    }
    api_5xx = {
      description = "The HTTP API answered with 5xx. Check the access log ${local.access_log_group.name} and the API Lambda log."
      threshold   = 1
      metric = {
        namespace   = "AWS/ApiGateway"
        metric_name = "5xx"
        dimensions  = { ApiId = module.api.api_id }
        statistic   = "Sum"
        period      = 300
      }
    }
  }
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"

  name_prefix    = "${local.name_prefix}-api"
  alarms         = local.alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
