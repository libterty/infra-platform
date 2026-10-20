# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "alb_dns_name" {
  description = "DNS name of the ALB; point the CDN origin or a Route 53 alias at it."
  value       = module.alb.alb_dns_name
}
