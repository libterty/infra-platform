# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream value below stands in for what foundation publishes.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/flow_log_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-flow-logs-placeholder" }
}

run "tfvars_build_the_network" {
  command = plan

  assert {
    condition     = toset(keys(module.sg.security_group_ids)) == toset(["opensearch", "firehose", "sagemaker", "client_vpn", "search_admin"])
    error_message = "The tfvars must create the five security groups"
  }

  assert {
    condition     = local.vpc.nat_mode == "none" && local.vpc.gateway_endpoints == toset(["s3"])
    error_message = "The tfvars must describe a VPC without NAT and with only the s3 gateway endpoint"
  }
}

run "tfvars_env_account_and_cidr_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }

  assert {
    condition     = var.vpc_cidr == (var.env == "dev" ? "10.40.0.0/20" : "10.41.0.0/20")
    error_message = "dev must use 10.40.0.0/20 and sit 10.41.0.0/20 (design K32)"
  }
}

run "tfvars_use_two_azs_and_flow_logs" {
  command = plan

  assert {
    condition     = length(var.azs) == 2 && length(distinct(var.azs)) == 2
    error_message = "The VPC must span exactly two distinct AZs"
  }

  assert {
    condition     = var.flow_log
    error_message = "Flow logs must be on in dev and sit; the bucket exists for it"
  }
}

# Design section 7.5: inference has no endpoint in dev and sit, so nothing needs the SageMaker runtime endpoint yet.
run "tfvars_create_no_interface_endpoint" {
  command = plan

  assert {
    condition     = length(local.interface_endpoints.services) == 0
    error_message = "dev and sit tfvars must not create interface endpoints"
  }
}

# Subnets are cut from the VPC CIDR, so both tiers must fit in it for the two AZs and leave room for four.
run "subnets_fit_in_the_cidr" {
  command = plan

  assert {
    condition     = alltrue([for t, s in local.vpc.subnets : s.newbits != null && s.netnum_base + 4 <= pow(2, s.newbits)])
    error_message = "Each tier reserves four AZ slots, so netnum_base + 4 must fit in 2^newbits"
  }
}
