output "nlb_arn" {
  description = "NLB ARN。"
  value       = aws_lb.this.arn
}

output "nlb_arn_suffix" {
  description = "`net/<name>/<id>`，CloudWatch 的 `LoadBalancer` 維度。"
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "NLB DNS 名稱。"
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "NLB 的 Route 53 hosted zone ID，給 alias record 用。"
  value       = aws_lb.this.zone_id
}

output "listener_arns" {
  description = "key 同 `listeners` 的 map，值是 listener ARN；沒給時是空 map。"
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "target_group_arns" {
  description = "key 同 `target_groups` 的 map，值是 target group ARN。"
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }
}

output "target_group_arn_suffixes" {
  description = "key 同 `target_groups` 的 map，值是 `targetgroup/<name>/<id>`，給 CloudWatch dimension 用。"
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}

output "alarm_arns" {
  description = "key 同 `target_groups` 的 map，值是 `UnHealthyHostCount` 告警 ARN。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.unhealthy_hosts : k => a.arn }
}
