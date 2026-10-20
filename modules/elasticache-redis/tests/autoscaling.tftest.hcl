mock_provider "aws" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_elasticache_replication_group.this
  override_during = plan
  values = {
    arn                            = "arn:aws:elasticache:ap-northeast-1:111111111111:replicationgroup:alpha-dev-redis"
    configuration_endpoint_address = "clustercfg.alpha-dev-redis.abc123.apne1.cache.amazonaws.com"
    member_clusters                = ["alpha-dev-redis-0001-001", "alpha-dev-redis-0001-002"]
  }
}

variables {
  name               = "alpha-dev-redis"
  engine_version     = "7.1"
  node_type          = "cache.r7g.large"
  subnet_ids         = ["subnet-0aaa1111", "subnet-0bbb2222"]
  security_group_ids = ["sg-0123456789abcdef0"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "no_autoscaling_creates_nothing" {
  command = plan

  assert {
    condition     = length(aws_appautoscaling_target.this) == 0
    error_message = "autoscaling = null must create no scalable target"
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0
    error_message = "autoscaling = null must create no scaling policy"
  }
}

run "autoscaling_creates_target_and_cpu_policy" {
  command = plan

  variables {
    autoscaling = { min_shards = 1, max_shards = 5 }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1 && length(aws_appautoscaling_policy.cpu) == 1
    error_message = "autoscaling must create one target and one policy"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].service_namespace == "elasticache" && aws_appautoscaling_target.this[0].scalable_dimension == "elasticache:replication-group:NodeGroups"
    error_message = "Target must scale ElastiCache node groups"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].resource_id == "replication-group/alpha-dev-redis"
    error_message = "resource_id must be replication-group/<name>"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].min_capacity == 1 && aws_appautoscaling_target.this[0].max_capacity == 5
    error_message = "min and max capacity must come from autoscaling"
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling"
    error_message = "Policy must be target tracking"
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].target_value == 70
    error_message = "Default target_cpu must be 70"
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ElastiCachePrimaryEngineCPUUtilization"
    error_message = "Policy must track primary engine CPU"
  }
}

run "target_cpu_override" {
  command = plan

  variables {
    autoscaling = { min_shards = 1, max_shards = 5, target_cpu = 60 }
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].target_value == 60
    error_message = "target_cpu must pass through"
  }
}

run "burstable_node_type_without_autoscaling_is_accepted" {
  command = plan

  variables {
    node_type = "cache.t4g.small"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.node_type == "cache.t4g.small"
    error_message = "cache.t* is fine when autoscaling is not used"
  }
}

run "burstable_t4g_with_autoscaling_is_rejected" {
  command = plan

  variables {
    node_type   = "cache.t4g.small"
    autoscaling = { min_shards = 1, max_shards = 3 }
  }

  expect_failures = [var.autoscaling]
}

run "burstable_t3_with_autoscaling_is_rejected" {
  command = plan

  variables {
    node_type   = "cache.t3.medium"
    autoscaling = { min_shards = 1, max_shards = 3 }
  }

  expect_failures = [var.autoscaling]
}

run "non_burstable_with_autoscaling_is_accepted" {
  command = plan

  variables {
    node_type   = "cache.m7g.large"
    autoscaling = { min_shards = 1, max_shards = 3 }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1
    error_message = "cache.m7g.* may use autoscaling"
  }
}

run "min_above_max_is_rejected" {
  command = plan

  variables {
    autoscaling = { min_shards = 4, max_shards = 3 }
  }

  expect_failures = [var.autoscaling]
}

run "min_equal_max_is_accepted" {
  command = plan

  variables {
    autoscaling = { min_shards = 1, max_shards = 1 }
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].min_capacity == 1
    error_message = "min_shards == max_shards is valid"
  }
}

run "num_node_groups_below_min_is_rejected" {
  command = plan

  variables {
    num_node_groups = 1
    autoscaling     = { min_shards = 2, max_shards = 4 }
  }

  expect_failures = [var.autoscaling]
}

run "num_node_groups_above_max_is_rejected" {
  command = plan

  variables {
    num_node_groups = 5
    autoscaling     = { min_shards = 1, max_shards = 4 }
  }

  expect_failures = [var.autoscaling]
}

run "target_cpu_out_of_range_is_rejected" {
  command = plan

  variables {
    autoscaling = { min_shards = 1, max_shards = 3, target_cpu = 101 }
  }

  expect_failures = [var.autoscaling]
}

run "min_shards_zero_is_rejected" {
  command = plan

  variables {
    autoscaling = { min_shards = 0, max_shards = 3 }
  }

  expect_failures = [var.autoscaling]
}

run "max_shards_above_500_is_rejected" {
  command = plan

  variables {
    autoscaling = { min_shards = 1, max_shards = 501 }
  }

  expect_failures = [var.autoscaling]
}

# num_node_groups is ignored after creation so autoscaling owns the shard count.
run "create_with_one_shard" {
  command = apply

  # Applied (not plan-time) override: the mock provider cannot keep plan-time overrides stable across apply.
  override_resource {
    target = aws_elasticache_replication_group.this
    values = {
      arn                            = "arn:aws:elasticache:ap-northeast-1:111111111111:replicationgroup:alpha-dev-redis"
      configuration_endpoint_address = "clustercfg.alpha-dev-redis.abc123.apne1.cache.amazonaws.com"
      member_clusters                = ["alpha-dev-redis-0001-001", "alpha-dev-redis-0001-002"]
    }
  }

  variables {
    autoscaling = { min_shards = 1, max_shards = 4 }
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_node_groups == 1
    error_message = "Initial shard count must be 1"
  }
}

run "changing_num_node_groups_afterwards_has_no_effect" {
  command = plan

  variables {
    num_node_groups = 2
    autoscaling     = { min_shards = 1, max_shards = 4 }
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_node_groups == 1
    error_message = "ignore_changes must keep the existing num_node_groups"
  }
}
