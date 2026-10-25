# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_firehose_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/telemetry_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-telemetry" }
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

run "tfvars_names_and_arns_follow_the_env" {
  command = plan

  assert {
    condition     = local.firehose_log_group_arn == "arn:aws:logs:ap-northeast-1:${var.expected_account_id}:log-group:/aws/kinesisfirehose/example-${var.env}-*"
    error_message = "The Firehose log group scope must be built from the tfvars env and account"
  }
}
