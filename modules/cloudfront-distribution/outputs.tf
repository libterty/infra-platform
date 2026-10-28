output "distribution_id" {
  value       = aws_cloudfront_distribution.this.id
  description = "distribution ID（建立 invalidation 時用）。"
}

output "arn" {
  value       = aws_cloudfront_distribution.this.arn
  description = "distribution 的 ARN，給 `s3-bucket` 的 `cloudfront_distribution_arns` 與 `log-delivery` 的 source 用。"
}

output "domain_name" {
  value       = aws_cloudfront_distribution.this.domain_name
  description = "distribution 的網域（`*.cloudfront.net`），alias record 指向它。"
}

output "hosted_zone_id" {
  value       = aws_cloudfront_distribution.this.hosted_zone_id
  description = "CloudFront 的 hosted zone ID，給 Route 53 alias record 用。"
}

output "oac_ids" {
  value       = { for k, o in aws_cloudfront_origin_access_control.this : k => o.id }
  description = "`s3` origin 的 key 對應 OAC ID。"
}
