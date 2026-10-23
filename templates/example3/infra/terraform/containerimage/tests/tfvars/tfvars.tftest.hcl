# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

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

run "tfvars_have_a_repository_for_every_workload_and_the_breaker" {
  command = plan

  assert {
    condition     = length(setsubtract(["api", "worker", "import-extract", "import-load", "traffic-breaker"], var.services)) == 0
    error_message = "The EKS workloads, the two import Lambdas and the canary breaker Lambda of loadbalancer each need a repository"
  }
}
