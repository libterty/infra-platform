# ISM policy JSON, FGAC roles and mappings, index templates. No domain is contacted: the provider is mocked.

mock_provider "opensearch" {}

# ---- ISM -----------------------------------------------------------------------------------------------------

run "hot_warm_cold_delete" {
  command = plan

  variables {
    ism_policies = {
      logs = {
        index_patterns  = ["logs-*"]
        warm_days       = 3
        cold_days       = 7
        delete_days     = 30
        timestamp_field = "@timestamp"
      }
    }
  }

  assert {
    condition     = opensearch_ism_policy.this["logs"].policy_id == "logs"
    error_message = "the policy id is the map key"
  }

  assert {
    condition     = join(",", [for s in jsondecode(opensearch_ism_policy.this["logs"].body).policy.states : s.name]) == "hot,warm,cold,delete"
    error_message = "states must be ordered hot, warm, cold, delete"
  }

  assert {
    condition     = jsondecode(opensearch_ism_policy.this["logs"].body).policy.default_state == "hot"
    error_message = "new indices must start in hot"
  }

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[0].transitions[0].state_name == "warm" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[0].transitions[0].conditions.min_index_age == "3d" &&
      length(jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[0].actions) == 0
    )
    error_message = "hot has no action and moves to warm at warm_days"
  }

  assert {
    condition = (
      contains(keys(jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[1].actions[0]), "warm_migration") &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[1].transitions[0].state_name == "cold" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[1].transitions[0].conditions.min_index_age == "7d"
    )
    error_message = "warm runs warm_migration and moves to cold at cold_days"
  }

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[2].actions[0].cold_migration.timestamp_field == "@timestamp" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[2].transitions[0].state_name == "delete" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[2].transitions[0].conditions.min_index_age == "30d"
    )
    error_message = "cold runs cold_migration with the timestamp field and moves to delete at delete_days"
  }

  assert {
    condition = (
      contains(keys(jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[3].actions[0]), "cold_delete") &&
      length(jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[3].transitions) == 0
    )
    error_message = "an index that went through cold is removed with cold_delete, and delete is terminal"
  }

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.ism_template[0].index_patterns[0] == "logs-*" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.ism_template[0].priority == 1
    )
    error_message = "the policy must attach itself to new indices matching index_patterns"
  }
}

run "hot_warm_delete" {
  command = plan

  variables {
    ism_policies = {
      logs = {
        index_patterns = ["logs-*"]
        warm_days      = 3
        delete_days    = 30
      }
    }
  }

  assert {
    condition     = join(",", [for s in jsondecode(opensearch_ism_policy.this["logs"].body).policy.states : s.name]) == "hot,warm,delete"
    error_message = "without cold the states are hot, warm, delete"
  }

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[1].transitions[0].state_name == "delete" &&
      jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[1].transitions[0].conditions.min_index_age == "30d" &&
      contains(keys(jsondecode(opensearch_ism_policy.this["logs"].body).policy.states[2].actions[0]), "delete")
    )
    error_message = "a warm index is removed with the plain delete action"
  }
}

run "hot_to_delete_only" {
  command = plan

  variables {
    ism_policies = {
      app = {
        index_patterns = ["app-*"]
        delete_days    = 14
      }
    }
  }

  assert {
    condition     = join(",", [for s in jsondecode(opensearch_ism_policy.this["app"].body).policy.states : s.name]) == "hot,delete"
    error_message = "hot only: states are hot, delete"
  }

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["app"].body).policy.states[0].transitions[0].state_name == "delete" &&
      jsondecode(opensearch_ism_policy.this["app"].body).policy.states[0].transitions[0].conditions.min_index_age == "14d" &&
      contains(keys(jsondecode(opensearch_ism_policy.this["app"].body).policy.states[1].actions[0]), "delete")
    )
    error_message = "hot moves straight to delete at delete_days"
  }
}

run "timestamp_field_without_cold_is_harmless" {
  command = plan

  variables {
    ism_policies = {
      logs = {
        index_patterns  = ["logs-*"]
        warm_days       = 3
        delete_days     = 30
        timestamp_field = "@timestamp"
      }
    }
  }

  assert {
    condition     = !strcontains(opensearch_ism_policy.this["logs"].body, "cold_migration")
    error_message = "cold_migration must only appear when cold_days is set"
  }
}

run "several_policies_and_outputs" {
  command = plan

  variables {
    ism_policies = {
      logs = {
        index_patterns = ["logs-*"]
        delete_days    = 30
      }
      metrics = {
        index_patterns = ["metrics-*", "stats-*"]
        delete_days    = 90
      }
    }
  }

  assert {
    condition     = length(opensearch_ism_policy.this) == 2
    error_message = "one ISM policy per entry"
  }

  assert {
    condition     = output.ism_policy_ids == ["logs", "metrics"]
    error_message = "ism_policy_ids must list the policy ids sorted by key"
  }
}

# ---- FGAC writer roles and role mappings ----------------------------------------------------------------------

run "firehose_writer_role_and_mapping" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = {
        index_patterns    = ["firehose-*"]
        backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"]
      }
    }
  }

  assert {
    condition = (
      opensearch_role.writer["firehose_writer"].role_name == "firehose_writer" &&
      opensearch_role.writer["firehose_writer"].cluster_permissions == toset(["cluster_composite_ops", "cluster_monitor"])
    )
    error_message = "the writer role gets exactly cluster_composite_ops and cluster_monitor"
  }

  assert {
    condition = (
      one(opensearch_role.writer["firehose_writer"].index_permissions).index_patterns == toset(["firehose-*"]) &&
      one(opensearch_role.writer["firehose_writer"].index_permissions).allowed_actions == toset(["create_index", "manage", "crud"])
    )
    error_message = "index permissions are create_index, manage and crud on the given patterns only"
  }

  assert {
    condition = (
      opensearch_roles_mapping.writer["firehose_writer"].role_name == "firehose_writer" &&
      opensearch_roles_mapping.writer["firehose_writer"].backend_roles == toset(["arn:aws:iam::111111111111:role/alpha-dev-firehose"])
    )
    error_message = "the writer role must be mapped to the given IAM role as a backend role"
  }

  assert {
    condition     = output.writer_role_names == ["firehose_writer"]
    error_message = "writer_role_names must list the writer roles"
  }
}

run "ultrawarm_and_cold_manager_mappings" {
  command = plan

  variables {
    role_mappings = {
      ultrawarm_manager = {
        users             = ["ops-admin"]
        backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-ops"]
      }
      cold_manager = {
        backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-ops"]
      }
    }
  }

  assert {
    condition = (
      opensearch_roles_mapping.builtin["ultrawarm_manager"].role_name == "ultrawarm_manager" &&
      opensearch_roles_mapping.builtin["ultrawarm_manager"].users == toset(["ops-admin"]) &&
      opensearch_roles_mapping.builtin["ultrawarm_manager"].backend_roles == toset(["arn:aws:iam::111111111111:role/alpha-dev-ops"])
    )
    error_message = "ultrawarm_manager must map the given user and backend role"
  }

  assert {
    condition = (
      opensearch_roles_mapping.builtin["cold_manager"].role_name == "cold_manager" &&
      length(opensearch_roles_mapping.builtin["cold_manager"].users) == 0
    )
    error_message = "cold_manager must map only the backend role"
  }
}

run "nothing_by_default" {
  command = plan

  assert {
    condition = (
      length(opensearch_ism_policy.this) == 0 &&
      length(opensearch_role.writer) == 0 &&
      length(opensearch_roles_mapping.writer) == 0 &&
      length(opensearch_roles_mapping.builtin) == 0 &&
      length(opensearch_composable_index_template.this) == 0
    )
    error_message = "without inputs the module must create nothing"
  }
}

# ---- index templates -----------------------------------------------------------------------------------------

run "index_template_body" {
  command = plan

  variables {
    index_templates = {
      logs = {
        index_patterns     = ["logs-*"]
        priority           = 200
        number_of_shards   = 1
        number_of_replicas = 1
        mappings           = "{\"properties\":{\"@timestamp\":{\"type\":\"date\"}}}"
      }
    }
  }

  assert {
    condition = (
      opensearch_composable_index_template.this["logs"].name == "logs" &&
      jsondecode(opensearch_composable_index_template.this["logs"].body).index_patterns[0] == "logs-*" &&
      jsondecode(opensearch_composable_index_template.this["logs"].body).priority == 200 &&
      jsondecode(opensearch_composable_index_template.this["logs"].body).template.settings.index.number_of_shards == 1 &&
      jsondecode(opensearch_composable_index_template.this["logs"].body).template.settings.index.number_of_replicas == 1 &&
      jsondecode(opensearch_composable_index_template.this["logs"].body).template.mappings.properties["@timestamp"].type == "date"
    )
    error_message = "the template body must carry patterns, priority, shard settings and mappings"
  }
}
