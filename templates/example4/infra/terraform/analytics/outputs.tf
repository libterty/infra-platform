# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "workgroup_name" {
  description = "Athena workgroup 名稱（`<project>-<env>-analytics`）。"
  value       = module.workgroup.name
}

output "workgroup_arn" {
  description = "Athena workgroup 的 ARN。"
  value       = module.workgroup.arn
}
