mock_provider "aws" {}

override_resource {
  target          = aws_cloudwatch_log_group.this
  override_during = plan
  values = {
    arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/vpn/alpha-dev-onprem"
  }
}

override_resource {
  target          = aws_vpn_gateway.this
  override_during = plan
  values = {
    id = "vgw-0123456789abcdef0"
  }
}

override_resource {
  target          = aws_vpn_connection.this
  override_during = plan
  values = {
    id                = "vpn-0123456789abcdef0"
    preshared_key_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:s2svpn/vpn-0123456789abcdef0-AbCdEf"
    tunnel1_address   = "203.0.113.10"
    tunnel2_address   = "203.0.113.20"
  }
}

# Defaults describe a VPN Gateway connection with static routes, the common case for a customer device without BGP.
variables {
  name        = "alpha-dev-onprem"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  vpc_id      = "vpc-0123456789abcdef0"
  vpn_gateway = {}
  customer_gateway = {
    ip_address = "198.51.100.10"
  }
  routing = {
    static_routes_only = true
    static_routes      = ["192.168.10.0/24"]
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "vgw_with_static_routes" {
  command = plan

  assert {
    condition     = length(aws_vpn_gateway.this) == 1 && aws_vpn_gateway.this[0].vpc_id == "vpc-0123456789abcdef0"
    error_message = "VGW mode must create a virtual private gateway attached to the VPC"
  }

  assert {
    condition     = aws_vpn_connection.this.vpn_gateway_id == "vgw-0123456789abcdef0" && aws_vpn_connection.this.transit_gateway_id == null
    error_message = "The connection must terminate on the virtual private gateway only"
  }

  assert {
    condition     = aws_vpn_connection.this.static_routes_only == true
    error_message = "Static routing must set static_routes_only"
  }

  assert {
    condition     = keys(aws_vpn_connection_route.this) == ["192.168.10.0/24"]
    error_message = "Each static route must become a connection route"
  }

  assert {
    condition     = aws_vpn_connection.this.type == "ipsec.1"
    error_message = "The connection type must be ipsec.1"
  }

  assert {
    condition     = aws_customer_gateway.this.ip_address == "198.51.100.10" && aws_customer_gateway.this.type == "ipsec.1"
    error_message = "The customer gateway must use the given address"
  }
}

run "vgw_amazon_side_asn_is_passed_through" {
  command = plan

  variables {
    vpn_gateway = { amazon_side_asn = 64513 }
  }

  assert {
    condition     = aws_vpn_gateway.this[0].amazon_side_asn == "64513"
    error_message = "amazon_side_asn must be passed to the virtual private gateway"
  }
}

run "vgw_route_propagation" {
  command = plan

  variables {
    propagate_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0fedcba9876543210"]
  }

  assert {
    condition     = length(aws_vpn_gateway_route_propagation.this) == 2
    error_message = "Every route table must get a propagation"
  }

  assert {
    condition     = aws_vpn_gateway_route_propagation.this[0].route_table_id == "rtb-0123456789abcdef0" && aws_vpn_gateway_route_propagation.this[0].vpn_gateway_id == "vgw-0123456789abcdef0"
    error_message = "Propagation must point the route table at the module's virtual private gateway"
  }
}

run "no_propagation_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpn_gateway_route_propagation.this) == 0
    error_message = "No propagation without propagate_route_table_ids"
  }
}

run "tgw_with_bgp" {
  command = plan

  variables {
    vpc_id             = null
    vpn_gateway        = null
    transit_gateway_id = "tgw-0123456789abcdef0"
    customer_gateway = {
      ip_address = "198.51.100.10"
      bgp_asn    = 65010
    }
    routing = {}
  }

  assert {
    condition     = length(aws_vpn_gateway.this) == 0
    error_message = "TGW mode must not create a virtual private gateway"
  }

  assert {
    condition     = aws_vpn_connection.this.transit_gateway_id == "tgw-0123456789abcdef0" && aws_vpn_connection.this.vpn_gateway_id == null
    error_message = "The connection must terminate on the transit gateway only"
  }

  assert {
    condition     = aws_vpn_connection.this.static_routes_only == false
    error_message = "Dynamic routing must not set static_routes_only"
  }

  assert {
    condition     = aws_customer_gateway.this.bgp_asn == "65010"
    error_message = "The customer BGP ASN must be passed through"
  }

  assert {
    condition     = length(aws_vpn_connection_route.this) == 0
    error_message = "A BGP connection has no static routes"
  }

  assert {
    condition     = output.vpn_gateway_id == null
    error_message = "vpn_gateway_id must be null in TGW mode"
  }
}

run "tgw_32bit_customer_asn_uses_extended_attribute" {
  command = plan

  variables {
    vpc_id             = null
    vpn_gateway        = null
    transit_gateway_id = "tgw-0123456789abcdef0"
    customer_gateway = {
      ip_address = "198.51.100.10"
      bgp_asn    = 4200000001
    }
    routing = {}
  }

  assert {
    condition     = aws_customer_gateway.this.bgp_asn == null && aws_customer_gateway.this.bgp_asn_extended == "4200000001"
    error_message = "ASNs above 2147483647 must use bgp_asn_extended"
  }
}

run "psk_is_stored_in_secrets_manager" {
  command = plan

  assert {
    condition     = aws_vpn_connection.this.preshared_key_storage == "SecretsManager"
    error_message = "The pre-shared key must live in Secrets Manager, never in state"
  }

  assert {
    condition     = output.preshared_key_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:s2svpn/vpn-0123456789abcdef0-AbCdEf"
    error_message = "preshared_key_secret_arn must expose the managed secret"
  }
}

run "tunnel_logs_are_on_for_both_tunnels" {
  command = plan

  assert {
    condition     = aws_vpn_connection.this.tunnel1_log_options[0].cloudwatch_log_options[0].log_enabled == true && aws_vpn_connection.this.tunnel2_log_options[0].cloudwatch_log_options[0].log_enabled == true
    error_message = "Tunnel activity logs must be on for both tunnels"
  }

  assert {
    condition = (
      aws_vpn_connection.this.tunnel1_log_options[0].cloudwatch_log_options[0].log_group_arn == aws_cloudwatch_log_group.this.arn &&
      aws_vpn_connection.this.tunnel2_log_options[0].cloudwatch_log_options[0].log_group_arn == aws_cloudwatch_log_group.this.arn
    )
    error_message = "Both tunnels must log to the module's log group"
  }

  assert {
    condition     = aws_vpn_connection.this.tunnel1_log_options[0].cloudwatch_log_options[0].bgp_log_enabled == false
    error_message = "A static connection has no BGP session to log"
  }
}

run "bgp_connection_also_logs_bgp" {
  command = plan

  variables {
    customer_gateway = {
      ip_address = "198.51.100.10"
      bgp_asn    = 65010
    }
    routing = {}
  }

  assert {
    condition     = aws_vpn_connection.this.tunnel1_log_options[0].cloudwatch_log_options[0].bgp_log_enabled == true && aws_vpn_connection.this.tunnel2_log_options[0].cloudwatch_log_options[0].bgp_log_enabled == true
    error_message = "A BGP connection must log BGP status on both tunnels"
  }
}

run "log_group_is_encrypted_with_the_given_key" {
  command = plan

  variables {
    log_retention_days = 365
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The log group must use the key given as input"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "log_retention_days must be passed through"
  }

  assert {
    condition     = startswith(aws_cloudwatch_log_group.this.name, "/aws/vendedlogs/")
    error_message = "The log group must sit under /aws/vendedlogs/ to stay clear of the CloudWatch Logs resource policy size limit"
  }
}

run "default_tunnel_options_are_strong" {
  command = plan

  assert {
    condition     = aws_vpn_connection.this.tunnel1_ike_versions == toset(["ikev2"]) && aws_vpn_connection.this.tunnel2_ike_versions == toset(["ikev2"])
    error_message = "Only IKEv2 may be negotiated"
  }

  assert {
    condition     = !contains(aws_vpn_connection.this.tunnel1_phase1_integrity_algorithms, "SHA1") && !contains(aws_vpn_connection.this.tunnel1_phase2_integrity_algorithms, "SHA1")
    error_message = "SHA1 must not be offered"
  }

  assert {
    condition     = alltrue([for g in concat(tolist(aws_vpn_connection.this.tunnel1_phase1_dh_group_numbers), tolist(aws_vpn_connection.this.tunnel1_phase2_dh_group_numbers), tolist(aws_vpn_connection.this.tunnel2_phase1_dh_group_numbers), tolist(aws_vpn_connection.this.tunnel2_phase2_dh_group_numbers)) : g >= 14])
    error_message = "DH groups 2 and 5 must not be offered"
  }

  assert {
    condition     = aws_vpn_connection.this.tunnel1_phase1_lifetime_seconds == 28800 && aws_vpn_connection.this.tunnel1_phase2_lifetime_seconds == 3600
    error_message = "Lifetimes must default to the AWS defaults"
  }
}

run "tunnel_options_apply_to_both_tunnels" {
  command = plan

  variables {
    tunnel_options = {
      phase1_encryption_algorithms = ["AES256-GCM-16"]
      phase1_integrity_algorithms  = ["SHA2-384"]
      phase1_dh_group_numbers      = [20]
      phase2_encryption_algorithms = ["AES256-GCM-16"]
      phase2_integrity_algorithms  = ["SHA2-256"]
      phase2_dh_group_numbers      = [19]
      phase1_lifetime_seconds      = 14400
      phase2_lifetime_seconds      = 1800
    }
  }

  assert {
    condition = (
      aws_vpn_connection.this.tunnel1_phase1_encryption_algorithms == toset(["AES256-GCM-16"]) &&
      aws_vpn_connection.this.tunnel2_phase1_encryption_algorithms == toset(["AES256-GCM-16"]) &&
      aws_vpn_connection.this.tunnel1_phase1_integrity_algorithms == toset(["SHA2-384"]) &&
      aws_vpn_connection.this.tunnel2_phase1_integrity_algorithms == toset(["SHA2-384"]) &&
      aws_vpn_connection.this.tunnel1_phase1_dh_group_numbers == toset([20]) &&
      aws_vpn_connection.this.tunnel2_phase2_dh_group_numbers == toset([19]) &&
      aws_vpn_connection.this.tunnel2_phase2_integrity_algorithms == toset(["SHA2-256"]) &&
      aws_vpn_connection.this.tunnel1_phase1_lifetime_seconds == 14400 &&
      aws_vpn_connection.this.tunnel2_phase2_lifetime_seconds == 1800
    )
    error_message = "Tunnel options must apply to both tunnels"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.vpn_connection_id == "vpn-0123456789abcdef0"
    error_message = "vpn_connection_id must be the connection ID"
  }

  assert {
    condition     = output.tunnel_addresses == ["203.0.113.10", "203.0.113.20"]
    error_message = "tunnel_addresses must list tunnel 1 then tunnel 2"
  }

  assert {
    condition     = output.vpn_gateway_id == "vgw-0123456789abcdef0"
    error_message = "vpn_gateway_id must be the module's gateway in VGW mode"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_vpn_connection.this.tags["Project"] == "alpha" && aws_vpn_connection.this.tags["Name"] == "alpha-dev-onprem"
    error_message = "Name must be added to the given tags"
  }
}

# ---- negative: endpoint ---------------------------------------------------------------------------------------

run "vgw_and_tgw_together_are_rejected" {
  command = plan

  variables {
    transit_gateway_id = "tgw-0123456789abcdef0"
    customer_gateway   = { ip_address = "198.51.100.10", bgp_asn = 65010 }
    routing            = {}
  }

  expect_failures = [var.vpn_gateway]
}

run "neither_vgw_nor_tgw_is_rejected" {
  command = plan

  variables {
    vpc_id      = null
    vpn_gateway = null
  }

  expect_failures = [var.vpn_gateway]
}

run "vgw_without_vpc_is_rejected" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [var.vpc_id]
}

run "tgw_with_vpc_is_rejected" {
  command = plan

  variables {
    vpn_gateway        = null
    transit_gateway_id = "tgw-0123456789abcdef0"
    customer_gateway   = { ip_address = "198.51.100.10", bgp_asn = 65010 }
    routing            = {}
  }

  expect_failures = [var.vpc_id]
}

run "bad_transit_gateway_id_is_rejected" {
  command = plan

  variables {
    vpc_id             = null
    vpn_gateway        = null
    transit_gateway_id = "tgw-xyz"
    customer_gateway   = { ip_address = "198.51.100.10", bgp_asn = 65010 }
    routing            = {}
  }

  expect_failures = [var.transit_gateway_id]
}

run "bad_vpc_id_is_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-xyz"
  }

  expect_failures = [var.vpc_id]
}

# ---- negative: BGP ASN ----------------------------------------------------------------------------------------

run "amazon_side_asn_in_public_range_is_rejected" {
  command = plan

  variables {
    vpn_gateway = { amazon_side_asn = 65535 }
  }

  expect_failures = [var.vpn_gateway]
}

run "amazon_side_asn_32bit_private_range_is_accepted" {
  command = plan

  variables {
    vpn_gateway = { amazon_side_asn = 4200000000 }
  }

  assert {
    condition     = aws_vpn_gateway.this[0].amazon_side_asn == "4200000000"
    error_message = "A 32-bit private ASN is valid on the Amazon side"
  }
}

run "customer_asn_zero_is_rejected" {
  command = plan

  variables {
    customer_gateway = { ip_address = "198.51.100.10", bgp_asn = 0 }
  }

  expect_failures = [var.customer_gateway]
}

run "customer_asn_above_32bit_is_rejected" {
  command = plan

  variables {
    customer_gateway = { ip_address = "198.51.100.10", bgp_asn = 4294967296 }
  }

  expect_failures = [var.customer_gateway]
}

run "customer_asn_7224_is_rejected" {
  command = plan

  variables {
    customer_gateway = { ip_address = "198.51.100.10", bgp_asn = 7224 }
  }

  expect_failures = [var.customer_gateway]
}

run "bad_customer_ip_is_rejected" {
  command = plan

  variables {
    customer_gateway = { ip_address = "198.51.100.300" }
  }

  expect_failures = [var.customer_gateway]
}

# ---- negative: routing ----------------------------------------------------------------------------------------

run "bgp_without_customer_asn_is_rejected" {
  command = plan

  variables {
    routing = {}
  }

  expect_failures = [var.routing]
}

run "static_without_routes_on_vgw_is_rejected" {
  command = plan

  variables {
    routing = { static_routes_only = true }
  }

  expect_failures = [var.routing]
}

run "routes_without_static_only_are_rejected" {
  command = plan

  variables {
    customer_gateway = { ip_address = "198.51.100.10", bgp_asn = 65010 }
    routing          = { static_routes = ["192.168.10.0/24"] }
  }

  expect_failures = [var.routing]
}

run "static_routes_on_tgw_are_rejected" {
  command = plan

  variables {
    vpc_id             = null
    vpn_gateway        = null
    transit_gateway_id = "tgw-0123456789abcdef0"
  }

  expect_failures = [var.routing]
}

run "malformed_static_route_is_rejected" {
  command = plan

  variables {
    routing = { static_routes_only = true, static_routes = ["192.168.10.0/33"] }
  }

  expect_failures = [var.routing]
}

run "static_route_with_host_bits_is_rejected" {
  command = plan

  variables {
    routing = { static_routes_only = true, static_routes = ["192.168.10.5/24"] }
  }

  expect_failures = [var.routing]
}

run "default_static_route_is_rejected" {
  command = plan

  variables {
    routing = { static_routes_only = true, static_routes = ["0.0.0.0/0"] }
  }

  expect_failures = [var.routing]
}

run "duplicate_static_routes_are_rejected" {
  command = plan

  variables {
    routing = { static_routes_only = true, static_routes = ["192.168.10.0/24", "192.168.10.0/24"] }
  }

  expect_failures = [var.routing]
}

run "propagation_on_tgw_is_rejected" {
  command = plan

  variables {
    vpc_id                    = null
    vpn_gateway               = null
    transit_gateway_id        = "tgw-0123456789abcdef0"
    customer_gateway          = { ip_address = "198.51.100.10", bgp_asn = 65010 }
    routing                   = {}
    propagate_route_table_ids = ["rtb-0123456789abcdef0"]
  }

  expect_failures = [var.propagate_route_table_ids]
}

run "bad_route_table_id_is_rejected" {
  command = plan

  variables {
    propagate_route_table_ids = ["rtb-xyz"]
  }

  expect_failures = [var.propagate_route_table_ids]
}

run "duplicate_route_table_ids_are_rejected" {
  command = plan

  variables {
    propagate_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef0"]
  }

  expect_failures = [var.propagate_route_table_ids]
}

# ---- negative: weak tunnel parameters -------------------------------------------------------------------------

run "sha1_integrity_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase1_integrity_algorithms = ["SHA1", "SHA2-256"] }
  }

  expect_failures = [var.tunnel_options]
}

run "sha1_phase2_integrity_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase2_integrity_algorithms = ["SHA1"] }
  }

  expect_failures = [var.tunnel_options]
}

run "dh_group_2_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase1_dh_group_numbers = [2, 14] }
  }

  expect_failures = [var.tunnel_options]
}

run "dh_group_5_in_phase2_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase2_dh_group_numbers = [5] }
  }

  expect_failures = [var.tunnel_options]
}

run "unknown_encryption_algorithm_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase1_encryption_algorithms = ["3DES"] }
  }

  expect_failures = [var.tunnel_options]
}

run "empty_algorithm_list_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase2_encryption_algorithms = [] }
  }

  expect_failures = [var.tunnel_options]
}

run "phase1_lifetime_out_of_range_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase1_lifetime_seconds = 28801 }
  }

  expect_failures = [var.tunnel_options]
}

run "phase2_lifetime_out_of_range_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase2_lifetime_seconds = 899 }
  }

  expect_failures = [var.tunnel_options]
}

run "phase2_lifetime_not_below_phase1_is_rejected" {
  command = plan

  variables {
    tunnel_options = { phase1_lifetime_seconds = 3600, phase2_lifetime_seconds = 3600 }
  }

  expect_failures = [var.tunnel_options]
}

# ---- negative: names and logs ---------------------------------------------------------------------------------

run "bad_name_is_rejected" {
  command = plan

  variables {
    name = "Alpha_Dev"
  }

  expect_failures = [var.name]
}

run "bad_kms_key_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/alpha"
  }

  expect_failures = [var.kms_key_arn]
}

run "bad_retention_is_rejected" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}
