locals {
  ssm_input_strings = {
    alarm_topic_arn        = "foundation/alarm_topic_arn"
    app_secret_arn         = "foundation/app_secret_arn"
    vpc_id                 = "network/vpc_id"
    data_access            = "network/data_access"
    role_ecs_execution_arn = "iam-base/role_ecs_execution_arn"
    database               = "data/database"
    alb_arn_suffix         = "loadbalancer/alb_arn_suffix"
    listener_arn           = "loadbalancer/listener_arn"
  }
  ssm_input_lists = {
    services       = "containerimage/services"
    subnet_ids_app = "network/subnet_ids_app"
  }
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

# Per-service keys are derived from the services configured here. guards.tf fails the plan when they differ from
# containerimage/services.
locals {
  # SSM keys cannot contain hyphens: service order-api uses sg_order_api_id.
  service_key = { for s in keys(var.services) : s => replace(s, "-", "_") }

  ssm_service_strings = merge(
    { for s, k in local.service_key : "ecr_${k}_url" => "containerimage/ecr_${k}_url" },
    { for s, k in local.service_key : "sg_${k}_id" => "network/sg_${k}_id" },
    { for s, k in local.service_key : "role_${k}_task_arn" => "iam-app/role_${k}_task_arn" },
    { for s, k in local.service_key : "ecs_exec_${k}" => "iam-app/ecs_exec_${k}" },
  )
}

module "in_services" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_service_strings
}
