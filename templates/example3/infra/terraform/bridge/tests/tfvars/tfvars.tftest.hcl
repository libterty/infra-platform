# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
      agent_runtimes                 = "[\"agent\"]"
      ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
      vpc_id                         = "vpc-0aaaaaaa00000001"
      alb_sg_id                      = "sg-0aaaaaaa00000001"
      app_sg_id                      = "sg-0aaaaaaa00000002"
      agent_sg_id                    = "sg-0aaaaaaa00000003"
      bastion_sg_id                  = "sg-0aaaaaaa00000004"
      db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
      stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
      db_name                        = "app"
      stream_shard_count             = "1"
      import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
      import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
      agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
      eks_api_sg_id                  = "sg-0aaaaaaa00000005"
      node_sg_id                     = "sg-0aaaaaaa00000006"
      eks_cluster_role_arn           = "arn:aws:iam::111111111111:role/example-dev-eks-cluster"
      eks_node_role_arn              = "arn:aws:iam::111111111111:role/example-dev-eks-node"
      api_pod_role_arn               = "arn:aws:iam::111111111111:role/example-dev-api-pod"
      worker_pod_role_arn            = "arn:aws:iam::111111111111:role/example-dev-worker-pod"
      lb_controller_role_arn         = "arn:aws:iam::111111111111:role/example-dev-lb-controller"
      keda_role_arn                  = "arn:aws:iam::111111111111:role/example-dev-keda"
      cloudwatch_agent_role_arn      = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent"
    }
    lists = {
      services          = ["api", "worker"]
      public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
      app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
      app_subnet_cidrs  = ["10.10.64.0/19", "10.10.96.0/19"]
      agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
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
