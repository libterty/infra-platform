output "thing_type_arns" {
  description = "thing type 名稱 → ARN。"
  value       = { for k, t in aws_iot_thing_type.this : k => t.arn }
}

output "thing_group_arns" {
  description = "thing group 名稱 → ARN（所有層級）。"
  value = merge(
    { for k, g in aws_iot_thing_group.level_0 : k => g.arn },
    { for k, g in aws_iot_thing_group.level_1 : k => g.arn },
    { for k, g in aws_iot_thing_group.level_2 : k => g.arn },
    { for k, g in aws_iot_thing_group.level_3 : k => g.arn },
  )
}

output "policy_names" {
  description = "`policies` 的 key → IoT policy 名稱。"
  value       = { for k, p in aws_iot_policy.this : k => p.name }
}

output "role_alias_arn" {
  description = "role alias 的 ARN；沒建時是 `null`。"
  value       = one(aws_iot_role_alias.this[*].arn)
}

output "provisioning_template_name" {
  description = "fleet provisioning template 名稱；沒建時是 `null`。"
  value       = one(aws_iot_provisioning_template.this[*].name)
}

output "ca_certificate_id" {
  description = "註冊的 CA 憑證 ID；沒註冊時是 `null`。"
  value       = one(aws_iot_ca_certificate.this[*].id)
}
