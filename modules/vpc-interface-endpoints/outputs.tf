output "endpoint_ids" {
  description = "Service name => endpoint ID."
  value       = { for k, e in aws_vpc_endpoint.this : k => e.id }
}

output "security_group_id" {
  description = "Endpoint SG ID; null when services is empty."
  value       = one(aws_security_group.this[*].id)
}
