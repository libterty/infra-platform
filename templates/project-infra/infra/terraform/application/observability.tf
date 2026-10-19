# Both are empty by default and then create nothing. Examples are in envs/examples/.
locals {
  # Names that are not services are reported by guards.tf; they are skipped here so that one clear error is raised.
  log_alarm_inputs = {
    for s, alarms in var.log_alarms : s => {
      name_prefix    = "${local.name_prefix}-${s}"
      log_group_name = module.service[s].log_group_name
      namespace      = "${var.project}/${var.env}"
      alarms         = alarms
      sns_topic_arns = local.alarm_inputs.sns_topic_arns
    } if contains(keys(var.services), s)
  }
}

module "log_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/log-metric-alarm/aws"
  version  = "~> 0.1.0"
  for_each = local.log_alarm_inputs

  name_prefix    = each.value.name_prefix
  log_group_name = each.value.log_group_name
  namespace      = each.value.namespace
  alarms         = each.value.alarms
  sns_topic_arns = each.value.sns_topic_arns
}

module "xray" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/xray/aws"
  version = "~> 0.1.0"

  name_prefix    = local.name_prefix
  sampling_rules = var.xray_sampling_rules
  groups         = var.xray_groups
}
