output "endpoint_address" {
  description = "workgroup 的連線 DNS 位址（VPC 內）。"
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].address
}

output "port" {
  description = "workgroup 的連線埠。"
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].port
}

output "database_name" {
  description = "namespace 的第一個資料庫名稱。"
  value       = aws_redshiftserverless_namespace.this.db_name
}

output "admin_secret_arn" {
  description = "Redshift 代管的管理者帳密 secret 的 ARN（Secrets Manager）。"
  value       = aws_redshiftserverless_namespace.this.admin_password_secret_arn
}

output "namespace_name" {
  description = "namespace 名稱。"
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "workgroup_name" {
  description = "workgroup 名稱。"
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_arn" {
  description = "workgroup 的 ARN。"
  value       = aws_redshiftserverless_workgroup.this.arn
}
