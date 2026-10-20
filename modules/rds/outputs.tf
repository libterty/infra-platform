locals {
  writer_endpoint   = local.is_rds ? aws_db_instance.this[0].address : aws_rds_cluster.this[0].endpoint
  reader_endpoint   = local.is_rds ? aws_db_instance.this[0].address : aws_rds_cluster.this[0].reader_endpoint
  proxy_endpoint    = one(aws_db_proxy.this[*].endpoint)
  proxy_ro_endpoint = one(aws_db_proxy_endpoint.read_only[*].endpoint)

  app_reader_endpoint = (
    var.proxy == null ? local.reader_endpoint :
    local.proxy_ro_endpoint != null ? local.proxy_ro_endpoint :
    local.proxy_endpoint
  )
}

output "writer_endpoint" {
  description = "Writer host without port: instance address for rds, cluster endpoint for Aurora."
  value       = local.writer_endpoint
}

output "reader_endpoint" {
  description = "Reader host: same as writer_endpoint for rds, cluster reader endpoint for Aurora."
  value       = local.reader_endpoint
}

output "has_reader" {
  description = "true when the database has at least one reader (Aurora with reader_count > 0)."
  value       = local.has_reader
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint, null without a Proxy."
  value       = local.proxy_endpoint
}

output "app_endpoint" {
  description = "Host the application should connect to for writes: the Proxy when enabled, else the writer."
  value       = var.proxy == null ? local.writer_endpoint : local.proxy_endpoint
}

output "app_reader_endpoint" {
  description = "Host the application should connect to for reads: Proxy read-only endpoint, else Proxy, else reader_endpoint."
  value       = local.app_reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master user secret."
  value       = local.master_secret_arn
}

output "db_identifier" {
  description = "DB instance identifier (rds) or cluster identifier (Aurora)."
  value       = local.is_rds ? aws_db_instance.this[0].identifier : aws_rds_cluster.this[0].cluster_identifier
}

output "identifier_type" {
  description = "\"instance\" or \"cluster\"."
  value       = local.identifier_type
}

output "cluster_id" {
  description = "Aurora cluster id, null for rds."
  value       = local.is_rds ? null : aws_rds_cluster.this[0].id
}

output "instance_ids" {
  description = "Instance identifiers in order; index 0 is the writer."
  value       = tolist(local.is_rds ? [aws_db_instance.this[0].identifier] : aws_rds_cluster_instance.this[*].identifier)
}

output "cloudwatch_dimension" {
  description = "Dimension for extra alarms or dashboards: { name = DBInstanceIdentifier | DBClusterIdentifier, value = ... }."
  value       = local.cloudwatch_dimension
}

output "arn" {
  description = "ARN of the instance (rds) or cluster (Aurora)."
  value       = local.is_rds ? aws_db_instance.this[0].arn : aws_rds_cluster.this[0].arn
}

output "resource_id" {
  description = "DbiResourceId (rds) or DbClusterResourceId (Aurora), used in rds-db:connect policies."
  value       = local.is_rds ? aws_db_instance.this[0].resource_id : aws_rds_cluster.this[0].cluster_resource_id
}

output "alarm_arns" {
  description = "Alarm ARNs keyed by <alarm>[_<instance key>]."
  value = merge(
    { for k, a in aws_cloudwatch_metric_alarm.cpu_high : "cpu_high_${k}" => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.freeable_memory_low : "freeable_memory_low_${k}" => a.arn },
    { connections_high = aws_cloudwatch_metric_alarm.connections_high.arn },
    { for a in aws_cloudwatch_metric_alarm.replica_lag_high : "replica_lag_high" => a.arn },
    { for a in aws_cloudwatch_metric_alarm.proxy_borrowed_high : "proxy_borrowed_high" => a.arn },
    { for a in aws_cloudwatch_metric_alarm.proxy_pinned_high : "proxy_pinned_high" => a.arn },
  )
}

output "deployment" {
  description = "Deployment type as given: rds, aurora or aurora_serverless."
  value       = var.deployment
}

output "database_name" {
  description = "Name of the database created with the instance or cluster."
  value       = var.database_name
}

output "log_group_name" {
  description = "Name of the PostgreSQL CloudWatch log group the module creates."
  value       = aws_cloudwatch_log_group.postgresql.name
}
