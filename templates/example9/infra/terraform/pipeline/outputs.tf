# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "pipeline_names" {
  description = "三條 pipeline 的名稱；手動執行用 `aws codepipeline start-pipeline-execution --name <name>`。"
  value       = { for k, m in module.pipeline : k => m.name }
}

output "build_project_names" {
  description = "各建置專案的名稱。"
  value       = { for k, m in module.build : k => m.name }
}
