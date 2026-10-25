mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

run "reads_no_ssm_keys" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "pki must not read SSM keys: the CA depends on nothing earlier"
  }
}

# ca defaults to null (design D4): the stack must then create nothing and say so in the SSM contract.
run "defaults_create_no_ca" {
  command = plan

  assert {
    condition     = var.ca == null
    error_message = "ca must default to null"
  }

  assert {
    condition     = length(module.ca) == 0
    error_message = "With ca null, the acm-pca module must not be called"
  }
}

run "defaults_publish_disabled_marker" {
  command = plan

  assert {
    condition     = local.published_strings == { ca = "{\"enabled\":false}" }
    error_message = "A CA that is off must publish exactly {\"enabled\":false}, and ca is the only key"
  }

  assert {
    condition     = module.ssm_publish.names == { ca = "/example/dev/pki/ca" }
    error_message = "ssm-publish must write the ca key under the pki stack path"
  }
}

run "root_ca_publishes_arn_and_certificate" {
  command = plan

  variables {
    ca = {
      type    = "ROOT"
      subject = { organization = "Example", country = "JP" }
    }
  }

  override_module {
    target = module.ca
    outputs = {
      ca_arn             = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/11111111-2222-3333-4444-555555555555"
      ca_certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
      csr                = "-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----"
    }
  }

  assert {
    condition     = length(module.ca) == 1
    error_message = "Giving ca must call the acm-pca module"
  }

  assert {
    condition = jsondecode(local.published_strings["ca"]) == {
      enabled         = true
      arn             = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/11111111-2222-3333-4444-555555555555"
      certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    }
    error_message = "ca must publish enabled = true with the CA ARN and its certificate"
  }
}

run "ca_common_name_comes_from_the_prefix" {
  command = plan

  variables {
    ca = {
      type    = "ROOT"
      subject = { organization = "Example" }
    }
  }

  assert {
    condition     = local.ca.subject.common_name == "example-dev-device-ca" && local.ca.subject.organization == "Example"
    error_message = "The CA common name must be <name_prefix>-device-ca, and the other subject fields come from tfvars"
  }

  assert {
    condition     = local.ca.type == "ROOT" && local.ca.usage_mode == "GENERAL_PURPOSE" && local.ca.key_algorithm == "EC_prime256v1" && local.ca.validity_years == 10
    error_message = "Unset fields must fall back to the module defaults"
  }
}

run "ca_module_receives_every_setting" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["type", "usage_mode", "key_algorithm", "subject", "validity_years", "permanent_deletion_time_in_days", "subordinate_certificate"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*local\\.ca\\.${f}\\s*$", file("${path.module}/ca.tf"))) == 1
    ])
    error_message = "The acm-pca module call must take every input from local.ca"
  }
}

run "ca_type_rejected" {
  command = plan

  variables {
    ca = { type = "INTERMEDIATE" }
  }

  expect_failures = [var.ca]
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
