output "user_pool_id" {
  description = "user pool 的 ID。"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "user pool 的 ARN。"
  value       = aws_cognito_user_pool.this.arn
}

output "issuer_url" {
  description = "token 的 issuer（`https://cognito-idp.<region>.amazonaws.com/<pool id>`），給 `apigateway-http` 的 JWT authorizer。"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "client_ids" {
  description = "client 名稱對應 client ID，給 JWT authorizer 的 `audience` 與前端設定。"
  value       = { for k, c in aws_cognito_user_pool_client.this : k => c.id }
}

output "hosted_ui_url" {
  description = "hosted UI 的網址（`https://<domain_prefix>.auth.<region>.amazoncognito.com`）。"
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}
