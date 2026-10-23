output "function_name" {
  description = "function 名稱。"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "function ARN。等所有 permission 建好才可用，所以下游的 S3 notification 或 EventBridge target 用它，會在呼叫權限建好之後才建立。"
  value       = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.this]
}

output "invoke_arn" {
  description = "invoke ARN，給 API Gateway 整合用。"
  value       = aws_lambda_function.this.invoke_arn
}

output "log_group_name" {
  description = "module 建的 log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}
