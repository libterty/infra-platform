resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = each.value.name
  description = each.value.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = each.value.name })
}

# Rules are standalone resources, never inline: an inline ingress or egress block makes Terraform
# authoritative for the whole group and silently deletes rules added outside Terraform.
# Keys come straight from var.rules so adding or removing a rule never re-addresses the others.
resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for k, r in var.rules : k => r if r.type == "ingress" }

  security_group_id            = aws_security_group.this[each.value.security_group].id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port != null ? each.value.to_port : each.value.from_port
  referenced_security_group_id = each.value.peer_group != null ? aws_security_group.this[each.value.peer_group].id : each.value.peer_group_id
  cidr_ipv4                    = each.value.cidr_ipv4
  prefix_list_id               = each.value.prefix_list_id

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for k, r in var.rules : k => r if r.type == "egress" }

  security_group_id            = aws_security_group.this[each.value.security_group].id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port != null ? each.value.to_port : each.value.from_port
  referenced_security_group_id = each.value.peer_group != null ? aws_security_group.this[each.value.peer_group].id : each.value.peer_group_id
  cidr_ipv4                    = each.value.cidr_ipv4
  prefix_list_id               = each.value.prefix_list_id

  tags = merge(var.tags, { Name = each.key })
}
