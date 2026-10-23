mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  cors_allow_origins  = ["https://app.example.com"]
}

override_module {
  target = module.in
  outputs = {
    strings = {
      api_target_group_arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab"
      alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
      target_group_arn_suffixes = "{\"api\":\"targetgroup/example-dev-alb-api/0123456789ab\"}"
      agent_runtime_arns        = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\"}"
      guardrail_ids             = "{\"default\":\"gr0input00001\",\"output\":\"gr0output00003\"}"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id                         = "vpc-0123456789abcdef0"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
      db_proxy_endpoint              = "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint      = "clustercfg.example-dev-rate-limit.abc123.apne1.cache.amazonaws.com:6379"
      stream_redis_endpoint          = "clustercfg.example-dev-stream.abc123.apne1.cache.amazonaws.com:6379"
      db_name                        = "app"
      stream_shard_count             = "3"
      ecr_repository_urls = jsonencode({
        api    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
        worker = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
      })
    }
    lists = {
      services = ["api", "worker", "import-extract", "import-load"]
    }
  }
}

override_data {
  target = data.aws_vpc.this
  values = { cidr_block = "10.10.0.0/16" }
}

# ---- reads ----

run "reads_the_late_stack_keys_from_tree_a_and_the_rest_from_tree_b" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      api_target_group_arn      = "loadbalancer/api_target_group_arn"
      alb_arn_suffix            = "loadbalancer/alb_arn_suffix"
      target_group_arn_suffixes = "loadbalancer/target_group_arn_suffixes"
      agent_runtime_arns        = "agent/agent_runtime_arns"
      guardrail_ids             = "agent/guardrail_ids"
    }
    error_message = "application reads the target group and ALB from loadbalancer and the Runtime and guardrails from agent"
  }

  assert {
    condition     = local.shared_input_strings["db_name"] == "infra/db_name" && local.shared_input_strings["stream_shard_count"] == "infra/stream_shard_count"
    error_message = "The database name and the shard count come from tree B"
  }

  assert {
    condition     = !contains(keys(local.shared_input_strings), "alarm_topic_arn") && contains(keys(local.shared_input_lists), "services")
    error_message = "application raises no alarms; it reads the service list"
  }
}

run "fails_when_the_service_list_misses_a_service" {
  command = plan

  override_module {
    target = module.shared
    outputs = {
      strings = {
        vpc_id                         = "vpc-0123456789abcdef0"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
        db_proxy_endpoint              = "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "clustercfg.example-dev-rate-limit.abc123.apne1.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "clustercfg.example-dev-stream.abc123.apne1.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "3"
        ecr_repository_urls = jsonencode({
          api    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
          worker = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
        })
      }
      lists = {
        services = ["api"]
      }
    }
  }

  expect_failures = [terraform_data.services_present]
}

# ---- FORWARDED_ALLOW_IPS: the three trust modes ----

run "vpc_trust_lists_only_the_vpc_cidr" {
  command = plan

  assert {
    condition     = local.forwarded_allow_ips == "10.10.0.0/16"
    error_message = "vpc mode trusts the VPC only"
  }

  assert {
    condition     = length(data.aws_ec2_managed_prefix_list.cdn_origin_facing) == 0
    error_message = "The CloudFront list is only read in vpc_and_cdn mode"
  }
}

run "any_trust_is_a_wildcard" {
  command = plan

  variables {
    trusted_proxies = "any"
  }

  assert {
    condition     = local.forwarded_allow_ips == "*"
    error_message = "any mode trusts every hop"
  }

  assert {
    condition     = length(data.aws_ec2_managed_prefix_list.cdn_origin_facing) == 0
    error_message = "Nothing to look up in any mode"
  }
}

run "vpc_and_cdn_trust_adds_the_sorted_cloudfront_ranges" {
  command = plan

  variables {
    trusted_proxies = "vpc_and_cdn"
  }

  override_data {
    target = data.aws_ec2_managed_prefix_list.cdn_origin_facing[0]
    values = {
      entries = [
        { cidr = "203.0.113.0/24", description = "range b" },
        { cidr = "198.51.100.0/24", description = "range a" },
      ]
    }
  }

  assert {
    condition     = local.forwarded_allow_ips == "10.10.0.0/16,198.51.100.0/24,203.0.113.0/24"
    error_message = "VPC first, then the CloudFront ranges in sorted order so the task definition does not change on every plan"
  }
}

run "rejects_an_unknown_trust_mode" {
  command = plan

  variables {
    trusted_proxies = "everyone"
  }

  expect_failures = [var.trusted_proxies]
}

# ---- services and secrets ----

run "api_reads_both_signing_keys_and_the_worker_only_the_public_one" {
  command = plan

  assert {
    condition     = contains(keys(local.api_environment), "SIGNING_PRIVATE_KEY_SECRET_ARN") && contains(keys(local.api_environment), "SIGNING_PUBLIC_KEY_SECRET_ARN")
    error_message = "The api signs with the private key and verifies with the public one"
  }

  assert {
    condition     = !contains(keys(local.worker_environment), "SIGNING_PRIVATE_KEY_SECRET_ARN") && contains(keys(local.worker_environment), "SIGNING_PUBLIC_KEY_SECRET_ARN")
    error_message = "The worker never gets the private key"
  }

  assert {
    condition     = !anytrue([for v in values(local.worker_environment) : strcontains(v, "private-key")])
    error_message = "No private key reference anywhere in the worker environment"
  }
}

run "secrets_are_passed_as_arns_the_pod_role_reads_at_runtime" {
  command = plan

  assert {
    condition     = alltrue([for k, v in local.api_environment : endswith(k, "_ARN") ? startswith(v, "arn:") : true])
    error_message = "Names ending in _ARN carry ARNs; the Pod fetches the value itself with its Pod Identity role"
  }
}

run "api_port_follows_app_port" {
  command = plan

  assert {
    condition     = local.api_environment["PORT"] == "8080"
    error_message = "The container port follows app_port"
  }
}

run "db_and_redis_endpoints_are_split_into_host_and_port" {
  command = plan

  assert {
    condition     = local.api_environment["STREAM_REDIS_HOST"] == "clustercfg.example-dev-stream.abc123.apne1.cache.amazonaws.com" && local.api_environment["STREAM_REDIS_PORT"] == "6379"
    error_message = "host:port is split"
  }

  assert {
    condition     = local.worker_environment["STREAM_SHARDS"] == "3" && local.api_environment["STREAM_SHARDS"] == "3"
    error_message = "The shard count is the one the database stack published, not a second copy"
  }

  assert {
    condition     = local.worker_environment["DB_HOST"] == "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com" && local.worker_environment["DB_NAME"] == "app"
    error_message = "Both workloads connect through the proxy"
  }
}

# ---- publishing ----

run "publishes_the_deploy_contract_and_the_stream_cap" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      # postdeploy sizes its backlog alarms from it, so the two stacks cannot drift apart.
      stream_length_cap       = "/example/dev/application/stream_length_cap"
      app_port                = "/example/dev/application/app_port"
      vpc_cidr                = "/example/dev/application/vpc_cidr"
      api_target_group_arn    = "/example/dev/application/api_target_group_arn"
      api_image_repository    = "/example/dev/application/api_image_repository"
      worker_image_repository = "/example/dev/application/worker_image_repository"
      api_environment_json    = "/example/dev/application/api_environment_json"
      worker_environment_json = "/example/dev/application/worker_environment_json"
      api_scaling_json        = "/example/dev/application/api_scaling_json"
      worker_scaling_json     = "/example/dev/application/worker_scaling_json"
    }
    error_message = "application publishes the stream cap and the nine deploy contract keys; the ECS keys are gone (design v4 §8.1)"
  }

  assert {
    condition     = local.published_strings.stream_length_cap == "100000"
    error_message = "The stream cap is published as a string"
  }
}

run "creates_nothing" {
  command = plan

  assert {
    condition     = length(module.ssm_publish.names) == 10 && local.workloads == ["api", "worker"]
    error_message = "application only publishes the deploy contract; CI runs the workloads with Helm"
  }
}

# ---- deploy contract (design v4 §8.1, §9) ----

run "deploy_contract_forwards_what_the_chart_needs" {
  command = plan

  assert {
    condition = (
      local.published_strings.app_port == "8080" &&
      local.published_strings.vpc_cidr == "10.10.0.0/16" &&
      local.published_strings.api_target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab" &&
      local.published_strings.api_image_repository == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api" &&
      local.published_strings.worker_image_repository == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
    )
    error_message = "CI reads the port, the VPC CIDR, the api target group and both repositories from the application prefix only"
  }
}

run "environment_json_is_the_workload_environment" {
  command = plan

  assert {
    condition     = jsondecode(local.published_strings.api_environment_json) == local.api_environment
    error_message = "api_environment_json is local.api_environment, unchanged"
  }

  assert {
    condition     = jsondecode(local.published_strings.worker_environment_json) == local.worker_environment
    error_message = "worker_environment_json is local.worker_environment, unchanged"
  }

  assert {
    condition     = alltrue([for k, v in jsondecode(local.published_strings.api_environment_json) : can(regex("^[A-Z][A-Z0-9_]*$", k)) && can(tostring(v))])
    error_message = "Every environment entry is an upper-case name with a string value"
  }

  assert {
    condition     = !anytrue([for k, _ in jsondecode(local.published_strings.api_environment_json) : can(regex("SECRET$|PASSWORD|PRIVATE_KEY$", k))])
    error_message = "Secrets travel as ARNs only (design v4 §8.2)"
  }
}

run "api_scaling_json_has_the_keda_fields" {
  command = plan

  variables {
    api_min_capacity          = 3
    api_max_capacity          = 9
    api_cpu_target_percent    = 55
    api_requests_per_target   = 250
    api_streams_per_task_high = 80
  }

  assert {
    condition = jsondecode(local.published_strings.api_scaling_json) == {
      min_replicas            = 3
      max_replicas            = 9
      cpu_target_percent      = 55
      requests_per_target     = 250
      streams_per_replica     = 80
      region                  = "ap-northeast-1"
      alb_arn_suffix          = "app/example-dev-alb/0123456789abcdef"
      target_group_arn_suffix = "targetgroup/example-dev-alb-api/0123456789ab"
    }
    error_message = "api scaling: replica bounds, the three triggers of design v4 §9 and the ALB dimensions"
  }
}

run "worker_scaling_json_targets_a_quarter_of_the_cap_per_replica" {
  command = plan

  variables {
    worker_min_capacity = 2
    worker_max_capacity = 5
    stream_length_cap   = 40000
  }

  assert {
    condition = jsondecode(local.published_strings.worker_scaling_json) == {
      min_replicas        = 2
      max_replicas        = 5
      backlog_per_replica = 10000
      region              = "ap-northeast-1"
      metric_namespace    = "Example/dev"
      metric_name         = "StreamBacklogMax"
      dimension_name      = "Env"
      dimension_value     = "dev"
    }
    error_message = "worker scaling follows the same backlog metric as example2, a quarter of stream_length_cap per replica"
  }
}
