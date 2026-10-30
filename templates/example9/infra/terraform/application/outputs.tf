# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_service_name" {
  description = "api 的 ECS service 名稱。"
  value       = module.api.service_name
}

output "fn_alias_arn" {
  description = "fn 函式 alias `live` 的 ARN；呼叫端要指到這個 alias。"
  value       = module.fn.alias_arn
}
