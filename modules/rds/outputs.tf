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
  description = "writer 的 host，不帶 port：`rds` 是 instance 的 `address`，Aurora 是 cluster `endpoint`。"
  value       = local.writer_endpoint
}

output "reader_endpoint" {
  description = "reader 的 host：`rds` 等於 `writer_endpoint`，Aurora 是 cluster 的 `reader_endpoint`。"
  value       = local.reader_endpoint
}

output "has_reader" {
  description = "至少有一個 reader 時為 `true`：`rds` 一律 `false`，Aurora 是 `reader_count > 0`。"
  value       = local.has_reader
}

output "proxy_endpoint" {
  description = "RDS Proxy 端點；沒開 Proxy 時為 `null`。"
  value       = local.proxy_endpoint
}

output "app_endpoint" {
  description = "應用程式寫入要連的 host：有 Proxy 時是 Proxy，否則是 writer。"
  value       = var.proxy == null ? local.writer_endpoint : local.proxy_endpoint
}

output "app_reader_endpoint" {
  description = "應用程式讀取要連的 host：有 Proxy read-only endpoint 用它；有 Proxy 沒有 read-only 用 Proxy；沒開 Proxy 用 `reader_endpoint`。"
  value       = local.app_reader_endpoint
}

output "port" {
  description = "PostgreSQL port（數字，`5432`）。"
  value       = local.port
}

output "master_user_secret_arn" {
  description = "RDS 管理的 master 帳號 secret 在 Secrets Manager 的 ARN。"
  value       = local.master_secret_arn
}

output "db_identifier" {
  description = "DB 識別碼：`rds` 是 instance identifier，Aurora 是 cluster identifier。"
  value       = local.is_rds ? aws_db_instance.this[0].identifier : aws_rds_cluster.this[0].cluster_identifier
}

output "identifier_type" {
  description = "識別碼型別：`instance` 或 `cluster`。"
  value       = local.identifier_type
}

output "cluster_id" {
  description = "Aurora cluster ID；`rds` 時為 `null`。"
  value       = local.is_rds ? null : aws_rds_cluster.this[0].id
}

output "instance_ids" {
  description = "instance identifier 清單，依序排列，index 0 是 writer。"
  value       = tolist(local.is_rds ? [aws_db_instance.this[0].identifier] : aws_rds_cluster_instance.this[*].identifier)
}

output "cloudwatch_dimension" {
  description = "額外告警或 dashboard 用的 dimension，形狀 `{ name, value }`；`name` 是 `DBInstanceIdentifier` 或 `DBClusterIdentifier`。"
  value       = local.cloudwatch_dimension
}

output "arn" {
  description = "instance（`rds`）或 cluster（Aurora）的 ARN。"
  value       = local.is_rds ? aws_db_instance.this[0].arn : aws_rds_cluster.this[0].arn
}

output "resource_id" {
  description = "`DbiResourceId`（`rds`）或 `DbClusterResourceId`（Aurora），給 `rds-db:connect` policy 用。"
  value       = local.is_rds ? aws_db_instance.this[0].resource_id : aws_rds_cluster.this[0].cluster_resource_id
}

output "alarm_arns" {
  description = "告警 ARN 的 map，key 是 `<alarm>[_<instance key>]`，例如 `cpu_high_writer`、`connections_high`、`proxy_pinned_high`。"
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
  description = "輸入的 `deployment` 原樣輸出：`rds`、`aurora` 或 `aurora_serverless`。"
  value       = var.deployment
}

output "database_name" {
  description = "輸入的 `database_name` 原樣輸出，也就是隨 instance 或 cluster 建立的資料庫名稱。"
  value       = var.database_name
}

output "log_group_name" {
  description = "module 建立的 PostgreSQL CloudWatch log group 名稱：`rds` 是 `/aws/rds/instance/<name>/postgresql`，Aurora 是 `/aws/rds/cluster/<name>/postgresql`（0.2.0 起）。"
  value       = aws_cloudwatch_log_group.postgresql.name
}
