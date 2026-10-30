# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "alb_dns_name" {
  description = "內部 ALB 的 DNS 名稱，只能從 VPC 內連線。"
  value       = module.alb.alb_dns_name
}
