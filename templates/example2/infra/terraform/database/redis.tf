locals {
  # Parameters are part of what each cluster is for, so they are not tfvars.
  redis_parameters = {
    # Rate-limit counters all carry a TTL, so evicting the least recently used of them under memory pressure is fine.
    "rate-limit" = { "maxmemory-policy" = "volatile-lru" }
    # The stream is a queue; dropping entries would lose work, so a full cluster must refuse writes instead.
    "stream" = { "maxmemory-policy" = "noeviction", "stream-node-max-entries" = "100" }
  }

  redis_descriptions = {
    "rate-limit" = "Request counters for rate limiting."
    "stream"     = "Work queue: a Redis Stream with a consumer group."
  }

  redis = {
    for key, c in var.redis : key => {
      name               = "${local.name_prefix}-${key}"
      description        = local.redis_descriptions[key]
      engine_version     = c.engine_version
      node_type          = c.node_type
      num_node_groups    = c.num_node_groups
      apply_immediately  = c.apply_immediately
      autoscaling        = c.autoscaling
      parameters         = local.redis_parameters[key]
      subnet_ids         = module.in.lists["db_subnet_ids"]
      security_group_ids = [module.in.strings["cache_sg_id"]]
    }
  }
}

module "redis" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/elasticache-redis/aws"
  version = "~> 0.1.0"

  for_each = local.redis

  name               = each.value.name
  description        = each.value.description
  engine_version     = each.value.engine_version
  node_type          = each.value.node_type
  num_node_groups    = each.value.num_node_groups
  apply_immediately  = each.value.apply_immediately
  autoscaling        = each.value.autoscaling
  parameters         = each.value.parameters
  subnet_ids         = each.value.subnet_ids
  security_group_ids = each.value.security_group_ids
  log_retention_days = var.log_retention_days
  sns_topic_arns     = [module.in.strings["alarm_topic_arn"]]
}
