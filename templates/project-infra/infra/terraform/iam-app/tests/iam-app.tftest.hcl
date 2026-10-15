mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_rds_proxy_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/data_access"]
  values = { insecure_value = "{\"db\":[\"api\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = {
    insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"has_reader\":false}"
  }
}

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == {
        kms_key_arn        = "foundation/kms_key_arn"
        data_access        = "network/data_access"
        role_rds_proxy_arn = "iam-base/role_rds_proxy_arn"
        database           = "data/database"
      } &&
      local.ssm_input_lists == { services = "containerimage/services" }
    )
    error_message = "iam-app must read the key, the data access list, the Proxy role, the database and the service list"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      role_api_task_arn    = "/alpha/dev/iam-app/role_api_task_arn"
      role_worker_task_arn = "/alpha/dev/iam-app/role_worker_task_arn"
      ecs_exec_api         = "/alpha/dev/iam-app/ecs_exec_api"
      ecs_exec_worker      = "/alpha/dev/iam-app/ecs_exec_worker"
      tracing              = "/alpha/dev/iam-app/tracing"
    }
    error_message = "ssm-publish must write a task role ARN and an ECS Exec flag per service, and the tracing list, under the iam-app path"
  }
}

run "proxy_policy_resource_is_secret" {
  command = plan

  assert {
    condition     = length(module.proxy_secret_access) == 1 && local.proxy_secret_access.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy"
    error_message = "The policy must be attached to the Proxy role created by iam-base"
  }

  assert {
    condition = [
      for s in jsondecode(local.proxy_secret_access.policies["read-master-secret"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "secretsmanager:GetSecretValue")
    ] == [["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"]]
    error_message = "The Proxy role must read exactly the master secret of the database"
  }

  assert {
    condition     = keys(local.proxy_secret_access.policies) == ["read-master-secret"]
    error_message = "The Proxy role must get one policy and nothing more"
  }
}

run "proxy_kms_via_service" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(local.proxy_secret_access.policies["read-master-secret"]).Statement : s
      if contains(flatten([s.Action]), "kms:Decrypt")
      ] == [{
        Sid       = "DecryptMasterSecret"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = "arn:aws:kms:ap-northeast-1:111111111111:key/0000"
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.ap-northeast-1.amazonaws.com" } }
    }]
    error_message = "kms:Decrypt must be limited to the project key and to calls through Secrets Manager"
  }
}

# This stack does not read db_proxy at all, so the policy cannot depend on whether a Proxy is in use.
run "proxy_policy_even_when_proxy_off" {
  command = plan

  assert {
    condition     = !contains(values(local.ssm_input_strings), "network/db_proxy") && length(module.proxy_secret_access) == 1
    error_message = "The Proxy policy must be attached whenever the database exists, so enabling the Proxy later needs no apply of iam-app"
  }
}

run "no_db_no_db_permissions" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition     = length(module.proxy_secret_access) == 0
    error_message = "Without a database no policy may be attached to the Proxy role"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies), "secretsmanager:")
    error_message = "Without a database no task role may get a Secrets Manager permission"
  }
}

run "task_role_per_service" {
  command = plan

  assert {
    condition     = length(module.task_role) == 2 && module.task_role["api"].name == "alpha-dev-api-task" && module.task_role["worker"].name == "alpha-dev-worker-task"
    error_message = "iam-role must be called once per service"
  }

  assert {
    condition     = local.task_trust == { service_principals = ["ecs-tasks.amazonaws.com"], source_account = "111111111111" }
    error_message = "Task roles must trust only ECS tasks of this account"
  }
}

run "data_access_services_read_db_secret" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(local.task_policies["api"]["read-db-secret"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "secretsmanager:GetSecretValue")
    ] == [["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"]]
    error_message = "A service on the data_access list must read exactly the database secret"
  }
}

run "others_cannot_read_db_secret" {
  command = plan

  assert {
    condition     = length(local.task_policies["worker"]) == 0
    error_message = "A service that is not on the data_access list must have no permission at all by default"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies["worker"]), "secretsmanager:")
    error_message = "A service that is not on the data_access list must not read any secret"
  }
}

run "no_execution_role_changes" {
  command = plan

  assert {
    condition     = !contains(values(local.ssm_input_strings), "iam-base/role_ecs_execution_arn") && toset(keys(module.proxy_secret_access)) == toset(["proxy"])
    error_message = "The database secret is read by task roles; this stack must not touch the shared execution role"
  }
}

run "exec_permissions_and_flag" {
  command = plan

  variables {
    ecs_exec_services = ["api"]
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.task_policies["api"]["ecs-exec"]).Statement : s.Action
    ])) == toset(["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"])
    error_message = "ECS Exec needs the four ssmmessages actions"
  }

  assert {
    condition     = !contains(keys(local.task_policies["worker"]), "ecs-exec")
    error_message = "A service that is not listed must not get the ECS Exec permissions"
  }

  assert {
    condition     = local.published_strings["ecs_exec_api"] == "{\"enabled\":true}" && local.published_strings["ecs_exec_worker"] == "{\"enabled\":false}"
    error_message = "The published flags must agree with the permissions"
  }
}

run "exec_off_by_default" {
  command = plan

  assert {
    condition     = local.published_strings["ecs_exec_api"] == "{\"enabled\":false}" && local.published_strings["ecs_exec_worker"] == "{\"enabled\":false}"
    error_message = "ECS Exec must be off for every service by default"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies), "ssmmessages:")
    error_message = "Without ecs_exec_services no task role may get ssmmessages permissions"
  }
}

run "ecs_exec_services_must_be_known" {
  command = plan

  variables {
    ecs_exec_services = ["ghost"]
  }

  expect_failures = [terraform_data.ecs_exec_services_are_known]
}

run "ecs_exec_known_service_passes" {
  command = plan

  variables {
    ecs_exec_services = ["api", "worker"]
  }

  assert {
    condition     = toset(var.ecs_exec_services) == toset(["api", "worker"])
    error_message = "Known services must pass the precondition"
  }
}

run "tracing_off_by_default" {
  command = plan

  assert {
    condition     = local.published_strings["tracing"] == "[]"
    error_message = "Tracing must be off for every service by default and published as an empty JSON array"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies), "xray:")
    error_message = "Without tracing no task role may get an X-Ray permission"
  }
}

run "tracing_permissions_and_flag" {
  command = plan

  variables {
    tracing = ["api"]
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.task_policies["api"]["tracing"]).Statement : s.Action
    ])) == toset(["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"])
    error_message = "A traced service must get exactly the four X-Ray actions"
  }

  assert {
    condition     = alltrue([for s in jsondecode(local.task_policies["api"]["tracing"]).Statement : s.Effect == "Allow" && s.Resource == "*"])
    error_message = "The X-Ray actions only support Resource *"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies["worker"]), "xray:") && !contains(keys(local.task_policies["worker"]), "tracing")
    error_message = "A service that is not traced must not get any X-Ray action"
  }

  assert {
    condition     = local.published_strings["tracing"] == "[\"api\"]"
    error_message = "The published tracing list must name the traced services"
  }
}

run "tracing_list_is_published_sorted" {
  command = plan

  variables {
    tracing = ["worker", "api"]
  }

  assert {
    condition     = local.published_strings["tracing"] == "[\"api\",\"worker\"]"
    error_message = "The tracing list must be published as a sorted JSON array so the value does not depend on input order"
  }
}

run "tracing_must_be_known_services" {
  command = plan

  variables {
    tracing = ["ghost"]
  }

  expect_failures = [terraform_data.tracing_services_are_known]
}

run "tracing_known_services_pass" {
  command = plan

  variables {
    tracing = ["api", "worker"]
  }

  assert {
    condition     = alltrue([for s in ["api", "worker"] : contains(keys(local.task_policies[s]), "tracing")])
    error_message = "Known services must pass the precondition and each get the tracing policy"
  }
}

# Terraform cannot list the resources of a policy by type, so walk every statement of every role and policy.
run "wildcard_resource_allowlist" {
  command = plan

  variables {
    ecs_exec_services = ["api", "worker"]
    tracing           = ["api", "worker"]
  }

  assert {
    condition = alltrue(flatten([
      for p in concat(values(local.proxy_secret_access.policies), flatten([for s in values(local.task_policies) : values(s)])) : [
        for s in jsondecode(p).Statement : [
          for a in flatten([s.Action]) : contains([
            "ecr:GetAuthorizationToken",
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
            "xray:PutTraceSegments",
            "xray:PutTelemetryRecords",
            "xray:GetSamplingRules",
            "xray:GetSamplingTargets",
          ], a)
        ] if contains(flatten([s.Resource]), "*")
      ]
    ]))
    error_message = "Only actions that do not support resource-level permissions may use Resource *"
  }
}

run "publishes_task_role_arns" {
  command = plan

  override_module {
    target = module.task_role["api"]
    outputs = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-api-task"
    }
  }

  override_module {
    target = module.task_role["worker"]
    outputs = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-worker-task"
    }
  }

  assert {
    condition = (
      local.published_strings["role_api_task_arn"] == "arn:aws:iam::111111111111:role/alpha-dev-api-task" &&
      local.published_strings["role_worker_task_arn"] == "arn:aws:iam::111111111111:role/alpha-dev-worker-task"
    )
    error_message = "Each published ARN must come from the task role of its service"
  }
}

run "keys_follow_the_service_list" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "order-api" }
  }

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["role_order_api_task_arn", "ecs_exec_order_api", "tracing"])
    error_message = "A hyphen in the service name must become an underscore in the SSM keys"
  }
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
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
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
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
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
