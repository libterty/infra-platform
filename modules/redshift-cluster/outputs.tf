output "endpoint_address" {
  description = "cluster 的連線 DNS 位址（VPC 內）。"
  value       = aws_redshift_cluster.this.dns_name
}

output "port" {
  description = "cluster 的連線埠。"
  value       = aws_redshift_cluster.this.port
}

output "database_name" {
  description = "cluster 的第一個資料庫名稱。"
  value       = aws_redshift_cluster.this.database_name
}

output "admin_secret_arn" {
  description = "Redshift 代管的管理者帳密 secret 的 ARN（Secrets Manager）。"
  value       = aws_redshift_cluster.this.master_password_secret_arn
}

output "cluster_identifier" {
  description = "cluster 識別名稱。"
  value       = aws_redshift_cluster.this.cluster_identifier
}

output "arn" {
  description = "cluster 的 ARN。"
  value       = aws_redshift_cluster.this.arn
}
