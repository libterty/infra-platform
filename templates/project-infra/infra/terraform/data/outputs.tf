# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "database" {
  description = "The database JSON published to SSM."
  value       = local.database
}
