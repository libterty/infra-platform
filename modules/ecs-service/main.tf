locals {
  # arn:aws:ecs:<region>:<account>:cluster/<name>
  cluster_name = split("/", var.cluster_arn)[1]
  region       = split(":", var.cluster_arn)[3]
  log_group    = coalesce(var.log_group_name, "/ecs/${var.name}")
  tags         = merge(var.tags, { Name = var.name })
  has_lb       = var.load_balancer != null

  container_definition = merge(
    {
      name      = "app"
      image     = var.image
      essential = true

      environment = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
      secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "app"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }

      stopTimeout     = 120
      linuxParameters = { initProcessEnabled = true }
    },
    var.container_port == null ? {} : {
      portMappings = [{ name = "app", containerPort = var.container_port, protocol = "tcp" }]
    },
    var.container_health_check == null ? {} : {
      healthCheck = {
        command     = var.container_health_check.command
        interval    = var.container_health_check.interval
        timeout     = var.container_health_check.timeout
        retries     = var.container_health_check.retries
        startPeriod = var.container_health_check.start_period
      }
    },
  )
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = local.log_group })
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([local.container_definition])

  tags = local.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.network.subnet_ids
    security_groups  = var.network.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.has_lb ? [1] : []
    content {
      target_group_arn = local.target_group_arn
      container_name   = "app"
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = local.has_lb ? var.health_check_grace_period_seconds : null

  dynamic "service_connect_configuration" {
    for_each = var.service_connect != null ? [var.service_connect] : []
    content {
      enabled   = true
      namespace = service_connect_configuration.value.namespace_arn

      service {
        port_name = "app"
        client_alias {
          port     = var.container_port
          dns_name = coalesce(service_connect_configuration.value.dns_name, var.name)
        }
      }
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags                = "SERVICE"
  availability_zone_rebalancing = "ENABLED"
  enable_execute_command        = var.enable_execute_command
  wait_for_steady_state         = false

  tags = local.tags

  # aws_appautoscaling_target 擁有容量；沒有這行，每次 apply 都會把 desired_count 改回輸入值。
  lifecycle {
    ignore_changes = [desired_count]
  }
}
