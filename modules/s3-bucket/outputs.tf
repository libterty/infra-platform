output "bucket_name" {
  description = "bucket 名稱。"
  value       = aws_s3_bucket.this.bucket
}

output "arn" {
  description = "bucket 的 ARN。"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "bucket 的 regional domain name。"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
