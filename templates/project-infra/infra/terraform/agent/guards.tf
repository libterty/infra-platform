# Single decision point: the Runtime list belongs to containerimage. A Runtime missing there has no repository,
# security group or execution role.
resource "terraform_data" "agent_runtimes_match_containerimage" {
  lifecycle {
    precondition {
      condition     = jsonencode(keys(var.agent_runtimes)) == jsonencode(sort(jsondecode(module.in.strings["agent_runtimes"])))
      error_message = "agent_runtimes must have exactly the keys of containerimage/agent_runtimes (${join(", ", jsondecode(module.in.strings["agent_runtimes"]))})."
    }
  }
}

# A PUBLIC Runtime is outside the VPC and cannot reach the isolated data tier.
resource "terraform_data" "public_runtime_without_data_access" {
  lifecycle {
    precondition {
      condition     = alltrue([for r, cfg in var.agent_runtimes : cfg.network_mode != "PUBLIC" || !contains(local.data_store_runtimes, r)])
      error_message = "A Runtime with network_mode PUBLIC must not be in network agent_data_access; use VPC to reach a data store."
    }
  }
}

# iam-base decides which service roles exist; iam-app attaches their permissions after this stack.
resource "terraform_data" "service_roles_exist" {
  lifecycle {
    precondition {
      condition     = length(var.knowledge_bases) == 0 || contains(local.agent_service_roles, "knowledge_base")
      error_message = "knowledge_bases needs the knowledge base role: add knowledge_base to agent_service_roles in iam-base and apply it first."
    }

    precondition {
      condition     = var.agentcore_gateway == null || contains(local.agent_service_roles, "gateway")
      error_message = "agentcore_gateway needs the gateway role: add gateway to agent_service_roles in iam-base and apply it first."
    }
  }
}

# Bedrock knowledge bases on Aurora go through the Data API, which only Aurora clusters have.
resource "terraform_data" "knowledge_base_database" {
  lifecycle {
    precondition {
      condition     = length(var.knowledge_bases) == 0 || local.knowledge_base_database_ready
      error_message = "knowledge_bases needs an Aurora database (deployment aurora or aurora_serverless) with db.data_api = true in the data stack."
    }
  }
}

locals {
  # Endpoints the VPC Runtimes need when there is no NAT. nat mode external is a customer VPC whose NAT is the
  # customer's to provide, so it is not checked; PUBLIC Runtimes do not use the VPC.
  agent_required_endpoints = length(local.vpc_runtimes) == 0 ? toset([]) : toset(concat(
    ["bedrock-runtime", "bedrock-agentcore"],
    var.bedrock_invoke != null ? ["sts"] : [],
    anytrue([for cfg in values(local.vpc_runtimes) : cfg.tracing]) ? ["xray"] : [],
    anytrue([for cfg in values(local.vpc_runtimes) : length(cfg.knowledge_bases) > 0]) ? ["bedrock-agent-runtime"] : [],
    # Runtimes in network agent_data_access db read the database secret with their execution role.
    length(setintersection(local.db_runtimes, keys(local.vpc_runtimes))) > 0 ? ["secretsmanager"] : [],
  ))
  agent_missing_endpoints = local.nat_mode == "none" ? setsubtract(local.agent_required_endpoints, local.interface_endpoints) : toset([])
}

resource "terraform_data" "no_nat_endpoints_exist" {
  lifecycle {
    precondition {
      condition     = length(local.agent_missing_endpoints) == 0
      error_message = "network has no NAT (nat mode none), so the VPC Runtimes need these interface endpoints: ${join(", ", sort(tolist(local.agent_missing_endpoints)))}. Add them to interface_endpoints.services in network."
    }
  }
}

# Which endpoint a Runtime in a VPC needs to reach a gateway has not been verified, so without a NAT the gateway is
# blocked instead of timing out at run time.
resource "terraform_data" "no_nat_no_gateway" {
  lifecycle {
    precondition {
      condition     = local.nat_mode != "none" || !anytrue([for cfg in values(local.vpc_runtimes) : cfg.gateway])
      error_message = "network has no NAT (nat mode none); a VPC Runtime cannot use the gateway until the endpoint it needs is verified."
    }
  }
}
