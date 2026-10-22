locals {
  alarm_topic_arns = [module.shared.strings["alarm_topic_arn"]]

  target_group_arn_suffixes = jsondecode(module.in.strings["target_group_arn_suffixes"])

  # The ceilings come from the application stack, so the at-max-capacity alarm always matches the autoscaling target.
  service_alarm_services = {
    api = {
      service_name = module.in.strings["api_service_name"]
      load_balancer = {
        alb_arn_suffix          = module.in.strings["alb_arn_suffix"]
        target_group_arn_suffix = local.target_group_arn_suffixes["api"]
      }
      max_capacity   = tonumber(module.in.strings["api_max_capacity"])
      dashboard_name = module.in.strings["api_service_name"]
    }
    worker = {
      service_name   = module.in.strings["worker_service_name"]
      load_balancer  = null
      max_capacity   = tonumber(module.in.strings["worker_max_capacity"])
      dashboard_name = module.in.strings["worker_service_name"]
    }
  }
}

module "service_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-service-alarms/aws"
  version = "~> 0.1.0"

  # A for expression, not a conditional: the two services have different attribute types, which a conditional cannot unify.
  for_each = { for k, v in local.service_alarm_services : k => v if var.service_alarms_enabled }

  name           = each.value.service_name
  cluster_name   = module.in.strings["cluster_name"]
  service_name   = each.value.service_name
  sns_topic_arns = local.alarm_topic_arns
  load_balancer  = each.value.load_balancer
  max_capacity   = each.value.max_capacity
  dashboard_name = each.value.dashboard_name
}
