# The two CloudTrail alarms auditors ask about most (design K6); the other CIS monitoring items are left to the
# Security Hub CIS findings. Patterns follow the CIS AWS Foundations Benchmark.
locals {
  trail_alarms = {
    root_account_usage = {
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      metric_name = "RootAccountUsage"
      description = "The root user of ${local.name_prefix} made an API call."
    }
    unauthorized_api_calls = {
      pattern     = "{ (($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\")) && ($.sourceIPAddress != \"delivery.logs.amazonaws.com\") && ($.eventName != \"HeadBucket\") }"
      metric_name = "UnauthorizedApiCalls"
      description = "An API call in ${local.name_prefix} was denied as unauthorized."
    }
  }
  # Every alarm goes to the security alert topic of foundation, both on alarm and back to OK.
  trail_alarm_topic_arns = [module.in.strings["alert_topic_arn"]]
}

module "trail_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.1"

  name_prefix    = "${local.name_prefix}-trail"
  log_group_name = module.trail_log_group.name
  namespace      = "${var.project}/${var.env}/cloudtrail"
  alarms         = local.trail_alarms
  sns_topic_arns = local.trail_alarm_topic_arns
}
