# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "issuer_url" {
  description = "token 的 issuer，`api` stack 的 JWT authorizer 用它。"
  value       = module.user_pool.issuer_url
}

output "spa_client_id" {
  description = "SPA 的 client ID（public client，沒有 secret），前端設定用。"
  value       = module.user_pool.client_ids["spa"]
}

output "hosted_ui_url" {
  description = "hosted UI 的網址，前端登入時導向這裡。"
  value       = module.user_pool.hosted_ui_url
}
