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
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
  values = { insecure_value = "{}" }
}


override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/models"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/bedrock_invoke"]
  values = { insecure_value = "{\"enabled\":false}" }
}

# The Runtime "assistant" and the service roles; read only by the runs that publish them.
override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
  values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[\"chat\"],\"memories\":[\"conversation\"],\"guardrails\":[\"safety\",\"english\"],\"knowledge_bases\":[\"products\"],\"gateway\":true,\"tracing\":true}" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agent_assistant_execution_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_bedrock_kb_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agentcore_gateway_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/data_access"]
  values = { insecure_value = "{\"db\":[\"api\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = {
    insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"has_reader\":false,\"cluster_arn\":\"arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db\",\"data_api\":true}"
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
        agent_runtimes     = "containerimage/agent_runtimes"
        agent_data_access  = "network/agent_data_access"
        models             = "agent/models"
        guardrails         = "agent/guardrails"
        agent_memories     = "agent/agent_memories"
        knowledge_bases    = "agent/knowledge_bases"
        agentcore_gateway  = "agent/agentcore_gateway"
        bedrock_invoke     = "agent/bedrock_invoke"
      } &&
      local.ssm_input_lists == { services = "containerimage/services" }
    )
    error_message = "iam-app must read the key, the data access list, the Proxy role, the database, the service list and the agent keys"
  }

  assert {
    condition     = local.ssm_agent_strings == {}
    error_message = "With an empty agent stack the second read must be empty"
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
      agent_access         = "/alpha/dev/iam-app/agent_access"
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
    agent_access      = { api = { runtimes = ["assistant"], models = ["chat"], guardrails = ["safety"], knowledge_bases = ["products"] } }
  }

  # A second Runtime without tracing: xray:PutSpans must stay limited to the traced one.
  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\",\"order-bot\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_order_bot"]
    values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_order_bot-AbCdEfGhIj\",\"id\":\"alpha_dev_order_bot-AbCdEfGhIj\",\"name\":\"alpha_dev_order_bot\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-order-bot\",\"models\":[\"chat\"],\"memories\":[],\"guardrails\":[],\"knowledge_bases\":[],\"gateway\":false,\"tracing\":false}" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agent_order_bot_execution_arn"]
    values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agent-order-bot" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = length(local.agent_runtime_policies) == 2 && length(merge(local.bedrock_kb_policy, local.agentcore_gateway_policy)) == 2
    error_message = "The allow-list check must also walk the Runtime, knowledge base and gateway policies"
  }

  assert {
    condition = alltrue(flatten([
      for p in concat(
        values(local.proxy_secret_access.policies),
        flatten([for s in values(local.task_policies) : values(s)]),
        flatten([for x in values(merge(local.bedrock_kb_policy, local.agentcore_gateway_policy)) : values(x.policies)]),
        ) : [
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

  # xray:PutSpans is an addition only for a Runtime with tracing. cloudwatch:PutMetricData has no resource-level
  # permissions, so it is added with Resource * and must be limited to the bedrock-agentcore namespace instead.
  assert {
    condition = alltrue(flatten([
      for r, x in local.agent_runtime_policies : [
        for p in values(x.policies) : [
          for s in jsondecode(p).Statement : [
            for a in flatten([s.Action]) : contains(concat([
              "ecr:GetAuthorizationToken",
              "xray:PutTraceSegments",
              "xray:PutTelemetryRecords",
              ], local.runtime_grants[r].tracing ? ["xray:PutSpans"] : []), a) || (
              a == "cloudwatch:PutMetricData" && try(s.Condition.StringEquals["cloudwatch:namespace"], null) == "bedrock-agentcore"
            )
          ] if contains(flatten([s.Resource]), "*")
        ]
      ]
    ]))
    error_message = "A Runtime execution role may use Resource * only for the X-Ray actions (xray:PutSpans only with tracing) and for cloudwatch:PutMetricData in the bedrock-agentcore namespace"
  }

  assert {
    condition     = alltrue([for x in values(local.agent_runtime_policies) : strcontains(x.policies["agent"], "cloudwatch:PutMetricData")])
    error_message = "Every Runtime execution role must be able to publish AgentCore metrics"
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
    condition     = toset(keys(local.published_strings)) == toset(["role_order_api_task_arn", "ecs_exec_order_api", "tracing", "agent_access"])
    error_message = "A hyphen in the service name must become an underscore in the SSM keys"
  }
}

# ---- AgentCore and Bedrock permissions (second step after the agent stack) ----

run "agent_default_no_change" {
  command = plan

  assert {
    condition     = length(module.agent_runtime_policy) == 0 && length(module.agent_service_policy) == 0 && length(module.in_agents.strings) == 0
    error_message = "With an empty agent stack no AgentCore or Bedrock policy may be attached and nothing may be read"
  }

  assert {
    condition     = toset(keys(local.task_policies["api"])) == toset(["read-db-secret"]) && length(local.task_policies["worker"]) == 0
    error_message = "With agent_access empty the task role policies must be exactly what they were before the agent stack"
  }

  assert {
    condition     = local.published_strings["agent_access"] == "{}"
    error_message = "agent_access must be published as {} by default"
  }
}

run "runtime_execution_permissions_exact" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = local.agent_runtime_policies["assistant"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant"
    error_message = "The Runtime permissions must be attached to the execution role published by iam-base"
  }

  assert {
    condition = jsonencode(jsondecode(local.agent_runtime_policies["assistant"].policies["agent"]).Statement) == jsonencode([
      {
        Sid    = "InvokeModels"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
        ]
      },
      {
        Sid    = "ApplyGuardrails"
        Effect = "Allow"
        Action = ["bedrock:ApplyGuardrail"]
        Resource = [
          "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234",
          "arn:aws:bedrock:*:111111111111:guardrail-profile/apac.guardrail.v1:0",
          "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678",
        ]
      },
      {
        Sid      = "UseMemories"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:GetEvent", "bedrock-agentcore:RetrieveMemoryRecords"]
        Resource = ["arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj"]
      },
      {
        Sid      = "QueryKnowledgeBases"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = ["arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"]
      },
      {
        Sid      = "InvokeGateway"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeGateway"]
        Resource = ["arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij"]
      },
      {
        Sid      = "ReadDatabaseMasterSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"
      },
      {
        Sid       = "DecryptMasterSecret"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = "arn:aws:kms:ap-northeast-1:111111111111:key/0000"
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.ap-northeast-1.amazonaws.com" } }
      },
      {
        Sid      = "XRayTraces"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:PutSpans"]
        Resource = "*"
      },
      {
        Sid       = "PutAgentCoreMetrics"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" } }
      },
    ])
    error_message = "Every Runtime permission must point at the exact ARNs the agent stack published; * only in the region of the foundation model and guardrail profile ARNs, for X-Ray, and for metrics in the bedrock-agentcore namespace; no workload access token without workload_identity"
  }
}

run "workload_identity_grants_access_token" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
    values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[],\"memories\":[],\"guardrails\":[],\"knowledge_bases\":[],\"gateway\":false,\"tracing\":false,\"workload_identity\":true}" }
  }

  assert {
    condition = [for s in jsondecode(local.agent_runtime_policies["assistant"].policies["agent"]).Statement : s if strcontains(jsonencode(s.Action), "GetWorkloadAccessToken")] == [{
      Sid    = "GetWorkloadAccessTokens"
      Effect = "Allow"
      Action = [
        "bedrock-agentcore:GetWorkloadAccessToken",
        "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
        "bedrock-agentcore:GetWorkloadAccessTokenForUserId",
      ]
      Resource = [
        "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:workload-identity-directory/default",
        "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:workload-identity-directory/default/workload-identity/*",
      ]
    }]
    error_message = "A Runtime with workload_identity must get exactly the three workload access token actions on the default directory of this account and region"
  }
}

run "workload_identity_false_grants_no_access_token" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
    values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[],\"memories\":[],\"guardrails\":[],\"knowledge_bases\":[],\"gateway\":false,\"tracing\":false,\"workload_identity\":false}" }
  }

  assert {
    condition     = !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "GetWorkloadAccessToken") && !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "workload-identity")
    error_message = "A Runtime with workload_identity = false must not get any workload access token action"
  }
}

run "guardrail_profile_region_star" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition = (
      contains(flatten([for s in jsondecode(local.agent_runtime_policies["assistant"].policies["agent"]).Statement : flatten([s.Resource]) if contains(s.Action, "bedrock:ApplyGuardrail")]), "arn:aws:bedrock:*:111111111111:guardrail-profile/apac.guardrail.v1:0") &&
      !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "guardrail-profile/*")
    )
    error_message = "A STANDARD guardrail needs its profile in any region, with the exact profile id"
  }

  assert {
    condition     = length(regexall("guardrail-profile", local.agent_runtime_policies["assistant"].policies["agent"])) == 1
    error_message = "The CLASSIC guardrail must not add a profile ARN"
  }
}

run "runtime_without_permissions_gets_only_metrics" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
    values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[],\"memories\":[],\"guardrails\":[],\"knowledge_bases\":[],\"gateway\":false,\"tracing\":false}" }
  }

  # Every Runtime publishes AgentCore metrics, so even a Runtime that may use nothing else gets that one statement.
  assert {
    condition     = [for s in jsondecode(local.agent_runtime_policies["assistant"].policies["agent"]).Statement : s.Sid] == ["PutAgentCoreMetrics"]
    error_message = "A Runtime that may use nothing else must get only the AgentCore metrics statement"
  }
}

run "untraced_runtime_has_no_xray" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }


  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
    values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[\"chat\"],\"memories\":[\"conversation\"],\"guardrails\":[\"safety\",\"english\"],\"knowledge_bases\":[\"products\"],\"gateway\":true,\"tracing\":false}" }
  }

  assert {
    condition     = !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "xray:")
    error_message = "A Runtime without tracing must not get any X-Ray action"
  }

  assert {
    condition     = !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "secretsmanager:")
    error_message = "A Runtime that is not in agent_data_access must not read the database secret"
  }
}

run "cross_account_assumes_role_instead_of_invoking" {
  command = plan

  variables {
    agent_access = { api = { models = ["chat"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/bedrock_invoke"]
    values = { insecure_value = "{\"enabled\":true,\"role_arn\":\"arn:aws:iam::333333333333:role/bedrock-invoke\",\"session_seconds\":3600}" }
  }

  assert {
    condition = (
      [for s in jsondecode(local.agent_runtime_policies["assistant"].policies["agent"]).Statement : s.Resource if contains(s.Action, "sts:AssumeRole")] == [["arn:aws:iam::333333333333:role/bedrock-invoke"]] &&
      !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "bedrock:InvokeModel")
    )
    error_message = "With bedrock_invoke a Runtime must assume exactly the role in account B and must not invoke models itself"
  }

  assert {
    condition     = strcontains(local.task_policies["api"]["agent"], "sts:AssumeRole") && !strcontains(local.task_policies["api"]["agent"], "bedrock:InvokeModel")
    error_message = "With bedrock_invoke a service must assume the role too"
  }
}

run "same_account_invokes_models" {
  command = plan

  variables {
    agent_access = { api = { models = ["chat"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = !strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "sts:AssumeRole") && strcontains(local.agent_runtime_policies["assistant"].policies["agent"], "bedrock:InvokeModel")
    error_message = "Without bedrock_invoke there must be no sts:AssumeRole and the model is invoked directly"
  }
}

run "kb_role_does_not_read_master_secret" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = local.bedrock_kb_policy["bedrock_kb"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb"
    error_message = "The knowledge base permissions must be attached to the role published by iam-base"
  }

  assert {
    condition = [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s.Resource if contains(s.Action, "secretsmanager:GetSecretValue")] == [[
      "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf",
      "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf",
    ]]
    error_message = "The knowledge base role must read exactly the dedicated secret of each knowledge base"
  }

  assert {
    condition     = !strcontains(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"], "rds!cluster-0000")
    error_message = "The knowledge base role must never read the master secret of the database"
  }

  assert {
    condition = [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s if contains(s.Action, "kms:Decrypt")] == [{
      Sid      = "DecryptKnowledgeBaseUserSecrets"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = "arn:aws:kms:ap-northeast-1:111111111111:key/0000"
      Condition = { StringEquals = {
        "kms:ViaService" = "secretsmanager.ap-northeast-1.amazonaws.com"
        "kms:EncryptionContext:SecretARN" = [
          "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf",
          "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf",
        ]
      } }
    }]
    error_message = "kms:Decrypt must be limited to the project key, to calls through Secrets Manager, and to the dedicated secret of each knowledge base"
  }

  assert {
    condition = (
      [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s.Resource if contains(s.Action, "rds-data:ExecuteStatement")] == [["arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"]] &&
      [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s.Resource if contains(s.Action, "rds:DescribeDBClusters")] == [["arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"]] &&
      [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s.Resource if contains(s.Action, "bedrock:InvokeModel")] == [["arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0"]]
    )
    error_message = "The Data API, the cluster description and the embedding model must point at exactly the database cluster and the embedding model"
  }
}

run "kb_role_reads_only_own_corpus_bucket" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition = jsonencode([for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s if contains(s.Action, "s3:ListBucket")]) == jsonencode([
      { Action = ["s3:ListBucket"], Condition = { StringEquals = { "aws:ResourceAccount" = "111111111111" } }, Effect = "Allow", Resource = ["arn:aws:s3:::alpha-dev-kb-policies-111111111111"] },
      { Action = ["s3:ListBucket"], Condition = { StringEquals = { "aws:ResourceAccount" = "111111111111" }, StringLike = { "s3:prefix" = ["faq/*", "manuals/*"] } }, Effect = "Allow", Resource = ["arn:aws:s3:::alpha-dev-kb-products-111111111111"] },
    ])
    error_message = "Listing must be limited to the corpus bucket of each knowledge base in this account, and to its prefixes when every data source has one"
  }

  assert {
    condition = [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : try(s.Condition, null) if contains(s.Action, "s3:GetObject")] == [
      { StringEquals = { "aws:ResourceAccount" = "111111111111" } },
      { StringEquals = { "aws:ResourceAccount" = "111111111111" } },
    ]
    error_message = "Reading corpus objects must be limited to buckets in this account"
  }

  assert {
    condition = [for s in jsondecode(local.bedrock_kb_policy["bedrock_kb"].policies["knowledge-bases"]).Statement : s.Resource if contains(s.Action, "s3:GetObject")] == [
      ["arn:aws:s3:::alpha-dev-kb-policies-111111111111/*"],
      ["arn:aws:s3:::alpha-dev-kb-products-111111111111/faq/*", "arn:aws:s3:::alpha-dev-kb-products-111111111111/manuals/*"],
    ]
    error_message = "Reading objects must be limited to the corpus bucket of each knowledge base and its prefixes"
  }
}

run "gateway_role_invokes_lambda_targets" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"],\"tool_schema_arns\":[\"arn:aws:s3:::alpha-dev-tools/order-lookup.json\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition = local.agentcore_gateway_policy["agentcore_gateway"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway" && jsondecode(local.agentcore_gateway_policy["agentcore_gateway"].policies["lambda-targets"]).Statement == [{
      Sid      = "InvokeLambdaTargets"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = ["arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup", "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup:*"]
      }, {
      Sid       = "ReadToolSchemas"
      Effect    = "Allow"
      Action    = ["s3:GetObject"]
      Resource  = ["arn:aws:s3:::alpha-dev-tools/order-lookup.json"]
      Condition = { StringEquals = { "aws:ResourceAccount" = "111111111111" } }
    }]
    error_message = "The gateway role must invoke exactly the Lambda targets, with their versions and aliases, and read exactly their tool schema objects in this account"
  }
}

run "kb_secret_wildcard_from_ssm_rejected" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:*\"}}" }
  }

  expect_failures = [terraform_data.knowledge_base_secrets_are_exact]
}

run "gateway_without_lambda_gets_no_policy" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[]}" }
  }
  assert {
    condition     = length(local.agentcore_gateway_policy) == 0 && !contains(keys(local.ssm_agent_strings), "role_agentcore_gateway_arn")
    error_message = "Without a Lambda target the gateway role needs no policy"
  }
}

run "service_agent_permissions" {
  command = plan

  variables {
    agent_access = { api = { runtimes = ["assistant"], models = ["chat"], guardrails = ["safety"], knowledge_bases = ["products"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition = jsonencode(jsondecode(local.task_policies["api"]["agent"]).Statement) == jsonencode([
      {
        Sid      = "InvokeAgentRuntimes"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
        Resource = ["arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj", "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj/runtime-endpoint/*"]
      },
      {
        Sid    = "InvokeModels"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
        ]
      },
      {
        Sid      = "ApplyGuardrails"
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = ["arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234", "arn:aws:bedrock:*:111111111111:guardrail-profile/apac.guardrail.v1:0"]
      },
      {
        Sid      = "QueryKnowledgeBases"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = ["arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"]
      },
    ])
    error_message = "A listed service must get exactly the Runtime, model, guardrail and knowledge base ARNs it names"
  }

  assert {
    condition     = !strcontains(jsonencode(local.task_policies["worker"]), "bedrock")
    error_message = "A service that is not in agent_access must get no bedrock or bedrock-agentcore action"
  }

  assert {
    condition     = jsondecode(local.published_strings["agent_access"]) == { api = { runtimes = ["assistant"], models = ["chat"], guardrails = ["safety"], knowledge_bases = ["products"] } }
    error_message = "agent_access must be published as it is for application"
  }
}

run "agent_access_unknown_service_rejected" {
  command = plan

  variables {
    agent_access = { ghost = { runtimes = ["assistant"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  expect_failures = [terraform_data.agent_access_is_known]
}

run "agent_access_unknown_runtime_rejected" {
  command = plan

  variables {
    agent_access = { api = { runtimes = ["ghost"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  expect_failures = [terraform_data.agent_access_is_known]
}

run "agent_access_unknown_model_rejected" {
  command = plan

  variables {
    agent_access = { api = { models = ["ghost"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  expect_failures = [terraform_data.agent_access_is_known]
}

run "agent_access_known_passes" {
  command = plan

  variables {
    agent_access = { api = { runtimes = ["assistant"], knowledge_bases = ["policies"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/models"]
    values = { insecure_value = "{\"chat\":{\"model_id\":\"apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"invoke_arns\":[\"arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0\",\"arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0\"]},\"embedding\":{\"model_id\":\"amazon.titan-embed-text-v2:0\",\"invoke_arns\":[\"arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0\"]}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
    values = { insecure_value = "{\"safety\":{\"id\":\"abcdefgh1234\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234\",\"version\":\"DRAFT\",\"profile_id\":\"apac.guardrail.v1:0\"},\"english\":{\"id\":\"ijklmnop5678\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678\",\"version\":\"DRAFT\",\"profile_id\":null}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
    values = { insecure_value = "{\"conversation\":{\"id\":\"alpha_dev_conversation-AbCdEfGhIj\",\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
    values = { insecure_value = "{\"products\":{\"id\":\"KBID000001\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-products-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-products-111111111111\",\"inclusion_prefixes\":{\"manuals\":[\"manuals/\"],\"faq\":[\"faq/\"]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf\"},\"policies\":{\"id\":\"KBID000002\",\"arn\":\"arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000002\",\"embedding_model\":\"embedding\",\"bucket_name\":\"alpha-dev-kb-policies-111111111111\",\"bucket_arn\":\"arn:aws:s3:::alpha-dev-kb-policies-111111111111\",\"inclusion_prefixes\":{\"all\":[]},\"credentials_secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf\"}}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij\",\"url\":\"https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp\",\"lambda_arns\":[\"arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = contains(keys(local.task_policies["api"]), "agent")
    error_message = "Names published by the agent stack must pass"
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
