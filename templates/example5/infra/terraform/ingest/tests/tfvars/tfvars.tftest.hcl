# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

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

run "tfvars_build_both_rules_and_streams" {
  command = plan

  assert {
    condition     = length(local.rules) == 2 && module.firehose_s3.name == "example-${var.env}-to-raw" && module.firehose_opensearch.name == "example-${var.env}-to-search"
    error_message = "The tfvars must build both rules and both delivery streams"
  }
}
