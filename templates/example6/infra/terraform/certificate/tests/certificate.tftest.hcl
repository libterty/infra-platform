mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_id"]
  values = { insecure_value = "Z0000000000000000000A" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
  values = { insecure_value = "dev.example.com" }
}

run "reads_only_the_dns_keys" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { zone_id = "dns/zone_id", zone_name = "dns/zone_name" } && local.ssm_input_lists == {}
    error_message = "certificate may read only dns/zone_id and dns/zone_name (design 8.2)"
  }
}

# Design K16: one distribution, so one certificate for app.<zone> in us-east-1 and no regional certificate.
run "one_cloudfront_certificate_in_us_east_1" {
  command = plan

  assert {
    condition = local.web_certificate == {
      domain_name = "app.dev.example.com"
      zone_id     = "Z0000000000000000000A"
      region      = "us-east-1"
      tags        = { Name = "example-dev-web" }
    }
    error_message = "The certificate must be app.<zone>, validated in the env zone, in us-east-1 for CloudFront"
  }

  assert {
    condition     = length(regexall("acm-certificate/aws", join("\n", [for f in fileset(path.module, "*.tf") : file("${path.module}/${f}")]))) == 1
    error_message = "certificate must create exactly one certificate; the API needs no regional one (design K16)"
  }

  assert {
    condition     = !strcontains(file("${path.module}/certificates.tf"), "subject_alternative_names")
    error_message = "The certificate covers app.<zone> only"
  }
}

run "publishes_exactly_the_certificate_arn" {
  command = plan

  override_module {
    target = module.web_certificate
    outputs = {
      certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = local.published_strings == { web_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000" }
    error_message = "certificate must publish exactly web_certificate_arn (design 8.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { web_certificate_arn = "/example/dev/certificate/web_certificate_arn" }
    error_message = "ssm-publish must write the key under the certificate path"
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
