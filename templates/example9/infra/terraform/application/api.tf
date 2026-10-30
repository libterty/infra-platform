# The api service (design 8.1, D6, D8). The pipeline deploys it (pipeline_managed): Terraform creates the service with
# the bootstrap image and afterwards only registers new task definition revisions, which the api-deploy project picks
# up on the next run. The bootstrap image must be in the repository before the first apply (K10).
locals {
  api_service = {
    # Must match iam/naming.tf: ecs-service names the task family after the service and creates /ecs/<name>, and
    # the execution role, the api-deploy role and RegisterTaskDefinition are scoped to those names.
    name               = "${local.name_prefix}-api"
    image              = "${module.in.strings["api_repository_url"]}:${var.api_bootstrap_image_tag}"
    cpu                = var.api_cpu
    memory             = var.api_memory
    container_port     = var.app_port
    execution_role_arn = module.in.strings["api_execution_role_arn"]
    task_role_arn      = module.in.strings["api_task_role_arn"]
    network = {
      subnet_ids         = module.in.lists["app_subnet_ids"]
      security_group_ids = [module.sg.security_group_ids["api"]]
    }
    # The module creates the target group and a catch-all rule on the internal ALB's HTTP listener.
    load_balancer = {
      listener_arn  = module.in.strings["listener_arn"]
      vpc_id        = module.in.strings["vpc_id"]
      priority      = 100
      path_patterns = ["/*"]
      health_check  = { path = var.api_health_check_path }
    }
    desired_count    = var.api_desired_count
    pipeline_managed = true
    # Rolling is the template's strategy; BLUE_GREEN also needs a role (iam-role 0.6.0) and is covered by the module tests.
    deployment = { strategy = "ROLLING" }
  }
}

module "api" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-service/aws"
  version = "~> 0.3.0"

  name               = local.api_service.name
  cluster_arn        = module.cluster.cluster_arn
  image              = local.api_service.image
  cpu                = local.api_service.cpu
  memory             = local.api_service.memory
  container_port     = local.api_service.container_port
  execution_role_arn = local.api_service.execution_role_arn
  task_role_arn      = local.api_service.task_role_arn
  network            = local.api_service.network
  load_balancer      = local.api_service.load_balancer
  desired_count      = local.api_service.desired_count
  pipeline_managed   = local.api_service.pipeline_managed
  deployment         = local.api_service.deployment
  log_retention_days = var.log_retention_days
  log_kms_key_arn    = module.in.strings["kms_key_arn"]
}
