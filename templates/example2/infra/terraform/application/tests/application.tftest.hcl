mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  api_image_tag       = "0.1.0"
  worker_image_tag    = "0.1.0"
  cors_allow_origins  = ["https://app.example.com"]
}

override_module {
  target = module.in
  outputs = {
    strings = {
      api_target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab"
      alb_arn_suffix       = "app/example-dev-alb/0123456789abcdef"
      agent_runtime_arns   = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\"}"
      guardrail_ids        = "{\"default\":\"gr0input00001\",\"output\":\"gr0output00003\"}"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id                         = "vpc-0123456789abcdef0"
      app_sg_id                      = "sg-0123456789abcdef0"
      ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
      api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api-task"
      worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker-task"
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
      app_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
      services       = ["api", "worker", "import-extract", "import-load"]
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
      api_target_group_arn = "loadbalancer/api_target_group_arn"
      alb_arn_suffix       = "loadbalancer/alb_arn_suffix"
      agent_runtime_arns   = "agent/agent_runtime_arns"
      guardrail_ids        = "agent/guardrail_ids"
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
        app_sg_id                      = "sg-0123456789abcdef0"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api-task"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker-task"
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
        app_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
        services       = ["api"]
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

run "cluster_and_services_are_named_after_the_prefix" {
  command = plan

  assert {
    condition     = local.cluster_name == "example-dev-app" && local.service_names == { api = "example-dev-api", worker = "example-dev-worker" }
    error_message = "Names are <project>-<env>-<name>"
  }
}

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

run "secrets_are_passed_as_arns_the_task_role_reads_at_runtime" {
  command = plan

  assert {
    condition     = alltrue([for k, v in local.api_environment : endswith(k, "_ARN") ? startswith(v, "arn:") : true])
    error_message = "Names ending in _ARN carry ARNs; the execution role has no secret access, so the task fetches the value itself"
  }
}

run "api_registers_with_the_target_group_and_keeps_the_port" {
  command = plan

  assert {
    condition     = module.api.target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab"
    error_message = "The api service registers with the target group loadbalancer created"
  }

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
    error_message = "Both services connect through the proxy"
  }
}

run "system_controls_keep_idle_connections_alive" {
  command = plan

  assert {
    condition     = length(local.system_controls) == 3 && alltrue([for k in keys(local.system_controls) : startswith(k, "net.ipv4.tcp_keepalive_")])
    error_message = "Long-lived streams need TCP keepalive tuned on both services"
  }
}

# ---- autoscaling ----

run "api_scales_by_requests_cpu_connections_and_schedule" {
  command = plan

  variables {
    api_scheduled_scaling = {
      business_hours = { schedule = "cron(0 1 ? * MON-FRI *)", min_capacity = 4, max_capacity = 10 }
    }
  }

  assert {
    condition     = local.api_autoscaling.policy == "target_tracking" && local.api_autoscaling.target_tracking.requests_per_target == 300
    error_message = "Target tracking on requests per target, plus the built-in CPU policy"
  }

  assert {
    condition     = keys(local.api_autoscaling.step_policies) == ["streams_high"]
    error_message = "One step policy on the approximate active streams per task"
  }

  assert {
    condition     = length(local.api_autoscaling.step_policies["streams_high"].queries) == 3
    error_message = "Connections per task is metric math over two metrics"
  }

  assert {
    condition     = toset(keys(local.api_autoscaling.scheduled_actions)) == toset(["business_hours"])
    error_message = "Scheduled windows come from api_scheduled_scaling"
  }
}

run "connection_step_adjustments_grow_with_the_breach" {
  command = plan

  assert {
    condition = [for a in local.api_autoscaling.step_policies["streams_high"].adjustments : a.change] == [1, 2] && (
      local.api_autoscaling.step_policies["streams_high"].adjustments[0].upper == local.api_autoscaling.step_policies["streams_high"].adjustments[1].lower
    )
    error_message = "One more task for a moderate breach, two for a large one, and the bands must join up"
  }
}

run "worker_uses_custom_policy_with_a_high_and_a_low_backlog_step" {
  command = plan

  assert {
    condition     = local.worker_autoscaling.policy == "custom"
    error_message = "The worker scales on the stream backlog only"
  }

  assert {
    condition     = toset(keys(local.worker_autoscaling.step_policies)) == toset(["backlog_high", "backlog_drained"])
    error_message = "One policy to scale out and one to scale in"
  }

  assert {
    condition = (
      local.worker_autoscaling.step_policies["backlog_high"].threshold == 25000 &&
      local.worker_autoscaling.step_policies["backlog_drained"].threshold == 5000
    )
    error_message = "Thresholds are a quarter and a twentieth of the stream length cap"
  }

  assert {
    condition     = [for a in local.worker_autoscaling.step_policies["backlog_drained"].adjustments : a.change] == [-1]
    error_message = "Scale-in removes one task at a time"
  }
}

run "worker_metric_namespace_matches_the_iam_condition" {
  command = plan

  assert {
    condition     = local.metric_namespace == "Example/dev" && local.worker_autoscaling.step_policies["backlog_high"].metric.namespace == "Example/dev"
    error_message = "iam lets the worker publish metrics only into <Project>/<env>"
  }
}

run "rejects_a_scheduled_window_above_the_ceiling" {
  command = plan

  variables {
    api_scheduled_scaling = {
      too_big = { schedule = "cron(0 1 ? * MON-FRI *)", min_capacity = 4, max_capacity = 99 }
    }
  }

  expect_failures = [var.api_scheduled_scaling]
}

# ---- log groups follow the pattern iam grants ----

run "log_groups_are_under_the_ecs_prefix_iam_allows" {
  command = plan

  assert {
    condition     = module.api.log_group_name == "/ecs/example-dev-api" && module.worker.log_group_name == "/ecs/example-dev-worker"
    error_message = "iam grants log writes on /ecs/<project>-<env>-*"
  }
}

# ---- publishing ----

run "publishes_the_cluster_services_and_log_groups" {
  command = plan

  override_module {
    target = module.cluster
    outputs = {
      cluster_name = "example-dev-app"
      cluster_arn  = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/example-dev-app"
    }
  }

  override_module {
    target = module.api
    outputs = {
      service_name   = "example-dev-api"
      log_group_name = "/ecs/example-dev-api"
    }
  }

  override_module {
    target = module.worker
    outputs = {
      service_name   = "example-dev-worker"
      log_group_name = "/ecs/example-dev-worker"
    }
  }

  assert {
    condition = module.ssm_publish.names == {
      cluster_name          = "/example/dev/application/cluster_name"
      api_service_name      = "/example/dev/application/api_service_name"
      worker_service_name   = "/example/dev/application/worker_service_name"
      api_log_group_name    = "/example/dev/application/api_log_group_name"
      worker_log_group_name = "/example/dev/application/worker_log_group_name"
      api_max_capacity      = "/example/dev/application/api_max_capacity"
      worker_max_capacity   = "/example/dev/application/worker_max_capacity"
      stream_length_cap     = "/example/dev/application/stream_length_cap"
    }
    error_message = "application publishes eight keys under its own path"
  }

  assert {
    condition     = local.published_strings.api_max_capacity == "10" && local.published_strings.worker_max_capacity == "6" && local.published_strings.stream_length_cap == "100000"
    error_message = "The scaling ceilings and the stream cap are published so postdeploy sizes its alarms from the same numbers"
  }
}
