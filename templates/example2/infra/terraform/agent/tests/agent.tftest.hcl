mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  agent_image_tag     = "0.1.0"
  model_id            = "apac.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      agent_sg_id            = "sg-0123456789abcdef0"
      agent_runtime_role_arn = "arn:aws:iam::111111111111:role/example-dev-agent-runtime"
      agent_runtimes         = "[\"agent\"]"
      ecr_repository_urls = jsonencode({
        api    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
        worker = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
        agent  = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent"
      })
    }
    lists = {
      agent_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
}

# ---- reads ----

run "reads_only_tree_b" {
  command = plan

  assert {
    condition = local.shared_input_strings == {
      agent_sg_id            = "infra/agent_sg_id"
      agent_runtime_role_arn = "infra/agent_runtime_role_arn"
      agent_runtimes         = "infra/agent_runtimes"
      ecr_repository_urls    = "infra/ecr_repository_urls"
    } && local.shared_input_lists == { agent_subnet_ids = "infra/agent_subnet_ids" }
    error_message = "agent reads its security group, role, Runtime list, image repositories and subnets from tree B"
  }
}

# ---- guardrail profiles ----

run "there_is_one_input_guardrail_per_profile" {
  command = plan

  assert {
    condition     = toset(keys(local.guardrail_profiles)) == toset(["default", "profile_a"])
    error_message = "default screens everything without a profile of its own; profile_a is the example of a specific one"
  }

  assert {
    condition     = toset(keys(module.input_guardrail)) == toset(["default", "profile_a"])
    error_message = "One guardrail module instance per profile"
  }
}

run "every_profile_picks_content_filters_and_both_example_topics" {
  command = plan

  assert {
    condition = alltrue([
      for p in values(local.guardrail_profiles) :
      toset(p.content) == toset(["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT", "PROMPT_ATTACK"]) &&
      toset(p.topics) == toset(["InvestmentAdvice", "MedicalAdvice"])
    ])
    error_message = "Both profiles use all six content filters and both example topics"
  }
}

run "only_profile_a_has_a_word_list" {
  command = plan

  assert {
    condition     = length(local.guardrail_input_targets["default"].words) == 0 && length(local.guardrail_input_targets["profile_a"].words) > 0
    error_message = "Word blocks are resolved to the words themselves, and only profile_a names one"
  }
}

run "profiles_have_their_own_blocked_message" {
  command = plan

  assert {
    condition     = local.guardrail_profiles["default"].blocked_message != local.guardrail_profiles["profile_a"].blocked_message
    error_message = "A profile exists to say something different when it blocks"
  }
}

run "input_guardrails_only_evaluate_the_input_side" {
  command = plan

  assert {
    condition = alltrue([
      for t in values(local.guardrail_input_targets) :
      alltrue([for f in values(t.content_filters) : f.output_enabled == false && f.output_strength == "NONE"])
    ])
    error_message = "Input guardrails are applied to prompts only, so the output side stays off"
  }

  assert {
    condition     = local.guardrail_input_targets["default"].content_filters["PROMPT_ATTACK"].input_strength == "HIGH"
    error_message = "Prompt attacks are filtered at HIGH"
  }
}

run "output_guardrail_has_no_prompt_attack_filter" {
  command = plan

  assert {
    condition     = !contains(keys(local.guardrail_output_content_filters), "PROMPT_ATTACK") && length(local.guardrail_output_content_filters) == 5
    error_message = "The API rejects a prompt attack filter on the output side; the output guardrail has the other five"
  }

  assert {
    condition     = alltrue([for f in values(local.guardrail_output_content_filters) : f.input_enabled == false && f.output_enabled == true])
    error_message = "The output guardrail only evaluates generated text"
  }
}

run "guardrail_names_fit_the_bedrock_limit" {
  command = plan

  assert {
    condition = alltrue([
      for n in concat([for t in values(local.guardrail_input_targets) : t.name], [local.guardrail_output_name]) :
      length(n) <= 50 && can(regex("^[0-9A-Za-z_-]+$", n))
    ])
    error_message = "Guardrail names are 1-50 characters of letters, digits, hyphens and underscores"
  }

  assert {
    condition     = local.guardrail_input_targets["profile_a"].name == "example-dev-input-profile_a" && local.guardrail_output_name == "example-dev-output"
    error_message = "Guardrails are <project>-<env>-input-<profile> and <project>-<env>-output"
  }
}

# ---- Runtime and Memory ----

run "runtime_and_memory_names_follow_the_iam_naming_rule" {
  command = plan

  assert {
    condition     = local.runtime_names == { agent = "example_dev_agent" } && local.memory_name == "example_dev_memory"
    error_message = "Names are <project>_<env>_<runtime> and <project>_<env>_memory with hyphens turned into underscores; the iam stack builds its ARNs from them"
  }
}

run "a_hyphenated_runtime_name_becomes_underscores" {
  command = plan

  override_module {
    target = module.shared
    outputs = {
      strings = {
        agent_sg_id            = "sg-0123456789abcdef0"
        agent_runtime_role_arn = "arn:aws:iam::111111111111:role/example-dev-agent-runtime"
        agent_runtimes         = "[\"agent\",\"agent-lite\"]"
        ecr_repository_urls = jsonencode({
          agent      = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent"
          agent-lite = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent-lite"
        })
      }
      lists = {
        agent_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
      }
    }
  }

  assert {
    condition     = local.runtime_names == { agent = "example_dev_agent", agent-lite = "example_dev_agent_lite" }
    error_message = "iam replaces - with _ in the Runtime name, so this stack must too"
  }

  assert {
    condition     = toset(keys(module.runtime)) == toset(["agent", "agent-lite"])
    error_message = "One Runtime per entry of the Runtime list"
  }
}

run "no_runtime_in_the_list_creates_none" {
  command = plan

  override_module {
    target = module.shared
    outputs = {
      strings = {
        agent_sg_id            = "sg-0123456789abcdef0"
        agent_runtime_role_arn = "arn:aws:iam::111111111111:role/example-dev-agent-runtime"
        agent_runtimes         = "[]"
        ecr_repository_urls    = "{}"
      }
      lists = {
        agent_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
      }
    }
  }

  assert {
    condition     = length(module.runtime) == 0
    error_message = "An empty Runtime list means no Runtime; the memory and guardrails stay"
  }
}

run "runtime_image_is_the_repository_url_plus_the_tag" {
  command = plan

  assert {
    condition     = local.runtime_images == { agent = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent:0.1.0" }
    error_message = "Terraform owns the image tag: it is set here and applied"
  }
}

run "rejects_the_latest_tag" {
  command = plan

  variables {
    agent_image_tag = "latest"
  }

  expect_failures = [var.agent_image_tag]
}

# ---- environment variables ----

run "environment_uses_generic_names_the_module_accepts" {
  command = plan

  assert {
    condition = toset(keys(local.runtime_environment)) == toset([
      "AWS_REGION", "AGENT_MODEL_ID", "AGENT_MEMORY_ID", "AGENT_BACKEND_MODE", "AGENT_MAX_OUTPUT_LENGTH",
      "AGENT_OUTPUT_GUARDRAIL_ID",
    ])
    error_message = "Without a backend URL the optional variable is absent, not empty"
  }

  assert {
    condition     = !anytrue([for k in keys(local.runtime_environment) : can(regex("(SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL)", upper(k)))])
    error_message = "The agentcore-runtime module rejects names that look like secrets"
  }
}

run "backend_url_is_added_in_http_mode" {
  command = plan

  variables {
    backend_mode = "http"
    backend_url  = "https://backend.example.com"
  }

  assert {
    condition     = local.runtime_environment["AGENT_BACKEND_URL"] == "https://backend.example.com" && local.runtime_environment["AGENT_BACKEND_MODE"] == "http"
    error_message = "http mode passes the URL"
  }
}

run "http_mode_needs_a_url" {
  command = plan

  variables {
    backend_mode = "http"
  }

  expect_failures = [var.backend_url]
}

run "rejects_an_unknown_backend_mode" {
  command = plan

  variables {
    backend_mode = "other"
  }

  expect_failures = [var.backend_mode]
}

# ---- Runtime log delivery ----

run "each_runtime_has_a_log_group_and_a_delivery" {
  command = plan

  assert {
    condition     = local.runtime_log_group_names == { agent = "/aws/vendedlogs/bedrock-agentcore/example_dev_agent" }
    error_message = "Log groups are named after the Runtime"
  }

  assert {
    condition     = keys(local.log_delivery_deliveries) == ["agent"]
    error_message = "One delivery from each Runtime to its log group"
  }
}

# ---- publishing ----

run "publishes_the_runtime_memory_and_guardrail_values" {
  command = plan

  override_module {
    target = module.runtime
    # An override applies to every instance of a for_each module; there is one Runtime here.
    outputs = {
      runtime_arn  = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGhIj"
      runtime_id   = "example_dev_agent-AbCdEfGhIj"
      runtime_name = "example_dev_agent"
    }
  }

  override_module {
    target = module.memory
    outputs = {
      memory_id  = "example_dev_memory-KlMnOpQrSt"
      memory_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/example_dev_memory-KlMnOpQrSt"
    }
  }

  override_module {
    target = module.input_guardrail
    # Both profile instances get the same id from the override; only the keys are told apart.
    outputs = { guardrail_id = "gr0input00001" }
  }

  override_module {
    target  = module.output_guardrail
    outputs = { guardrail_id = "gr0output00003" }
  }

  assert {
    condition = module.ssm_publish.names == {
      agent_runtime_arns = "/example/dev/agent/agent_runtime_arns"
      agent_memory_id    = "/example/dev/agent/agent_memory_id"
      agent_memory_arn   = "/example/dev/agent/agent_memory_arn"
      guardrail_ids      = "/example/dev/agent/guardrail_ids"
    }
    error_message = "agent publishes four keys under its own path"
  }

  assert {
    condition     = jsondecode(local.published_strings.agent_runtime_arns) == { agent = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGhIj" }
    error_message = "Runtime ARNs are published as a JSON map keyed by Runtime"
  }

  assert {
    condition     = jsondecode(local.published_strings.guardrail_ids) == { default = "gr0input00001", profile_a = "gr0input00001", output = "gr0output00003" }
    error_message = "Guardrail ids are published as a JSON map: one per input profile plus output"
  }
}
