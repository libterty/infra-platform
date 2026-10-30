mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
  vpc_cidr            = "10.30.0.0/16"
  azs                 = ["ap-northeast-1a", "ap-northeast-1c"]
}

run "reads_nothing" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "network needs nothing from earlier stacks and must not read SSM"
  }
}

run "public_and_app_tiers_only" {
  command = plan

  assert {
    condition     = keys(local.vpc_subnets) == ["app", "public"] && local.vpc_subnets.app.type == "private" && local.vpc_subnets.public.type == "public"
    error_message = "The VPC has a public tier for the NAT and a private app tier for ECS and the internal ALB (design 8.1)"
  }

  assert {
    condition     = module.vpc.subnet_cidrs["public"] == ["10.30.0.0/24", "10.30.1.0/24"] && module.vpc.subnet_cidrs["app"] == ["10.30.16.0/20", "10.30.32.0/20"]
    error_message = "The subnet layout must match the comment in vpc.tf"
  }

  assert {
    condition     = local.vpc.nat_mode == "single" && local.vpc.gateway_endpoints == toset(["s3"])
    error_message = "The default is one NAT gateway plus the free S3 gateway endpoint"
  }
}

run "three_azs_fit_without_overlap" {
  command = plan

  variables {
    azs = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  }

  assert {
    condition = (
      module.vpc.subnet_cidrs["public"] == ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"] &&
      module.vpc.subnet_cidrs["app"] == ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
    )
    error_message = "With three AZs the public /24s must stay below 10.30.16.0, outside the app /20s"
  }
}

run "nat_none_is_rejected" {
  command = plan

  variables {
    nat_mode = "none"
  }

  expect_failures = [var.nat_mode]
}

run "per_az_nat_is_accepted" {
  command = plan

  variables {
    nat_mode = "per_az"
  }

  assert {
    condition     = local.vpc.nat_mode == "per_az"
    error_message = "per_az must pass through to the vpc module"
  }
}

run "vpc_cidr_must_be_a_slash_16" {
  command = plan

  variables {
    vpc_cidr = "10.30.0.0/20"
  }

  expect_failures = [var.vpc_cidr]
}

run "one_az_is_rejected" {
  command = plan

  variables {
    azs = ["ap-northeast-1a"]
  }

  expect_failures = [var.azs]
}

run "publishes_exactly_the_network_keys" {
  command = plan

  override_module {
    target = module.vpc
    outputs = {
      vpc_id     = "vpc-0123456789abcdef0"
      vpc_cidr   = "10.30.0.0/16"
      subnet_ids = { public = ["subnet-0000000000000000a", "subnet-0000000000000000b"], app = ["subnet-0000000000000000c", "subnet-0000000000000000d"] }
    }
  }

  assert {
    condition     = local.published_strings == { vpc_id = "vpc-0123456789abcdef0", vpc_cidr = "10.30.0.0/16" }
    error_message = "network must publish vpc_id and vpc_cidr as strings (design 8.3)"
  }

  assert {
    condition     = local.published_lists == { app_subnet_ids = ["subnet-0000000000000000c", "subnet-0000000000000000d"] }
    error_message = "network must publish only the app subnets as a list; nothing runs in the public tier"
  }

  assert {
    condition = module.ssm_publish.names == {
      vpc_id         = "/cicd/dev/network/vpc_id"
      vpc_cidr       = "/cicd/dev/network/vpc_cidr"
      app_subnet_ids = "/cicd/dev/network/app_subnet_ids"
    }
    error_message = "ssm-publish must write the keys under the network path"
  }
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
    condition     = local.name_prefix == "cicd-dev" && local.ssm_prefix == "/cicd/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Cicd"
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
    condition     = local.name_prefix == "cicd-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
