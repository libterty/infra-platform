# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_arns" {
  description = "Role ARN by role: ecs_execution, rds_proxy, rds_monitoring."
  value       = { for k, m in module.role : k => m.arn }
}

output "agent_role_arns" {
  description = "Role ARN by role: agent_<runtime>_execution per AgentCore Runtime, bedrock_kb and agentcore_gateway when listed in agent_service_roles."
  value       = merge({ for k, m in module.agent_runtime_role : k => m.arn }, { for k, m in module.agent_service_role : k => m.arn })
}
