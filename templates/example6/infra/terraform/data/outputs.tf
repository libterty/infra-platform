# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "table_name" {
  description = "應用程式的 DynamoDB table 名稱。"
  value       = module.table.table_name
}
