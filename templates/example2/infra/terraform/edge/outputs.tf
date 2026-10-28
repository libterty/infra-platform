# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "api_url" {
  description = "Public URL of the api, served by CloudFront."
  value       = "https://${local.api_domain}"
}

output "distribution_id" {
  description = "CloudFront distribution ID, for cache invalidations."
  value       = module.cdn.distribution_id
}
