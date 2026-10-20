locals {
  # Keyed by route table index plus CIDR: route table IDs may be unknown at plan time and cannot be for_each keys.
  routes = {
    for pair in setproduct(range(length(var.route_table_ids)), var.peer_cidrs) :
    "${pair[0]}-${pair[1]}" => { index = pair[0], cidr = pair[1] }
  }
}

# Requester side only. The peer account must accept the request in its own account.
resource "aws_vpc_peering_connection" "this" {
  vpc_id        = var.vpc_id
  peer_vpc_id   = var.peer_vpc_id
  peer_owner_id = var.peer_owner_id
  peer_region   = var.peer_region
  auto_accept   = false

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_route" "this" {
  for_each = local.routes

  route_table_id            = var.route_table_ids[each.value.index]
  destination_cidr_block    = each.value.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
