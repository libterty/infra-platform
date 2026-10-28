output "certificate_arn" {
  description = "憑證 ARN，取自驗證完成的 resource，所以拿到時憑證已經簽發，可以直接給 ALB listener 或 CloudFront。"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "憑證的主要名稱。"
  value       = aws_acm_certificate.this.domain_name
}
