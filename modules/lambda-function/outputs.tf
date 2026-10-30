output "function_name" {
  description = "function 名稱。"
  value       = local.function.function_name
}

output "function_arn" {
  description = "function ARN。等所有 permission 建好才可用，所以下游的 S3 notification 或 EventBridge target 用它，會在呼叫權限建好之後才建立。"
  value       = local.function.arn

  depends_on = [aws_lambda_permission.this]
}

output "invoke_arn" {
  description = "invoke ARN，給 API Gateway 整合用。"
  value       = local.function.invoke_arn
}

output "log_group_name" {
  description = "module 建的 log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}

output "version" {
  description = "最新發布的版本號；沒有 `alias` 時不發布版本，值是 `$LATEST`。`pipeline_managed` 時是 Terraform 最後發布的版本，不一定是 alias 目前指的版本。"
  value       = local.function.version
}

output "alias_name" {
  description = "alias 名稱；沒有 `alias` 時是 `null`。"
  value       = try(local.alias.name, null)
}

output "alias_arn" {
  description = "alias ARN，給 EventBridge target、API Gateway 這類呼叫端指到 alias 用；沒有 `alias` 時是 `null`。"
  value       = try(local.alias.arn, null)
}
