# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.shared
  outputs = {
    strings = {
      eks_api_sg_id             = "sg-0aaaaaaa00000005"
      eks_cluster_role_arn      = "arn:aws:iam::111111111111:role/example-dev-eks-cluster"
      eks_node_role_arn         = "arn:aws:iam::111111111111:role/example-dev-eks-node"
      api_pod_role_arn          = "arn:aws:iam::111111111111:role/example-dev-api-pod"
      worker_pod_role_arn       = "arn:aws:iam::111111111111:role/example-dev-worker-pod"
      lb_controller_role_arn    = "arn:aws:iam::111111111111:role/example-dev-lb-controller"
      keda_role_arn             = "arn:aws:iam::111111111111:role/example-dev-keda"
      cloudwatch_agent_role_arn = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent"
    }
    lists = {
      app_subnet_ids = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
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

run "tfvars_principals_live_in_the_env_account" {
  command = plan

  assert {
    condition = alltrue([
      for a in concat(var.cluster_admin_principal_arns, [var.addons_apply_principal_arn, var.ci_deploy_principal_arn]) :
      split(":", a)[4] == var.expected_account_id
    ])
    error_message = "The placeholder access entry principals must be in expected_account_id of the same env"
  }
}
