# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "ism_policy_ids" {
  description = "ISM policy id。"
  value       = module.config.ism_policy_ids
}

output "writer_role_names" {
  description = "寫入用 FGAC role 的名稱。"
  value       = module.config.writer_role_names
}
