mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_module {
  target = module.in
  outputs = {
    strings = {
      alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
      target_group_arn_suffixes = "{\"api\":\"targetgroup/example-dev-alb-api/0123456789ab\"}"
      cluster_name              = "example-dev"
      app_namespace             = "app"
      stream_length_cap         = "100000"
      agent_runtime_arns        = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\"}"
      agent_memory_arn          = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/example_dev_memory-KlMnOpQr"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
    }
  }
}

# ---- reads ----

run "reads_the_late_stack_keys_from_tree_a_and_only_the_topic_from_tree_b" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      alb_arn_suffix            = "loadbalancer/alb_arn_suffix"
      target_group_arn_suffixes = "loadbalancer/target_group_arn_suffixes"
      cluster_name              = "eks-cluster/cluster_name"
      app_namespace             = "eks-cluster/app_namespace"
      stream_length_cap         = "application/stream_length_cap"
      agent_runtime_arns        = "agent/agent_runtime_arns"
      agent_memory_arn          = "agent/agent_memory_arn"
    }
    error_message = "postdeploy reads what the other late stacks published"
  }

  assert {
    condition     = local.shared_input_strings == { alarm_topic_arn = "infra/alarm_topic_arn" }
    error_message = "The alarm topic is the only tree B key"
  }
}

# ---- every feature is off until it is switched on ----

run "nothing_is_created_by_default" {
  command = plan

  assert {
    condition = (
      length(module.workload_alarms) == 0 && length(module.stream_alarms) == 0 &&
      length(module.api_log_alarms) == 0 && length(module.worker_log_alarms) == 0 && length(module.traces) == 0
    )
    error_message = "All five features default to off"
  }
}

# ---- the switches are independent ----

run "workload_alarms_alone" {
  command = plan

  variables {
    workload_alarms_enabled = true
  }

  assert {
    condition = (
      toset(keys(module.workload_alarms)) == toset(["api", "worker"]) && length(module.stream_alarms) == 0 &&
      length(module.api_log_alarms) == 0 && length(module.worker_log_alarms) == 0 && length(module.traces) == 0
    )
    error_message = "Only the two workload alarm modules appear"
  }
}

run "stream_alarms_alone" {
  command = plan

  variables {
    stream_alarms_enabled = true
  }

  assert {
    condition = (
      length(module.stream_alarms) == 1 && length(module.workload_alarms) == 0 &&
      length(module.api_log_alarms) == 0 && length(module.worker_log_alarms) == 0 && length(module.traces) == 0
    )
    error_message = "Only the stream alarms appear"
  }
}

run "log_alarms_alone" {
  command = plan

  variables {
    log_alarms_enabled = true
  }

  assert {
    condition = (
      length(module.api_log_alarms) == 1 && length(module.worker_log_alarms) == 1 && length(module.workload_alarms) == 0 &&
      length(module.stream_alarms) == 0 && length(module.traces) == 0
    )
    error_message = "Only the two log alarm modules appear"
  }
}

run "tracing_alone" {
  command = plan

  variables {
    tracing_enabled = true
  }

  assert {
    condition = (
      length(module.traces) == 1 && length(module.workload_alarms) == 0 && length(module.stream_alarms) == 0 &&
      length(module.api_log_alarms) == 0 && length(module.worker_log_alarms) == 0
    )
    error_message = "Only the trace delivery appears"
  }
}

run "all_features_together" {
  command = plan

  variables {
    workload_alarms_enabled = true
    stream_alarms_enabled   = true
    log_alarms_enabled      = true
    tracing_enabled         = true
  }

  assert {
    condition = (
      length(module.workload_alarms) == 2 && length(module.stream_alarms) == 1 && length(module.api_log_alarms) == 1 &&
      length(module.worker_log_alarms) == 1 && length(module.traces) == 1
    )
    error_message = "Switching everything on adds up"
  }
}

# ---- workload alarms (design v4 §10) ----

run "api_alarms_include_the_target_group" {
  command = plan

  assert {
    condition = local.workloads["api"].load_balancer == {
      alb_arn_suffix          = "app/example-dev-alb/0123456789abcdef"
      target_group_arn_suffix = "targetgroup/example-dev-alb-api/0123456789ab"
    }
    error_message = "The api gets the target 5xx, latency and healthy host alarms on its target group"
  }

  assert {
    condition     = local.workloads["worker"].load_balancer == null
    error_message = "The worker sits behind no load balancer"
  }
}

run "workload_alarms_watch_the_deployments_ci_creates" {
  command = plan

  variables {
    workload_alarms_enabled = true
  }

  assert {
    condition     = toset(keys(module.workload_alarms)) == toset(["api", "worker"])
    error_message = "One alarm set per workload"
  }

  assert {
    condition = (
      local.workload_alarm_inputs["api"].cluster_name == "example-dev" &&
      local.workload_alarm_inputs["api"].namespace == "app" &&
      local.workload_alarm_inputs["api"].workload_name == "api" &&
      local.workload_alarm_inputs["api"].container_name == "api" &&
      local.workload_alarm_inputs["worker"].workload_name == "worker" &&
      local.workload_alarm_inputs["api"].name == "example-dev-api"
    )
    error_message = "Deployments and containers are named after the workload (deploy/charts/app, release api or worker) in the eks-cluster namespace"
  }

  assert {
    condition     = length(module.workload_alarms["api"].alarm_names) > length(module.workload_alarms["worker"].alarm_names)
    error_message = "The api has the load balancer alarms on top of the workload ones"
  }
}

# ---- stream alarms ----

run "stream_backlog_pages_at_half_the_cap_and_missing_consumers_page_on_silence" {
  command = plan

  assert {
    condition     = local.stream_alarms["backlog_high"].threshold == 50000 && local.stream_alarms["backlog_high"].evaluation_periods == 5
    error_message = "A backlog above half of the cap that lasts five minutes is the page; the autoscaling alarms at a quarter are only for capacity"
  }

  assert {
    condition     = local.stream_alarms["no_consumers"].comparison_operator == "LessThanThreshold" && local.stream_alarms["no_consumers"].treat_missing_data == "breaching"
    error_message = "No metric at all means the reporter is gone too, so missing data counts as a breach"
  }

  assert {
    condition     = alltrue([for a in values(local.stream_alarms) : a.metric.namespace == "Example/dev" && a.metric.dimensions == { Env = "dev" }])
    error_message = "The stream metrics are the custom ones the worker publishes into <Project>/<env>"
  }
}

# ---- log alarms ----

run "log_alarms_match_json_events_in_the_right_log_group" {
  command = plan

  assert {
    condition     = toset(keys(local.api_log_alarms)) == toset(["record_enqueue_dropped", "record_enqueue_failed", "rate_limiter_unavailable"])
    error_message = "The api reports dropped or failed hand-offs and rate limit fail-open"
  }

  assert {
    condition     = toset(keys(local.worker_log_alarms)) == toset(["record_write_failed", "record_dead_lettered", "record_consumer_stopped"])
    error_message = "The worker reports failed writes, dead letters and a dead consumer"
  }

  assert {
    condition = alltrue([
      for k, a in local.api_log_alarms : a.pattern == "{ $.kubernetes.namespace_name = \"app\" && $.kubernetes.container_name = \"api\" && $.log_processed.event = \"${k}\" }"
    ])
    error_message = "Fluent Bit puts the parsed JSON line under log_processed; the api filters also match the namespace and the container"
  }

  assert {
    condition = alltrue([
      for k, a in local.worker_log_alarms : strcontains(a.pattern, "$.kubernetes.container_name = \"worker\"") && strcontains(a.pattern, "$.log_processed.event = \"${k}\"")
    ])
    error_message = "The worker filters match the worker container only"
  }
}

run "rate_limiter_unavailable_alarms_on_a_minute_of_pod_seconds_in_five_minutes" {
  command = plan

  assert {
    condition     = local.api_log_alarms["rate_limiter_unavailable"].period == 300 && local.api_log_alarms["rate_limiter_unavailable"].threshold == 60
    error_message = "A short blip is tolerated; a minute of Pod time unmetered in five minutes is not"
  }
}

run "log_alarms_read_the_container_insights_application_log_group" {
  command = plan

  variables {
    log_alarms_enabled = true
  }

  assert {
    condition     = local.application_log_group_name == "/aws/containerinsights/example-dev/application"
    error_message = "The CloudWatch observability add-on writes every container log of the cluster to this group"
  }
}

# ---- trace delivery ----

run "traces_cover_each_runtime_and_the_memory_and_go_to_xray" {
  command = plan

  assert {
    condition     = toset(keys(local.trace_sources)) == toset(["runtime-agent", "memory"])
    error_message = "One source per Runtime plus the Memory"
  }

  assert {
    condition     = alltrue([for s in values(local.trace_sources) : s.log_type == "TRACES"])
    error_message = "Traces, not application logs"
  }

  assert {
    condition     = local.trace_destinations == { xray = { type = "XRAY" } }
    error_message = "A single X-Ray destination"
  }

  assert {
    condition     = toset(keys(local.trace_deliveries)) == toset(["runtime-agent", "memory"]) && alltrue([for d in values(local.trace_deliveries) : d.destination == "xray"])
    error_message = "Every source is delivered to X-Ray"
  }
}

run "a_second_runtime_gets_its_own_trace_source" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
        target_group_arn_suffixes = "{\"api\":\"targetgroup/example-dev-alb-api/0123456789ab\"}"
        cluster_name              = "example-dev"
        app_namespace             = "app"
        stream_length_cap         = "100000"
        agent_runtime_arns        = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\",\"agent-lite\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent_lite-XyZxYzXy\"}"
        agent_memory_arn          = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/example_dev_memory-KlMnOpQr"
      }
    }
  }

  assert {
    condition     = length(local.trace_sources) == 3
    error_message = "Two Runtimes and the Memory"
  }
}
