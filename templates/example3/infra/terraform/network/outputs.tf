# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "security_group_ids" {
  description = "Security group ID by tier."
  value       = module.sg.security_group_ids
}

output "peering_connection_id" {
  description = "Give this ID to the owner of the peer VPC so the request can be accepted; null without a peering."
  value       = one(module.peering[*].peering_connection_id)
}
