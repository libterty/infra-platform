mock_provider "aws" {}

override_resource {
  target          = aws_athena_workgroup.this
  override_during = plan
  values = {
    arn = "arn:aws:athena:ap-northeast-1:111111111111:workgroup/alpha-dev"
  }
}

variables {
  name                = "alpha-dev"
  results_bucket_name = "alpha-dev-athena-results"
  kms_key_arn         = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive --------------------------------------------------------------------------------------------------

run "workgroup_settings_override_client_settings" {
  command = plan

  assert {
    condition     = one(aws_athena_workgroup.this.configuration).enforce_workgroup_configuration == true
    error_message = "The workgroup configuration must be enforced so clients cannot change the result location or encryption"
  }

  assert {
    condition     = one(aws_athena_workgroup.this.configuration).publish_cloudwatch_metrics_enabled == true
    error_message = "CloudWatch metrics must be published"
  }
}

run "results_are_encrypted_with_sse_kms_and_the_given_key" {
  command = plan

  assert {
    condition = (
      one(one(one(aws_athena_workgroup.this.configuration).result_configuration).encryption_configuration).encryption_option == "SSE_KMS" &&
      one(one(one(aws_athena_workgroup.this.configuration).result_configuration).encryption_configuration).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    )
    error_message = "Query results must be encrypted with SSE_KMS and the given key"
  }
}

run "results_location_defaults_to_the_athena_results_prefix" {
  command = plan

  assert {
    condition     = one(one(aws_athena_workgroup.this.configuration).result_configuration).output_location == "s3://alpha-dev-athena-results/athena-results/"
    error_message = "The result location must be s3://<bucket>/athena-results/ by default"
  }
}

run "results_prefix_is_overridable_and_may_be_empty" {
  command = plan

  variables {
    results_prefix = "queries/dev/"
  }

  assert {
    condition     = one(one(aws_athena_workgroup.this.configuration).result_configuration).output_location == "s3://alpha-dev-athena-results/queries/dev/"
    error_message = "The result location must follow results_prefix"
  }
}

run "empty_results_prefix_writes_to_the_bucket_root" {
  command = plan

  variables {
    results_prefix = ""
  }

  assert {
    condition     = one(one(aws_athena_workgroup.this.configuration).result_configuration).output_location == "s3://alpha-dev-athena-results/"
    error_message = "An empty prefix must give the bucket root"
  }
}

run "scan_cutoff_defaults_to_10_gib" {
  command = plan

  assert {
    condition     = one(aws_athena_workgroup.this.configuration).bytes_scanned_cutoff_per_query == 10737418240
    error_message = "bytes_scanned_cutoff_per_query must default to 10 GiB"
  }
}

run "scan_cutoff_is_overridable_down_to_the_minimum" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = 10485760
  }

  assert {
    condition     = one(aws_athena_workgroup.this.configuration).bytes_scanned_cutoff_per_query == 10485760
    error_message = "A cutoff at the minimum must be accepted and passed through"
  }
}

run "engine_version_defaults_to_auto" {
  command = plan

  assert {
    condition     = one(one(aws_athena_workgroup.this.configuration).engine_version).selected_engine_version == "AUTO"
    error_message = "The engine version must default to AUTO"
  }
}

run "engine_version_can_be_pinned" {
  command = plan

  variables {
    engine_version = "Athena engine version 3"
  }

  assert {
    condition     = one(one(aws_athena_workgroup.this.configuration).engine_version).selected_engine_version == "Athena engine version 3"
    error_message = "A pinned engine version must be passed through"
  }
}

run "name_force_destroy_and_tags" {
  command = plan

  variables {
    force_destroy = true
    tags = {
      Project = "alpha"
    }
  }

  assert {
    condition     = aws_athena_workgroup.this.name == "alpha-dev" && aws_athena_workgroup.this.force_destroy == true
    error_message = "name and force_destroy must be passed through"
  }

  assert {
    condition     = aws_athena_workgroup.this.tags["Name"] == "alpha-dev" && aws_athena_workgroup.this.tags["Project"] == "alpha"
    error_message = "The workgroup must carry the given tags plus Name"
  }
}

run "force_destroy_defaults_to_false" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this.force_destroy == false
    error_message = "force_destroy must default to false"
  }
}

run "no_named_queries_by_default" {
  command = plan

  assert {
    condition     = length(aws_athena_named_query.this) == 0
    error_message = "No named query may be created unless asked for"
  }
}

run "named_queries_land_in_the_workgroup" {
  command = plan

  variables {
    named_queries = {
      daily-count = {
        database    = "alpha_dev_curated"
        query       = "SELECT count(*) FROM events"
        description = "每日筆數"
      }
      latest = {
        database = "alpha_dev_curated"
        query    = "SELECT * FROM events LIMIT 10"
      }
    }
  }

  assert {
    condition     = length(aws_athena_named_query.this) == 2
    error_message = "One named query per entry"
  }

  assert {
    condition = (
      aws_athena_named_query.this["daily-count"].name == "daily-count" &&
      aws_athena_named_query.this["daily-count"].database == "alpha_dev_curated" &&
      aws_athena_named_query.this["daily-count"].query == "SELECT count(*) FROM events" &&
      aws_athena_named_query.this["daily-count"].description == "每日筆數" &&
      aws_athena_named_query.this["daily-count"].workgroup == "alpha-dev"
    )
    error_message = "A named query must carry its name, database, query and description and belong to the workgroup"
  }

  assert {
    condition     = aws_athena_named_query.this["latest"].description == null
    error_message = "A missing description must stay unset"
  }
}

run "outputs_expose_name_and_arn" {
  command = plan

  assert {
    condition     = output.name == "alpha-dev" && output.arn == "arn:aws:athena:ap-northeast-1:111111111111:workgroup/alpha-dev"
    error_message = "name and arn outputs must match the workgroup"
  }
}

# ---- negative --------------------------------------------------------------------------------------------------

run "cutoff_below_the_minimum_is_rejected" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = 10485759
  }

  expect_failures = [var.bytes_scanned_cutoff_per_query]
}

run "fractional_cutoff_is_rejected" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = 10485760.5
  }

  expect_failures = [var.bytes_scanned_cutoff_per_query]
}

# nullable = false: null falls back to the 10 GiB default, so the cap cannot be switched off.
run "null_cutoff_falls_back_to_the_default" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = null
  }

  assert {
    condition     = one(aws_athena_workgroup.this.configuration).bytes_scanned_cutoff_per_query == 10737418240
    error_message = "A null cutoff must not remove the cap"
  }
}

run "bucket_name_with_uppercase_is_rejected" {
  command = plan

  variables {
    results_bucket_name = "Alpha-Results"
  }

  expect_failures = [var.results_bucket_name]
}

run "bucket_name_as_s3_url_is_rejected" {
  command = plan

  variables {
    results_bucket_name = "s3://alpha-dev-athena-results"
  }

  expect_failures = [var.results_bucket_name]
}

run "bucket_name_too_short_is_rejected" {
  command = plan

  variables {
    results_bucket_name = "ab"
  }

  expect_failures = [var.results_bucket_name]
}

run "prefix_with_a_leading_slash_is_rejected" {
  command = plan

  variables {
    results_prefix = "/athena-results/"
  }

  expect_failures = [var.results_prefix]
}

run "prefix_without_a_trailing_slash_is_rejected" {
  command = plan

  variables {
    results_prefix = "athena-results"
  }

  expect_failures = [var.results_prefix]
}

run "prefix_as_s3_url_is_rejected" {
  command = plan

  variables {
    results_prefix = "s3://other/athena-results/"
  }

  expect_failures = [var.results_prefix]
}

run "kms_key_alias_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "name_with_a_space_is_rejected" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "unknown_engine_version_is_rejected" {
  command = plan

  variables {
    engine_version = "PySpark engine version 3"
  }

  expect_failures = [var.engine_version]
}

run "empty_named_query_is_rejected" {
  command = plan

  variables {
    named_queries = {
      broken = {
        database = "alpha_dev_curated"
        query    = ""
      }
    }
  }

  expect_failures = [var.named_queries]
}
