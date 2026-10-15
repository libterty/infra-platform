output "alb_dns_name" {
  description = "DNS name of the ALB; point a Route 53 alias or CNAME at it."
  value       = module.alb.alb_dns_name
}

output "listener_protocol" {
  description = "HTTPS or HTTP."
  value       = module.alb.listener_protocol
}
