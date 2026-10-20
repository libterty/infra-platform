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

run "cluster_mode_is_always_enabled" {
  command = plan

  assert {
    condition     = { for p in aws_elasticache_parameter_group.this.parameter : p.name => p.value } == { "cluster-enabled" = "yes" }
    error_message = "With no parameters the group must only set cluster-enabled = yes"
  }
}

run "parameters_are_merged_on_top" {
  command = plan

  variables {
    parameters = { "maxmemory-policy" = "volatile-lru" }
  }

  assert {
    condition     = { for p in aws_elasticache_parameter_group.this.parameter : p.name => p.value } == { "cluster-enabled" = "yes", "maxmemory-policy" = "volatile-lru" }
    error_message = "Caller parameters must be merged with cluster-enabled"
  }
}

run "replication_group_uses_the_parameter_group" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.parameter_group_name == aws_elasticache_parameter_group.this.name
    error_message = "Replication group must use the module parameter group"
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.name == "alpha-dev-redis"
    error_message = "Parameter group is named after name"
  }
}

run "overriding_cluster_enabled_is_rejected" {
  command = plan

  variables {
    parameters = { "cluster-enabled" = "no" }
  }

  expect_failures = [var.parameters]
}

run "overriding_cluster_enabled_is_rejected_case_insensitive" {
  command = plan

  variables {
    parameters = { "Cluster-Enabled" = "no" }
  }

  expect_failures = [var.parameters]
}

run "family_for_redis_7_1" {
  command = plan

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "redis7"
    error_message = "7.1 must map to redis7"
  }
}

run "family_for_redis_7_0" {
  command = plan

  variables {
    engine_version = "7.0"
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "redis7"
    error_message = "7.0 must map to redis7"
  }
}

run "family_for_redis_6_2" {
  command = plan

  variables {
    engine_version = "6.2"
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "redis6.x"
    error_message = "6.2 must map to redis6.x, the family name AWS uses for Redis 6"
  }
}

run "family_for_redis_6_x" {
  command = plan

  variables {
    engine_version = "6.x"
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "redis6.x"
    error_message = "6.x must map to redis6.x"
  }
}
