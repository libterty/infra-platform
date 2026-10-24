# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, network and storage publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_quicksight_id"]
  values = { insecure_value = "sg-0aaaaaaa00000008" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/raw_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-raw" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/glue_assets_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-placeholder-glue-assets" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/raw_database_name"]
  values = { insecure_value = "example_placeholder_raw" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_placeholder_curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

run "tfvars_build_the_six_roles" {
  command = plan

  assert {
    condition     = toset(keys(module.role)) == toset(["firehose", "glue_crawler", "glue_job", "glue_events", "redshift", "quicksight_vpc"])
    error_message = "The tfvars must build the six roles"
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

# The glue-events policy and trust are built from the env and account of the tfvars, never from a wildcard.
run "tfvars_glue_events_arns_follow_the_env" {
  command = plan

  assert {
    condition     = local.workflow_arn == "arn:aws:glue:ap-northeast-1:${var.expected_account_id}:workflow/example-${var.env}-raw-to-curated"
    error_message = "The workflow ARN must be built from the tfvars env and account"
  }

  assert {
    condition     = local.roles["glue_events"].trust.source_arn == "arn:aws:events:ap-northeast-1:${var.expected_account_id}:rule/example-${var.env}-raw-to-curated-s3-event"
    error_message = "The trust source_arn must be built from the tfvars env and account"
  }
}
