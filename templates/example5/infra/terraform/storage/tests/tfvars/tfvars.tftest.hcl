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
    condition     = toset(keys(module.bucket)) == toset(["telemetry", "greengrass_artifacts", "ota", "ml"]) && toset(keys(module.queue)) == toset(["rule_errors", "model_approved"])
    error_message = "The tfvars must build the four buckets and the two queues"
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

run "tfvars_stream_matches_the_design" {
  command = plan

  assert {
    condition     = local.stream.mode == "PROVISIONED" && local.stream.shard_count == 1 && local.stream.retention_hours == 24
    error_message = "dev and sit run one provisioned shard with 24 hours of retention (design section 7.5)"
  }
}
