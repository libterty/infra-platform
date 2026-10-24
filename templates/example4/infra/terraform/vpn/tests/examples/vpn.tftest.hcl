# Run by scripts/validate.sh with -var-file=envs/examples/vpn.tfvars; it checks the example that turns the VPNs on.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_cidr"]
  values = { insecure_value = "10.30.0.0/20" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_client_vpn_id"]
  values = { insecure_value = "sg-0aaaaaaa00000005" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_cidrs_data"]
  values = { insecure_value = "10.30.5.0/27,10.30.5.32/27" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/route_table_ids_private"]
  values = { insecure_value = "rtb-0aaa0001,rtb-0aaa0002,rtb-0ddd0001,rtb-0ddd0002" }
}
run "example_enables_both_vpns" {
  command = plan

  override_module {
    target = module.client_vpn
    outputs = {
      endpoint_id    = "cvpn-endpoint-0123456789abcdef0"
      dns_name       = "cvpn-endpoint-0123456789abcdef0.clientvpn.example.com"
      log_group_name = "/aws/client-vpn/example-dev-client-vpn"
    }
  }

  override_module {
    target = module.site_to_site
    outputs = {
      vpn_connection_id        = "vpn-0123456789abcdef0"
      tunnel_addresses         = ["198.51.100.1", "198.51.100.2"]
      preshared_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-psk-AbCdEf"
      vpn_gateway_id           = "vgw-0123456789abcdef0"
      log_group_name           = "/aws/vpn/example-dev-site-to-site"
    }
  }

  assert {
    condition     = length(module.client_vpn) == 1 && length(module.site_to_site) == 1
    error_message = "The example must turn both VPNs on"
  }

  assert {
    condition     = jsondecode(local.published_strings["client_vpn"]).enabled == true && jsondecode(local.published_strings["site_to_site"]).enabled == true
    error_message = "With the example, both SSM keys must say enabled = true"
  }
}

run "example_client_vpn_uses_mutual_tls_only" {
  command = plan

  assert {
    condition     = local.client_vpn.authentication.mutual_tls_root_certificate_arn != null && local.client_vpn.authentication.saml_provider_arn == null && local.client_vpn.authentication.self_service_saml_provider_arn == null
    error_message = "The example authenticates with mutual TLS only (design D8: SAML providers are created outside Terraform)"
  }
}

run "example_client_vpn_has_one_subnet_association" {
  command = plan

  assert {
    condition     = tolist(local.client_vpn.subnet_ids) == tolist(["subnet-0dda0001"])
    error_message = "The example associates exactly one data subnet (the first one)"
  }
}

run "example_client_vpn_authorizes_only_the_data_subnets" {
  command = plan

  assert {
    condition     = tolist([for r in local.client_vpn.authorization_rules : r.target_cidr]) == tolist(["10.30.5.0/27", "10.30.5.32/27"])
    error_message = "Authorization rules must be exactly the CIDRs of the data subnets"
  }

  assert {
    condition     = alltrue([for r in local.client_vpn.authorization_rules : r.target_cidr != "0.0.0.0/0" && r.target_cidr != "10.30.0.0/20" && r.access_group_id == null])
    error_message = "Clients must not be authorized to the whole VPC, the internet or by SAML group"
  }
}

run "example_client_vpn_takes_network_and_foundation_values" {
  command = plan

  assert {
    condition = (
      local.client_vpn.vpc_id == "vpc-0123456789abcdef0" &&
      tolist(local.client_vpn.vpc_cidr_blocks) == tolist(["10.30.0.0/20"]) &&
      tolist(local.client_vpn.security_group_ids) == tolist(["sg-0aaaaaaa00000005"]) &&
      local.client_vpn.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    )
    error_message = "Client VPN must use the VPC, its CIDR, the client VPN security group and the shared key published by earlier stacks"
  }

  assert {
    condition     = local.client_vpn.name == "example-dev-client-vpn"
    error_message = "The endpoint name must be <name_prefix>-client-vpn"
  }
}

run "example_client_vpn_module_receives_every_setting" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "kms_key_arn", "server_certificate_arn", "authentication", "client_cidr_block", "vpc_id", "vpc_cidr_blocks", "subnet_ids", "security_group_ids", "authorization_rules", "session_timeout_hours", "dns_servers", "log_retention_days"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*local\\.client_vpn\\.${f}\\s*$", file("${path.module}/client-vpn.tf"))) == 1
    ])
    error_message = "The client-vpn module call must take every input from local.client_vpn"
  }
}

run "example_site_to_site_uses_a_new_vgw_on_the_vpc" {
  command = plan

  assert {
    condition = (
      local.site_to_site.vpc_id == "vpc-0123456789abcdef0" &&
      length(keys(local.site_to_site.vpn_gateway)) == 0 &&
      local.site_to_site.customer_gateway.ip_address == "203.0.113.10" &&
      local.site_to_site.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" &&
      local.site_to_site.name == "example-dev-site-to-site"
    )
    error_message = "Site-to-Site must create a virtual private gateway on the network VPC, use the shared key and name <name_prefix>-site-to-site"
  }

  assert {
    condition     = tolist(local.site_to_site.propagate_route_table_ids) == tolist(["rtb-0aaa0001", "rtb-0aaa0002", "rtb-0ddd0001", "rtb-0ddd0002"])
    error_message = "Route propagation must be on for every private route table of the VPC"
  }
}

run "example_site_to_site_module_receives_every_setting" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "kms_key_arn", "vpc_id", "vpn_gateway", "customer_gateway", "routing", "propagate_route_table_ids", "log_retention_days"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*local\\.site_to_site\\.${f}\\s*$", file("${path.module}/site-to-site.tf"))) == 1
    ])
    error_message = "The vpn-site-to-site module call must take every input from local.site_to_site"
  }
}

run "example_env_and_account_correspond" {
  command = plan

  assert {
    condition     = var.env == "dev" && var.expected_account_id == "111111111111"
    error_message = "The example uses the dev placeholders"
  }
}
