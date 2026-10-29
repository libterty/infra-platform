output "arn" {
  description = "trail 的 ARN，KMS key policy 的 `kms:EncryptionContext:aws:cloudtrail:arn` 條件與 bucket policy 的 `aws:SourceArn` 用。"
  value       = aws_cloudtrail.this.arn
}

output "name" {
  description = "trail 名稱。"
  value       = aws_cloudtrail.this.name
}

output "home_region" {
  description = "trail 建立所在的 region。"
  value       = aws_cloudtrail.this.home_region
}
