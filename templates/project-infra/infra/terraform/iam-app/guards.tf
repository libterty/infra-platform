# ECS Exec is switched on per service here and published to application; a name that is not a service would silently do nothing.
resource "terraform_data" "ecs_exec_services_are_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in var.ecs_exec_services : contains(module.in.lists["services"], s)])
      error_message = "ecs_exec_services must name services published by containerimage (${join(", ", module.in.lists["services"])})."
    }
  }
}

# Tracing is switched on per service here and published to application; a name that is not a service would silently do nothing.
resource "terraform_data" "tracing_services_are_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in var.tracing : contains(module.in.lists["services"], s)])
      error_message = "tracing must name services published by containerimage (${join(", ", module.in.lists["services"])})."
    }
  }
}

# What a service may call is decided here and published to application; a name that does not exist would silently do
# nothing.
resource "terraform_data" "agent_access_is_known" {
  lifecycle {
    precondition {
      condition     = alltrue([for s in keys(var.agent_access) : contains(module.in.lists["services"], s)])
      error_message = "agent_access must be keyed by services published by containerimage (${join(", ", module.in.lists["services"])})."
    }

    precondition {
      condition = alltrue([for a in values(var.agent_access) :
        alltrue([for r in a.runtimes : contains(local.agent_runtime_names, r)]) &&
        alltrue([for m in a.models : contains(keys(local.agent_models), m)]) &&
        alltrue([for g in a.guardrails : contains(keys(local.agent_guardrails), g)]) &&
        alltrue([for k in a.knowledge_bases : contains(keys(local.agent_knowledge_bases), k)])
      ])
      error_message = "agent_access may only name Runtimes, models, guardrails and knowledge bases that the agent stack publishes."
    }
  }
}

# This stack grants secretsmanager:GetSecretValue on these ARNs as published, so a wildcard here would let the knowledge
# base role read any secret, including the master secret of the database.
resource "terraform_data" "knowledge_base_secrets_are_exact" {
  lifecycle {
    precondition {
      condition = alltrue([for kb in values(local.agent_knowledge_bases) :
        can(regex("^arn:aws:secretsmanager:${var.aws_region}:${var.expected_account_id}:secret:[A-Za-z0-9/_+=.@!-]+-[A-Za-z0-9]{6}$", kb.credentials_secret_arn))
      ])
      error_message = "agent/knowledge_bases publishes a credentials_secret_arn that is not the exact ARN of one secret in this region and account."
    }
  }
}
