# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation and network publish.
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
run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

# Design section 7.5: both VPNs are off in dev and sit; envs/examples/vpn.tfvars shows how to turn them on.
run "tfvars_leave_both_vpns_off" {
  command = plan

  assert {
    condition     = var.client_vpn == null && var.site_to_site == null
    error_message = "dev and sit tfvars must not enable either VPN"
  }

  assert {
    condition     = length(module.client_vpn) == 0 && length(module.site_to_site) == 0
    error_message = "With the tfvars of dev and sit, neither VPN module may be called"
  }

  assert {
    condition     = local.published_strings == { client_vpn = "{\"enabled\":false}", site_to_site = "{\"enabled\":false}" }
    error_message = "With the VPNs off, vpn must publish {\"enabled\":false} for both keys"
  }
}
