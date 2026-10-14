resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.name}-elb-5xx"
  alarm_description   = "HTTPCode_ELB_5XX_Count >= ${var.alarm_config.elb_5xx_threshold} within ${var.alarm_config.period} seconds (the ALB itself returned 5xx)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_config.period
  statistic           = "Sum"
  threshold           = var.alarm_config.elb_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = var.tags
}
