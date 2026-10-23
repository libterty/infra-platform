output "runtime_arn" {
  description = "Runtime ARN。"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "runtime_id" {
  description = "Runtime ID。"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "runtime_name" {
  description = "Runtime 名稱。"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_name
}

output "runtime_version" {
  description = "Runtime 版本，每次更新都會變。"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_version
}

output "workload_identity_arn" {
  description = "AWS 為 Runtime 建立的 workload identity ARN；沒有回報時是 `null`。"
  value       = try(aws_bedrockagentcore_agent_runtime.this.workload_identity_details[0].workload_identity_arn, null)
}
