locals {
  worker_autoscaling = {
    min_capacity = var.worker_min_capacity
    max_capacity = var.worker_max_capacity
    # Only the stream backlog drives the worker, so none of the built-in policies applies.
    policy = "custom"

    step_policies = {
      backlog_high = {
        comparison_operator = "GreaterThanOrEqualToThreshold"
        threshold           = var.stream_length_cap / 4
        evaluation_periods  = 3
        datapoints_to_alarm = 3
        cooldown            = 300
        metric = {
          namespace   = local.metric_namespace
          metric_name = "StreamBacklogMax"
          dimensions  = { Env = var.env }
          statistic   = "Maximum"
        }
        adjustments = [
          { lower = 0, upper = var.stream_length_cap / 4, change = 1 },
          { lower = var.stream_length_cap / 4, change = 2 },
        ]
      }
      # Step policies do not take part in scale-in negotiation, so without this one the worker would only grow.
      backlog_drained = {
        comparison_operator = "LessThanThreshold"
        threshold           = var.stream_length_cap / 20
        evaluation_periods  = 15
        datapoints_to_alarm = 15
        cooldown            = 600
        metric = {
          namespace   = local.metric_namespace
          metric_name = "StreamBacklogMax"
          dimensions  = { Env = var.env }
          statistic   = "Maximum"
        }
        adjustments = [
          { upper = 0, change = -1 },
        ]
      }
    }
  }
}

module "worker" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-service/aws"
  version = "~> 0.2.0"

  name               = local.service_names["worker"]
  cluster_arn        = module.cluster.cluster_arn
  image              = "${local.ecr_urls["worker"]}:${var.worker_image_tag}"
  cpu                = var.worker_cpu
  memory             = var.worker_memory
  environment        = local.worker_environment
  execution_role_arn = module.shared.strings["ecs_execution_role_arn"]
  task_role_arn      = module.shared.strings["worker_task_role_arn"]
  system_controls    = local.system_controls

  network = {
    subnet_ids         = module.shared.lists["app_subnet_ids"]
    security_group_ids = [module.shared.strings["app_sg_id"]]
  }

  desired_count          = var.worker_min_capacity
  autoscaling            = local.worker_autoscaling
  enable_execute_command = var.enable_execute_command
  log_retention_days     = var.log_retention_days
}
