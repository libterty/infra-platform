# Only the project's own Runtimes call the gateway, so it signs with their execution roles (AWS_IAM).
module "gateway" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/agentcore-gateway/aws"
  version  = "~> 0.1.0"
  for_each = var.agentcore_gateway == null ? {} : { this = var.agentcore_gateway }

  name       = "${local.name_prefix}-gateway"
  role_arn   = module.in_agents.strings["role_agentcore_gateway_arn"]
  authorizer = { type = "AWS_IAM" }
  targets    = each.value.targets
}
