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

run "replicas_zero_is_rejected" {
  command = plan

  variables {
    replicas_per_node_group = 0
  }

  expect_failures = [var.replicas_per_node_group]
}

run "replicas_one_is_accepted" {
  command = plan

  variables {
    replicas_per_node_group = 1
  }

  assert {
    condition     = aws_elasticache_replication_group.this.replicas_per_node_group == 1
    error_message = "One replica per shard is the minimum"
  }
}

run "replicas_above_5_is_rejected" {
  command = plan

  variables {
    replicas_per_node_group = 6
  }

  expect_failures = [var.replicas_per_node_group]
}

run "name_of_41_chars_is_rejected" {
  command = plan

  variables {
    name = "a2345678901234567890123456789012345678901"
  }

  expect_failures = [var.name]
}

run "name_of_40_chars_is_accepted" {
  command = plan

  variables {
    name = "a234567890123456789012345678901234567890"
  }

  override_resource {
    target          = aws_elasticache_replication_group.this
    override_during = plan
    values = {
      member_clusters = ["a234567890123456789012345678901234567890-0001-001", "a234567890123456789012345678901234567890-0001-002"]
    }
  }

  assert {
    condition     = length(aws_elasticache_replication_group.this.replication_group_id) == 40
    error_message = "A 40 char name is the limit and must be accepted"
  }
}

run "name_with_uppercase_is_rejected" {
  command = plan

  variables {
    name = "Alpha-dev-redis"
  }

  expect_failures = [var.name]
}

run "name_with_double_hyphen_is_rejected" {
  command = plan

  variables {
    name = "alpha--redis"
  }

  expect_failures = [var.name]
}

run "name_ending_with_hyphen_is_rejected" {
  command = plan

  variables {
    name = "alpha-redis-"
  }

  expect_failures = [var.name]
}

run "empty_name_is_rejected" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "engine_version_5_is_rejected" {
  command = plan

  variables {
    engine_version = "5.0.6"
  }

  expect_failures = [var.engine_version]
}

run "engine_version_garbage_is_rejected" {
  command = plan

  variables {
    engine_version = "latest"
  }

  expect_failures = [var.engine_version]
}

run "node_type_without_cache_prefix_is_rejected" {
  command = plan

  variables {
    node_type = "r7g.large"
  }

  expect_failures = [var.node_type]
}

run "single_subnet_is_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaa1111"]
  }

  expect_failures = [var.subnet_ids]
}

run "empty_security_groups_are_rejected" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "num_node_groups_zero_is_rejected" {
  command = plan

  variables {
    num_node_groups = 0
  }

  expect_failures = [var.num_node_groups]
}

run "num_node_groups_above_500_is_rejected" {
  command = plan

  variables {
    num_node_groups = 501
  }

  expect_failures = [var.num_node_groups]
}

run "port_zero_is_rejected" {
  command = plan

  variables {
    port = 0
  }

  expect_failures = [var.port]
}

run "port_above_65535_is_rejected" {
  command = plan

  variables {
    port = 65536
  }

  expect_failures = [var.port]
}

run "snapshot_retention_above_35_is_rejected" {
  command = plan

  variables {
    snapshot_retention_limit = 36
  }

  expect_failures = [var.snapshot_retention_limit]
}

run "log_retention_zero_is_rejected" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

run "log_retention_unsupported_value_is_rejected" {
  command = plan

  variables {
    log_retention_days = 2
  }

  expect_failures = [var.log_retention_days]
}

run "description_defaults_to_a_generated_text" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.description != null && aws_elasticache_replication_group.this.description != ""
    error_message = "A replication group always needs a description"
  }
}

run "description_override" {
  command = plan

  variables {
    description = "Rate limit store"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.description == "Rate limit store"
    error_message = "description must pass through"
  }
}
