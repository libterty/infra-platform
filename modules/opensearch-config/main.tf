locals {
  # Ages are cumulative index ages (ISM min_index_age). Cold requires warm (validated), so the chain is
  # hot -> [warm] -> [cold] -> delete, and an index that went through cold is removed with cold_delete.
  ism_states = {
    for id, p in var.ism_policies : id => concat(
      [{
        name    = "hot"
        actions = []
        transitions = [{
          state_name = p.warm_days != null ? "warm" : "delete"
          conditions = { min_index_age = "${coalesce(p.warm_days, p.delete_days)}d" }
        }]
      }],
      p.warm_days == null ? [] : [{
        name = "warm"
        actions = [{
          warm_migration = {}
          retry          = { count = 5, delay = "1h" }
        }]
        transitions = [{
          state_name = p.cold_days != null ? "cold" : "delete"
          conditions = { min_index_age = "${coalesce(p.cold_days, p.delete_days)}d" }
        }]
      }],
      p.cold_days == null ? [] : [{
        name    = "cold"
        actions = [{ cold_migration = { timestamp_field = p.timestamp_field } }]
        transitions = [{
          state_name = "delete"
          conditions = { min_index_age = "${p.delete_days}d" }
        }]
      }],
      [{
        name        = "delete"
        actions     = [{ for action in [p.cold_days != null ? "cold_delete" : "delete"] : action => {} }]
        transitions = []
      }],
    )
  }
}

resource "opensearch_ism_policy" "this" {
  for_each = var.ism_policies

  policy_id = each.key
  body = jsonencode({
    policy = {
      description   = "Managed by Terraform (opensearch-config)."
      default_state = "hot"
      states        = local.ism_states[each.key]
      ism_template = [{
        index_patterns = each.value.index_patterns
        priority       = 1
      }]
    }
  })
}

# Write access for an AWS service role (the permission set AWS documents for Firehose).
resource "opensearch_role" "writer" {
  for_each = var.writer_roles

  role_name   = each.key
  description = "Managed by Terraform: write access to ${join(", ", each.value.index_patterns)}."

  cluster_permissions = ["cluster_composite_ops", "cluster_monitor"]

  index_permissions {
    index_patterns  = each.value.index_patterns
    allowed_actions = ["create_index", "manage", "crud"]
  }
}

resource "opensearch_roles_mapping" "writer" {
  for_each = var.writer_roles

  role_name     = opensearch_role.writer[each.key].role_name
  backend_roles = each.value.backend_role_arns
}

# Built-in roles such as ultrawarm_manager and cold_manager; all_access and security_manager are rejected by validation.
resource "opensearch_roles_mapping" "builtin" {
  for_each = var.role_mappings

  role_name     = each.key
  users         = each.value.users
  backend_roles = each.value.backend_role_arns
}

resource "opensearch_composable_index_template" "this" {
  for_each = var.index_templates

  name = each.key
  body = jsonencode({
    index_patterns = each.value.index_patterns
    priority       = each.value.priority
    template = {
      settings = {
        index = { for k, v in {
          number_of_shards   = each.value.number_of_shards
          number_of_replicas = each.value.number_of_replicas
        } : k => v if v != null }
      }
      mappings = try(jsondecode(each.value.mappings), {})
    }
  })
}
