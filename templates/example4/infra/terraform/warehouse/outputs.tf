# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "warehouse_mode" {
  description = "目前的 Redshift 型態：serverless 或 provisioned。"
  value       = local.warehouse.mode
}

output "endpoint" {
  description = "Redshift 連線位址與埠號。"
  value       = "${local.warehouse.host}:${local.warehouse.port}"
}

output "admin_secret_arn" {
  description = "Redshift 管理者密碼所在的 Secrets Manager secret ARN（密碼由服務代管）。"
  value       = local.warehouse.admin_secret_arn
}
