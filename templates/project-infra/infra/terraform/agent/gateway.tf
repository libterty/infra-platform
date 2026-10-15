# Only the project's own Runtimes call the gateway, so it signs with their execution roles (AWS_IAM).
module "gateway" {
  source   = "../../../../../modules/agentcore-gateway"
  for_each = var.agentcore_gateway == null ? {} : { this = var.agentcore_gateway }

  name       = "${local.name_prefix}-gateway"
  role_arn   = module.in_agents.strings["role_agentcore_gateway_arn"]
  authorizer = { type = "AWS_IAM" }
  targets    = each.value.targets
}
