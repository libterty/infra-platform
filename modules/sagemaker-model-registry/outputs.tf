output "name" {
  description = "model package group 名稱。"
  value       = aws_sagemaker_model_package_group.this.model_package_group_name
}

output "arn" {
  description = "model package group 的 ARN。"
  value       = aws_sagemaker_model_package_group.this.arn
}
