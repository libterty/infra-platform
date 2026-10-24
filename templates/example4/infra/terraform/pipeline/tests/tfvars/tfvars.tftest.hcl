# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-placeholder-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_firehose_id"]
  values = { insecure_value = "sg-0aaaaaaa00000005" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/raw_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-raw-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-curated-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/glue_assets_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-glue-assets-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/raw_database_name"]
  values = { insecure_value = "example_dev_raw" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_dev_curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-placeholder-events" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-firehose" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_crawler_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-glue-crawler" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_job_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-glue-job" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_events_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-glue-events" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_domain_arn"]
  values = { insecure_value = "arn:aws:es:ap-northeast-1:111111111111:domain/example-placeholder-search" }
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

# Design section 7.4 and 7.5: the pipeline settings are the same in dev and sit.
run "tfvars_build_the_same_pipeline_in_both_envs" {
  command = plan

  assert {
    condition     = local.firehose_s3.s3.buffering_interval == 900 && local.event_trigger.batch_size == 100 && local.event_trigger.batch_window_seconds == 900
    error_message = "Both envs must buffer 900 seconds and batch 100 events per 900 seconds"
  }

  assert {
    condition     = module.etl.workflow_name == "example-${var.env}-raw-to-curated"
    error_message = "The workflow name must follow the iam-base naming rule in both envs"
  }
}
