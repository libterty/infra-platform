# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "vpc_id" {
  description = "VPC ID。"
  value       = module.vpc.vpc_id
}

output "app_subnet_ids" {
  description = "app tier 的 subnet ID，依 `azs` 的順序；ECS task 與內部 ALB 放在這裡。"
  value       = module.vpc.subnet_ids["app"]
}
