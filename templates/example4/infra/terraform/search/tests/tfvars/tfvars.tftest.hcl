# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, network and iam-base publish.
mock_provider "aws" {
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"admin-placeholder\",\"password\":\"not-a-real-password-1A!\"}"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "ap-northeast-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-placeholder-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/opensearch_master_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-placeholder-opensearch-master-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_opensearch_id"]
  values = { insecure_value = "sg-0aaaaaaa00000001" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-firehose" }
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

# Design section 7.5: dev and sit both run the full hot, UltraWarm and cold layout, so ISM has somewhere to move indexes.
run "tfvars_have_both_warm_and_cold" {
  command = plan

  assert {
    condition     = var.warm != null && var.cold_storage
    error_message = "dev and sit must both enable warm and cold storage (design D6)"
  }

  assert {
    condition     = var.warm.instance_type == "ultrawarm1.medium.search" && var.warm.count == 2
    error_message = "warm must be 2 x ultrawarm1.medium.search (design K17)"
  }
}

run "tfvars_master_is_dedicated_and_not_burstable" {
  command = plan

  assert {
    condition     = var.dedicated_master != null && var.dedicated_master.count == 3
    error_message = "dev and sit must use 3 dedicated master nodes"
  }

  assert {
    condition     = var.dedicated_master.instance_type == "m7g.large.search" && !can(regex("^t[23]\\.", var.dedicated_master.instance_type))
    error_message = "master must be m7g.large.search and never a T2 or T3 type (design K17)"
  }
}

run "tfvars_hot_tier_and_azs_match_the_design" {
  command = plan

  assert {
    condition     = var.hot.instance_type == "m7g.large.search" && var.hot.instance_count == 2 && var.hot.ebs.volume_size == 20
    error_message = "hot must be 2 x m7g.large.search with 20 GiB gp3 each (design section 7.5)"
  }

  assert {
    condition     = var.hot.ebs.volume_type == "gp3" && var.availability_zone_count == 2 && length(local.domain.subnet_ids) == var.availability_zone_count
    error_message = "The domain must use 2 AZs, gp3 volumes, and one data subnet per AZ"
  }

  assert {
    condition     = var.hot.instance_count >= var.availability_zone_count
    error_message = "There must be at least one hot node per AZ"
  }
}

run "tfvars_access_policy_is_the_firehose_role_only" {
  command = plan

  assert {
    condition     = length(local.domain.access_principal_arns) == 1 && endswith(local.domain.access_principal_arns[0], "-firehose")
    error_message = "The access policy must list exactly one principal, the iam-base Firehose role"
  }
}

run "tfvars_build_the_domain_and_its_alarms" {
  command = plan

  assert {
    condition     = module.domain.domain_name == "example-${var.env}-search"
    error_message = "The tfvars must build one domain named <project>-<env>-search"
  }

  assert {
    condition     = length(local.alarms) == 6
    error_message = "With warm and cold on, the tfvars must create the six alarms"
  }
}
