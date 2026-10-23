output "arn" {
  description = "OIDC provider 的 ARN，給 `iam-role` 的 `trust.federated.oidc_provider_arn`。"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "issuer" {
  description = "issuer URL 去掉 `https://`，也就是 trust policy 裡 `<issuer>:sub`、`<issuer>:aud` 條件鍵的前綴。"
  value       = trimprefix(var.issuer_url, "https://")
}
