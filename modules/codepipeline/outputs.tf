output "name" {
  description = "pipeline 名稱；手動執行用 `aws codepipeline start-pipeline-execution --name <name>`。"
  value       = aws_codepipeline.this.name
}

output "arn" {
  description = "pipeline 的 ARN；給 IAM policy（`codepipeline:StartPipelineExecution`）與 EventBridge rule 的 `resources` 用。"
  value       = aws_codepipeline.this.arn
}
