output "alarm_arns" {
  description = "key 是 `<breaker key>-<signal>`（`signal` 為 `error-rate`、`healthy-hosts`、`custom`）的 map，值是 alarm ARN。"
  value = merge(
    { for k, a in aws_cloudwatch_metric_alarm.error_rate : "${k}-error-rate" => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.healthy_hosts : "${k}-healthy-hosts" => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.custom : "${k}-custom" => a.arn },
  )
}

output "alarm_names" {
  description = "key 同 `alarm_arns` 的 map，值是 alarm 名稱；由輸入組成，plan 時就已知。"
  value       = { for k, a in local.alarms : k => a.name }
}

output "lambda_config_json" {
  description = "斷路器 Lambda 環境變數 `BREAKER_CONFIG` 的 JSON：`schema_version`，以及每個 alarm 名稱對應要改寫的 `listener_arn` 或 `rule_arn` 與 `stable_target_group_arn`。"
  value       = jsonencode(local.lambda_config)
}

output "lambda_permissions" {
  description = "直接傳給 `lambda-function` 的 `permissions`：只允許本帳號的這些 alarm 呼叫 function。principal 是 `lambda.alarms.cloudwatch.amazonaws.com`，`source_arn` 是各 alarm 的 ARN，`source_account` 是目前帳號。alarm ARN 由名稱與目前的 partition、region、帳號組成，不取自 alarm 資源，所以與 `lambda_function_arn` 沒有循環相依。"
  value = {
    for a in local.alarms : a.name => {
      principal      = "lambda.alarms.cloudwatch.amazonaws.com"
      source_arn     = "arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:${a.name}"
      source_account = data.aws_caller_identity.current.account_id
    }
  }
}
