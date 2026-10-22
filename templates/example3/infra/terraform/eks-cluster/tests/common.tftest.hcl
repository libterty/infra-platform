# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
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

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan.
  kubernetes_version           = "1.36"
  cluster_admin_principal_arns = ["arn:aws:iam::111111111111:role/example-dev-eks-admin"]
  addons_apply_principal_arn   = "arn:aws:iam::111111111111:role/example-dev-eks-addons-apply"
  ci_deploy_principal_arn      = "arn:aws:iam::111111111111:role/example-dev-ci-deploy"
}

run "dev_accepts_its_account" {
  command = plan

  assert {
    condition     = local.name_prefix == "example-dev"
    error_message = "dev with the dev account must plan, and name_prefix must be <project>-<env>"
  }

  assert {
    condition     = local.ssm_prefix == "/example/dev" && local.shared_ssm_prefix == "/example-shared/dev"
    error_message = "ssm_prefix and shared_ssm_prefix must follow the two-tree layout"
  }
}

run "sit_accepts_its_account" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit"
    error_message = "sit with the sit account must plan"
  }
}

run "rejects_an_account_of_another_env" {
  command = plan

  variables {
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "rejects_an_env_without_an_account" {
  command = plan

  variables {
    env = "other"
  }

  expect_failures = [var.expected_account_id]
}

run "rejects_a_malformed_env" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "rejects_a_deploy_role_in_another_account" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "accepts_a_deploy_role_in_the_same_account" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn != ""
    error_message = "A role in expected_account_id must be accepted"
  }
}
