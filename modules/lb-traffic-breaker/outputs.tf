output "alarm_arns" {
  description = "Alarm ARNs keyed by <breaker key>-<signal> (error-rate, healthy-hosts, custom)."
  value = merge(
    { for k, a in aws_cloudwatch_metric_alarm.error_rate : "${k}-error-rate" => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.healthy_hosts : "${k}-healthy-hosts" => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.custom : "${k}-custom" => a.arn },
  )
}

output "alarm_names" {
  description = "Alarm names keyed by <breaker key>-<signal>. Known at plan time: built from the inputs."
  value       = { for k, a in local.alarms : k => a.name }
}

output "lambda_config_json" {
  description = "JSON for the BREAKER_CONFIG environment variable of the breaker Lambda: schema_version and, per alarm name, the listener_arn or rule_arn to rewrite and the stable_target_group_arn."
  value       = jsonencode(local.lambda_config)
}

output "lambda_permissions" {
  description = "Value for the permissions input of lambda-function: lets CloudWatch invoke the function from exactly these alarms in this account. The alarm ARNs are built from the names plus the current partition, region and account, not from the alarm resources, so there is no dependency cycle with lambda_function_arn."
  value = {
    for a in local.alarms : a.name => {
      principal      = "lambda.alarms.cloudwatch.amazonaws.com"
      source_arn     = "arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:${a.name}"
      source_account = data.aws_caller_identity.current.account_id
    }
  }
}
