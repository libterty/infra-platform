output "web_acl_arn" {
  description = "Web ACL ARN，傳給 `alb` module 或 CloudFront distribution 做關聯；這個 module 不建關聯。"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Web ACL 名稱。"
  value       = aws_wafv2_web_acl.this.name
}

output "ip_set_arn" {
  description = "allowlist IP set ARN；沒有 allowlist 時是 `null`。"
  value       = one(aws_wafv2_ip_set.allowlist[*].arn)
}

output "log_group_name" {
  description = "WAF log group 名稱 `aws-waf-logs-<name>`；沒開 logging 時是 `null`。"
  value       = one(aws_cloudwatch_log_group.waf[*].name)
}
