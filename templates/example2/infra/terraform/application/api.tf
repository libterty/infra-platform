locals {
  api_autoscaling = {
    min_capacity = var.api_min_capacity
    max_capacity = var.api_max_capacity
    policy       = "target_tracking"
    target_tracking = {
      cpu_percent         = var.api_cpu_target_percent
      requests_per_target = var.api_requests_per_target
    }
    scheduled_actions = var.api_scheduled_scaling

    # Step scaling on top of target tracking: streaming responses are long-lived and barely move the request count.
    step_policies = {
      streams_high = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = var.api_streams_per_task_high
        evaluation_periods  = 3
        cooldown            = 60
        queries = [
          {
            id          = "per_task"
            expression  = "streams / tasks"
            label       = "ActiveStreamsPerTask"
            return_data = true
          },
          {
            id = "streams"
            metric = {
              namespace   = "AWS/ApplicationELB"
              metric_name = "ActiveConnectionCount"
              dimensions  = { LoadBalancer = module.in.strings["alb_arn_suffix"] }
            }
          },
          {
            id = "tasks"
            metric = {
              namespace   = "ECS/ContainerInsights"
              metric_name = "RunningTaskCount"
              dimensions  = { ClusterName = local.cluster_name, ServiceName = local.service_names["api"] }
            }
          },
        ]
        # The bands are relative to the threshold: up to one more threshold above it adds a task, beyond that two.
        adjustments = [
          { lower = 0, upper = var.api_streams_per_task_high, change = 1 },
          { lower = var.api_streams_per_task_high, change = 2 },
        ]
      }
    }
  }
}

module "api" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-service/aws"
  version = "~> 0.2.0"

  name               = local.service_names["api"]
  cluster_arn        = module.cluster.cluster_arn
  image              = "${local.ecr_urls["api"]}:${var.api_image_tag}"
  cpu                = var.api_cpu
  memory             = var.api_memory
  container_port     = var.app_port
  environment        = local.api_environment
  execution_role_arn = module.shared.strings["ecs_execution_role_arn"]
  task_role_arn      = module.shared.strings["api_task_role_arn"]
  system_controls    = local.system_controls

  network = {
    subnet_ids         = module.shared.lists["app_subnet_ids"]
    security_group_ids = [module.shared.strings["app_sg_id"]]
  }

  load_balancer = {
    target_group_arn = module.in.strings["api_target_group_arn"]
    alb_arn_suffix   = module.in.strings["alb_arn_suffix"]
  }

  desired_count          = var.api_min_capacity
  autoscaling            = local.api_autoscaling
  enable_execute_command = var.enable_execute_command
  log_retention_days     = var.log_retention_days
}
