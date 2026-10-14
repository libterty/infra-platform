data "aws_region" "current" {}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_route_table_keys : aws_route_table.this[k].id]

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_security_group" "vpce" {
  count = var.interface_endpoints == null ? 0 : 1

  name        = "${var.name}-vpce"
  description = "HTTPS from the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  count = var.interface_endpoints == null ? 0 : 1

  security_group_id = aws_security_group.vpce[0].id
  cidr_ipv4         = var.cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from the VPC CIDR"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints == null ? toset([]) : var.interface_endpoints.services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for az in var.azs : aws_subnet.this["${var.interface_endpoints.subnet_tier}/${az}"].id]
  security_group_ids  = [aws_security_group.vpce[0].id]

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
