# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "web_url" {
  description = "前端的網址（CloudFront 預設網域）。"
  value       = "https://${module.cdn.domain_name}"
}
