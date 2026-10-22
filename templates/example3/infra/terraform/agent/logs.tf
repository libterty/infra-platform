locals {
  # The vendedlogs prefix keeps the log group out of the account's CloudWatch Logs resource policy size limit.
  runtime_log_group_names = { for r, n in local.runtime_names : r => "/aws/vendedlogs/bedrock-agentcore/${n}" }

  log_delivery_deliveries = { for r in keys(local.runtime_names) : r => { source = r, destination = r } }
}

module "runtime_log_group" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-group/aws"
  version = "~> 0.1.0"

  for_each = local.runtime_log_group_names

  name           = each.value
  retention_days = var.runtime_log_retention_days
}

module "runtime_log_delivery" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.1.0"

  name_prefix  = "${local.name_prefix}-runtime-logs"
  sources      = { for r, m in module.runtime : r => { resource_arn = m.runtime_arn, log_type = "APPLICATION_LOGS" } }
  destinations = { for r, m in module.runtime_log_group : r => { type = "CWL", resource_arn = m.arn } }
  deliveries   = local.log_delivery_deliveries
}
