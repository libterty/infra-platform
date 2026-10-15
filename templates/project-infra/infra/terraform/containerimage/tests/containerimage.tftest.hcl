mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"
  services            = ["api", "worker"]
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { kms_key_arn = "foundation/kms_key_arn" } && local.ssm_input_lists == {}
    error_message = "containerimage must read foundation/kms_key_arn and nothing else"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      services       = "/alpha/dev/containerimage/services"
      ecr_api_url    = "/alpha/dev/containerimage/ecr_api_url"
      ecr_api_arn    = "/alpha/dev/containerimage/ecr_api_arn"
      ecr_worker_url = "/alpha/dev/containerimage/ecr_worker_url"
      ecr_worker_arn = "/alpha/dev/containerimage/ecr_worker_arn"
    }
    error_message = "ssm-publish must write the services list plus a url and an arn per service under the containerimage path"
  }
}

run "publishes_services" {
  command = plan

  assert {
    condition     = local.published_lists.services == tolist(["api", "worker"])
    error_message = "services must be published as a list; it is the single decision point for the service list"
  }
}

run "one_repository_per_service" {
  command = plan

  assert {
    condition     = length(module.ecr) == 2 && toset(keys(module.ecr)) == toset(["api", "worker"])
    error_message = "ecr-repository must be called once per service"
  }

  assert {
    condition     = module.ecr["api"].name == "alpha-dev-api" && module.ecr["worker"].name == "alpha-dev-worker"
    error_message = "Repository names must be <project>-<env>-<service>"
  }

  assert {
    condition     = alltrue([for r in values(local.repositories) : r.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/0000"])
    error_message = "Repositories must be encrypted with the foundation key read from SSM"
  }
}

run "lifecycle_defaults_passed" {
  command = plan

  assert {
    condition     = alltrue([for r in values(local.repositories) : r.lifecycle_rules.untagged_expire_days == 7 && r.lifecycle_rules.keep_count == 50])
    error_message = "Without an override the lifecycle must expire untagged images after 7 days and keep 50 images"
  }
}

run "lifecycle_override_passed" {
  command = plan

  variables {
    lifecycle_rules = { untagged_expire_days = 3, keep_count = 100 }
  }

  assert {
    condition     = alltrue([for r in values(local.repositories) : r.lifecycle_rules.untagged_expire_days == 3 && r.lifecycle_rules.keep_count == 100])
    error_message = "An override must reach every repository"
  }
}

run "service_name_uppercase_rejected" {
  command = plan

  variables {
    services = ["Api"]
  }

  expect_failures = [var.services]
}

run "service_name_with_space_rejected" {
  command = plan

  variables {
    services = ["order api"]
  }

  expect_failures = [var.services]
}

run "service_name_trailing_hyphen_rejected" {
  command = plan

  variables {
    services = ["order-"]
  }

  expect_failures = [var.services]
}

run "service_name_kebab_case_passes" {
  command = plan

  variables {
    services = ["order-api"]
  }

  assert {
    condition     = keys(module.ecr) == ["order-api"]
    error_message = "order-api must be accepted"
  }
}

run "empty_services_rejected" {
  command = plan

  variables {
    services = []
  }

  expect_failures = [var.services]
}

run "duplicate_services_rejected" {
  command = plan

  variables {
    services = ["api", "api"]
  }

  expect_failures = [var.services]
}

run "service_name_too_long_for_ecs_service_rejected" {
  command = plan

  variables {
    services = ["a-very-long-service-name"]
  }

  expect_failures = [var.services]
}

run "service_name_at_ecs_service_limit_passes" {
  command = plan

  variables {
    # alpha-dev- is 10 characters, so 16 more make exactly 26.
    services = ["abcdefghijklmnop"]
  }

  assert {
    condition     = length("alpha-dev-abcdefghijklmnop") == 26 && length(module.ecr) == 1
    error_message = "A name of exactly 26 characters must pass"
  }
}

run "publishes_url_and_arn" {
  command = plan

  variables {
    services = ["order-api"]
  }

  override_module {
    target = module.ecr["order-api"]
    outputs = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-order-api"
      arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-order-api"
    }
  }

  assert {
    condition = local.published_strings == {
      ecr_order_api_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-order-api"
      ecr_order_api_arn = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-order-api"
    }
    error_message = "Hyphens in the service name must become underscores in the SSM keys, and the values must come from the repository"
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
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
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
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
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
