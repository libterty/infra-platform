output "configuration_endpoint" {
  description = "Cluster mode configuration endpoint. Clients must use a cluster-aware Redis client with TLS."
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}

output "port" {
  description = "Port the cluster listens on."
  value       = aws_elasticache_replication_group.this.port
}

output "replication_group_id" {
  description = "Replication group id."
  value       = aws_elasticache_replication_group.this.replication_group_id
}

output "member_clusters" {
  description = "Member cluster ids as reported by AWS, sorted."
  value       = sort(tolist(aws_elasticache_replication_group.this.member_clusters))
}

output "arn" {
  description = "Replication group ARN."
  value       = aws_elasticache_replication_group.this.arn
}

output "log_group_names" {
  description = "Names of the slow log and engine log groups."
  value = {
    slow_log   = aws_cloudwatch_log_group.slow_log.name
    engine_log = aws_cloudwatch_log_group.engine_log.name
  }
}

output "alarm_arns" {
  description = "Alarm ARNs keyed by alarm name."
  value = merge(
    { for a in aws_cloudwatch_metric_alarm.memory_high : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.evictions_high : a.alarm_name => a.arn },
  )
}
