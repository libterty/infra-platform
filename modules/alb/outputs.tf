output "alb_arn" {
  description = "ALB ARN。"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "`app/<name>/<id>`，給 CloudWatch dimension 與 `requests_per_target` 的 resource label 用。"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS 名稱。"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB 的 Route 53 hosted zone ID，給 alias record 用。"
  value       = aws_lb.this.zone_id
}

output "listener_arn" {
  description = "有憑證時是 HTTPS listener ARN，否則是 HTTP listener ARN。"
  value       = local.has_certificate ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

output "listener_arns" {
  description = "依協定分的 listener ARN，`{ http, https }`；`http` 一定有值，沒有憑證時 `https` 是 `null`。"
  value = {
    http  = aws_lb_listener.http.arn
    https = local.has_certificate ? aws_lb_listener.https[0].arn : null
  }
}

output "listener_rule_arns" {
  description = "key 同 `listener_rules` 的 map，值是 listener rule ARN；沒給時是空 map。"
  value       = { for k, r in aws_lb_listener_rule.this : k => r.arn }
}

output "listener_protocol" {
  description = "`listener_arn` 的協定，`HTTPS` 或 `HTTP`。"
  value       = local.has_certificate ? "HTTPS" : "HTTP"
}

output "alarm_arns" {
  description = "告警名稱對應告警 ARN 的 map，目前只有 `elb_5xx`。"
  value       = { elb_5xx = aws_cloudwatch_metric_alarm.elb_5xx.arn }
}

output "target_group_arns" {
  description = "key 同 `target_groups` 的 map，值是 target group ARN；沒給時是空 map。"
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }
}

output "target_group_arn_suffixes" {
  description = "key 同 `target_groups` 的 map，值是 `targetgroup/<name>/<id>`，給 CloudWatch dimension 用。"
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}

output "web_acl_association_ids" {
  description = "Web ACL 關聯 ID 的 list；沒有關聯時是空 list。"
  value       = aws_wafv2_web_acl_association.this[*].id
}
