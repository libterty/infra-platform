output "function_name" {
  description = "Function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Function ARN. Waits for every permission, so a downstream S3 notification or EventBridge target that uses it is created only after the invoke permission exists."
  value       = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.this]
}

output "invoke_arn" {
  description = "Invoke ARN, for API Gateway integrations."
  value       = aws_lambda_function.this.invoke_arn
}

output "log_group_name" {
  description = "Name of the log group the module created."
  value       = aws_cloudwatch_log_group.this.name
}
