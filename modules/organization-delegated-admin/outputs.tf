output "delegated_admin_account_id" {
  description = "被委派的帳號 ID。"
  value       = var.delegated_admin_account_id
}

output "trusted_service_principals" {
  description = "開了 trusted access 的 service principal 清單（已排序）。"
  value       = sort([for p, _ in aws_organizations_aws_service_access.this : p])
}
