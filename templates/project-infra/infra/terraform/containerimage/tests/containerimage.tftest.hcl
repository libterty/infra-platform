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
      services        = "/alpha/dev/containerimage/services"
      mirrored_images = "/alpha/dev/containerimage/mirrored_images"
      ecr_api_url     = "/alpha/dev/containerimage/ecr_api_url"
      ecr_api_arn     = "/alpha/dev/containerimage/ecr_api_arn"
      ecr_worker_url  = "/alpha/dev/containerimage/ecr_worker_url"
      ecr_worker_arn  = "/alpha/dev/containerimage/ecr_worker_arn"
    }
    error_message = "ssm-publish must write the services list, the mirror list, and a url and an arn per service under the containerimage path"
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
      mirrored_images   = "[]"
    }
    error_message = "Hyphens in the service name must become underscores in the SSM keys, and the values must come from the repository"
  }
}

# ---- mirrored_images: repositories that hold copies of external images ----

run "no_mirrors_by_default" {
  command = plan

  assert {
    condition     = length(module.ecr_mirror) == 0
    error_message = "Without mirrored_images no mirror repository may exist"
  }

  assert {
    condition     = local.published_strings["mirrored_images"] == "[]"
    error_message = "The mirror list must still be published, as an empty JSON array, so downstream stacks can always read it"
  }

  assert {
    condition     = length([for k in keys(local.published_strings) : k if startswith(k, "ecr_mirror_")]) == 0
    error_message = "Without mirrors no ecr_mirror_* key may be published"
  }
}

run "mirror_repository_is_created" {
  command = plan

  variables {
    mirrored_images = ["adot-collector"]
  }

  assert {
    condition     = keys(module.ecr_mirror) == ["adot-collector"]
    error_message = "ecr-repository must be called once per mirror"
  }

  assert {
    condition     = module.ecr_mirror["adot-collector"].name == "alpha-dev-mirror-adot-collector"
    error_message = "Mirror repository names must be <project>-<env>-mirror-<name>"
  }

  assert {
    condition     = local.mirror_repositories["adot-collector"].kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/0000"
    error_message = "Mirror repositories must be encrypted with the foundation key"
  }

  assert {
    condition     = length(module.ecr) == 2
    error_message = "Adding a mirror must not change the service repositories"
  }
}

run "mirror_gets_the_lifecycle_settings" {
  command = plan

  variables {
    mirrored_images = ["adot-collector"]
    lifecycle_rules = { untagged_expire_days = 3, keep_count = 100 }
  }

  assert {
    condition     = local.mirror_repositories["adot-collector"].lifecycle_rules.untagged_expire_days == 3 && local.mirror_repositories["adot-collector"].lifecycle_rules.keep_count == 100
    error_message = "The lifecycle override must reach the mirror repositories"
  }
}

run "mirror_publishes_url_arn_and_list" {
  command = plan

  variables {
    mirrored_images = ["adot-collector", "other-image"]
  }

  override_module {
    target = module.ecr_mirror["adot-collector"]
    outputs = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-mirror-adot-collector"
      arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-adot-collector"
    }
  }

  override_module {
    target = module.ecr_mirror["other-image"]
    outputs = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-mirror-other-image"
      arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-other-image"
    }
  }

  assert {
    condition = (
      local.published_strings["ecr_mirror_adot_collector_url"] == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-mirror-adot-collector" &&
      local.published_strings["ecr_mirror_adot_collector_arn"] == "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-adot-collector" &&
      local.published_strings["ecr_mirror_other_image_arn"] == "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-other-image"
    )
    error_message = "Each mirror must publish ecr_mirror_<name>_url and _arn with hyphens turned into underscores"
  }

  assert {
    condition     = jsondecode(local.published_strings["mirrored_images"]) == ["adot-collector", "other-image"]
    error_message = "The mirror list must be published as a sorted JSON array of the mirror names"
  }

  assert {
    condition     = contains(keys(module.ssm_publish.names), "ecr_mirror_adot_collector_url") && contains(keys(module.ssm_publish.names), "mirrored_images")
    error_message = "The mirror keys must be written to SSM under the containerimage path"
  }
}

run "mirror_name_uppercase_rejected" {
  command = plan

  variables {
    mirrored_images = ["Adot"]
  }

  expect_failures = [var.mirrored_images]
}

run "mirror_name_with_underscore_rejected" {
  command = plan

  variables {
    mirrored_images = ["adot_collector"]
  }

  expect_failures = [var.mirrored_images]
}

run "mirror_name_with_slash_rejected" {
  command = plan

  variables {
    mirrored_images = ["aws-observability/adot"]
  }

  expect_failures = [var.mirrored_images]
}

run "mirror_with_same_name_as_service_rejected" {
  command = plan

  variables {
    services        = ["api", "adot-collector"]
    mirrored_images = ["adot-collector"]
  }

  expect_failures = [var.mirrored_images]
}

run "mirror_repository_name_colliding_with_service_rejected" {
  command = plan

  variables {
    # The service repository alpha-dev-mirror-adot would have the same name as the mirror repository.
    services        = ["mirror-adot"]
    mirrored_images = ["adot"]
  }

  expect_failures = [var.mirrored_images]
}

run "mirror_next_to_unrelated_service_passes" {
  command = plan

  variables {
    services        = ["mirror"]
    mirrored_images = ["adot"]
  }

  assert {
    condition     = keys(module.ecr) == ["mirror"] && keys(module.ecr_mirror) == ["adot"]
    error_message = "A service called mirror does not collide with a mirror called adot (alpha-dev-mirror vs alpha-dev-mirror-adot)"
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
