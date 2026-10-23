output "strings" {
  description = "`String` 參數的值，key 為本地名稱。"
  value       = { for name, path in var.strings : name => data.aws_ssm_parameter.this[path].insecure_value }
}

output "lists" {
  description = "`StringList` 參數以逗號切開的清單，key 為本地名稱。"
  value       = { for name, path in var.lists : name => split(",", data.aws_ssm_parameter.this[path].insecure_value) }
}
