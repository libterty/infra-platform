locals {
  engine_major = tonumber(split(".", var.engine_version)[0])
  # AWS names the Redis 6 family redis6.x; Redis 7 is redis7.
  parameter_group_family = local.engine_major == 6 ? "redis6.x" : "redis${local.engine_major}"

  description = coalesce(var.description, "Redis cluster mode replication group ${var.name}")

  slow_log_group   = "/aws/elasticache/${var.name}/slow-log"
  engine_log_group = "/aws/elasticache/${var.name}/engine-log"

  # cluster-enabled comes last so no caller parameter can override it.
  parameters = merge(var.parameters, { "cluster-enabled" = "yes" })

  # Cluster mode members are named <replication group id>-<shard, 4 digits>-<node, 3 digits>.
  member_ids = flatten([
    for shard in range(1, var.num_node_groups + 1) : [
      for node in range(1, var.replicas_per_node_group + 2) : format("%s-%04d-%03d", var.name, shard, node)
    ]
  ])
}

resource "aws_elasticache_subnet_group" "this" {
  name        = var.name
  description = "Subnets for ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_elasticache_parameter_group" "this" {
  name        = var.name
  description = "Parameters for ${var.name}"
  family      = local.parameter_group_family

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

# Created ahead of the replication group so retention and KMS are ours.
resource "aws_cloudwatch_log_group" "slow_log" {
  name              = local.slow_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.slow_log_group })
}

resource "aws_cloudwatch_log_group" "engine_log" {
  name              = local.engine_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.engine_log_group })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = local.description

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = var.security_group_ids

  num_node_groups         = var.num_node_groups
  replicas_per_node_group = var.replicas_per_node_group

  # Fixed on purpose, there is no switch for these.
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = true
  multi_az_enabled           = true

  kms_key_id               = var.kms_key_arn
  snapshot_retention_limit = var.snapshot_retention_limit
  apply_immediately        = var.apply_immediately

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # Autoscaling changes the shard count; without this every plan would try to put it back.
    ignore_changes = [num_node_groups]
  }
}

resource "aws_appautoscaling_target" "this" {
  count = var.autoscaling == null ? 0 : 1

  service_namespace  = "elasticache"
  scalable_dimension = "elasticache:replication-group:NodeGroups"
  resource_id        = "replication-group/${aws_elasticache_replication_group.this.replication_group_id}"
  min_capacity       = var.autoscaling.min_shards
  max_capacity       = var.autoscaling.max_shards

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling == null ? 0 : 1

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling.target_cpu

    predefined_metric_specification {
      predefined_metric_type = "ElastiCachePrimaryEngineCPUUtilization"
    }
  }
}
