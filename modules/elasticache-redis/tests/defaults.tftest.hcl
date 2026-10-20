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

run "fixed_security_settings" {
  command = plan

  assert {
    condition     = tostring(aws_elasticache_replication_group.this.at_rest_encryption_enabled) == "true"
    error_message = "At-rest encryption must always be on"
  }

  assert {
    condition     = tostring(aws_elasticache_replication_group.this.transit_encryption_enabled) == "true"
    error_message = "Transit encryption must always be on"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled == true
    error_message = "Automatic failover must always be on"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.multi_az_enabled == true
    error_message = "Multi-AZ must always be on"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.engine == "redis"
    error_message = "Engine must be redis"
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.replication_group_id == "alpha-dev-redis"
    error_message = "Replication group id must equal name"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_node_groups == 1 && aws_elasticache_replication_group.this.replicas_per_node_group == 1
    error_message = "Default is one shard with one replica"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.port == 6379
    error_message = "Default port must be 6379"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.snapshot_retention_limit == 0
    error_message = "Snapshots must be off by default"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.apply_immediately == false
    error_message = "apply_immediately must default to false"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == null
    error_message = "Without kms_key_arn the AWS managed key is used"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.node_type == "cache.r7g.large" && aws_elasticache_replication_group.this.engine_version == "7.1"
    error_message = "node_type and engine_version must pass through"
  }

  assert {
    condition     = toset(aws_elasticache_replication_group.this.security_group_ids) == toset(["sg-0123456789abcdef0"])
    error_message = "security_group_ids must pass through"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.subnet_group_name == aws_elasticache_subnet_group.this.name
    error_message = "Replication group must use the module subnet group"
  }

  assert {
    condition     = toset(aws_elasticache_subnet_group.this.subnet_ids) == toset(["subnet-0aaa1111", "subnet-0bbb2222"])
    error_message = "Subnet group must hold the given subnets"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.tags == tomap({ Name = "alpha-dev-redis" })
    error_message = "Without tags input the only tag is Name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.name != aws_cloudwatch_log_group.engine_log.name
    error_message = "Slow log and engine log must be separate log groups"
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.retention_in_days == 30 && aws_cloudwatch_log_group.engine_log.retention_in_days == 30
    error_message = "Default log retention must be 30 days"
  }
}

run "security_settings_stay_fixed_when_everything_is_customised" {
  command = plan

  variables {
    kms_key_arn              = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    num_node_groups          = 2
    replicas_per_node_group  = 2
    snapshot_retention_limit = 7
    apply_immediately        = true
    autoscaling              = { min_shards = 2, max_shards = 4 }
  }

  assert {
    condition = alltrue([
      tostring(aws_elasticache_replication_group.this.at_rest_encryption_enabled) == "true",
      tostring(aws_elasticache_replication_group.this.transit_encryption_enabled) == "true",
      aws_elasticache_replication_group.this.automatic_failover_enabled == true,
      aws_elasticache_replication_group.this.multi_az_enabled == true,
    ])
    error_message = "Encryption, failover and multi-AZ stay on no matter what else is set"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_node_groups == 2 && aws_elasticache_replication_group.this.replicas_per_node_group == 2
    error_message = "Shard and replica counts must pass through"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.snapshot_retention_limit == 7 && aws_elasticache_replication_group.this.apply_immediately == true
    error_message = "snapshot_retention_limit and apply_immediately must pass through"
  }
}

run "kms_key_is_used_for_data_and_logs" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_arn must be the at-rest key"
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.engine_log.kms_key_id == var.kms_key_arn
    error_message = "kms_key_arn must also encrypt both log groups"
  }
}

run "log_retention_override_and_tags" {
  command = plan

  variables {
    log_retention_days = 90
    tags               = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.retention_in_days == 90 && aws_cloudwatch_log_group.engine_log.retention_in_days == 90
    error_message = "log_retention_days must apply to both log groups"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-redis" })
    error_message = "Input tags must be kept and Name added"
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.tags["Project"] == "alpha" && aws_elasticache_subnet_group.this.tags["Project"] == "alpha"
    error_message = "Tags must reach the log groups and the subnet group"
  }
}

run "log_delivery_points_at_matching_log_groups" {
  command = plan

  assert {
    condition = {
      for l in aws_elasticache_replication_group.this.log_delivery_configuration : l.log_type => l.destination
      } == {
      "slow-log"   = "/aws/elasticache/alpha-dev-redis/slow-log"
      "engine-log" = "/aws/elasticache/alpha-dev-redis/engine-log"
    }
    error_message = "slow-log and engine-log must each deliver to their own log group"
  }

  assert {
    condition     = alltrue([for l in aws_elasticache_replication_group.this.log_delivery_configuration : l.destination_type == "cloudwatch-logs" && l.log_format == "json"])
    error_message = "Both deliveries must be cloudwatch-logs in json format"
  }

  assert {
    condition     = aws_cloudwatch_log_group.slow_log.name == "/aws/elasticache/alpha-dev-redis/slow-log" && aws_cloudwatch_log_group.engine_log.name == "/aws/elasticache/alpha-dev-redis/engine-log"
    error_message = "Log group names must follow /aws/elasticache/<name>/<type>"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.configuration_endpoint == "clustercfg.alpha-dev-redis.abc123.apne1.cache.amazonaws.com"
    error_message = "configuration_endpoint must be the cluster-mode configuration endpoint"
  }

  assert {
    condition     = output.port == 6379 && output.replication_group_id == "alpha-dev-redis"
    error_message = "port and replication_group_id outputs are wrong"
  }

  assert {
    condition     = join(",", output.member_clusters) == "alpha-dev-redis-0001-001,alpha-dev-redis-0001-002"
    error_message = "member_clusters must list the members"
  }

  assert {
    condition     = output.arn == "arn:aws:elasticache:ap-northeast-1:111111111111:replicationgroup:alpha-dev-redis"
    error_message = "arn output is wrong"
  }

  assert {
    condition     = output.log_group_names == { slow_log = "/aws/elasticache/alpha-dev-redis/slow-log", engine_log = "/aws/elasticache/alpha-dev-redis/engine-log" }
    error_message = "log_group_names must expose both log groups"
  }
}
