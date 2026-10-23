output "policy_names" {
  description = "已附加的 inline policy 名稱清單。"
  value       = keys(aws_iam_role_policy.this)
}

output "role_name" {
  description = "從 `role_arn` 取出的 role 名稱。"
  value       = local.role_name
}
