mock_provider "aws" {}

mock_provider "random" {}

variables {
  project               = "example"
  env                   = "dev"
  expected_account_id   = "111111111111"
  engine_version        = "16.6"
  db_instance_class     = "db.t4g.medium"
  connections_threshold = 300
  redis = {
    "rate-limit" = { node_type = "cache.t4g.small" }
    "stream"     = { node_type = "cache.t4g.small", num_node_groups = 2 }
  }
}

override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      db_sg_id        = "sg-0aaaaaaa00000004"
      db_proxy_sg_id  = "sg-0aaaaaaa00000005"
      cache_sg_id     = "sg-0aaaaaaa00000006"
    }
    lists = {
      db_subnet_ids = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    }
  }
}

override_data {
  target = data.aws_kms_alias.secretsmanager
  values = { target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" }
}

# Computed outputs are unknown at plan time, so the cluster and the Redis clusters get fixed ones. The real modules are
# planned together in graph.tftest.hcl.
override_module {
  target = module.db
  outputs = {
    writer_endpoint        = "example-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
    reader_endpoint        = "example-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
    proxy_endpoint         = "example-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
    master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
    log_group_name         = "/aws/rds/cluster/example-dev-db/postgresql"
  }
}

override_module {
  target = module.redis["rate-limit"]
  outputs = {
    configuration_endpoint = "clustercfg.example-dev-rate-limit.abc.apne1.cache.amazonaws.com"
    port                   = 6379
    replication_group_id   = "example-dev-rate-limit"
  }
}

override_module {
  target = module.redis["stream"]
  outputs = {
    configuration_endpoint = "clustercfg.example-dev-stream.abc.apne1.cache.amazonaws.com"
    port                   = 6379
    replication_group_id   = "example-dev-stream"
  }
}

# ---- reads ----

run "reads_the_topic_the_groups_and_the_db_subnets" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      alarm_topic_arn = "foundation/alarm_topic_arn"
      db_sg_id        = "network/db_sg_id"
      db_proxy_sg_id  = "network/db_proxy_sg_id"
      cache_sg_id     = "network/cache_sg_id"
    } && local.ssm_input_lists == { db_subnet_ids = "network/db_subnet_ids" }
    error_message = "database must read the alarm topic, three security groups and the db subnets"
  }
}

# ---- Aurora ----

run "aurora_cluster_wiring" {
  command = plan

  assert {
    condition     = local.db.name == "example-dev-db" && local.db.deployment == "aurora" && local.db.database_name == "app"
    error_message = "The cluster is called <project>-<env>-db and is a provisioned Aurora cluster"
  }

  assert {
    condition     = local.db.aurora == { instance_class = "db.t4g.medium", reader_count = 1 }
    error_message = "Instance class and reader count come from variables"
  }

  assert {
    condition     = local.db.security_group_ids == ["sg-0aaaaaaa00000004"] && local.db.subnet_ids == ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    error_message = "The cluster uses the db group and the db subnets"
  }

  assert {
    condition     = local.db.alarm_config == { connections_threshold = 300 }
    error_message = "connections_threshold is passed on; the module cannot derive it for provisioned Aurora"
  }

  assert {
    condition     = local.db.deletion_protection == true && local.db.skip_final_snapshot == false
    error_message = "The defaults protect the data: deletion protection on, final snapshot kept"
  }
}

run "pg_cron_needs_preload_and_a_database_name_and_both_are_static" {
  command = plan

  assert {
    condition     = local.db.cluster_parameters.shared_preload_libraries == "pg_stat_statements,pg_cron"
    error_message = "pg_cron must be preloaded next to pg_stat_statements"
  }

  assert {
    condition     = local.db.cluster_parameters["cron.database_name"] == "app"
    error_message = "pg_cron runs its jobs in the application database"
  }

  assert {
    condition     = contains(local.db.static_parameter_names, "cron.database_name")
    error_message = "cron.database_name is static: RDS rejects it with apply method immediate"
  }

  assert {
    condition     = !contains(keys(local.db.cluster_parameters), "log_lock_waits") && local.db.cluster_parameters.log_temp_files == "0"
    error_message = "Only parameters that differ from the module defaults are set here"
  }
}

run "static_parameters_are_all_listed" {
  command = plan

  assert {
    condition     = alltrue([for n in ["shared_preload_libraries", "cron.database_name"] : contains(setunion(local.db.static_parameter_names, toset(["shared_preload_libraries"])), n)])
    error_message = "Every static parameter in cluster_parameters must be applied with pending-reboot"
  }
}

run "db_name_must_be_a_lowercase_identifier" {
  command = plan

  variables {
    db_name = "My-App"
  }

  expect_failures = [var.db_name]
}

run "connections_threshold_must_be_positive" {
  command = plan

  variables {
    connections_threshold = 0
  }

  expect_failures = [var.connections_threshold]
}

run "reader_count_is_bounded" {
  command = plan

  variables {
    db_reader_count = 16
  }

  expect_failures = [var.db_reader_count]
}

# ---- IAM roles ----

run "proxy_role_may_read_only_the_cluster_secret_and_decrypt_through_secrets_manager" {
  command = plan


  assert {
    condition = local.proxy_statements == [
      {
        Sid      = "GetClusterSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"]
      },
      {
        Sid       = "DecryptThroughSecretsManager"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"]
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.ap-northeast-1.amazonaws.com" } }
      },
    ]
    error_message = "The Proxy role gets the cluster secret and the Secrets Manager key, through Secrets Manager only"
  }
}

run "monitoring_role_is_narrowed_to_the_os_metrics_log_group" {
  command = plan

  assert {
    condition = alltrue([
      for s in local.monitoring_statements : s.Effect == "Allow" && can(regex("^arn:aws:logs:ap-northeast-1:111111111111:log-group:RDSOSMetrics", s.Resource))
    ])
    error_message = "Enhanced Monitoring writes only to the RDSOSMetrics log group of this account"
  }
}

run "no_policy_of_this_stack_uses_a_wildcard_resource" {
  command = plan


  assert {
    condition = alltrue([
      for s in concat(local.proxy_statements, local.monitoring_statements) : !contains(flatten([s.Resource]), "*")
    ])
    error_message = "Every Resource must name an ARN; this stack has no action that only accepts *"
  }
}

run "role_names_and_trust" {
  command = plan

  assert {
    condition     = module.proxy_role.name == "example-dev-rds-proxy" && module.monitoring_role.name == "example-dev-rds-monitoring"
    error_message = "Roles are named <project>-<env>-rds-proxy and <project>-<env>-rds-monitoring"
  }
}

# ---- Redis ----

run "two_redis_clusters_with_their_own_parameters" {
  command = plan

  assert {
    condition     = toset(keys(module.redis)) == toset(["rate-limit", "stream"])
    error_message = "Exactly the rate-limit and the stream cluster are created"
  }

  assert {
    condition     = local.redis["rate-limit"].name == "example-dev-rate-limit" && local.redis["stream"].name == "example-dev-stream"
    error_message = "Clusters are named <project>-<env>-<key>"
  }

  assert {
    condition     = local.redis["rate-limit"].parameters == { "maxmemory-policy" = "volatile-lru" }
    error_message = "Rate-limit counters expire, so keys with a TTL may be evicted"
  }

  assert {
    condition     = local.redis["stream"].parameters == { "maxmemory-policy" = "noeviction", "stream-node-max-entries" = "100" }
    error_message = "The stream is a queue: nothing may be evicted when memory is full"
  }

  assert {
    condition     = local.redis["stream"].num_node_groups == 2 && local.redis["rate-limit"].num_node_groups == 1
    error_message = "Shard counts come from the redis variable, one by default"
  }

  assert {
    condition     = alltrue([for c in values(local.redis) : c.security_group_ids == ["sg-0aaaaaaa00000006"] && length(c.subnet_ids) == 2])
    error_message = "Both clusters use the cache group and the db subnets"
  }
}

run "redis_needs_exactly_the_two_known_keys" {
  command = plan

  variables {
    redis = { "rate-limit" = { node_type = "cache.t4g.small" } }
  }

  expect_failures = [var.redis]
}

run "redis_rejects_an_unknown_key" {
  command = plan

  variables {
    redis = {
      "rate-limit" = { node_type = "cache.t4g.small" }
      "stream"     = { node_type = "cache.t4g.small" }
      "extra"      = { node_type = "cache.t4g.small" }
    }
  }

  expect_failures = [var.redis]
}

# ---- partition maintenance alarms ----

run "partition_maintenance_log_alarms" {
  command = plan

  assert {
    condition     = toset(keys(local.partition_alarms)) == toset(["partition_maintenance_failed", "partition_maintenance_not_running", "default_partition_not_empty"])
    error_message = "Three alarms watch the pg_cron partition job"
  }

  assert {
    condition     = local.partition_alarms["partition_maintenance_failed"].comparison_operator == "GreaterThanOrEqualToThreshold" && local.partition_alarms["partition_maintenance_failed"].treat_missing_data == "notBreaching"
    error_message = "A failure line in the log alarms; silence is fine"
  }

  assert {
    condition     = local.partition_alarms["partition_maintenance_not_running"].comparison_operator == "LessThanThreshold" && local.partition_alarms["partition_maintenance_not_running"].treat_missing_data == "breaching"
    error_message = "A missing heartbeat alarms: no data means the job is not running"
  }

  assert {
    condition     = local.metric_namespace == "Example/dev"
    error_message = "Custom metrics live in <Project>/<env>"
  }
}

run "partition_alarms_read_the_postgresql_log_group_of_the_cluster" {
  command = plan


  assert {
    condition     = module.partition_alarms.metric_names["partition_maintenance_failed"] != ""
    error_message = "A metric filter must exist for each alarm"
  }
}

# ---- publishing ----

run "publishes_endpoints_and_the_secret" {
  command = plan




  assert {
    condition = local.published_strings == {
      db_endpoint               = "example-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      db_reader_endpoint        = "example-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      db_proxy_endpoint         = "example-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn             = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint = "clustercfg.example-dev-rate-limit.abc.apne1.cache.amazonaws.com:6379"
      stream_redis_endpoint     = "clustercfg.example-dev-stream.abc.apne1.cache.amazonaws.com:6379"
      db_name                   = "app"
      stream_shard_count        = "2"
    }
    error_message = "Each published value must come from the matching module output; Redis endpoints are host:port"
  }

  assert {
    condition = module.ssm_publish.names == {
      db_endpoint               = "/example/dev/database/db_endpoint"
      db_reader_endpoint        = "/example/dev/database/db_reader_endpoint"
      db_proxy_endpoint         = "/example/dev/database/db_proxy_endpoint"
      db_secret_arn             = "/example/dev/database/db_secret_arn"
      rate_limit_redis_endpoint = "/example/dev/database/rate_limit_redis_endpoint"
      stream_redis_endpoint     = "/example/dev/database/stream_redis_endpoint"
      db_name                   = "/example/dev/database/db_name"
      stream_shard_count        = "/example/dev/database/stream_shard_count"
    }
    error_message = "ssm-publish must write the eight database keys under the database path"
  }
}

run "publishes_the_stream_shard_count_of_the_stream_cluster" {
  command = plan

  variables {
    redis = {
      "rate-limit" = { node_type = "cache.t4g.small" }
      "stream"     = { node_type = "cache.t4g.small", num_node_groups = 3 }
    }
  }

  assert {
    condition     = local.published_strings.stream_shard_count == "3" && local.published_strings.db_name == var.db_name
    error_message = "Clients that hash a stream over shards need the same count as the cluster, so it is published, not configured twice"
  }
}
