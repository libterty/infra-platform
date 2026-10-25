output "endpoint_name" {
  description = "endpoint 名稱，呼叫端 `sagemaker:InvokeEndpoint` 用。"
  value       = aws_sagemaker_endpoint.this.name
}

output "endpoint_arn" {
  description = "endpoint 的 ARN。"
  value       = aws_sagemaker_endpoint.this.arn
}
