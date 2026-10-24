mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# Upstream values: what foundation, network, storage, iam-base and search publish. Every role differs, so a call wired to
# the wrong role fails the assertions.
override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
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
  values = { insecure_value = "arn:aws:s3:::example-dev-raw-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-curated-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/glue_assets_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-glue-assets-111111111111" }
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
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_crawler_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-glue-crawler" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_job_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-glue-job" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_glue_events_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-glue-events" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_domain_arn"]
  values = { insecure_value = "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" }
}

run "reads_only_keys_from_earlier_stacks" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn            = "foundation/kms_key_arn"
      alarm_topic_arn        = "foundation/alarm_topic_arn"
      sg_firehose_id         = "network/sg_firehose_id"
      raw_bucket_arn         = "storage/raw_bucket_arn"
      curated_bucket_arn     = "storage/curated_bucket_arn"
      glue_assets_bucket_arn = "storage/glue_assets_bucket_arn"
      raw_database_name      = "storage/raw_database_name"
      curated_database_name  = "storage/curated_database_name"
      stream_arn             = "storage/stream_arn"
      role_firehose_arn      = "iam-base/role_firehose_arn"
      role_glue_crawler_arn  = "iam-base/role_glue_crawler_arn"
      role_glue_job_arn      = "iam-base/role_glue_job_arn"
      role_glue_events_arn   = "iam-base/role_glue_events_arn"
      opensearch_domain_arn  = "search/opensearch_domain_arn"
    } && local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    error_message = "pipeline may only read keys that foundation, network, storage, iam-base and search publish (design section 7.2)"
  }
}

run "firehose_s3_reads_the_stream_and_writes_gzip_to_raw" {
  command = plan

  assert {
    condition     = local.firehose_s3.source_stream_arn == "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events"
    error_message = "The S3 delivery stream must read the Kinesis stream storage publishes"
  }

  assert {
    condition     = local.firehose_s3.s3.bucket_arn == "arn:aws:s3:::example-dev-raw-111111111111" && local.firehose_s3.s3.compression == "GZIP"
    error_message = "The S3 delivery stream must write GZIP objects to the raw bucket (design D5)"
  }

  assert {
    condition     = module.firehose_s3.name == "example-dev-to-raw"
    error_message = "The S3 delivery stream must be named <name_prefix>-to-raw"
  }
}

run "firehose_s3_buffers_900_seconds_with_time_and_error_prefixes" {
  command = plan

  assert {
    condition     = local.firehose_s3.s3.buffering_interval == 900 && local.firehose_s3.s3.buffering_size == 64
    error_message = "The S3 delivery stream must buffer 64 MiB or 900 seconds: it sets how often the ETL fires (design section 7.4)"
  }

  assert {
    condition     = startswith(local.firehose_s3.s3.prefix, "raw/!{timestamp:") && endswith(local.firehose_s3.s3.prefix, "/")
    error_message = "Objects must go under raw/ with a time prefix, because the EventBridge rule matches the raw/ prefix"
  }

  assert {
    condition     = startswith(local.firehose_s3.s3.error_output_prefix, "errors/") && strcontains(local.firehose_s3.s3.error_output_prefix, "!{firehose:error-output-type}")
    error_message = "Failed records must go under errors/ (outside the rule prefix) with the error type in the path"
  }
}

run "firehose_roles_are_the_iam_base_firehose_role" {
  command = plan

  assert {
    condition = (
      local.firehose_s3.role_arn == "arn:aws:iam::111111111111:role/example-dev-firehose" &&
      local.firehose_opensearch.role_arn == "arn:aws:iam::111111111111:role/example-dev-firehose"
    )
    error_message = "Both delivery streams must use the firehose role of iam-base"
  }
}

run "firehose_opensearch_runs_in_the_data_subnets_and_backs_up_failures" {
  command = plan

  assert {
    condition     = local.firehose_opensearch.source_stream_arn == "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events"
    error_message = "The OpenSearch delivery stream must read the same Kinesis stream"
  }

  assert {
    condition = (
      local.firehose_opensearch.opensearch.domain_arn == "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" &&
      local.firehose_opensearch.opensearch.index_name == "example-dev-events"
    )
    error_message = "The OpenSearch delivery stream must write the index to the domain search publishes"
  }

  assert {
    condition     = local.firehose_opensearch.opensearch.subnet_ids == toset(["subnet-0dat1", "subnet-0dat2"]) && local.firehose_opensearch.opensearch.security_group_ids == toset(["sg-0aaaaaaa00000005"])
    error_message = "The OpenSearch delivery stream must sit in the data subnets with the firehose security group"
  }

  assert {
    condition     = startswith(local.firehose_opensearch.s3.prefix, "errors/") && local.firehose_opensearch.s3.bucket_arn == "arn:aws:s3:::example-dev-raw-111111111111"
    error_message = "The backup of failed documents must go to errors/ in the raw bucket, outside the rule prefix"
  }

  assert {
    condition     = local.firehose_opensearch.s3.buffering_size == 5 && local.firehose_opensearch.s3.buffering_interval == 60
    error_message = "The OpenSearch delivery stream must buffer 5 MiB or 60 seconds (design section 7.5)"
  }

  assert {
    condition     = module.firehose_opensearch.name == "example-dev-to-search"
    error_message = "The OpenSearch delivery stream must be named <name_prefix>-to-search"
  }
}

run "etl_encrypts_with_the_foundation_key" {
  command = plan

  assert {
    condition     = local.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The security configuration, the log groups and both delivery streams must use the foundation key"
  }
}

run "raw_crawler_runs_daily_with_the_crawler_role" {
  command = plan

  assert {
    condition     = local.crawlers["raw"].role_arn == "arn:aws:iam::111111111111:role/example-dev-glue-crawler"
    error_message = "The crawler must use the glue-crawler role of iam-base"
  }

  assert {
    condition     = local.crawlers["raw"].database_name == "example_dev_raw" && local.crawlers["raw"].s3_paths == ["s3://example-dev-raw-111111111111/raw/"]
    error_message = "The crawler must scan the raw/ prefix of the raw bucket into the raw database"
  }

  assert {
    condition     = can(regex("^cron\\(\\d+ \\d+ \\* \\* \\? \\*\\)$", local.crawlers["raw"].schedule))
    error_message = "The crawler must run once a day (design K22), not on every event"
  }
}

run "job_reads_raw_writes_curated_with_the_job_role" {
  command = plan

  assert {
    condition     = local.jobs["raw_to_curated"].role_arn == "arn:aws:iam::111111111111:role/example-dev-glue-job"
    error_message = "The job must use the glue-job role of iam-base"
  }

  assert {
    condition     = local.jobs["raw_to_curated"].script_location == "s3://example-dev-glue-assets-111111111111/scripts/raw_to_curated.py"
    error_message = "The script must live under scripts/ of the glue-assets bucket (design K10)"
  }

  assert {
    condition = (
      local.jobs["raw_to_curated"].default_arguments["--raw_database"] == "example_dev_raw" &&
      local.jobs["raw_to_curated"].default_arguments["--curated_database"] == "example_dev_curated" &&
      local.jobs["raw_to_curated"].default_arguments["--raw_path"] == "s3://example-dev-raw-111111111111/raw/" &&
      local.jobs["raw_to_curated"].default_arguments["--curated_path"] == "s3://example-dev-curated-111111111111/"
    )
    error_message = "The job must read the raw bucket and database and write the curated bucket and database"
  }

  assert {
    condition     = local.jobs["raw_to_curated"].default_arguments["--job-bookmark-option"] == "job-bookmark-enable" && local.jobs["raw_to_curated"].default_arguments["--TempDir"] == "s3://example-dev-glue-assets-111111111111/tmp/"
    error_message = "The job must use a bookmark (design section 7.4) and the tmp/ prefix of glue-assets for temporary files"
  }

  assert {
    condition     = local.jobs["raw_to_curated"].execution_class == "FLEX" && local.jobs["raw_to_curated"].worker_type == "G.1X" && local.jobs["raw_to_curated"].number_of_workers == 2
    error_message = "The job must be Flex on two G.1X workers (design section 7.4 cost estimate)"
  }

  assert {
    condition     = jsonencode(module.etl.job_names) == jsonencode(["example-dev-raw-to-curated-job"]) && startswith(module.etl.job_names[0], "example-dev-")
    error_message = "The job name must start with <name_prefix>-: iam-base grants bookmark permissions on job/<name_prefix>-*"
  }
}

# The strings below are written out on purpose: iam-base builds the workflow ARN and the rule ARN (<workflow>-s3-event, named by glue-etl) from the same naming
# rule, so a rename here must break this test instead of silently breaking glue:notifyEvent.
run "workflow_name_matches_the_iam_base_naming_rule" {
  command = plan

  assert {
    condition     = module.etl.workflow_name == "example-dev-raw-to-curated"
    error_message = "The workflow must be named <name_prefix>-raw-to-curated, as iam-base expects"
  }
}

run "event_trigger_watches_raw_prefix_in_batches_of_100_per_900_seconds" {
  command = plan

  assert {
    condition     = local.event_trigger.bucket_name == "example-dev-raw-111111111111" && local.event_trigger.key_prefix == "raw/"
    error_message = "The rule must match only the raw bucket and the raw/ prefix"
  }

  assert {
    condition     = local.event_trigger.batch_size == 100 && local.event_trigger.batch_window_seconds == 900
    error_message = "The EVENT trigger must batch 100 events or 900 seconds, the upper limits (design section 7.4)"
  }

  assert {
    condition     = local.event_trigger.role_arn == "arn:aws:iam::111111111111:role/example-dev-glue-events"
    error_message = "EventBridge must call the workflow with the glue-events role of iam-base"
  }

  assert {
    condition     = jsonencode(local.event_trigger.actions) == jsonencode([{ job = "example-dev-raw-to-curated-job", arguments = {} }])
    error_message = "Each event must run the job only, not the crawler (design K22)"
  }
}

run "alarms_watch_the_data_freshness_of_both_streams" {
  command = plan

  assert {
    condition     = toset(keys(local.alarms)) == toset(["firehose_s3_data_freshness", "firehose_opensearch_data_freshness"])
    error_message = "pipeline must alarm on the data freshness of both delivery streams"
  }

  assert {
    condition = (
      local.alarms["firehose_s3_data_freshness"].metric.namespace == "AWS/Firehose" &&
      local.alarms["firehose_s3_data_freshness"].metric.metric_name == "DeliveryToS3.DataFreshness" &&
      local.alarms["firehose_s3_data_freshness"].metric.dimensions == { DeliveryStreamName = "example-dev-to-raw" } &&
      local.alarms["firehose_opensearch_data_freshness"].metric.metric_name == "DeliveryToAmazonOpenSearchService.DataFreshness" &&
      local.alarms["firehose_opensearch_data_freshness"].metric.dimensions == { DeliveryStreamName = "example-dev-to-search" }
    )
    error_message = "Each alarm must watch DataFreshness of its own delivery stream"
  }

  # The S3 stream holds data up to 900 seconds by design, so its threshold must be well above that.
  assert {
    condition     = local.alarms["firehose_s3_data_freshness"].threshold > 900
    error_message = "The S3 threshold must exceed the 900 second buffer, or the alarm fires on normal operation"
  }
}

run "publishes_exactly_the_pipeline_keys" {
  command = plan

  # A mock provider leaves computed ARNs unknown at plan, so pin the two ARNs to compare them.
  override_module {
    target  = module.firehose_s3
    outputs = { name = "example-dev-to-raw", arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-raw", log_group_name = "x" }
  }

  override_module {
    target  = module.firehose_opensearch
    outputs = { name = "example-dev-to-search", arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-search", log_group_name = "x" }
  }

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["firehose_s3_arn", "firehose_opensearch_arn", "glue_workflow_name"])
    error_message = "pipeline must publish exactly the keys of design section 7.2"
  }

  assert {
    condition     = local.published_strings["glue_workflow_name"] == "example-dev-raw-to-curated"
    error_message = "glue_workflow_name must be the workflow name"
  }

  assert {
    condition = (
      local.published_strings["firehose_s3_arn"] == "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-raw" &&
      local.published_strings["firehose_opensearch_arn"] == "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-search"
    )
    error_message = "The firehose keys must come from the matching module outputs"
  }

  assert {
    condition = module.ssm_publish.names == {
      firehose_s3_arn         = "/example/dev/pipeline/firehose_s3_arn"
      firehose_opensearch_arn = "/example/dev/pipeline/firehose_opensearch_arn"
      glue_workflow_name      = "/example/dev/pipeline/glue_workflow_name"
    }
    error_message = "ssm-publish must write the contract keys under the pipeline stack path"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
