# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {}
mock_provider "helm" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      contract_version = "1"
      cluster_name     = "example-dev"
      cluster_endpoint = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      cluster_ca_data  = "Y2VydGlmaWNhdGU="
      cluster_sg_id    = "sg-0aaaaaaa00000007"
      service_cidr     = "172.20.0.0/16"
      app_namespace    = "app"
    }
    lists = {}
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id            = "vpc-0aaaaaaa00000001"
      app_sg_id         = "sg-0aaaaaaa00000002"
      node_sg_id        = "sg-0aaaaaaa00000006"
      eks_node_role_arn = "arn:aws:iam::111111111111:role/example-dev-eks-node"
    }
    lists = {
      app_subnet_cidrs = ["10.10.64.0/19", "10.10.96.0/19"]
    }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
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
