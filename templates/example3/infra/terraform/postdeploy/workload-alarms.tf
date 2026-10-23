locals {
  alarm_topic_arns = [module.shared.strings["alarm_topic_arn"]]

  target_group_arn_suffixes = jsondecode(module.in.strings["target_group_arn_suffixes"])

  # CI deploys deploy/charts/app as releases api and worker; the Deployment and the container carry the release name.
  workloads = {
    api = {
      load_balancer = {
        alb_arn_suffix          = module.in.strings["alb_arn_suffix"]
        target_group_arn_suffix = local.target_group_arn_suffixes["api"]
      }
    }
    worker = { load_balancer = null }
  }

  workload_alarm_inputs = {
    for k, w in local.workloads : k => {
      name           = "${local.name_prefix}-${k}"
      cluster_name   = module.in.strings["cluster_name"]
      namespace      = module.in.strings["app_namespace"]
      workload_name  = k
      container_name = k
      load_balancer  = w.load_balancer
    }
  }
}

# Workload alarms of design v4 §10. No dashboard and no at-max-capacity alarm: KEDA moves the replica count.
module "workload_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eks-workload-alarms/aws"
  version = "~> 0.1.0"

  for_each = { for k, v in local.workload_alarm_inputs : k => v if var.workload_alarms_enabled }

  name           = each.value.name
  cluster_name   = each.value.cluster_name
  namespace      = each.value.namespace
  workload_name  = each.value.workload_name
  container_name = each.value.container_name
  load_balancer  = each.value.load_balancer
  sns_topic_arns = local.alarm_topic_arns
}
