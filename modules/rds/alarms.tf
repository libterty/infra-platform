locals {
  # Serverless: 80% of max_connections, which Aurora derives from the ACU memory (2 GiB per ACU), capped at 5000.
  connections_threshold = (
    var.alarm_config.connections_threshold != null ? var.alarm_config.connections_threshold :
    local.is_serverless ? floor(min(var.serverless.max_capacity * 2 * 1073741824 / 9531392, 5000) * 0.8) :
    null
  )

  cloudwatch_dimension = {
    name  = local.is_rds ? "DBInstanceIdentifier" : "DBClusterIdentifier"
    value = var.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.instances

  alarm_name          = "${var.name}-cpu-high-${each.key}"
  alarm_description   = "CPUUtilization of ${each.value} is at or above ${var.alarm_config.cpu_threshold}%."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarm_config.cpu_threshold
  treat_missing_data  = "missing"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${var.name}-cpu-high-${each.key}" })
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  for_each = local.instances

  alarm_name          = "${var.name}-freeable-memory-low-${each.key}"
  alarm_description   = "FreeableMemory of ${each.value} is at or below ${var.alarm_config.freeable_memory_bytes} bytes for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = each.value }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 15
  datapoints_to_alarm = 15
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = var.alarm_config.freeable_memory_bytes
  treat_missing_data  = "breaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${var.name}-freeable-memory-low-${each.key}" })
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.name}-connections-high"
  alarm_description   = "DatabaseConnections of ${var.name} is at or above ${local.connections_threshold}."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { (local.cloudwatch_dimension.name) = local.cloudwatch_dimension.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.connections_threshold
  treat_missing_data  = "missing"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${var.name}-connections-high" })
}

resource "aws_cloudwatch_metric_alarm" "replica_lag_high" {
  count = local.has_reader ? 1 : 0

  alarm_name          = "${var.name}-replica-lag-high"
  alarm_description   = "AuroraReplicaLag of ${var.name} is at or above ${var.alarm_config.replica_lag_threshold_ms} ms."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  dimensions          = { DBClusterIdentifier = var.name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarm_config.replica_lag_threshold_ms
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${var.name}-replica-lag-high" })
}

resource "aws_cloudwatch_metric_alarm" "proxy_borrowed_high" {
  count = var.proxy != null ? 1 : 0

  alarm_name          = "${var.name}-proxy-borrowed-high"
  alarm_description   = "Borrowed backend connections are above ${var.alarm_config.proxy_borrowed_percent}% of the allowed maximum."
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_config.proxy_borrowed_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  metric_query {
    id          = "pct"
    expression  = "100 * borrowed / MAX(allowed)"
    label       = "Borrowed as % of MaxDatabaseConnectionsAllowed"
    return_data = true
  }

  metric_query {
    id = "borrowed"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "DatabaseConnectionsCurrentlyBorrowed"
      dimensions  = { ProxyName = aws_db_proxy.this[0].name }
      period      = 60
      stat        = "Maximum"
    }
  }

  metric_query {
    id = "allowed"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "MaxDatabaseConnectionsAllowed"
      dimensions  = { ProxyName = aws_db_proxy.this[0].name }
      period      = 60
      stat        = "Maximum"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-proxy-borrowed-high" })
}

resource "aws_cloudwatch_metric_alarm" "proxy_pinned_high" {
  count = var.proxy != null ? 1 : 0

  alarm_name          = "${var.name}-proxy-pinned-high"
  alarm_description   = "Session-pinned connections are above ${var.alarm_config.proxy_pinned_percent}% of the allowed maximum; pinning defeats connection multiplexing."
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_config.proxy_pinned_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  metric_query {
    id          = "pct"
    expression  = "100 * pinned / MAX(allowed)"
    label       = "Session-pinned as % of MaxDatabaseConnectionsAllowed"
    return_data = true
  }

  metric_query {
    id = "pinned"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "DatabaseConnectionsCurrentlySessionPinned"
      dimensions  = { ProxyName = aws_db_proxy.this[0].name }
      period      = 60
      stat        = "Maximum"
    }
  }

  metric_query {
    id = "allowed"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "MaxDatabaseConnectionsAllowed"
      dimensions  = { ProxyName = aws_db_proxy.this[0].name }
      period      = 60
      stat        = "Maximum"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-proxy-pinned-high" })
}
