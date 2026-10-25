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

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

run "reads_the_network_and_foundation_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn      = "foundation/kms_key_arn"
      vpc_id           = "network/vpc_id"
      vpc_cidr         = "network/vpc_cidr"
      sg_client_vpn_id = "network/sg_client_vpn_id"
      } && local.ssm_input_lists == {
      subnet_ids_data   = "network/subnet_ids_data"
      subnet_cidrs_data = "network/subnet_cidrs_data"
    }
    error_message = "vpn must read exactly the keys of foundation and network that the client-vpn module needs"
  }
}

# client_vpn defaults to null: the stack must then create nothing and say so in the SSM contract.
run "defaults_create_no_vpn" {
  command = plan

  assert {
    condition     = var.client_vpn == null
    error_message = "client_vpn must default to null"
  }

  assert {
    condition     = length(module.client_vpn) == 0
    error_message = "With client_vpn null, the client-vpn module must not be called"
  }
}

# Design K30: example5 keeps the Client VPN only; there is no Site-to-Site VPN.
run "no_site_to_site" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "site_to_site") && !strcontains(file("${path.module}/${f}"), "vpn-site-to-site")])
    error_message = "vpn of example5 must not configure a Site-to-Site VPN"
  }
}

run "defaults_publish_disabled_markers" {
  command = plan

  assert {
    condition     = local.published_strings == { client_vpn = "{\"enabled\":false}" }
    error_message = "A VPN that is off must publish exactly {\"enabled\":false}, and client_vpn is the only key"
  }

  assert {
    condition = module.ssm_publish.names == {
      client_vpn = "/example/dev/vpn/client_vpn"
    }
    error_message = "ssm-publish must write the client_vpn key under the vpn stack path"
  }
}

run "client_vpn_on_publishes_the_endpoint" {
  command = plan

  variables {
    client_vpn = {
      server_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
      authentication         = { mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000" }
      client_cidr_block      = "10.250.0.0/22"
    }
  }

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
    error_message = "Giving client_vpn must call the client-vpn module"
  }

  assert {
    condition = jsondecode(local.published_strings["client_vpn"]) == {
      enabled     = true
      endpoint_id = "cvpn-endpoint-0123456789abcdef0"
      dns_name    = "cvpn-endpoint-0123456789abcdef0.clientvpn.example.com"
    }
    error_message = "client_vpn must publish enabled = true with the endpoint ID and DNS name"
  }
}

run "client_vpn_subnet_count_zero_rejected" {
  command = plan

  variables {
    client_vpn = {
      server_certificate_arn  = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
      authentication          = { mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000" }
      client_cidr_block       = "10.250.0.0/22"
      associated_subnet_count = 0
    }
  }

  expect_failures = [var.client_vpn]
}

run "client_vpn_subnet_count_three_rejected" {
  command = plan

  variables {
    client_vpn = {
      server_certificate_arn  = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
      authentication          = { mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000" }
      client_cidr_block       = "10.250.0.0/22"
      associated_subnet_count = 3
    }
  }

  expect_failures = [var.client_vpn]
}
# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
