data "aws_region" "current" {}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_route_table_keys : aws_route_table.this[k].id]

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
