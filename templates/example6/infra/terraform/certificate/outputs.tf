# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "web_certificate_arn" {
  description = "CloudFront 用的憑證（us-east-1），名稱是 `app.<env 的網域>`。"
  value       = module.web_certificate.certificate_arn
}
