# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation and storage publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/athena_results_bucket_name"]
  values = { insecure_value = "example-placeholder-athena-results-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_placeholder_curated" }
}

run "tfvars_build_the_workgroup" {
  command = plan

  assert {
    condition     = module.workgroup.name == "${var.project}-${var.env}-analytics"
    error_message = "The tfvars must build the <project>-<env>-analytics workgroup"
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

# Design section 7.5: Athena stops a query after 10 GiB scanned in both envs.
run "tfvars_cutoff_matches_the_design" {
  command = plan

  assert {
    condition     = local.bytes_scanned_cutoff_per_query == 10737418240
    error_message = "The per-query scan limit must be 10 GiB in both envs (design section 7.5)"
  }
}
