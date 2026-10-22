mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  services            = ["api", "worker", "import-extract", "import-load"]
  agent_runtimes      = ["agent"]
}

# Computed outputs are unknown at plan time, so each repository module gets fixed outputs.
override_module {
  target = module.ecr["api"]
  outputs = {
    repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
    arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api"
    name           = "example-api"
  }
}

override_module {
  target = module.ecr["worker"]
  outputs = {
    repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
    arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-worker"
    name           = "example-worker"
  }
}

override_module {
  target = module.ecr["import-extract"]
  outputs = {
    repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-extract"
    arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-import-extract"
    name           = "example-import-extract"
  }
}

override_module {
  target = module.ecr["import-load"]
  outputs = {
    repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-load"
    arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-import-load"
    name           = "example-import-load"
  }
}

override_module {
  target = module.ecr["agent"]
  outputs = {
    repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent"
    arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-agent"
    name           = "example-agent"
  }
}

run "one_repository_per_image_without_env_in_the_name" {
  command = plan

  assert {
    condition = local.repository_names == {
      api            = "example-api"
      worker         = "example-worker"
      import-extract = "example-import-extract"
      import-load    = "example-import-load"
      agent          = "example-agent"
    }
    error_message = "Repository names must be <project>-<image> so an env that adopts them finds the same names"
  }

  assert {
    condition     = toset(keys(module.ecr)) == toset(["api", "worker", "import-extract", "import-load", "agent"])
    error_message = "ecr-repository must be called once per service and once per Runtime"
  }
}

run "lifecycle_rules_reach_every_repository" {
  command = plan

  variables {
    lifecycle_rules = { untagged_expire_days = 3, keep_count = 100 }
  }

  assert {
    condition     = alltrue([for k, r in local.repositories : r.lifecycle_rules.untagged_expire_days == 3 && r.lifecycle_rules.keep_count == 100])
    error_message = "A lifecycle override must reach every repository"
  }
}

run "lifecycle_defaults" {
  command = plan

  assert {
    condition     = alltrue([for k, r in local.repositories : r.lifecycle_rules.untagged_expire_days == 7 && r.lifecycle_rules.keep_count == 50])
    error_message = "Without an override untagged images expire after 7 days and 50 images are kept"
  }
}

run "publishes_the_image_lists_and_urls" {
  command = plan

  assert {
    condition     = local.published_lists.services == tolist(["api", "worker", "import-extract", "import-load"]) && keys(local.published_lists) == ["services"]
    error_message = "services must be published as a list"
  }

  assert {
    condition     = local.published_strings.agent_runtimes == "[\"agent\"]"
    error_message = "agent_runtimes must be published as a JSON array in a String (SSM rejects an empty list)"
  }

  assert {
    condition = jsondecode(local.published_strings.ecr_repository_urls) == {
      api            = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
      worker         = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
      import-extract = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-extract"
      import-load    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-load"
      agent          = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent"
    }
    error_message = "ecr_repository_urls must map every image and Runtime name to its repository URL"
  }

  assert {
    condition     = toset(keys(jsondecode(local.published_strings.ecr_repository_arns))) == toset(["api", "worker", "import-extract", "import-load", "agent"])
    error_message = "ecr_repository_arns must have one ARN per image and Runtime"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      services            = "/example/dev/containerimage/services"
      agent_runtimes      = "/example/dev/containerimage/agent_runtimes"
      ecr_repository_urls = "/example/dev/containerimage/ecr_repository_urls"
      ecr_repository_arns = "/example/dev/containerimage/ecr_repository_arns"
    }
    error_message = "ssm-publish must write exactly the four containerimage keys under the containerimage path"
  }
}

run "adopting_creates_no_repository_and_reads_the_existing_ones" {
  command = plan

  variables {
    adopt_existing = true
  }

  override_data {
    target = data.aws_ecr_repository.existing["api"]
    values = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
      arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api"
      name           = "example-api"
    }
  }

  assert {
    condition     = length(module.ecr) == 0
    error_message = "adopt_existing must not create any repository"
  }

  assert {
    condition     = toset(keys(data.aws_ecr_repository.existing)) == toset(["api", "worker", "import-extract", "import-load", "agent"])
    error_message = "adopt_existing must look up every repository by name"
  }

  assert {
    condition     = local.repository["api"].url == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
    error_message = "Published URLs must come from the existing repositories when adopting"
  }
}

run "services_must_not_be_empty" {
  command = plan

  variables {
    services = []
  }

  expect_failures = [var.services]
}

run "service_name_uppercase_rejected" {
  command = plan

  variables {
    services = ["Api"]
  }

  expect_failures = [var.services]
}

run "service_names_must_be_unique" {
  command = plan

  variables {
    services = ["api", "api"]
  }

  expect_failures = [var.services]
}

run "runtime_name_must_not_repeat_a_service" {
  command = plan

  variables {
    agent_runtimes = ["api"]
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_name_with_underscore_rejected" {
  command = plan

  variables {
    agent_runtimes = ["my_agent"]
  }

  expect_failures = [var.agent_runtimes]
}

run "no_runtime_is_allowed" {
  command = plan

  variables {
    agent_runtimes = []
  }

  assert {
    condition     = local.published_strings.agent_runtimes == "[]"
    error_message = "An empty Runtime list must publish \"[]\""
  }
}
