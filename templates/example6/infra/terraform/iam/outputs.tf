# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_role_arn" {
  description = "API Lambda 的 execution role。"
  value       = module.api_role.arn
}
