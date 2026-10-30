output "name" {
  description = "建置專案名稱（`codepipeline` 的 build action 的 `ProjectName`）。"
  value       = aws_codebuild_project.this.name
}

output "arn" {
  description = "建置專案的 ARN（pipeline role 的 `codebuild:StartBuild`、`codebuild:BatchGetBuilds` 的 resource）。"
  value       = aws_codebuild_project.this.arn
}

output "log_group_name" {
  description = "module 建的 log group 名稱（service role 寫 log 的 resource）。"
  value       = aws_cloudwatch_log_group.this.name
}
