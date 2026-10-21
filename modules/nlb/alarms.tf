# Missing data means the target group has no registered target (nothing can be unhealthy), so it must not alarm.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = var.target_groups

  alarm_name          = "${var.name}-${each.key}-unhealthy-hosts"
  alarm_description   = "UnHealthyHostCount > 0 in target group ${var.name}-${each.key} within 60 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  dimensions = {
    TargetGroup  = aws_lb_target_group.this[each.key].arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = var.tags
}
