mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/athena_results_bucket_name"]
  values = { insecure_value = "example-dev-athena-results-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_dev_curated" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                = "foundation/kms_key_arn"
      athena_results_bucket_name = "storage/athena_results_bucket_name"
      curated_database_name      = "storage/curated_database_name"
    } && local.ssm_input_lists == {}
    error_message = "analytics must read the shared key from foundation and the results bucket and curated database from storage, nothing else"
  }
}

run "workgroup_writes_results_to_the_storage_bucket_with_the_shared_key" {
  command = plan

  assert {
    condition     = local.results_bucket_name == "example-dev-athena-results-111111111111"
    error_message = "Query results must go to the athena-results bucket published by storage"
  }

  assert {
    condition     = local.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Query results must be encrypted with the shared key published by foundation"
  }

  assert {
    condition     = module.workgroup.name == "example-dev-analytics"
    error_message = "The workgroup must be named <name_prefix>-analytics"
  }
}

run "workgroup_stops_queries_at_10_gib" {
  command = plan

  assert {
    condition     = local.bytes_scanned_cutoff_per_query == 10737418240
    error_message = "The per-query scan limit must be 10 GiB"
  }
}

run "named_query_reads_the_curated_database" {
  command = plan

  assert {
    condition     = length(local.named_queries) >= 1 && alltrue([for q in values(local.named_queries) : q.database == "example_dev_curated"])
    error_message = "Every example named query must point at the curated database published by storage"
  }

  assert {
    condition     = alltrue([for q in values(local.named_queries) : trimspace(q.query) != ""])
    error_message = "Named queries need SQL"
  }
}

run "publishes_exactly_the_analytics_contract" {
  command = plan

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["athena_workgroup_name", "athena_workgroup_arn"])
    error_message = "analytics must publish athena_workgroup_name and athena_workgroup_arn and nothing else (design section 7.2)"
  }
}

run "rejects_unregistered_account" {
  command = plan

  variables {
    expected_account_id = "999999999999"
  }

  expect_failures = [var.expected_account_id]
}
