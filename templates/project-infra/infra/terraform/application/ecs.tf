locals {
  alarm_inputs = {
    sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
    alb_arn_suffix = module.in.strings["alb_arn_suffix"]
  }

  # The database may not exist, and then the secret and the endpoints are absent from the JSON.
  database    = jsondecode(module.in.strings["database"])
  data_access = jsondecode(module.in.strings["data_access"])
  db_readers  = toset(try(local.data_access["db"], []))

  # The application only needs these five values; whether a Proxy is used and which engine runs is not its business.
  # The secret itself is read by the task role from DB_SECRET_ARN, never injected through the shared execution role.
  db_environment = local.database.enabled ? {
    DB_HOST        = local.database.app_endpoint
    DB_READER_HOST = local.database.app_reader_endpoint
    DB_PORT        = tostring(local.database.port)
    DB_NAME        = local.database.name
    DB_SECRET_ARN  = local.database.secret_arn
  } : {}

  service_inputs = {
    for s, cfg in var.services : s => {
      name               = "${local.name_prefix}-${s}"
      image              = "${module.in_services.strings["ecr_${local.service_key[s]}_url"]}:${cfg.image_tag}"
      container_port     = cfg.container_port
      cpu                = cfg.cpu
      memory             = cfg.memory
      cpu_architecture   = cfg.cpu_architecture
      desired_count      = cfg.desired_count
      execution_role_arn = module.in.strings["role_ecs_execution_arn"]
      task_role_arn      = module.in_services.strings["role_${local.service_key[s]}_task_arn"]

      network = {
        subnet_ids         = module.in.lists["subnet_ids_app"]
        security_group_ids = [module.in_services.strings["sg_${local.service_key[s]}_id"]]
      }

      environment = merge(contains(local.db_readers, s) ? local.db_environment : {}, local.tracing_environment[s])
      sidecars    = local.tracing_sidecars[s]
      secrets     = { APP_SECRET = module.in.strings["app_secret_arn"] }

      # The flag comes from iam-app, the same source as the task role permissions.
      enable_execute_command = jsondecode(module.in_services.strings["ecs_exec_${local.service_key[s]}"]).enabled

      load_balancer = cfg.alb == null ? null : {
        listener_arn   = module.in.strings["listener_arn"]
        vpc_id         = module.in.strings["vpc_id"]
        priority       = cfg.alb.priority
        path_patterns  = cfg.alb.path_patterns
        host_headers   = cfg.alb.host_headers
        alb_arn_suffix = local.alarm_inputs.alb_arn_suffix
      }

      autoscaling = cfg.max_capacity == null ? null : {
        min_capacity    = cfg.desired_count
        max_capacity    = cfg.max_capacity
        target_tracking = { requests_per_target = try(cfg.alb.requests_per_target, null) }
      }
    }
  }
}

module "cluster" {
  source = "../../../../../modules/ecs-cluster"

  name = "${local.name_prefix}-app"
}

module "service" {
  source   = "../../../../../modules/ecs-service"
  for_each = local.service_inputs

  name                   = each.value.name
  cluster_arn            = module.cluster.cluster_arn
  image                  = each.value.image
  container_port         = each.value.container_port
  cpu                    = each.value.cpu
  memory                 = each.value.memory
  cpu_architecture       = each.value.cpu_architecture
  desired_count          = each.value.desired_count
  execution_role_arn     = each.value.execution_role_arn
  task_role_arn          = each.value.task_role_arn
  network                = each.value.network
  environment            = each.value.environment
  sidecars               = each.value.sidecars
  secrets                = each.value.secrets
  enable_execute_command = each.value.enable_execute_command
  load_balancer          = each.value.load_balancer
  autoscaling            = each.value.autoscaling
}

module "service_alarms" {
  source   = "../../../../../modules/ecs-service-alarms"
  for_each = local.service_inputs

  name           = module.service[each.key].service_name
  cluster_name   = module.cluster.cluster_name
  service_name   = module.service[each.key].service_name
  sns_topic_arns = local.alarm_inputs.sns_topic_arns
  max_capacity   = var.services[each.key].max_capacity
  dashboard_name = each.value.name

  load_balancer = each.value.load_balancer == null ? null : {
    alb_arn_suffix          = local.alarm_inputs.alb_arn_suffix
    target_group_arn_suffix = module.service[each.key].target_group_arn_suffix
  }
}
