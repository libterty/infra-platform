output "vpc_id" {
  description = "VPC ID。"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR。"
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "原樣回傳 `azs`；其他輸出的 list 都照這個順序。"
  value       = var.azs
}

output "subnet_ids" {
  description = "tier 對應 subnet ID 的 map，值是依 `azs` 順序的 list。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].id] }
}

output "subnet_cidrs" {
  description = "tier 對應 subnet CIDR 的 map，值是依 `azs` 順序的 list。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].cidr_block] }
}

output "route_table_ids" {
  description = "tier 對應 route table ID 的 map，值是依 `azs` 順序的 list。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_route_table.this["${tier}/${az}"].id] }
}

output "nat_gateway_ids" {
  description = "依 `azs` 順序的 NAT gateway ID list；`none` 時是 `[]`，`single` 時只有 1 個。"
  value       = [for az in var.azs : aws_nat_gateway.this[az].id if contains(local.nat_azs, az)]
}
