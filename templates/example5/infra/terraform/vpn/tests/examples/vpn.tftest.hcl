# Run by scripts/validate.sh with -var-file=envs/examples/vpn.tfvars; it checks the example that turns the Client VPN on.
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
  values = { insecure_value = "10.40.0.0/20" }
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
  values = { insecure_value = "10.40.5.0/27,10.40.5.32/27" }
}

run "example_enables_the_client_vpn" {
  command = plan

  override_module {
    target = module.client_vpn
    outputs = {
      endpoint_id    = "cvpn-endpoint-0123456789abcdef0"
      dns_name       = "cvpn-endpoint-0123456789abcdef0.clientvpn.example.com"
      log_group_name = "/aws/client-vpn/example-dev-client-vpn"
    }
  }


  assert {
    condition     = length(module.client_vpn) == 1
    error_message = "The example must turn the Client VPN on"
  }

  assert {
    condition     = jsondecode(local.published_strings["client_vpn"]).enabled == true
    error_message = "With the example, the client_vpn key must say enabled = true"
  }
}

run "example_client_vpn_uses_mutual_tls_only" {
  command = plan

  assert {
    condition     = local.client_vpn.authentication.mutual_tls_root_certificate_arn != null && local.client_vpn.authentication.saml_provider_arn == null && local.client_vpn.authentication.self_service_saml_provider_arn == null
    error_message = "The example authenticates with mutual TLS only (SAML providers are created outside Terraform)"
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
    condition     = tolist([for r in local.client_vpn.authorization_rules : r.target_cidr]) == tolist(["10.40.5.0/27", "10.40.5.32/27"])
    error_message = "Authorization rules must be exactly the CIDRs of the data subnets"
  }

  assert {
    condition     = alltrue([for r in local.client_vpn.authorization_rules : r.target_cidr != "0.0.0.0/0" && r.target_cidr != "10.40.0.0/20" && r.access_group_id == null])
    error_message = "Clients must not be authorized to the whole VPC, the internet or by SAML group"
  }
}

run "example_client_vpn_takes_network_and_foundation_values" {
  command = plan

  assert {
    condition = (
      local.client_vpn.vpc_id == "vpc-0123456789abcdef0" &&
      tolist(local.client_vpn.vpc_cidr_blocks) == tolist(["10.40.0.0/20"]) &&
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

run "example_env_and_account_correspond" {
  command = plan

  assert {
    condition     = var.env == "dev" && var.expected_account_id == "111111111111"
    error_message = "The example uses the dev placeholders"
  }
}
