output "pipeline_name" {
  description = "pipeline 名稱。"
  value       = aws_sagemaker_pipeline.this.pipeline_name
}

output "pipeline_arn" {
  description = "pipeline 的 ARN，給 `scheduler-schedule` 的 target 用。"
  value       = aws_sagemaker_pipeline.this.arn
}
