# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

variables {
  # Never in a tfvars file; a throwaway value so the stack can plan.
  origin_verify_header_value = "test-only-origin-secret"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alb_dns_name = "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id  = "Z14GRHDCWA56QT"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      zone_id                    = "Z0123456789ABCDEFGHIJ"
      zone_name                  = "dev.example.com"
      cloudfront_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
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

# Design 4.1: the value only comes from TF_VAR_origin_verify_header_value, and both stacks name the header alike.
run "tfvars_carry_the_header_name_but_never_its_value" {
  command = plan

  assert {
    condition     = !can(regex("(?m)^\\s*origin_verify_header_value\\s*=", file("${path.module}/envs/${var.env}.tfvars")))
    error_message = "The origin verify value is a secret: pass it with TF_VAR_origin_verify_header_value, never in tfvars"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*origin_verify_header_name\\s*=\\s*\"${var.origin_verify_header_name}\"\\s*$", file("${path.module}/../loadbalancer/envs/${var.env}.tfvars"))) == 1
    error_message = "origin_verify_header_name must equal the one in loadbalancer/envs/<env>.tfvars, which the ALB rules check"
  }
}
