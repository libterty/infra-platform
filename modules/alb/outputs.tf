output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "app/<name>/<id>; the CloudWatch dimension and the requests_per_target resource label."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB, for alias records."
  value       = aws_lb.this.zone_id
}

output "listener_arn" {
  description = "HTTPS listener when a certificate is given, otherwise the HTTP listener."
  value       = local.has_certificate ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

output "listener_arns" {
  description = "Listener ARNs by protocol: http is always set, https is null without a certificate."
  value = {
    http  = aws_lb_listener.http.arn
    https = local.has_certificate ? aws_lb_listener.https[0].arn : null
  }
}

output "listener_rule_arns" {
  description = "Listener rule ARNs keyed by the listener_rules key."
  value       = { for k, r in aws_lb_listener_rule.this : k => r.arn }
}

output "listener_protocol" {
  description = "HTTPS or HTTP, the protocol of listener_arn."
  value       = local.has_certificate ? "HTTPS" : "HTTP"
}

output "alarm_arns" {
  description = "ALB alarm ARNs keyed by alarm."
  value       = { elb_5xx = aws_cloudwatch_metric_alarm.elb_5xx.arn }
}

output "target_group_arns" {
  description = "Target group ARNs keyed by the target_groups key."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }
}

output "target_group_arn_suffixes" {
  description = "targetgroup/<name>/<id> keyed by the target_groups key, for CloudWatch dimensions."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}

output "web_acl_association_ids" {
  description = "Web ACL association IDs; empty when no Web ACL is associated."
  value       = aws_wafv2_web_acl_association.this[*].id
}
