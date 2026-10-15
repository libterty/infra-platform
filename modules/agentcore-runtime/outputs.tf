output "runtime_arn" {
  description = "Agent runtime ARN."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "runtime_id" {
  description = "Agent runtime ID."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "runtime_name" {
  description = "Agent runtime name."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_name
}

output "runtime_version" {
  description = "Agent runtime version; changes on every update."
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_version
}

output "workload_identity_arn" {
  description = "Workload identity ARN AWS creates for the runtime; null when none is reported."
  value       = try(aws_bedrockagentcore_agent_runtime.this.workload_identity_details[0].workload_identity_arn, null)
}
