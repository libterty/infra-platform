# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, search and iam-base publish.
# Not a mock: mock providers cannot open ephemeral resources (Terraform 1.15: "No ephemeral resource types in mock
# providers"), and no override block reaches them. This is a real aws provider with fake credentials, every API endpoint
# aimed at a closed local port and all startup calls skipped, so nothing can leave this machine. The SSM reads are
# overridden below, and read_master_secret = false keeps the ephemeral block from opening.
provider "aws" {
  region                      = "ap-northeast-1"
  access_key                  = "test-access-key"
  secret_key                  = "test-secret-key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ssm            = "http://127.0.0.1:9"
    sts            = "http://127.0.0.1:9"
    secretsmanager = "http://127.0.0.1:9"
  }
}
mock_provider "opensearch" {}

variables {
  read_master_secret = false
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/opensearch_master_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-placeholder-opensearch-master-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["search/opensearch_endpoint"]
  values = { insecure_value = "vpc-example-placeholder-search-abc123.ap-northeast-1.es.amazonaws.com" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-firehose" }
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

# Design section 7.5: ISM age is cumulative; dev is 3 / 7 / 30 days, sit is 7 / 30 / 90 days.
run "tfvars_ism_days_match_the_env" {
  command = plan

  assert {
    condition = (
      var.ism.warm_days == (var.env == "dev" ? 3 : 7) &&
      var.ism.cold_days == (var.env == "dev" ? 7 : 30) &&
      var.ism.delete_days == (var.env == "dev" ? 30 : 90)
    )
    error_message = "ISM must move to warm, move to cold and delete at 3 / 7 / 30 days in dev and 7 / 30 / 90 days in sit (design section 7.5)"
  }

  assert {
    condition     = var.ism.timestamp_field != null && length(var.ism.timestamp_field) > 0
    error_message = "The ISM policy needs a timestamp_field: cold migration fails without one"
  }
}

run "tfvars_build_policy_writer_role_and_template" {
  command = plan

  assert {
    condition     = length(local.ism_policies) == 1 && length(local.writer_roles) == 1 && length(local.index_templates) == 1
    error_message = "The tfvars must build one ISM policy, one writer role and one index template"
  }

  assert {
    condition     = alltrue([for p in local.index_patterns : p != "*" && endswith(p, "-events*")])
    error_message = "index_patterns must stay a prefix ending in -events*, never a bare *"
  }
}

run "tfvars_never_map_the_admin_roles" {
  command = plan

  assert {
    condition     = !contains(keys(local.role_mappings), "all_access") && !contains(keys(local.role_mappings), "security_manager")
    error_message = "The tfvars must not map all_access or security_manager"
  }
}
