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

run "default_creates_one_memory_alarm_per_member_and_no_evictions_alarm" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.memory_high) == 2
    error_message = "1 shard x (1 replica + 1 primary) must give 2 memory alarms"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.evictions_high) == 0
    error_message = "Without evictions_threshold no evictions alarm may exist"
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.memory_high)) == toset(["alpha-dev-redis-0001-001", "alpha-dev-redis-0001-002"])
    error_message = "Memory alarms must be keyed by the derived member ids"
  }
}

run "memory_alarm_settings" {
  command = plan

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.memory_high : a.metric_name == "DatabaseMemoryUsagePercentage" && a.namespace == "AWS/ElastiCache"])
    error_message = "Memory alarms must use AWS/ElastiCache DatabaseMemoryUsagePercentage"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.memory_high : a.threshold == 80 && a.comparison_operator == "GreaterThanOrEqualToThreshold"])
    error_message = "Default memory threshold is 80 with >="
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.memory_high["alpha-dev-redis-0001-002"].dimensions == tomap({ CacheClusterId = "alpha-dev-redis-0001-002" })
    error_message = "Each alarm must target its own member via CacheClusterId"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.memory_high["alpha-dev-redis-0001-001"].alarm_name == "alpha-dev-redis-0001-001-memory-high"
    error_message = "Alarm name must be <member>-memory-high"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.memory_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "alarm_actions and ok_actions must both be the SNS topics"
  }
}

run "memory_percent_override" {
  command = plan

  variables {
    alarm_config = { memory_percent = 90 }
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.memory_high : a.threshold == 90])
    error_message = "memory_percent must pass through"
  }
}

run "evictions_alarm_per_member_when_threshold_given" {
  command = plan

  variables {
    alarm_config = { evictions_threshold = 100 }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.evictions_high) == 2
    error_message = "evictions_threshold must create one evictions alarm per member"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.evictions_high : a.metric_name == "Evictions" && a.threshold == 100 && a.namespace == "AWS/ElastiCache"])
    error_message = "Evictions alarms must use the Evictions metric and the given threshold"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.evictions_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "Evictions alarms must notify the SNS topics on alarm and OK"
  }
}

run "memory_alarm_count_is_shards_times_nodes" {
  command = plan

  override_resource {
    target          = aws_elasticache_replication_group.this
    override_during = plan
    values = {
      member_clusters = [
        "alpha-dev-redis-0001-001", "alpha-dev-redis-0001-002", "alpha-dev-redis-0001-003",
        "alpha-dev-redis-0002-001", "alpha-dev-redis-0002-002", "alpha-dev-redis-0002-003",
      ]
    }
  }

  variables {
    num_node_groups         = 2
    replicas_per_node_group = 2
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.memory_high) == 6
    error_message = "2 shards x (2 replicas + 1 primary) must give 6 memory alarms"
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.memory_high), "alpha-dev-redis-0002-003")
    error_message = "Derived ids must use 4-digit shard and 3-digit node numbers"
  }
}

run "derived_ids_not_matching_the_real_members_are_rejected" {
  command = plan

  override_resource {
    target          = aws_elasticache_replication_group.this
    override_during = plan
    values = {
      member_clusters = ["alpha-dev-redis-001", "alpha-dev-redis-002"]
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.memory_high]
}

run "member_count_mismatch_is_rejected" {
  command = plan

  override_resource {
    target          = aws_elasticache_replication_group.this
    override_during = plan
    values = {
      member_clusters = ["alpha-dev-redis-0001-001", "alpha-dev-redis-0001-002", "alpha-dev-redis-0002-001", "alpha-dev-redis-0002-002"]
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.memory_high]
}

run "alarm_arns_output_is_keyed_by_alarm_name" {
  command = plan

  variables {
    alarm_config = { evictions_threshold = 100 }
  }

  assert {
    condition     = length(output.alarm_arns) == 4
    error_message = "alarm_arns must include memory and evictions alarms"
  }

  assert {
    condition     = contains(keys(output.alarm_arns), "alpha-dev-redis-0001-001-memory-high") && contains(keys(output.alarm_arns), "alpha-dev-redis-0001-002-evictions-high")
    error_message = "alarm_arns keys must be the alarm names"
  }
}

run "empty_sns_topics_are_rejected" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "non_sns_arn_is_rejected" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:alpha"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "memory_percent_above_100_is_rejected" {
  command = plan

  variables {
    alarm_config = { memory_percent = 101 }
  }

  expect_failures = [var.alarm_config]
}

run "memory_percent_zero_is_rejected" {
  command = plan

  variables {
    alarm_config = { memory_percent = 0 }
  }

  expect_failures = [var.alarm_config]
}

run "evictions_threshold_zero_is_rejected" {
  command = plan

  variables {
    alarm_config = { evictions_threshold = 0 }
  }

  expect_failures = [var.alarm_config]
}
