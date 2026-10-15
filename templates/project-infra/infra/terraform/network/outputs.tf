output "vpc_id" {
  description = "VPC ID, created here or registered from the existing VPC."
  value       = local.vpc_id
}

output "security_group_ids" {
  description = "Security group ID by key: alb, one per service, and <data store> and <data store>_proxy."
  value       = module.sg.security_group_ids
}
