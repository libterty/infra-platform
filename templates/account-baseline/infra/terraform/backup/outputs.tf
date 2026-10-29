# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "vault_name" {
  description = "每日備份的 vault 名稱。"
  value       = module.vault.name
}

output "plan_id" {
  description = "每日備份 plan 的 ID。"
  value       = module.plan.plan_id
}
