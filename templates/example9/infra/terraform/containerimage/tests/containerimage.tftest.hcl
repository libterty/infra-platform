mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# containerimage is first in ORDER, so it cannot read anything from SSM.
run "reads_nothing" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "containerimage is applied first and must not read SSM"
  }
}

# iam builds the push and pull scopes from these names, application and pipeline use the URLs.
run "one_repository_per_image_component" {
  command = plan

  assert {
    condition     = toset(keys(module.repository)) == toset(["api", "fn"])
    error_message = "There must be exactly the api and fn repositories (design 8.1)"
  }

  assert {
    condition     = module.repository["api"].name == "cicd-dev-api" && module.repository["fn"].name == "cicd-dev-fn"
    error_message = "The repositories must be named <name_prefix>-api and <name_prefix>-fn"
  }

  assert {
    condition     = alltrue([for r in values(local.repositories) : r.lifecycle_rules.untagged_expire_days == 7 && r.lifecycle_rules.keep_count == 50])
    error_message = "The default lifecycle rules must expire untagged images after 7 days and keep 50 images"
  }
}

# foundation comes after containerimage, so the shared key cannot be used here.
run "repositories_use_aes256" {
  command = plan

  assert {
    condition     = !strcontains(file("${path.module}/repositories.tf"), "kms_key_arn")
    error_message = "The repositories must not reference a KMS key; the shared key does not exist before foundation"
  }
}

run "publishes_exactly_the_repository_urls" {
  command = plan

  override_module {
    target = module.repository["api"]
    outputs = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api"
    }
  }

  override_module {
    target = module.repository["fn"]
    outputs = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn"
    }
  }

  assert {
    condition = local.published_strings == {
      api_repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api"
      fn_repository_url  = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn"
    }
    error_message = "containerimage must publish exactly api_repository_url and fn_repository_url (design 8.3)"
  }

  assert {
    condition = module.ssm_publish.names == {
      api_repository_url = "/cicd/dev/containerimage/api_repository_url"
      fn_repository_url  = "/cicd/dev/containerimage/fn_repository_url"
    }
    error_message = "ssm-publish must write the keys under the containerimage path"
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
