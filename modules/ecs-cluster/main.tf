resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

# Pre-created because AWS otherwise creates it on first write with no expiry.
resource "aws_cloudwatch_log_group" "container_insights" {
  count = var.container_insights != "disabled" ? 1 : 0

  name              = "/aws/ecs/containerinsights/${var.name}/performance"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "/aws/ecs/containerinsights/${var.name}/performance" })
}

resource "aws_service_discovery_http_namespace" "this" {
  count = var.service_connect_namespace != null ? 1 : 0

  name = var.service_connect_namespace

  tags = merge(var.tags, { Name = var.service_connect_namespace })
}
