locals {
  cluster_name  = "${local.name_prefix}-app"
  service_names = { api = "${local.name_prefix}-api", worker = "${local.name_prefix}-worker" }
  # iam allows the worker to publish metrics only into this namespace.
  metric_namespace = "${title(var.project)}/${var.env}"
}

module "cluster" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecs-cluster/aws"
  version = "~> 0.1.0"

  name = local.cluster_name
}
