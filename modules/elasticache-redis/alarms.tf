resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = toset(local.member_ids)

  alarm_name          = "${each.key}-memory-high"
  alarm_description   = "DatabaseMemoryUsagePercentage of ${each.key} is at or above ${var.alarm_config.memory_percent}%."
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = { CacheClusterId = each.key }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarm_config.memory_percent
  treat_missing_data  = "missing"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${each.key}-memory-high" })

  lifecycle {
    # The member ids are derived from the naming rule, so check them against what AWS really created.
    # Without autoscaling the sets must be equal. With autoscaling the shard count moves on its own,
    # so only require that the derived ids still overlap the real members.
    precondition {
      condition = (
        var.autoscaling == null
        ? toset(local.member_ids) == aws_elasticache_replication_group.this.member_clusters
        : length(setintersection(toset(local.member_ids), aws_elasticache_replication_group.this.member_clusters)) > 0
      )
      error_message = "The member cluster ids derived from name, num_node_groups and replicas_per_node_group do not match the replication group's member_clusters. Changing num_node_groups after creation is not applied (ignore_changes); recreate the group or use autoscaling."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "evictions_high" {
  for_each = var.alarm_config.evictions_threshold == null ? toset([]) : toset(local.member_ids)

  alarm_name          = "${each.key}-evictions-high"
  alarm_description   = "Evictions of ${each.key} are at or above ${var.alarm_config.evictions_threshold} in 5 minutes."
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  dimensions          = { CacheClusterId = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarm_config.evictions_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${each.key}-evictions-high" })
}
