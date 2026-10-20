output "web_acl_arn" {
  description = "Web ACL ARN. Associate it with an ALB through the alb module's web_acl_arn; this module creates no association."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Web ACL name."
  value       = aws_wafv2_web_acl.this.name
}

output "ip_set_arn" {
  description = "Allowlist IP set ARN, or null when there is no allowlist."
  value       = one(aws_wafv2_ip_set.allowlist[*].arn)
}

output "log_group_name" {
  description = "WAF log group name, or null when logging is off."
  value       = one(aws_cloudwatch_log_group.waf[*].name)
}
