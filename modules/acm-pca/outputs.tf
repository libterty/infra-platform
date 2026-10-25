output "ca_arn" {
  description = "CA 的 ARN，`iot-fleet` 註冊 CA 或簽發憑證時用。"
  value       = aws_acmpca_certificate_authority.this.arn
}

output "ca_certificate_pem" {
  description = "已安裝的 CA 憑證（PEM）：`ROOT` 是自簽憑證，`SUBORDINATE` 是 `subordinate_certificate.certificate`；還沒安裝時是 `null`。"
  value       = one(aws_acmpca_certificate_authority_certificate.this[*].certificate)
}

output "csr" {
  description = "CA 的 CSR（PEM）。`SUBORDINATE` 時拿去給上層 CA 簽。"
  value       = aws_acmpca_certificate_authority.this.certificate_signing_request
}
