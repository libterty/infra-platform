output "nlb_arn" {
  description = "NLB ARN."
  value       = aws_lb.this.arn
}

output "nlb_arn_suffix" {
  description = "net/<name>/<id>; the CloudWatch LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "NLB DNS name."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route 53 hosted zone ID of the NLB, for alias records."
  value       = aws_lb.this.zone_id
}

output "listener_arns" {
  description = "Listener ARNs keyed by the listeners key."
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "target_group_arns" {
  description = "Target group ARNs keyed by the target_groups key."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }
}

output "target_group_arn_suffixes" {
  description = "targetgroup/<name>/<id> keyed by the target_groups key, for CloudWatch dimensions."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}

output "alarm_arns" {
  description = "UnHealthyHostCount alarm ARNs keyed by the target_groups key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.unhealthy_hosts : k => a.arn }
}
