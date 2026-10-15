# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "vpc_id" {
  description = "VPC ID, created here or registered from the existing VPC."
  value       = local.vpc_id
}

output "security_group_ids" {
  description = "Security group ID by key: alb, one per service, agent_<runtime> per AgentCore Runtime, and <data store> and <data store>_proxy."
  value       = module.sg.security_group_ids
}
