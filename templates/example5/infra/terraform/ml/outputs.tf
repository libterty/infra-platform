# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "model_package_group_name" {
  description = "model package group 名稱；新版本在這裡等人工核准。"
  value       = module.registry.name
}

output "pipeline_name" {
  description = "訓練 pipeline 名稱。"
  value       = module.pipeline.pipeline_name
}

output "approved_rule_arn" {
  description = "把模型核准事件送進 model-approved queue 的 EventBridge rule ARN。"
  value       = module.approved_rule.rule_arn
}
