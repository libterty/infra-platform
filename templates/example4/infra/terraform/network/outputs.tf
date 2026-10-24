# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "vpc_id" {
  description = "VPC ID。"
  value       = module.vpc.vpc_id
}

output "security_group_ids" {
  description = "SG ID，key 為 opensearch、firehose、redshift、quicksight、client_vpn、search_admin。"
  value       = module.sg.security_group_ids
}
