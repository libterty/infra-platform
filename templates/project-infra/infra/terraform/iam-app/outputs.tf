# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "task_role_arns" {
  description = "Task role ARN by service."
  value       = { for s, m in module.task_role : s => m.arn }
}

output "agent_policy_roles" {
  description = "Roles that got AgentCore or Bedrock permissions here: Runtime execution roles by Runtime name, and bedrock_kb and agentcore_gateway."
  value       = merge({ for r, p in local.agent_runtime_policies : r => p.role_arn }, { for k, p in merge(local.bedrock_kb_policy, local.agentcore_gateway_policy) : k => p.role_arn })
}
