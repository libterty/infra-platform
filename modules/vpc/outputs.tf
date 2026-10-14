output "vpc_id" {
  description = "VPC ID。"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC 的 CIDR。"
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "原樣回傳 azs，下游依這個順序對應清單。"
  value       = var.azs
}

output "subnet_ids" {
  description = "tier => 依 azs 順序的 subnet id。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].id] }
}

output "subnet_cidrs" {
  description = "tier => 依 azs 順序的 subnet CIDR。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_subnet.this["${tier}/${az}"].cidr_block] }
}

output "route_table_ids" {
  description = "tier => 依 azs 順序的 route table id。"
  value       = { for tier in keys(var.subnets) : tier => [for az in var.azs : aws_route_table.this["${tier}/${az}"].id] }
}

output "nat_gateway_ids" {
  description = "依 azs 順序的 NAT gateway id；none 時為空，single 時只有一個。"
  value       = [for az in var.azs : aws_nat_gateway.this[az].id if contains(local.nat_azs, az)]
}

output "vpce_security_group_id" {
  description = "Interface endpoint 的 SG id；沒有 interface endpoint 時為 null。"
  value       = one(aws_security_group.vpce[*].id)
}
