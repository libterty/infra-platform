output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "azs as given; downstream lists follow this order."
  value       = var.azs
}

output "subnet_ids" {
  description = "tier => subnet IDs in azs order."
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].id] }
}

output "subnet_cidrs" {
  description = "tier => subnet CIDRs in azs order."
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].cidr_block] }
}

output "route_table_ids" {
  description = "tier => route table IDs in azs order."
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_route_table.this["${tier}/${az}"].id] }
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs in azs order; empty for none, one entry for single."
  value       = [for az in var.azs : aws_nat_gateway.this[az].id if contains(local.nat_azs, az)]
}
