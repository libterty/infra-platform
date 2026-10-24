mock_provider "aws" {}

override_resource {
  target          = aws_ec2_client_vpn_endpoint.this
  override_during = plan
  values = {
    id       = "cvpn-endpoint-0123456789abcdef0"
    dns_name = "cvpn-endpoint-0123456789abcdef0.prod.clientvpn.ap-northeast-1.amazonaws.com"
  }
}

# Defaults describe the standard endpoint: mutual TLS, split tunnel, one subnet, access to the data subnets only.
variables {
  name                   = "alpha-dev-vpn"
  kms_key_arn            = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  server_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  authentication = {
    mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
  }
  client_cidr_block  = "10.250.0.0/22"
  vpc_id             = "vpc-0123456789abcdef0"
  vpc_cidr_blocks    = ["10.30.0.0/20"]
  subnet_ids         = ["subnet-0123456789abcdef0"]
  security_group_ids = ["sg-0123456789abcdef0"]
  authorization_rules = [
    { target_cidr = "10.30.8.0/22", description = "data subnets" },
  ]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "mutual_tls" {
  command = plan

  assert {
    condition     = toset([for a in aws_ec2_client_vpn_endpoint.this.authentication_options : a.type]) == toset(["certificate-authentication"])
    error_message = "Mutual TLS alone must be the only authentication option"
  }

  assert {
    condition     = one(aws_ec2_client_vpn_endpoint.this.authentication_options).root_certificate_chain_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
    error_message = "The client root certificate must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.server_certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
    error_message = "The server certificate must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.self_service_portal == "disabled"
    error_message = "The self-service portal must stay off without a self-service SAML provider"
  }
}

run "saml_with_group_authorization" {
  command = plan

  variables {
    authentication = {
      saml_provider_arn = "arn:aws:iam::111111111111:saml-provider/example-idp"
    }
    authorization_rules = [
      { target_cidr = "10.30.8.0/22", access_group_id = "data-engineers" },
    ]
  }

  assert {
    condition     = toset([for a in aws_ec2_client_vpn_endpoint.this.authentication_options : a.type]) == toset(["federated-authentication"])
    error_message = "SAML alone must be the only authentication option"
  }

  assert {
    condition     = one(aws_ec2_client_vpn_endpoint.this.authentication_options).saml_provider_arn == "arn:aws:iam::111111111111:saml-provider/example-idp"
    error_message = "The SAML provider must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_authorization_rule.this[0].access_group_id == "data-engineers" && aws_ec2_client_vpn_authorization_rule.this[0].authorize_all_groups == null
    error_message = "A group rule must name the group and must not authorize all groups"
  }
}

run "mutual_tls_and_saml_together" {
  command = plan

  variables {
    authentication = {
      mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
      saml_provider_arn               = "arn:aws:iam::111111111111:saml-provider/example-idp"
    }
  }

  assert {
    condition     = toset([for a in aws_ec2_client_vpn_endpoint.this.authentication_options : a.type]) == toset(["certificate-authentication", "federated-authentication"])
    error_message = "Both options must be set when both are given"
  }

  assert {
    condition     = length(aws_ec2_client_vpn_endpoint.this.authentication_options) == 2
    error_message = "Exactly two authentication options are expected"
  }
}

run "self_service_portal_follows_the_self_service_provider" {
  command = plan

  variables {
    authentication = {
      saml_provider_arn              = "arn:aws:iam::111111111111:saml-provider/example-idp"
      self_service_saml_provider_arn = "arn:aws:iam::111111111111:saml-provider/example-portal"
    }
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.self_service_portal == "enabled" && one(aws_ec2_client_vpn_endpoint.this.authentication_options).self_service_saml_provider_arn == "arn:aws:iam::111111111111:saml-provider/example-portal"
    error_message = "A self-service SAML provider must enable the portal and be passed through"
  }
}

run "split_tunnel_is_the_default" {
  command = plan

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.split_tunnel == true
    error_message = "split_tunnel must default to true"
  }
}

run "full_tunnel_with_explicit_internet_access" {
  command = plan

  variables {
    split_tunnel          = false
    allow_internet_access = true
    authorization_rules = [
      { target_cidr = "10.30.8.0/22" },
      { target_cidr = "0.0.0.0/0" },
    ]
    routes = [
      { destination_cidr = "0.0.0.0/0", target_subnet_id = "subnet-0123456789abcdef0" },
    ]
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.split_tunnel == false
    error_message = "split_tunnel = false must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_authorization_rule.this[1].target_network_cidr == "0.0.0.0/0" && aws_ec2_client_vpn_route.this[0].destination_cidr_block == "0.0.0.0/0"
    error_message = "The default route and its authorization must be created when explicitly allowed"
  }
}

run "connection_log_is_always_on_and_encrypted" {
  command = plan

  variables {
    log_retention_days = 365
  }

  assert {
    condition     = one(aws_ec2_client_vpn_endpoint.this.connection_log_options).enabled == true
    error_message = "Connection logging must be on"
  }

  assert {
    condition     = one(aws_ec2_client_vpn_endpoint.this.connection_log_options).cloudwatch_log_group == aws_cloudwatch_log_group.this.name
    error_message = "Connection logs must go to the module's log group"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The log group must use the key given as input"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365 && aws_cloudwatch_log_group.this.name == "/aws/client-vpn/alpha-dev-vpn"
    error_message = "Retention must be passed through and the log group named after the endpoint"
  }
}

run "fixed_protocol_and_port" {
  command = plan

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.transport_protocol == "udp" && aws_ec2_client_vpn_endpoint.this.vpn_port == 443
    error_message = "The endpoint must use UDP 443"
  }
}

run "endpoint_network_settings" {
  command = plan

  variables {
    dns_servers           = ["10.30.0.2"]
    session_timeout_hours = 8
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.client_cidr_block == "10.250.0.0/22" && aws_ec2_client_vpn_endpoint.this.vpc_id == "vpc-0123456789abcdef0"
    error_message = "client CIDR and VPC must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "The given security groups must be applied"
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.dns_servers == tolist(["10.30.0.2"]) && aws_ec2_client_vpn_endpoint.this.session_timeout_hours == 8
    error_message = "DNS servers and session timeout must be passed through"
  }
}

run "session_timeout_defaults_to_twelve_hours" {
  command = plan

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.session_timeout_hours == 12
    error_message = "session_timeout_hours must default to 12"
  }
}

run "network_associations_one_per_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  }

  assert {
    condition     = length(aws_ec2_client_vpn_network_association.this) == 2
    error_message = "Every subnet needs an association"
  }

  assert {
    condition     = aws_ec2_client_vpn_network_association.this[0].subnet_id == "subnet-0123456789abcdef0" && aws_ec2_client_vpn_network_association.this[1].subnet_id == "subnet-0fedcba9876543210"
    error_message = "Associations must follow the subnet order"
  }

  assert {
    condition     = aws_ec2_client_vpn_network_association.this[0].client_vpn_endpoint_id == "cvpn-endpoint-0123456789abcdef0"
    error_message = "Associations must point at the module's endpoint"
  }
}

run "authorization_rule_for_all_groups" {
  command = plan

  assert {
    condition     = length(aws_ec2_client_vpn_authorization_rule.this) == 1
    error_message = "One rule per entry"
  }

  assert {
    condition     = aws_ec2_client_vpn_authorization_rule.this[0].target_network_cidr == "10.30.8.0/22" && aws_ec2_client_vpn_authorization_rule.this[0].authorize_all_groups == true && aws_ec2_client_vpn_authorization_rule.this[0].access_group_id == null
    error_message = "A rule without a group must authorize all groups"
  }

  assert {
    condition     = aws_ec2_client_vpn_authorization_rule.this[0].client_vpn_endpoint_id == "cvpn-endpoint-0123456789abcdef0"
    error_message = "Rules must point at the module's endpoint"
  }
}

run "route_to_an_associated_subnet" {
  command = plan

  variables {
    routes = [
      { destination_cidr = "192.168.10.0/24", target_subnet_id = "subnet-0123456789abcdef0", description = "on-premises" },
    ]
  }

  assert {
    condition     = length(aws_ec2_client_vpn_route.this) == 1 && aws_ec2_client_vpn_route.this[0].destination_cidr_block == "192.168.10.0/24" && aws_ec2_client_vpn_route.this[0].target_vpc_subnet_id == "subnet-0123456789abcdef0"
    error_message = "The route must be passed through"
  }

  assert {
    condition     = aws_ec2_client_vpn_route.this[0].client_vpn_endpoint_id == "cvpn-endpoint-0123456789abcdef0"
    error_message = "Routes must point at the module's endpoint"
  }
}

run "no_rules_or_routes_by_default" {
  command = plan

  variables {
    authorization_rules = []
  }

  assert {
    condition     = length(aws_ec2_client_vpn_authorization_rule.this) == 0 && length(aws_ec2_client_vpn_route.this) == 0
    error_message = "No rules or routes unless given"
  }
}

run "client_cidr_boundaries_are_accepted" {
  command = plan

  variables {
    client_cidr_block = "172.16.0.0/12"
    vpc_cidr_blocks   = ["10.30.0.0/20"]
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.client_cidr_block == "172.16.0.0/12"
    error_message = "/12 is the largest accepted client CIDR"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.endpoint_id == "cvpn-endpoint-0123456789abcdef0"
    error_message = "endpoint_id must be the endpoint ID"
  }

  assert {
    condition     = output.dns_name == "cvpn-endpoint-0123456789abcdef0.prod.clientvpn.ap-northeast-1.amazonaws.com"
    error_message = "dns_name must be the endpoint DNS name"
  }

  assert {
    condition     = output.log_group_name == "/aws/client-vpn/alpha-dev-vpn"
    error_message = "log_group_name must be the connection log group"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.tags["Project"] == "alpha" && aws_ec2_client_vpn_endpoint.this.tags["Name"] == "alpha-dev-vpn"
    error_message = "Name must be added to the given tags"
  }
}

# ---- negative: authentication ---------------------------------------------------------------------------------

run "no_authentication_method_is_rejected" {
  command = plan

  variables {
    authentication = {}
  }

  expect_failures = [var.authentication]
}

run "self_service_without_saml_is_rejected" {
  command = plan

  variables {
    authentication = {
      mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
      self_service_saml_provider_arn  = "arn:aws:iam::111111111111:saml-provider/example-portal"
    }
  }

  expect_failures = [var.authentication]
}

run "root_certificate_must_be_an_acm_arn" {
  command = plan

  variables {
    authentication = {
      mutual_tls_root_certificate_arn = "-----BEGIN CERTIFICATE-----"
    }
  }

  expect_failures = [var.authentication]
}

run "saml_provider_must_be_an_iam_saml_arn" {
  command = plan

  variables {
    authentication = {
      saml_provider_arn = "arn:aws:iam::111111111111:role/example"
    }
  }

  expect_failures = [var.authentication]
}

run "server_certificate_must_be_an_acm_arn" {
  command = plan

  variables {
    server_certificate_arn = "server.crt"
  }

  expect_failures = [var.server_certificate_arn]
}

# ---- negative: authorization and routes -----------------------------------------------------------------------

run "group_without_saml_is_rejected" {
  command = plan

  variables {
    authorization_rules = [
      { target_cidr = "10.30.8.0/22", access_group_id = "data-engineers" },
    ]
  }

  expect_failures = [var.authorization_rules]
}

run "default_authorization_is_rejected_with_split_tunnel" {
  command = plan

  variables {
    authorization_rules = [{ target_cidr = "0.0.0.0/0" }]
  }

  expect_failures = [var.authorization_rules]
}

run "default_authorization_is_rejected_without_explicit_allow" {
  command = plan

  variables {
    split_tunnel        = false
    authorization_rules = [{ target_cidr = "0.0.0.0/0" }]
  }

  expect_failures = [var.authorization_rules]
}

run "default_route_is_rejected_with_split_tunnel" {
  command = plan

  variables {
    routes = [{ destination_cidr = "0.0.0.0/0", target_subnet_id = "subnet-0123456789abcdef0" }]
  }

  expect_failures = [var.routes]
}

run "default_route_is_rejected_without_explicit_allow" {
  command = plan

  variables {
    split_tunnel = false
    routes       = [{ destination_cidr = "0.0.0.0/0", target_subnet_id = "subnet-0123456789abcdef0" }]
  }

  expect_failures = [var.routes]
}

run "internet_access_flag_needs_full_tunnel" {
  command = plan

  variables {
    allow_internet_access = true
  }

  expect_failures = [var.allow_internet_access]
}

run "malformed_authorization_cidr_is_rejected" {
  command = plan

  variables {
    authorization_rules = [{ target_cidr = "10.30.8.0/33" }]
  }

  expect_failures = [var.authorization_rules]
}

run "authorization_cidr_with_host_bits_is_rejected" {
  command = plan

  variables {
    authorization_rules = [{ target_cidr = "10.30.8.5/22" }]
  }

  expect_failures = [var.authorization_rules]
}

run "duplicate_authorization_rules_are_rejected" {
  command = plan

  variables {
    authorization_rules = [
      { target_cidr = "10.30.8.0/22" },
      { target_cidr = "10.30.8.0/22" },
    ]
  }

  expect_failures = [var.authorization_rules]
}

run "malformed_route_cidr_is_rejected" {
  command = plan

  variables {
    routes = [{ destination_cidr = "192.168.10.0/99", target_subnet_id = "subnet-0123456789abcdef0" }]
  }

  expect_failures = [var.routes]
}

run "route_to_a_subnet_without_association_is_rejected" {
  command = plan

  variables {
    routes = [{ destination_cidr = "192.168.10.0/24", target_subnet_id = "subnet-0fedcba9876543210" }]
  }

  expect_failures = [var.routes]
}

# ---- negative: client CIDR ------------------------------------------------------------------------------------

run "client_cidr_smaller_than_22_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.250.0.0/23"
  }

  expect_failures = [var.client_cidr_block]
}

run "client_cidr_larger_than_12_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.0.0.0/11"
  }

  expect_failures = [var.client_cidr_block]
}

run "malformed_client_cidr_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.250.0.0"
  }

  expect_failures = [var.client_cidr_block]
}

run "client_cidr_with_host_bits_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.250.1.0/22"
  }

  expect_failures = [var.client_cidr_block]
}

run "client_cidr_overlapping_the_vpc_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.30.0.0/22"
  }

  expect_failures = [var.client_cidr_block]
}

run "client_cidr_containing_the_vpc_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.16.0.0/12"
    vpc_cidr_blocks   = ["10.30.0.0/20"]
  }

  expect_failures = [var.client_cidr_block]
}

run "client_cidr_overlapping_a_secondary_vpc_cidr_is_rejected" {
  command = plan

  variables {
    client_cidr_block = "10.250.0.0/22"
    vpc_cidr_blocks   = ["10.30.0.0/20", "10.250.0.0/16"]
  }

  expect_failures = [var.client_cidr_block]
}

run "empty_vpc_cidr_list_is_rejected" {
  command = plan

  variables {
    vpc_cidr_blocks = []
  }

  expect_failures = [var.vpc_cidr_blocks]
}

# ---- negative: network and misc -------------------------------------------------------------------------------

run "no_subnet_is_rejected" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "bad_subnet_id_is_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-xyz"]
  }

  expect_failures = [var.subnet_ids]
}

run "duplicate_subnet_ids_are_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "no_security_group_is_rejected" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "bad_security_group_id_is_rejected" {
  command = plan

  variables {
    security_group_ids = ["default"]
  }

  expect_failures = [var.security_group_ids]
}

run "bad_vpc_id_is_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-xyz"
  }

  expect_failures = [var.vpc_id]
}

run "session_timeout_outside_the_allowed_set_is_rejected" {
  command = plan

  variables {
    session_timeout_hours = 16
  }

  expect_failures = [var.session_timeout_hours]
}

run "three_dns_servers_are_rejected" {
  command = plan

  variables {
    dns_servers = ["10.30.0.2", "10.30.0.3", "10.30.0.4"]
  }

  expect_failures = [var.dns_servers]
}

run "bad_dns_server_is_rejected" {
  command = plan

  variables {
    dns_servers = ["dns.example.com"]
  }

  expect_failures = [var.dns_servers]
}

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
