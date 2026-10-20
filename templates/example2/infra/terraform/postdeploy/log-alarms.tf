locals {
  log_group_names = {
    api    = module.in.strings["api_log_group_name"]
    worker = module.in.strings["worker_log_group_name"]
  }

  # The filters match the JSON field "event" the application writes on its own log lines.
  api_log_alarms = {
    persistence_enqueue_dropped = {
      pattern     = "{ $.event = \"persistence_enqueue_dropped\" }"
      metric_name = "PersistenceEnqueueDropped"
      description = "The hand-off queue to the stream is full and this turn's records were dropped without retry. Check the stream Redis latency and whether writes to it fail."
    }
    persistence_enqueue_failed = {
      pattern     = "{ $.event = \"persistence_enqueue_failed\" }"
      metric_name = "PersistenceEnqueueFailed"
      description = "Writing to the stream failed and the batch was dropped without retry. Memory errors point at the Redis memory; connection errors point at the cluster health or its security group."
    }
    rate_limit_fail_open = {
      pattern     = "{ $.event = \"rate_limit_fail_open\" }"
      metric_name = "RateLimitFailOpenSeconds"
      description = "The rate limit store is unreachable and requests pass unmetered. Users notice nothing, but only the WAF rate rule is left to cap spend. The unit is task-seconds."
      period      = 300
      threshold   = 60
    }
  }

  worker_log_alarms = {
    persistence_write_failed = {
      pattern     = "{ $.event = \"persistence_write_failed\" }"
      metric_name = "PersistenceWriteFailed"
      description = "Writing records to the database failed after retries. They stay pending and are retried, but sustained failure grows the stream until the cap trims it. Check the database proxy and the backlog growth."
    }
    persistence_dead_lettered = {
      pattern     = "{ $.event = \"persistence_dead_lettered\" }"
      metric_name = "PersistenceDeadLettered"
      description = "Records reached the dead-letter stream after retries or a decode failure. Nothing consumes that stream, so a person has to look at it to avoid losing the data."
    }
    persistence_consumer_died = {
      pattern     = "{ $.event = \"persistence_consumer_died\" }"
      metric_name = "PersistenceConsumerDied"
      description = "A consumer exited and nothing reads the stream until it is restarted. One event is self-healed; repeats mean the supervisor cannot recover it. Check the worker logs for the cause."
    }
  }
}

module "api_log_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.0"

  count = var.log_alarms_enabled ? 1 : 0

  name_prefix    = "${local.name_prefix}-api"
  log_group_name = local.log_group_names["api"]
  namespace      = local.metric_namespace
  alarms         = local.api_log_alarms
  sns_topic_arns = local.alarm_topic_arns
}

module "worker_log_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.0"

  count = var.log_alarms_enabled ? 1 : 0

  name_prefix    = "${local.name_prefix}-worker"
  log_group_name = local.log_group_names["worker"]
  namespace      = local.metric_namespace
  alarms         = local.worker_log_alarms
  sns_topic_arns = local.alarm_topic_arns
}
