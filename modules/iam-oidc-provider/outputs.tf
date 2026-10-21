output "arn" {
  description = "ARN of the OIDC provider. Use it as trust.federated.oidc_provider_arn of the iam-role module."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "issuer" {
  description = "Issuer URL without https://, the prefix of the :sub and :aud condition keys in a trust policy."
  value       = trimprefix(var.issuer_url, "https://")
}
