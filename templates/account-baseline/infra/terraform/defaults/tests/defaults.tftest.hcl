mock_provider "aws" {}

variables {
  project             = "baseline"
  env                 = "dev"
  expected_account_id = "111111111111"
}

run "all_account_defaults_are_on" {
  command = plan

  assert {
    condition = (
      local.security_defaults.s3_public_access_block &&
      local.security_defaults.ebs_encryption_by_default &&
      local.security_defaults.imdsv2_default
    )
    error_message = "The S3 public access block, EBS encryption by default and IMDSv2 by default must all be managed (design K14)"
  }

  assert {
    condition     = length(regexall("ebs_default_kms_key_arn", file("${path.module}/security.tf"))) == 0
    error_message = "EBS uses aws/ebs; the governance key does not grant EC2"
  }
}

run "password_policy_follows_k14" {
  command = plan

  assert {
    condition = local.security_defaults.password_policy == {
      minimum_length        = 14
      require_symbols       = true
      require_numbers       = true
      require_uppercase     = true
      require_lowercase     = true
      max_age_days          = 90
      reuse_prevention      = 24
      allow_users_to_change = true
    }
    error_message = "The password policy must be at least 14 chars with all character classes, expire after 90 days and remember 24 passwords (design K14)"
  }
}

run "analyzer_covers_this_account_only" {
  command = plan

  assert {
    condition     = local.analyzer == { name = "baseline-dev-account", type = "ACCOUNT" }
    error_message = "The analyzer must be <name_prefix>-account of type ACCOUNT; unused access analysis stays off (design K9)"
  }
}

run "publishes_only_the_analyzer" {
  command = plan

  override_module {
    target = module.access_analyzer
    outputs = {
      arn = "arn:aws:access-analyzer:ap-northeast-1:111111111111:analyzer/baseline-dev-account"
    }
  }

  assert {
    condition = local.published_strings == {
      access_analyzer_arn = "arn:aws:access-analyzer:ap-northeast-1:111111111111:analyzer/baseline-dev-account"
    }
    error_message = "defaults publishes the analyzer ARN only"
  }

  assert {
    condition     = module.ssm_publish.names == { access_analyzer_arn = "/baseline/dev/defaults/access_analyzer_arn" }
    error_message = "ssm-publish must write the key under the defaults stack path"
  }

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf")
    error_message = "defaults needs nothing from foundation"
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
    condition     = local.name_prefix == "baseline-dev" && local.ssm_prefix == "/baseline/dev"
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
    condition     = local.name_prefix == "baseline-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
