# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
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
