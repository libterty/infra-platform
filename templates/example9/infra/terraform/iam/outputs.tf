# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_arns" {
  description = "各 role 的 ARN，key 是元件或建置專案。"
  value       = { for k, m in module.role : k => m.arn }
}
