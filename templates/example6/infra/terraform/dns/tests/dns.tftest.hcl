mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  domain_name         = "dev.example.com"
}

# dns comes before every stack that reads from SSM except containerimage and foundation, and needs neither.
run "reads_nothing" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "dns needs no upstream value and must not read SSM"
  }
}

run "one_public_zone_for_the_env" {
  command = plan

  assert {
    condition     = module.zone.name == "dev.example.com"
    error_message = "The zone must be the env subdomain from tfvars"
  }

  assert {
    condition     = !strcontains(file("${path.module}/zone.tf"), "private_vpc_ids") && !strcontains(file("${path.module}/zone.tf"), "force_destroy")
    error_message = "The zone must be public and keep the module default force_destroy = false"
  }
}

run "publishes_exactly_the_zone_keys" {
  command = plan

  override_module {
    target = module.zone
    outputs = {
      zone_id      = "Z0000000000000000000A"
      name         = "dev.example.com"
      name_servers = ["ns-1.awsdns-00.com", "ns-2.awsdns-00.net"]
    }
  }

  assert {
    condition     = local.published_strings == { zone_id = "Z0000000000000000000A", zone_name = "dev.example.com" }
    error_message = "dns must publish zone_id and zone_name as Strings (design 8.2)"
  }

  assert {
    condition     = local.published_lists == { name_servers = ["ns-1.awsdns-00.com", "ns-2.awsdns-00.net"] }
    error_message = "dns must publish name_servers as a StringList for the manual NS delegation"
  }

  assert {
    condition = module.ssm_publish.names == {
      zone_id      = "/example/dev/dns/zone_id"
      zone_name    = "/example/dev/dns/zone_name"
      name_servers = "/example/dev/dns/name_servers"
    }
    error_message = "ssm-publish must write exactly the three keys under the dns path"
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
