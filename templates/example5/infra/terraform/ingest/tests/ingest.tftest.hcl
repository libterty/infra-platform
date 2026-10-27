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
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_firehose_id"]
  values = { insecure_value = "sg-0aaaaaaa00000002" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/telemetry_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-telemetry-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/rule_errors_queue_url"]
  values = { insecure_value = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/example-dev-rule-errors" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_rule_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-rule" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_domain_arn"]
  values = { insecure_value = "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" }
}

run "reads_only_keys_from_earlier_stacks" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn           = "foundation/kms_key_arn"
      alarm_topic_arn       = "foundation/alarm_topic_arn"
      sg_firehose_id        = "network/sg_firehose_id"
      telemetry_bucket_arn  = "storage/telemetry_bucket_arn"
      stream_arn            = "storage/stream_arn"
      rule_errors_queue_url = "storage/rule_errors_queue_url"
      role_iot_rule_arn     = "iam-base/role_iot_rule_arn"
      role_firehose_arn     = "iam-base/role_firehose_arn"
      opensearch_domain_arn = "search/opensearch_domain_arn"
    } && local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    error_message = "ingest may only read keys that foundation, network, storage, iam-base and search publish (design section 7.2)"
  }
}

# ---- IoT rules (design K15, K26) ----

run "two_rules_named_for_the_iam_base_trust" {
  command = plan

  assert {
    condition     = toset(keys(local.rules)) == toset(["example_dev_telemetry", "example_dev_inference"])
    error_message = "The rules must be <name_prefix with underscores>_telemetry and _inference"
  }

  assert {
    condition     = alltrue([for k in keys(local.rules) : startswith(k, "example_dev_")])
    error_message = "Rule names must match the iam-base trust of the iot-rule role (rule/example_dev_*)"
  }
}

run "rules_read_the_device_topics" {
  command = plan

  assert {
    condition     = strcontains(local.rules["example_dev_telemetry"].sql, "FROM 'example-dev/telemetry/+'")
    error_message = "The telemetry rule reads <name_prefix>/telemetry/+, the topic the device policy lets devices publish"
  }

  assert {
    condition     = strcontains(local.rules["example_dev_inference"].sql, "FROM 'example-dev/inference/+'")
    error_message = "The inference rule reads <name_prefix>/inference/+, the topic core devices publish results to"
  }

  assert {
    condition     = alltrue([for r in values(local.rules) : startswith(r.sql, "SELECT ") && strcontains(r.sql, "topic(3) AS thing_name")])
    error_message = "Every rule is a SELECT that adds the thing name from the topic"
  }
}

run "rules_put_to_the_storage_stream_with_the_rule_role" {
  command = plan

  assert {
    condition = alltrue([
      for r in values(local.rules) :
      r.actions.kinesis == [{ stream_name = "example-dev-telemetry", role_arn = "arn:aws:iam::111111111111:role/example-dev-iot-rule", partition_key = "$${topic(3)}" }]
    ])
    error_message = "Every rule puts to the storage stream, partitioned by thing name, with the iam-base iot-rule role"
  }

  assert {
    condition     = alltrue([for r in values(local.rules) : toset([for k, v in r.actions : k if length(v) > 0]) == toset(["kinesis"])])
    error_message = "Rules have only a Kinesis action; OpenSearch is reached through Firehose (design K15)"
  }
}

run "error_action_sends_to_rule_errors" {
  command = plan

  assert {
    condition     = local.error_action == { sqs = { queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/example-dev-rule-errors", role_arn = "arn:aws:iam::111111111111:role/example-dev-iot-rule", use_base64 = false } }
    error_message = "Failed actions must go to the rule-errors queue of storage with the iot-rule role"
  }
}

# ---- Firehose ----

run "firehose_s3_reads_the_stream_and_writes_gzip_to_raw" {
  command = plan

  assert {
    condition = (
      local.firehose_s3.source_stream_arn == "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry" &&
      local.firehose_s3.s3.bucket_arn == "arn:aws:s3:::example-dev-telemetry-111111111111" &&
      local.firehose_s3.s3.compression == "GZIP" &&
      module.firehose_s3.name == "example-dev-to-raw"
    )
    error_message = "The S3 delivery stream <name_prefix>-to-raw reads the stream and writes GZIP JSON to the telemetry bucket"
  }

  assert {
    condition     = startswith(local.firehose_s3.s3.prefix, "raw/!{timestamp:") && startswith(local.firehose_s3.s3.error_output_prefix, "errors/")
    error_message = "Objects go under raw/ with a time prefix and failures under errors/: the only prefixes iam-app lets Firehose write"
  }
}

run "firehose_roles_are_the_iam_base_firehose_role" {
  command = plan

  assert {
    condition     = local.firehose_s3.role_arn == "arn:aws:iam::111111111111:role/example-dev-firehose" && local.firehose_opensearch.role_arn == "arn:aws:iam::111111111111:role/example-dev-firehose"
    error_message = "Both delivery streams must use the firehose role of iam-base"
  }

  assert {
    condition     = alltrue([for n in [module.firehose_s3.name, module.firehose_opensearch.name] : startswith(n, "example-dev-")])
    error_message = "Stream names must start with <name_prefix>- so the log group scope of iam-app covers them"
  }
}

run "firehose_opensearch_runs_in_the_data_subnets_and_backs_up_failures" {
  command = plan

  assert {
    condition = (
      local.firehose_opensearch.opensearch.domain_arn == "arn:aws:es:ap-northeast-1:111111111111:domain/example-dev-search" &&
      local.firehose_opensearch.opensearch.index_name == "example-dev-events" &&
      module.firehose_opensearch.name == "example-dev-to-search"
    )
    error_message = "The OpenSearch delivery stream writes index <name_prefix>-events, the pattern search-config covers"
  }

  assert {
    condition     = local.firehose_opensearch.opensearch.subnet_ids == toset(["subnet-0dat1", "subnet-0dat2"]) && local.firehose_opensearch.opensearch.security_group_ids == toset(["sg-0aaaaaaa00000002"])
    error_message = "The OpenSearch delivery stream sits in the data subnets with the firehose security group"
  }

  assert {
    condition     = startswith(local.firehose_opensearch.s3.prefix, "errors/") && local.firehose_opensearch.s3.bucket_arn == "arn:aws:s3:::example-dev-telemetry-111111111111"
    error_message = "The backup of failed documents goes to errors/ in the telemetry bucket"
  }
}

run "everything_uses_the_foundation_key" {
  command = plan

  assert {
    condition     = length(regexall("(?m)^\\s*kms_key_arn\\s*=\\s*local\\.kms_key_arn\\s*$", file("${path.module}/firehose.tf"))) == 2 && local.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Both delivery streams must encrypt with the shared key"
  }
}

run "alarms_watch_the_data_freshness_of_both_streams" {
  command = plan

  assert {
    condition = (
      toset(keys(local.alarms)) == toset(["firehose_s3_data_freshness", "firehose_opensearch_data_freshness"]) &&
      local.alarms["firehose_s3_data_freshness"].metric.metric_name == "DeliveryToS3.DataFreshness" &&
      local.alarms["firehose_s3_data_freshness"].metric.dimensions == { DeliveryStreamName = "example-dev-to-raw" } &&
      local.alarms["firehose_opensearch_data_freshness"].metric.metric_name == "DeliveryToAmazonOpenSearchService.DataFreshness" &&
      local.alarms["firehose_opensearch_data_freshness"].metric.dimensions == { DeliveryStreamName = "example-dev-to-search" }
    )
    error_message = "ingest alarms on the data freshness of both delivery streams (the rule-errors queue alarms are in storage)"
  }

  assert {
    condition     = local.alarms["firehose_s3_data_freshness"].threshold > local.firehose_s3.s3.buffering_interval
    error_message = "The S3 threshold must exceed its buffer interval, or the alarm fires on normal operation"
  }
}

run "publishes_exactly_the_ingest_keys" {
  command = plan

  override_module {
    target  = module.firehose_s3
    outputs = { name = "example-dev-to-raw", arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-raw", log_group_name = "x" }
  }

  override_module {
    target  = module.firehose_opensearch
    outputs = { name = "example-dev-to-search", arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-search", log_group_name = "x" }
  }

  override_module {
    target  = module.rules
    outputs = { rule_arns = {}, rule_names = ["example_dev_inference", "example_dev_telemetry"] }
  }

  assert {
    condition = local.published_strings == {
      firehose_s3_arn         = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-raw"
      firehose_opensearch_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/example-dev-to-search"
    }
    error_message = "ingest publishes the two delivery stream ARNs (design section 7.2)"
  }

  assert {
    condition     = keys(local.published_lists) == ["rule_names"] && tolist(local.published_lists["rule_names"]) == tolist(["example_dev_inference", "example_dev_telemetry"])
    error_message = "ingest publishes rule_names as a StringList"
  }

  assert {
    condition = module.ssm_publish.names == {
      firehose_s3_arn         = "/example/dev/ingest/firehose_s3_arn"
      firehose_opensearch_arn = "/example/dev/ingest/firehose_opensearch_arn"
      rule_names              = "/example/dev/ingest/rule_names"
    }
    error_message = "ssm-publish must write the contract keys under the ingest stack path"
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
