locals {
  published_strings = {
    # postdeploy sizes its backlog alarms from it, so the two stacks cannot drift apart.
    stream_length_cap = tostring(var.stream_length_cap)

    # Deploy contract (design v4 §8.1): CI reads these and eks-cluster's keys, then runs Helm. The JSON fields are asserted in tests/application.tftest.hcl and read by
    # templates/example3/deploy/values-from-ssm.sh.
    app_port                = tostring(var.app_port)
    vpc_cidr                = data.aws_vpc.this.cidr_block
    api_target_group_arn    = module.in.strings["api_target_group_arn"]
    api_image_repository    = local.ecr_urls["api"]
    worker_image_repository = local.ecr_urls["worker"]
    api_environment_json    = jsonencode(local.api_environment)
    worker_environment_json = jsonencode(local.worker_environment)
    # KEDA triggers of design v4 §9.
    api_scaling_json = jsonencode({
      min_replicas            = var.api_min_capacity
      max_replicas            = var.api_max_capacity
      cpu_target_percent      = var.api_cpu_target_percent
      requests_per_target     = var.api_requests_per_target
      streams_per_replica     = var.api_streams_per_task_high
      region                  = var.aws_region
      alb_arn_suffix          = module.in.strings["alb_arn_suffix"]
      target_group_arn_suffix = jsondecode(module.in.strings["target_group_arn_suffixes"])["api"]
    })
    worker_scaling_json = jsonencode({
      min_replicas        = var.worker_min_capacity
      max_replicas        = var.worker_max_capacity
      backlog_per_replica = var.stream_length_cap / 4
      region              = var.aws_region
      metric_namespace    = local.metric_namespace
      metric_name         = "StreamBacklogMax"
      dimension_name      = "Env"
      dimension_value     = var.env
    })
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "application"
  strings    = local.published_strings
}
