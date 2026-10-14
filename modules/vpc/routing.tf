resource "aws_route_table" "this" {
  for_each = local.subnets

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-${each.value.tier}-${each.value.az}" })
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this["${local.public_tier}/${each.key}"].id

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "public_igw" {
  for_each = { for k, s in local.subnets : k => s if s.type == "public" }

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "private_nat" {
  for_each = { for k, s in local.subnets : k => s if s.type == "private" && length(local.nat_azs) > 0 }

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_mode == "single" ? var.azs[0] : each.value.az].id
}
