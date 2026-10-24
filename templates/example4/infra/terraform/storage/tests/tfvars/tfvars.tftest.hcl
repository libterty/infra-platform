# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation publishes.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-placeholder-alarms" }
}

run "tfvars_build_the_storage" {
  command = plan

  assert {
    condition     = toset(keys(module.bucket)) == toset(["raw", "curated", "athena_results", "glue_assets"]) && length(module.catalog.database_arns) == 2
    error_message = "The tfvars must build the four buckets and the two databases"
  }

  assert {
    condition     = length(module.table) >= 1
    error_message = "The tfvars must define at least one example table"
  }
}

run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

# Design section 7.5: DynamoDB is on-demand in both; PITR is 7 days in dev and 35 in sit.
run "tfvars_pitr_days_match_the_env" {
  command = plan

  assert {
    condition     = alltrue([for t in values(var.tables) : t.point_in_time_recovery_days == (var.env == "dev" ? 7 : 35)])
    error_message = "Every table must keep PITR for 7 days in dev and 35 days in sit (design section 7.5)"
  }
}

# Design section 7.5: Kinesis, buckets and databases are the same in dev and sit.
run "tfvars_stream_and_buckets_match_the_design" {
  command = plan

  assert {
    condition     = local.stream.mode == "PROVISIONED" && local.stream.shard_count == 1 && local.stream.retention_hours == 24
    error_message = "The stream must be provisioned with 1 shard and 24 hours of retention in both envs"
  }

  assert {
    condition     = local.buckets["raw"].eventbridge && local.buckets["curated"].never_expire && local.buckets["curated"].versioning != null
    error_message = "raw must send events and curated must never expire and be versioned"
  }
}
