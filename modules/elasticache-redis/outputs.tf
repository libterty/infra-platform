output "configuration_endpoint" {
  description = "cluster mode 的 configuration endpoint。client 必須用支援 cluster mode 的 Redis client 並開 TLS。"
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}

output "port" {
  description = "cluster 監聽的 port（數字）。"
  value       = aws_elasticache_replication_group.this.port
}

output "replication_group_id" {
  description = "replication group ID。"
  value       = aws_elasticache_replication_group.this.replication_group_id
}

output "member_clusters" {
  description = "AWS 回報的 member cluster ID 清單，已排序。"
  value       = sort(tolist(aws_elasticache_replication_group.this.member_clusters))
}

output "arn" {
  description = "replication group ARN。"
  value       = aws_elasticache_replication_group.this.arn
}

output "log_group_names" {
  description = "log group 名稱的 map，key 是 `slow_log`、`engine_log`。"
  value = {
    slow_log   = aws_cloudwatch_log_group.slow_log.name
    engine_log = aws_cloudwatch_log_group.engine_log.name
  }
}

output "alarm_arns" {
  description = "告警名稱對 ARN 的 map，包含每個 member 的 memory 告警與（有設門檻時的）evictions 告警。"
  value = merge(
    { for a in aws_cloudwatch_metric_alarm.memory_high : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.evictions_high : a.alarm_name => a.arn },
  )
}
