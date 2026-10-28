# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_endpoint" {
  description = "HTTP API 的 execute-api 網址。只給 CloudFront 當 origin；直接呼叫會因為缺少 origin verify header 被 Lambda 回 403。"
  value       = module.api.api_endpoint
}

output "function_name" {
  description = "API Lambda 的名稱。"
  value       = module.function.function_name
}
