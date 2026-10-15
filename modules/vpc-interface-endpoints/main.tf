data "aws_region" "current" {}

locals {
  create = length(var.services) > 0
}

resource "aws_security_group" "this" {
  count = local.create ? 1 : 0

  name        = "${var.name}-vpce"
  description = "HTTPS to interface endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

# No egress rule: interface endpoints only receive connections.
resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = local.create ? toset(var.allowed_cidrs) : toset([])

  security_group_id = aws_security_group.this[0].id
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from ${each.key}"

  tags = merge(var.tags, { Name = "${var.name}-vpce-https" })
}

resource "aws_vpc_endpoint" "this" {
  for_each = var.services

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = var.private_dns_enabled
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.this[0].id]

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
