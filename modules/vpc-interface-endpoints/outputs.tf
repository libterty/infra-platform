output "endpoint_ids" {
  description = "服務名稱對應 endpoint ID 的 map。"
  value       = { for k, e in aws_vpc_endpoint.this : k => e.id }
}

output "security_group_id" {
  description = "endpoint 的 security group ID；`services` 為空時是 `null`。"
  value       = one(aws_security_group.this[*].id)
}
