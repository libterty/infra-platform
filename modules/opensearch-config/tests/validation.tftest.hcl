# Every validation block has at least one run that must fail. Each run breaks exactly one rule.

mock_provider "opensearch" {}

# ---- ISM -----------------------------------------------------------------------------------------------------

run "warm_equals_cold" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], warm_days = 7, cold_days = 7, delete_days = 30, timestamp_field = "@timestamp" }
    }
  }

  expect_failures = [var.ism_policies]
}

run "cold_after_delete" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], warm_days = 3, cold_days = 40, delete_days = 30, timestamp_field = "@timestamp" }
    }
  }

  expect_failures = [var.ism_policies]
}

run "warm_after_delete_without_cold" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], warm_days = 30, delete_days = 30 }
    }
  }

  expect_failures = [var.ism_policies]
}

run "delete_days_zero" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], delete_days = 0 }
    }
  }

  expect_failures = [var.ism_policies]
}

run "cold_without_timestamp_field" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], warm_days = 3, cold_days = 7, delete_days = 30 }
    }
  }

  expect_failures = [var.ism_policies]
}

run "cold_without_warm" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = ["logs-*"], cold_days = 7, delete_days = 30, timestamp_field = "@timestamp" }
    }
  }

  expect_failures = [var.ism_policies]
}

run "ism_policy_without_index_patterns" {
  command = plan

  variables {
    ism_policies = {
      logs = { index_patterns = [], delete_days = 30 }
    }
  }

  expect_failures = [var.ism_policies]
}

run "ism_policy_id_with_a_space" {
  command = plan

  variables {
    ism_policies = {
      "my logs" = { index_patterns = ["logs-*"], delete_days = 30 }
    }
  }

  expect_failures = [var.ism_policies]
}

# ---- writer roles --------------------------------------------------------------------------------------------

run "backend_role_is_a_user_arn" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = ["firehose-*"], backend_role_arns = ["arn:aws:iam::111111111111:user/someone"] }
    }
  }

  expect_failures = [var.writer_roles]
}

run "backend_role_with_wildcard" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = ["firehose-*"], backend_role_arns = ["arn:aws:iam::111111111111:role/*"] }
    }
  }

  expect_failures = [var.writer_roles]
}

run "writer_without_backend_roles" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = ["firehose-*"], backend_role_arns = [] }
    }
  }

  expect_failures = [var.writer_roles]
}

run "writer_on_every_index" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = ["*"], backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"] }
    }
  }

  expect_failures = [var.writer_roles]
}

run "writer_without_index_patterns" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = [], backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"] }
    }
  }

  expect_failures = [var.writer_roles]
}

run "writer_named_all_access" {
  command = plan

  variables {
    writer_roles = {
      all_access = { index_patterns = ["firehose-*"], backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"] }
    }
  }

  expect_failures = [var.writer_roles]
}

# ---- role mappings -------------------------------------------------------------------------------------------

run "mapping_to_all_access" {
  command = plan

  variables {
    role_mappings = {
      all_access = { backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-ops"] }
    }
  }

  expect_failures = [var.role_mappings]
}

run "mapping_to_security_manager" {
  command = plan

  variables {
    role_mappings = {
      security_manager = { users = ["ops-admin"] }
    }
  }

  expect_failures = [var.role_mappings]
}

run "mapping_backend_role_not_an_iam_role" {
  command = plan

  variables {
    role_mappings = {
      ultrawarm_manager = { backend_role_arns = ["arn:aws:s3:::some-bucket"] }
    }
  }

  expect_failures = [var.role_mappings]
}

run "mapping_without_users_or_backend_roles" {
  command = plan

  variables {
    role_mappings = {
      ultrawarm_manager = {}
    }
  }

  expect_failures = [var.role_mappings]
}

run "mapping_collides_with_a_writer_role" {
  command = plan

  variables {
    writer_roles = {
      firehose_writer = { index_patterns = ["firehose-*"], backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"] }
    }
    role_mappings = {
      firehose_writer = { users = ["ops-admin"] }
    }
  }

  expect_failures = [var.role_mappings]
}

# ---- index templates -----------------------------------------------------------------------------------------

run "template_mappings_not_json" {
  command = plan

  variables {
    index_templates = {
      logs = { index_patterns = ["logs-*"], mappings = "not json" }
    }
  }

  expect_failures = [var.index_templates]
}

run "template_without_index_patterns" {
  command = plan

  variables {
    index_templates = {
      logs = { index_patterns = [] }
    }
  }

  expect_failures = [var.index_templates]
}

run "template_negative_priority" {
  command = plan

  variables {
    index_templates = {
      logs = { index_patterns = ["logs-*"], priority = -1 }
    }
  }

  expect_failures = [var.index_templates]
}
