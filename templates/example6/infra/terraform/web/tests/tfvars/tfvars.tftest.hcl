# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

variables {
  # Never in a tfvars file; a throwaway value so the stack can plan.
  origin_verify_header_value = "test-only-origin-secret"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_id"]
  values = { insecure_value = "Z0000000000000000000A" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
  values = { insecure_value = "dev.example.com" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["certificate/web_certificate_arn"]
  values = { insecure_value = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["api/api_endpoint"]
  values = { insecure_value = "a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com" }
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

# Design 8.3.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.log_retention_days == (var.env == "dev" ? 30 : 90)
    error_message = "Logs must be kept 30 days in dev and 90 days in sit"
  }
}

# Section 4.1: the value only comes from TF_VAR_origin_verify_header_value.
run "tfvars_never_hold_the_origin_verify_value" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "envs/*.tfvars") : length(regexall("(?m)^\\s*origin_verify_header_value\\s*=", file("${path.module}/${f}"))) == 0])
    error_message = "origin_verify_header_value must never be set in a tfvars file"
  }
}

# The api stack checks this header; both tfvars files must name it the same.
run "tfvars_origin_verify_header_name_matches_api" {
  command = plan

  assert {
    condition     = var.origin_verify_header_name == "X-Origin-Verify"
    error_message = "origin_verify_header_name must be X-Origin-Verify, the name api/envs/<env>.tfvars uses"
  }
}
