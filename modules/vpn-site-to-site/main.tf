locals {
  # The customer ASN goes into bgp_asn up to 2147483647 and into bgp_asn_extended above it (provider split).
  customer_asn          = var.customer_gateway.bgp_asn
  customer_asn_extended = local.customer_asn != null && local.customer_asn > 2147483647

  # Prefix keeps the log group clear of the 5120-character CloudWatch Logs resource policy limit (AWS Site-to-Site VPN logs doc).
  log_group_name = "/aws/vendedlogs/vpn/${var.name}"
  bgp_logs       = !var.routing.static_routes_only
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

resource "aws_customer_gateway" "this" {
  type        = "ipsec.1"
  ip_address  = var.customer_gateway.ip_address
  device_name = var.customer_gateway.device_name

  bgp_asn          = local.customer_asn == null || local.customer_asn_extended ? null : tostring(local.customer_asn)
  bgp_asn_extended = local.customer_asn_extended ? tostring(local.customer_asn) : null

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_vpn_gateway" "this" {
  count = var.vpn_gateway == null ? 0 : 1

  vpc_id          = var.vpc_id
  amazon_side_asn = var.vpn_gateway.amazon_side_asn == null ? null : tostring(var.vpn_gateway.amazon_side_asn)

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_vpn_connection" "this" {
  customer_gateway_id = aws_customer_gateway.this.id
  type                = "ipsec.1"

  vpn_gateway_id     = one(aws_vpn_gateway.this[*].id)
  transit_gateway_id = var.transit_gateway_id
  static_routes_only = var.routing.static_routes_only

  # The pre-shared key is generated and kept by the Site-to-Site VPN service in Secrets Manager. The module never sets
  # tunnelN_preshared_key, so no key goes through Terraform; Standard storage would keep it as plain text in the state.
  preshared_key_storage = "SecretsManager"

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = var.tunnel_options.phase1_encryption_algorithms
  tunnel1_phase1_integrity_algorithms  = var.tunnel_options.phase1_integrity_algorithms
  tunnel1_phase1_dh_group_numbers      = var.tunnel_options.phase1_dh_group_numbers
  tunnel1_phase1_lifetime_seconds      = var.tunnel_options.phase1_lifetime_seconds
  tunnel1_phase2_encryption_algorithms = var.tunnel_options.phase2_encryption_algorithms
  tunnel1_phase2_integrity_algorithms  = var.tunnel_options.phase2_integrity_algorithms
  tunnel1_phase2_dh_group_numbers      = var.tunnel_options.phase2_dh_group_numbers
  tunnel1_phase2_lifetime_seconds      = var.tunnel_options.phase2_lifetime_seconds

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = var.tunnel_options.phase1_encryption_algorithms
  tunnel2_phase1_integrity_algorithms  = var.tunnel_options.phase1_integrity_algorithms
  tunnel2_phase1_dh_group_numbers      = var.tunnel_options.phase1_dh_group_numbers
  tunnel2_phase1_lifetime_seconds      = var.tunnel_options.phase1_lifetime_seconds
  tunnel2_phase2_encryption_algorithms = var.tunnel_options.phase2_encryption_algorithms
  tunnel2_phase2_integrity_algorithms  = var.tunnel_options.phase2_integrity_algorithms
  tunnel2_phase2_dh_group_numbers      = var.tunnel_options.phase2_dh_group_numbers
  tunnel2_phase2_lifetime_seconds      = var.tunnel_options.phase2_lifetime_seconds

  # Tunnel activity logs are not optional: both tunnels write to the module's encrypted log group.
  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.this.arn
      log_output_format = "json"

      bgp_log_enabled       = local.bgp_logs
      bgp_log_group_arn     = local.bgp_logs ? aws_cloudwatch_log_group.this.arn : null
      bgp_log_output_format = local.bgp_logs ? "json" : null
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.this.arn
      log_output_format = "json"

      bgp_log_enabled       = local.bgp_logs
      bgp_log_group_arn     = local.bgp_logs ? aws_cloudwatch_log_group.this.arn : null
      bgp_log_output_format = local.bgp_logs ? "json" : null
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_vpn_connection_route" "this" {
  for_each = toset(var.routing.static_routes)

  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = each.value
}

resource "aws_vpn_gateway_route_propagation" "this" {
  count = length(var.propagate_route_table_ids)

  vpn_gateway_id = aws_vpn_gateway.this[0].id
  route_table_id = var.propagate_route_table_ids[count.index]
}
