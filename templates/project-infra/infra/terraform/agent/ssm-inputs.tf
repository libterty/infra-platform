locals {
  ssm_input_strings = {
    # JSON array of Runtime names; "[]" when containerimage has no Runtime.
    agent_runtimes      = "containerimage/agent_runtimes"
    nat                 = "network/nat"
    interface_endpoints = "network/interface_endpoints"
    agent_data_access   = "network/agent_data_access"
    agent_service_roles = "iam-base/agent_service_roles"
    database            = "data/database"
    kms_key_arn         = "foundation/kms_key_arn" # encrypts the knowledge base database user secrets
  }
  ssm_input_lists = {}
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

# Per-Runtime keys are derived from the Runtimes configured here (guards.tf checks them against containerimage), and
# the service role ARNs exist only when iam-base created the role, so they need a second read.
locals {
  # SSM keys cannot contain hyphens: Runtime order-bot uses ecr_agent_order_bot_url.
  agent_key    = { for r in keys(var.agent_runtimes) : r => replace(r, "-", "_") }
  vpc_runtimes = { for r, cfg in var.agent_runtimes : r => cfg if cfg.network_mode == "VPC" }

  ssm_agent_strings = merge(
    { for r, k in local.agent_key : "ecr_agent_${k}_url" => "containerimage/ecr_agent_${k}_url" },
    { for r, k in local.agent_key : "role_agent_${k}_execution_arn" => "iam-base/role_agent_${k}_execution_arn" },
    { for r, cfg in local.vpc_runtimes : "sg_agent_${local.agent_key[r]}_id" => "network/sg_agent_${local.agent_key[r]}_id" },
    length(var.knowledge_bases) > 0 ? { role_bedrock_kb_arn = "iam-base/role_bedrock_kb_arn" } : {},
    var.agentcore_gateway != null ? { role_agentcore_gateway_arn = "iam-base/role_agentcore_gateway_arn" } : {},
  )
  ssm_agent_lists = { for t in distinct([for cfg in values(local.vpc_runtimes) : cfg.subnet_tier]) : "subnet_ids_${t}" => "network/subnet_ids_${t}" }
}

module "in_agents" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_agent_strings
  lists      = local.ssm_agent_lists
}

locals {
  nat_mode            = jsondecode(module.in.strings["nat"]).mode
  interface_endpoints = toset(jsondecode(module.in.strings["interface_endpoints"]))
  agent_data_access   = jsondecode(module.in.strings["agent_data_access"])
  agent_service_roles = toset(jsondecode(module.in.strings["agent_service_roles"]))
  database            = jsondecode(module.in.strings["database"])

  # Runtimes that may connect to any data store, and those that get the db connection settings, as decided by network.
  data_store_runtimes = toset(flatten(values(local.agent_data_access)))
  db_runtimes         = toset(try(local.agent_data_access["db"], []))
}
