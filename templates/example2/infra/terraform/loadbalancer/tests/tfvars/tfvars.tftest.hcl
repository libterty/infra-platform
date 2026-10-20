# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

variables {
  # Never in a tfvars file; a throwaway value so the stack can plan.
  origin_verify_header_value = "test-only-origin-secret"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id          = "vpc-0123456789abcdef0"
      alb_sg_id       = "sg-0123456789abcdef0"
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
    }
    lists = {
      public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
}

run "tfvars_pair_env_with_a_registered_account" {
  command = plan

  assert {
    condition     = var.project == "example"
    error_message = "Every tfvars file of the template uses the placeholder project name"
  }

  assert {
    condition     = contains(local.accounts_by_env[var.env], var.expected_account_id)
    error_message = "expected_account_id in tfvars must be one of the accounts registered for env in common.tf"
  }

  assert {
    condition     = var.deploy_role_arn == ""
    error_message = "The template ships with an empty deploy_role_arn so it runs as the caller"
  }
}

run "tfvars_carry_the_header_name_but_never_its_value" {
  command = plan

  assert {
    condition     = var.origin_verify_header_name == "X-Origin-Verify"
    error_message = "tfvars name the origin verify header"
  }

  assert {
    condition     = !can(regex("(?m)^\\s*origin_verify_header_value\\s*=", file("${path.module}/envs/${var.env}.tfvars")))
    error_message = "The origin verify value is a secret: pass it with TF_VAR_origin_verify_header_value, never in tfvars"
  }

  assert {
    condition     = length(var.origin_verify_host_headers) == 1 && endswith(var.origin_verify_host_headers[0], ".example.com")
    error_message = "The placeholder host uses the example.com domain"
  }
}
