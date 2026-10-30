mock_provider "aws" {}

variables {
  project                 = "cicd"
  env                     = "dev"
  expected_account_id     = "111111111111"
  api_bootstrap_image_tag = "bootstrap"
  fn_bootstrap_image_tag  = "bootstrap"
  api_desired_count       = 1
  log_retention_days      = 30
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/fn_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/app_subnet_ids"]
  values = { insecure_value = "subnet-0000000000000000c,subnet-0000000000000000d" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_execution_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-execution" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_task_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-task" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/fn_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-fn" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/listener_arn"]
  values = { insecure_value = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/cicd-dev-alb/0123456789abcdef/0123456789abcdef" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/security_group_id"]
  values = { insecure_value = "sg-0000000000000000a" }
}

# The group ID is unknown at plan time; the service's network is checked with this value.
override_module {
  target  = module.sg
  outputs = { security_group_ids = { api = "sg-0000000000000000b" }, security_group_arns = { api = "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0000000000000000b" } }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      api_repository_url     = "containerimage/api_repository_url"
      fn_repository_url      = "containerimage/fn_repository_url"
      kms_key_arn            = "foundation/kms_key_arn"
      vpc_id                 = "network/vpc_id"
      api_execution_role_arn = "iam/api_execution_role_arn"
      api_task_role_arn      = "iam/api_task_role_arn"
      fn_role_arn            = "iam/fn_role_arn"
      listener_arn           = "loadbalancer/listener_arn"
      alb_security_group_id  = "loadbalancer/security_group_id"
    } && local.ssm_input_lists == { app_subnet_ids = "network/app_subnet_ids" }
    error_message = "application may read only the containerimage, foundation, network, iam and loadbalancer keys it needs (design 8.3)"
  }
}

# iam/naming.tf builds the deploy roles' scopes from these names; a different name leaves the pipeline without access.
run "names_match_the_iam_naming_rules" {
  command = plan

  assert {
    condition     = module.cluster.cluster_name == "cicd-dev"
    error_message = "The cluster must be named <name_prefix>, as iam/naming.tf expects"
  }

  assert {
    condition = (
      module.api.service_name == "cicd-dev-api" &&
      module.api.task_definition_family == "cicd-dev-api" &&
      module.api.log_group_name == "/ecs/cicd-dev-api"
    )
    error_message = "The api service, its task family and log group must be cicd-dev-api and /ecs/cicd-dev-api, as iam/naming.tf expects"
  }

  assert {
    condition     = module.fn.function_name == "cicd-dev-fn" && module.fn.log_group_name == "/aws/lambda/cicd-dev-fn"
    error_message = "The function must be cicd-dev-fn with /aws/lambda/cicd-dev-fn, as iam/naming.tf expects"
  }
}

# Design D6, D8 and L5 acceptance: the pipeline deploys both; the api rolls.
run "api_is_pipeline_managed_and_rolling" {
  command = plan

  assert {
    condition     = local.api_service.pipeline_managed && local.api_service.deployment == { strategy = "ROLLING" }
    error_message = "The api service must be pipeline_managed with the ROLLING strategy"
  }

  assert {
    condition     = local.api_service.image == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api:bootstrap"
    error_message = "The api service starts from the bootstrap tag in the api repository (K10)"
  }

  assert {
    condition = (
      local.api_service.execution_role_arn == "arn:aws:iam::111111111111:role/cicd-dev-api-execution" &&
      local.api_service.task_role_arn == "arn:aws:iam::111111111111:role/cicd-dev-api-task"
    )
    error_message = "The api service must use the two roles the api-deploy role may pass"
  }

  assert {
    condition     = local.api_service.desired_count == 1 && local.api_service.container_port == 8080
    error_message = "The api service runs var.api_desired_count tasks on var.app_port"
  }
}

run "fn_is_pipeline_managed_behind_live" {
  command = plan

  assert {
    condition     = local.fn_function.alias == "live" && local.fn_function.pipeline_managed && module.fn.alias_name == "live"
    error_message = "The function must have the alias live and be pipeline_managed"
  }

  assert {
    condition = (
      local.fn_function.image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn:bootstrap" &&
      local.fn_function.role_arn == "arn:aws:iam::111111111111:role/cicd-dev-fn" &&
      local.fn_function.architectures == ["arm64"]
    )
    error_message = "The function starts from the bootstrap tag in the fn repository, on arm64, with the fn role"
  }
}

# Design 8.1: the api is reachable only through the internal ALB.
run "api_admits_only_the_alb" {
  command = plan

  assert {
    condition = local.api_service.load_balancer == {
      listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/cicd-dev-alb/0123456789abcdef/0123456789abcdef"
      vpc_id        = "vpc-0123456789abcdef0"
      priority      = 100
      path_patterns = ["/*"]
      health_check  = { path = "/health" }
    }
    error_message = "The api service must hang its own target group on the loadbalancer listener"
  }

  assert {
    condition = (
      local.api_service.network.subnet_ids == tolist(["subnet-0000000000000000c", "subnet-0000000000000000d"]) &&
      local.api_service.network.security_group_ids == ["sg-0000000000000000b"]
    )
    error_message = "The api tasks run in the app subnets with the api group only"
  }

  assert {
    condition = local.sg_rules == {
      api_in_alb    = { security_group = "api", type = "ingress", description = "from the ALB", from_port = 8080, peer_group_id = "sg-0000000000000000a" }
      api_out_https = { security_group = "api", type = "egress", description = "AWS APIs through the NAT", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
    error_message = "The api group may accept only the ALB group on the app port, and send only HTTPS"
  }
}

run "logs_use_the_shared_key" {
  command = plan

  assert {
    condition     = length(regexall("(?m)^\\s*log_kms_key_arn\\s*=\\s*module\\.in\\.strings\\[\"kms_key_arn\"\\]\\s*$", join("\n", [for f in ["api.tf", "function.tf", "cluster.tf"] : file("${path.module}/${f}")]))) == 3
    error_message = "The service, function and Container Insights log groups must be encrypted with the shared key"
  }
}

run "publishes_the_deploy_targets" {
  command = plan

  assert {
    condition = local.published_strings == {
      cluster_name     = "cicd-dev"
      api_service_name = "cicd-dev-api"
      api_task_family  = "cicd-dev-api"
      fn_function_name = "cicd-dev-fn"
      fn_alias_name    = "live"
    }
    error_message = "application must publish the cluster, service, task family, function and alias names (design 8.3)"
  }

  assert {
    condition = module.ssm_publish.names == {
      cluster_name     = "/cicd/dev/application/cluster_name"
      api_service_name = "/cicd/dev/application/api_service_name"
      api_task_family  = "/cicd/dev/application/api_task_family"
      fn_function_name = "/cicd/dev/application/fn_function_name"
      fn_alias_name    = "/cicd/dev/application/fn_alias_name"
    }
    error_message = "ssm-publish must write the keys under the application path"
  }
}

run "latest_bootstrap_tag_rejected" {
  command = plan

  variables {
    api_bootstrap_image_tag = "latest"
  }

  expect_failures = [var.api_bootstrap_image_tag]
}

run "latest_fn_bootstrap_tag_rejected" {
  command = plan

  variables {
    fn_bootstrap_image_tag = "latest"
  }

  expect_failures = [var.fn_bootstrap_image_tag]
}

run "zero_tasks_rejected" {
  command = plan

  variables {
    api_desired_count = 0
  }

  expect_failures = [var.api_desired_count]
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "cicd-dev" && local.ssm_prefix == "/cicd/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Cicd"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "cicd-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
