output "fqdns" {
  description = "`records` 的 key 對應 record 的 FQDN。"
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}
