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
  target = module.in.data.aws_ssm_parameter.this["foundation/app_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/mirrored_images"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_api_arn"]
  values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_worker_arn"]
  values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-worker" }
}

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == { kms_key_arn = "foundation/kms_key_arn", app_secret_arn = "foundation/app_secret_arn", mirrored_images = "containerimage/mirrored_images", agent_runtimes = "containerimage/agent_runtimes" } &&
      local.ssm_input_lists == { services = "containerimage/services" }
    )
    error_message = "iam-base must read the project key, the app secret, the mirror list, the Runtime list and the service list"
  }

  assert {
    condition     = local.ssm_service_strings == { ecr_api_arn = "containerimage/ecr_api_arn", ecr_worker_arn = "containerimage/ecr_worker_arn" }
    error_message = "iam-base must read one repository ARN per service and nothing else"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      role_ecs_execution_arn  = "/alpha/dev/iam-base/role_ecs_execution_arn"
      role_rds_proxy_arn      = "/alpha/dev/iam-base/role_rds_proxy_arn"
      role_rds_monitoring_arn = "/alpha/dev/iam-base/role_rds_monitoring_arn"
      agent_service_roles     = "/alpha/dev/iam-base/agent_service_roles"
    }
    error_message = "ssm-publish must write the three role ARNs and the service role list under the iam-base path"
  }
}

run "three_roles" {
  command = plan

  assert {
    condition     = length(module.role) == 3 && toset(keys(module.role)) == toset(["ecs_execution", "rds_proxy", "rds_monitoring"])
    error_message = "iam-role must be called for the execution, Proxy and monitoring roles"
  }

  assert {
    condition     = module.role["ecs_execution"].name == "alpha-dev-ecs-execution" && module.role["rds_proxy"].name == "alpha-dev-rds-proxy" && module.role["rds_monitoring"].name == "alpha-dev-rds-monitoring"
    error_message = "Role names must be <name_prefix>-<role>"
  }
}

run "trust_principals" {
  command = plan

  assert {
    condition = (
      local.roles["ecs_execution"].trust.service_principals == ["ecs-tasks.amazonaws.com"] &&
      local.roles["rds_proxy"].trust.service_principals == ["rds.amazonaws.com"] &&
      local.roles["rds_monitoring"].trust.service_principals == ["monitoring.rds.amazonaws.com"]
    )
    error_message = "Each role must trust only its own service"
  }

  assert {
    condition     = alltrue([for r in values(local.roles) : r.trust.source_account == "111111111111"])
    error_message = "Every trust policy must be limited to this account with aws:SourceAccount"
  }
}

run "proxy_role_trust_only" {
  command = plan

  assert {
    condition     = length(local.roles["rds_proxy"].policies) == 0
    error_message = "The Proxy role must have no policy here; iam-app attaches the secret policy once the secret exists"
  }
}

run "ecr_pull_only_from_published_repos" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "ecr:BatchGetImage")
      ] == [[
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api",
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-worker",
    ]]
    error_message = "Image pulls must be limited to the repositories published by containerimage"
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : s.Action
      if contains(flatten([s.Action]), "ecr:BatchGetImage")
    ])) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"])
    error_message = "The pull statement must grant the three image download actions and nothing else"
  }

  assert {
    condition     = local.ssm_mirror_strings == {} && length(module.in_mirrors.strings) == 0
    error_message = "Without mirrors iam-base must read no mirror repository ARN"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : !contains(flatten([s.Resource]), "*")
      if contains(flatten([s.Action]), "ecr:BatchGetImage")
    ])
    error_message = "The pull statement must never use a wildcard Resource"
  }
}

run "ecr_pull_includes_mirror_repositories" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/mirrored_images"]
    values = { insecure_value = "[\"adot-collector\",\"other-image\"]" }
  }

  override_data {
    target = module.in_mirrors.data.aws_ssm_parameter.this["containerimage/ecr_mirror_adot_collector_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-adot-collector" }
  }

  override_data {
    target = module.in_mirrors.data.aws_ssm_parameter.this["containerimage/ecr_mirror_other_image_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-other-image" }
  }

  assert {
    condition = local.ssm_mirror_strings == {
      ecr_mirror_adot_collector_arn = "containerimage/ecr_mirror_adot_collector_arn"
      ecr_mirror_other_image_arn    = "containerimage/ecr_mirror_other_image_arn"
    }
    error_message = "iam-base must read one ARN per mirror, with hyphens turned into underscores in the key"
  }

  assert {
    condition = [
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "ecr:BatchGetImage")
      ] == [[
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api",
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-worker",
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-adot-collector",
        "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-mirror-other-image",
    ]]
    error_message = "Image pulls must cover the service repositories and exactly the mirror repositories"
  }
}

run "ecr_arns_follow_the_service_list" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "order-api" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_order_api_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-order-api" }
  }

  assert {
    condition     = local.ssm_service_strings == { ecr_order_api_arn = "containerimage/ecr_order_api_arn" }
    error_message = "A hyphen in the service name must become an underscore in the SSM key"
  }

  assert {
    condition     = local.ecr_repository_arns == ["arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-order-api"]
    error_message = "The execution role must follow the published service list"
  }
}

run "execution_logs_scoped_by_name" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "logs:PutLogEvents")
    ] == [["arn:aws:logs:ap-northeast-1:111111111111:log-group:/ecs/alpha-dev-*:*"]]
    error_message = "Log writes must be limited to the /ecs/<name_prefix>-* log groups of this account and region"
  }
}

run "execution_reads_app_secret_only" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "secretsmanager:GetSecretValue")
    ] == [["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"]]
    error_message = "The execution role must read exactly the application secret"
  }

  assert {
    condition = [
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "kms:Decrypt")
    ] == [["arn:aws:kms:ap-northeast-1:111111111111:key/0000"]]
    error_message = "kms:Decrypt must be limited to the project key"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(local.roles["ecs_execution"].policies["pull-and-log"]).Statement :
      !strcontains(jsonencode(s.Resource), "rds!") && !strcontains(jsonencode(s.Resource), "secret:rds")
    ])
    error_message = "The execution role is shared by every service and must have no permission on the database secret"
  }
}

run "monitoring_scoped_to_rdsosmetrics" {
  command = plan

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.roles["rds_monitoring"].policies["RDSOSMetrics"]).Statement : s.Action
    ])) == toset(["logs:CreateLogGroup", "logs:PutRetentionPolicy", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:GetLogEvents"])
    error_message = "Enhanced Monitoring needs exactly these six logs actions"
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.roles["rds_monitoring"].policies["RDSOSMetrics"]).Statement : s.Resource
      ])) == toset([
      "arn:aws:logs:ap-northeast-1:111111111111:log-group:RDSOSMetrics:*",
      "arn:aws:logs:ap-northeast-1:111111111111:log-group:RDSOSMetrics:log-stream:*",
    ])
    error_message = "Resources must be the RDSOSMetrics log group and its log streams only"
  }
}

# Terraform cannot list the resources of a policy by type, so walk every statement of every role.
run "wildcard_resource_allowlist" {
  command = plan

  variables {
    agent_service_roles = ["knowledge_base", "gateway"]
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_assistant_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-agent-assistant" }
  }

  assert {
    condition     = length(local.agent_runtime_roles) == 1 && length(local.agent_service_roles) == 2
    error_message = "The allow-list check must also walk the Runtime and service roles"
  }

  assert {
    condition = alltrue(flatten([
      for r in values(merge(local.roles, local.agent_runtime_roles, local.agent_service_roles)) : [
        for p in values(r.policies) : [
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
      ]
    ]))
    error_message = "Only actions that do not support resource-level permissions may use Resource *"
  }
}

run "publishes_role_arns" {
  command = plan

  override_module {
    target = module.role["ecs_execution"]
    outputs = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
    }
  }

  override_module {
    target = module.role["rds_proxy"]
    outputs = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy"
    }
  }

  override_module {
    target = module.role["rds_monitoring"]
    outputs = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-rds-monitoring"
    }
  }

  assert {
    condition = local.published_strings == {
      role_ecs_execution_arn  = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
      role_rds_proxy_arn      = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy"
      role_rds_monitoring_arn = "arn:aws:iam::111111111111:role/alpha-dev-rds-monitoring"
      agent_service_roles     = "[]"
    }
    error_message = "Each published ARN must come from its role"
  }
}

# ---- AgentCore and Bedrock roles: trust and base permissions only ----

run "agent_roles_absent_by_default" {
  command = plan

  assert {
    condition     = length(module.agent_runtime_role) == 0 && length(module.agent_service_role) == 0
    error_message = "Without Runtimes and service roles no AgentCore or Bedrock role may exist"
  }

  assert {
    condition     = local.ssm_agent_strings == {} && length(module.in_agents.strings) == 0
    error_message = "Without Runtimes iam-base must read no Runtime repository ARN"
  }

  assert {
    condition     = local.published_strings["agent_service_roles"] == "[]" && !contains(keys(local.published_strings), "role_bedrock_kb_arn") && !contains(keys(local.published_strings), "role_agentcore_gateway_arn")
    error_message = "The service role list must be published as [] and the service role ARNs must be absent"
  }
}

run "agent_runtime_execution_role" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\",\"order-bot\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_assistant_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-agent-assistant" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_order_bot_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-agent-order-bot" }
  }

  assert {
    condition = local.ssm_agent_strings == {
      ecr_agent_assistant_arn = "containerimage/ecr_agent_assistant_arn"
      ecr_agent_order_bot_arn = "containerimage/ecr_agent_order_bot_arn"
    }
    error_message = "iam-base must read one repository ARN per Runtime, with hyphens turned into underscores"
  }

  assert {
    condition     = toset(keys(module.agent_runtime_role)) == toset(["agent_assistant_execution", "agent_order_bot_execution"]) && module.agent_runtime_role["agent_order_bot_execution"].name == "alpha-dev-agent-order-bot"
    error_message = "Each Runtime must get an execution role named <project>-<env>-agent-<name>"
  }

  assert {
    condition = alltrue([for r in values(local.agent_runtime_roles) :
      r.trust.service_principals == ["bedrock-agentcore.amazonaws.com"] && r.trust.source_account == "111111111111"
    ])
    error_message = "A Runtime execution role must trust only bedrock-agentcore.amazonaws.com, limited to this account"
  }

  assert {
    condition     = alltrue([for r in values(local.agent_runtime_roles) : r.trust.source_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:*"])
    error_message = "A Runtime execution role trust must also be limited with aws:SourceArn to AgentCore resources of this region and account"
  }

  assert {
    condition = [
      for s in jsondecode(local.agent_runtime_roles["agent_order_bot_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "ecr:BatchGetImage")
    ] == [["arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-agent-order-bot"]]
    error_message = "A Runtime may pull only from its own repository"
  }

  assert {
    condition = [
      for s in jsondecode(local.agent_runtime_roles["agent_order_bot_execution"].policies["pull-and-log"]).Statement : flatten([s.Resource])
      if contains(flatten([s.Action]), "logs:PutLogEvents") || contains(flatten([s.Action]), "logs:CreateLogGroup")
      ] == [
      ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/bedrock-agentcore/runtimes/alpha_dev_order_bot-*"],
      ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/bedrock-agentcore/runtimes/alpha_dev_order_bot-*:log-stream:*"],
    ]
    error_message = "Runtime logs must be limited to the log groups AgentCore names after this Runtime"
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(local.agent_runtime_roles["agent_assistant_execution"].policies["pull-and-log"]).Statement : s.Action
      ])) == toset([
      "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ecr:GetAuthorizationToken",
      "logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents",
    ])
    error_message = "The Runtime execution role gets only image pull and log permissions here; iam-app adds the rest"
  }

  assert {
    condition     = length(module.role) == 3
    error_message = "Adding a Runtime must not change the three base roles"
  }
}

run "agent_service_roles_trust_only" {
  command = plan

  variables {
    agent_service_roles = ["knowledge_base", "gateway"]
  }

  assert {
    condition     = module.agent_service_role["bedrock_kb"].name == "alpha-dev-bedrock-kb" && module.agent_service_role["agentcore_gateway"].name == "alpha-dev-agentcore-gateway"
    error_message = "The service roles must be named <project>-<env>-bedrock-kb and <project>-<env>-agentcore-gateway"
  }

  assert {
    condition = (
      local.agent_service_roles["bedrock_kb"].trust.service_principals == ["bedrock.amazonaws.com"] &&
      local.agent_service_roles["agentcore_gateway"].trust.service_principals == ["bedrock-agentcore.amazonaws.com"] &&
      alltrue([for r in values(local.agent_service_roles) : r.trust.source_account == "111111111111"])
    )
    error_message = "The knowledge base role must trust bedrock.amazonaws.com and the gateway role bedrock-agentcore.amazonaws.com, limited to this account"
  }

  assert {
    condition = (
      local.agent_service_roles["bedrock_kb"].trust.source_arn == "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*" &&
      local.agent_service_roles["agentcore_gateway"].trust.source_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:*"
    )
    error_message = "The knowledge base role must be limited with aws:SourceArn to knowledge bases, the gateway role to AgentCore resources, both in this region and account"
  }

  assert {
    condition     = alltrue([for r in values(local.agent_service_roles) : length(r.policies) == 0])
    error_message = "The service roles must have no policy here; iam-app attaches their permissions after the agent stack"
  }

  assert {
    condition     = local.published_strings["agent_service_roles"] == "[\"gateway\",\"knowledge_base\"]"
    error_message = "The service role list must be published as a sorted JSON array"
  }
}

run "agent_role_source_arn_follows_region" {
  command = plan

  variables {
    aws_region          = "us-west-2"
    agent_service_roles = ["knowledge_base", "gateway"]
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_assistant_arn"]
    values = { insecure_value = "arn:aws:ecr:us-west-2:111111111111:repository/alpha-dev-agent-assistant" }
  }

  assert {
    condition = (
      local.agent_runtime_roles["agent_assistant_execution"].trust.source_arn == "arn:aws:bedrock-agentcore:us-west-2:111111111111:*" &&
      local.agent_service_roles["bedrock_kb"].trust.source_arn == "arn:aws:bedrock:us-west-2:111111111111:knowledge-base/*" &&
      local.agent_service_roles["agentcore_gateway"].trust.source_arn == "arn:aws:bedrock-agentcore:us-west-2:111111111111:*"
    )
    error_message = "aws:SourceArn must be built from aws_region, not a fixed region"
  }

  assert {
    condition     = alltrue([for r in values(local.roles) : try(r.trust.source_arn, null) == null])
    error_message = "The three base roles must keep their trust unchanged, without aws:SourceArn"
  }
}

run "agent_service_role_only_listed" {
  command = plan

  variables {
    agent_service_roles = ["gateway"]
  }

  assert {
    condition     = keys(module.agent_service_role) == ["agentcore_gateway"]
    error_message = "Only the listed service roles may be created"
  }
}

run "agent_service_role_unknown_rejected" {
  command = plan

  variables {
    agent_service_roles = ["memory"]
  }

  expect_failures = [var.agent_service_roles]
}

run "publishes_agent_role_arns" {
  command = plan

  variables {
    agent_service_roles = ["knowledge_base", "gateway"]
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"order-bot\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_order_bot_arn"]
    values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-agent-order-bot" }
  }

  override_module {
    target  = module.agent_runtime_role["agent_order_bot_execution"]
    outputs = { arn = "arn:aws:iam::111111111111:role/alpha-dev-agent-order-bot" }
  }

  override_module {
    target  = module.agent_service_role["bedrock_kb"]
    outputs = { arn = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb" }
  }

  override_module {
    target  = module.agent_service_role["agentcore_gateway"]
    outputs = { arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway" }
  }

  assert {
    condition = (
      local.published_strings["role_agent_order_bot_execution_arn"] == "arn:aws:iam::111111111111:role/alpha-dev-agent-order-bot" &&
      local.published_strings["role_bedrock_kb_arn"] == "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb" &&
      local.published_strings["role_agentcore_gateway_arn"] == "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"
    )
    error_message = "role_agent_<runtime>_execution_arn, role_bedrock_kb_arn and role_agentcore_gateway_arn must come from their roles"
  }

  assert {
    condition     = contains(keys(module.ssm_publish.names), "role_agent_order_bot_execution_arn") && contains(keys(module.ssm_publish.names), "role_bedrock_kb_arn")
    error_message = "The Runtime and service role ARNs must be written under the iam-base path"
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
