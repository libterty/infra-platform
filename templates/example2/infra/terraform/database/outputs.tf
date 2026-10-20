# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "db_proxy_endpoint" {
  description = "RDS Proxy endpoint; connect applications here, not to the cluster endpoint."
  value       = module.db.proxy_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN of the master user secret that RDS manages."
  value       = module.db.master_user_secret_arn
}
