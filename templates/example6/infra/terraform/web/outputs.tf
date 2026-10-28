# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "app_url" {
  description = "前端與 API 共用的網址；API 在 `/api/` 底下。"
  value       = "https://${local.app_domain}"
}

output "site_bucket_name" {
  description = "放前端檔案的 bucket。"
  value       = module.site_bucket.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution ID，更新前端後建立 invalidation 用。"
  value       = module.cdn.distribution_id
}
