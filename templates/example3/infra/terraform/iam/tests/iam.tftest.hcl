mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  eval_batch_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0"
}

override_module {
  target = module.in
  outputs = {
    strings = {
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      agent_runtimes                 = "[\"agent\"]"
      ecr_repository_arns = jsonencode({
        api            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api"
        worker         = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-worker"
        import-extract = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-import-extract"
        import-load    = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-import-load"
        agent          = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-agent"
      })
    }
    lists = {}
  }
}

override_data {
  target = data.aws_kms_alias.secretsmanager
  values = { target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" }
}

# ---- reads ----

run "reads_the_secrets_the_repositories_and_the_runtime_list" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      signing_private_key_secret_arn = "foundation/signing_private_key_secret_arn"
      signing_public_key_secret_arn  = "foundation/signing_public_key_secret_arn"
      agent_runtimes                 = "containerimage/agent_runtimes"
      ecr_repository_arns            = "containerimage/ecr_repository_arns"
      db_secret_arn                  = "database/db_secret_arn"
    }
    error_message = "iam must read the three secrets, the repository ARNs and the Runtime list"
  }
}

# ---- which roles exist ----

run "dev_has_seven_roles_including_eval_batch" {
  command = plan

  assert {
    condition     = toset(keys(local.roles)) == toset(["import_extract", "import_load", "agent_runtime", "eval_batch", "eks_cluster", "eks_node", "api_pod", "worker_pod", "lb_controller", "keda", "cloudwatch_agent"])
    error_message = "dev gets the three service roles (one per Lambda function and the Runtime), the eval-batch role and the seven EKS roles"
  }
}

run "sit_has_no_eval_batch_role" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = toset(keys(local.roles)) == toset(["import_extract", "import_load", "agent_runtime", "eks_cluster", "eks_node", "api_pod", "worker_pod", "lb_controller", "keda", "cloudwatch_agent"])
    error_message = "eval_batch exists only when env is dev"
  }

  assert {
    condition     = !contains(keys(module.role), "eval_batch")
    error_message = "No eval-batch role module instance outside dev"
  }
}

run "dev_needs_an_eval_batch_model" {
  command = plan

  variables {
    eval_batch_model_id = ""
  }

  expect_failures = [var.eval_batch_model_id]
}

run "sit_does_not_need_an_eval_batch_model" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
    eval_batch_model_id = ""
  }

  assert {
    condition     = length(module.role) == 10
    error_message = "Without eval_batch there is nothing to name a model for"
  }
}

run "role_names_follow_the_prefix" {
  command = plan

  assert {
    condition = { for k, r in local.roles : k => r.name } == {
      import_extract   = "example-dev-import-extract"
      import_load      = "example-dev-import-load"
      agent_runtime    = "example-dev-agent-runtime"
      eval_batch       = "example-dev-eval-batch"
      eks_cluster      = "example-dev-eks-cluster"
      eks_node         = "example-dev-eks-node"
      api_pod          = "example-dev-api-pod"
      worker_pod       = "example-dev-worker-pod"
      lb_controller    = "example-dev-lb-controller"
      keda             = "example-dev-keda"
      cloudwatch_agent = "example-dev-cloudwatch-agent"
    }
    error_message = "Roles are named <project>-<env>-<role>"
  }
}

# ---- trust ----

run "every_role_trusts_one_service_in_this_account_only" {
  command = plan

  assert {
    condition     = alltrue([for k, r in local.roles : r.trust.source_account == "111111111111" && length(r.trust.service_principals) == 1 if !contains(["eks_cluster", "eks_node"], k)])
    error_message = "Each role must be assumable by one service, on behalf of this account only"
  }

  assert {
    condition     = local.roles.eks_cluster.trust.source_account == null && local.roles.eks_node.trust.source_account == null
    error_message = "The EKS cluster and node roles follow the AWS trust policies, which carry no aws:SourceAccount condition"
  }

  assert {
    condition = { for k, r in local.roles : k => one(r.trust.service_principals) } == {
      import_extract   = "lambda.amazonaws.com"
      import_load      = "lambda.amazonaws.com"
      agent_runtime    = "bedrock-agentcore.amazonaws.com"
      eval_batch       = "bedrock.amazonaws.com"
      eks_cluster      = "eks.amazonaws.com"
      eks_node         = "ec2.amazonaws.com"
      api_pod          = "pods.eks.amazonaws.com"
      worker_pod       = "pods.eks.amazonaws.com"
      lb_controller    = "pods.eks.amazonaws.com"
      keda             = "pods.eks.amazonaws.com"
      cloudwatch_agent = "pods.eks.amazonaws.com"
    }
    error_message = "Each role is trusted by the service that runs it"
  }

  assert {
    condition     = local.roles.agent_runtime.trust.source_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:*" && local.roles.eval_batch.trust.source_arn == "arn:aws:bedrock:ap-northeast-1:111111111111:model-invocation-job/*"
    error_message = "Bedrock services must also be pinned to this account's resources with aws:SourceArn"
  }
}

# ---- least privilege ----

run "wildcard_resources_are_the_known_exceptions_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for role, statements in local.statements : [
        for s in statements : "${role}/${s.Sid}" if contains(flatten([s.Resource]), "*")
      ]
      ])) == toset([
      "import_extract/VpcNetworkInterfaces",
      "import_load/VpcNetworkInterfaces",
      "agent_runtime/EcrLoginToken",
      "agent_runtime/TraceSegments",
      "api_pod/TraceSegments",
      "worker_pod/TraceSegments",
      "worker_pod/PutCustomMetrics",
    ])
    error_message = "Resource * is only for actions AWS does not scope by resource: ecr:GetAuthorizationToken, X-Ray, EC2 network interfaces, and PutMetricData (limited by a namespace condition)"
  }

  assert {
    condition = alltrue(flatten([
      for role, statements in local.statements : [
        for s in statements : s.Sid == "PutCustomMetrics" ? s.Condition.StringEquals["cloudwatch:namespace"] == "Example/dev" : true
      ]
    ]))
    error_message = "PutMetricData on * must be limited to the stack's metric namespace"
  }

  assert {
    condition = alltrue(flatten([
      for role, statements in local.statements : [
        for s in statements : [for a in s.Action : a != "*" && !endswith(a, ":*")]
      ]
    ]))
    error_message = "No statement may allow all actions or all actions of a service"
  }

  assert {
    condition = alltrue(flatten([
      for role, statements in local.statements : [
        for s in statements : [for r in flatten([s.Resource]) : r == "*" || startswith(r, "arn:aws:")]
      ]
    ]))
    error_message = "Every resource is * (the exceptions above) or an ARN"
  }
}

run "the_private_key_secret_is_for_the_api_only" {
  command = plan

  assert {
    condition = contains(
      flatten([for s in local.statements.api_pod : s.Resource if s.Sid == "ReadSecrets"]),
      "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl",
    )
    error_message = "The api signs tokens, so it reads the private key secret"
  }

  assert {
    condition = alltrue([
      for role in ["worker_pod", "import_extract", "import_load", "agent_runtime"] :
      !contains(flatten([for s in local.statements[role] : s.Resource]), "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl")
    ])
    error_message = "No other role may read the private key secret"
  }

  assert {
    condition     = toset(flatten([for s in local.statements.worker_pod : s.Resource if s.Sid == "ReadSecrets"])) == toset(["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000", "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"])
    error_message = "The worker reads the database secret and the public key only"
  }
}

run "secrets_are_decrypted_only_through_secrets_manager_with_the_named_key" {
  command = plan

  assert {
    condition = alltrue([
      for role in ["api_pod", "worker_pod", "import_load", "agent_runtime"] : anytrue([
        for s in local.statements[role] : s.Sid == "KmsDecryptViaSecretsManager" &&
        s.Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"] &&
        s.Condition.StringEquals["kms:ViaService"] == "secretsmanager.ap-northeast-1.amazonaws.com"
      ])
    ])
    error_message = "Every role that reads a secret decrypts with the Secrets Manager key, through Secrets Manager only"
  }
}

run "no_role_pulls_the_api_and_worker_images" {
  command = plan

  assert {
    condition = !anytrue(flatten([
      for role, statements in local.statements : [
        for s in statements : contains(flatten([s.Resource]), "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api") ||
        contains(flatten([s.Resource]), "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-worker")
      ]
    ]))
    error_message = "The EKS nodes pull the api and worker images with AmazonEC2ContainerRegistryPullOnly; no role of this stack grants them"
  }
}

run "agent_runtime_pulls_the_runtime_repositories_only_and_logs_under_its_names" {
  command = plan

  assert {
    condition     = flatten([for s in local.statements.agent_runtime : s.Resource if s.Sid == "PullRuntimeImage"]) == ["arn:aws:ecr:ap-northeast-1:111111111111:repository/example-agent"]
    error_message = "The Runtime role pulls the Runtime images only"
  }

  assert {
    condition     = flatten([for s in local.statements.agent_runtime : s.Resource if s.Sid == "ManageRuntimeLogGroups"]) == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/bedrock-agentcore/runtimes/example_dev_agent-*"]
    error_message = "Runtime log groups are named after the Runtime (<project>_<env>_<runtime>)"
  }

  assert {
    condition     = flatten([for s in local.statements.agent_runtime : s.Resource if s.Sid == "UseMemory"]) == ["arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/example_dev_memory-*"]
    error_message = "The Runtime may use its own Memory only"
  }
}

run "api_may_invoke_only_the_runtimes_of_this_env" {
  command = plan

  assert {
    condition = flatten([for s in local.statements.api_pod : s.Resource if s.Sid == "InvokeAgentRuntime"]) == [
      "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-*",
      "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-*/runtime-endpoint/*",
    ]
    error_message = "The runtime id is <name>-<suffix>, so the name scopes the grant without waiting for the agent stack"
  }
}

run "import_extract_reads_incoming_writes_extracted_and_embeds_but_has_no_database" {
  command = plan

  assert {
    condition = {
      for s in local.statements.import_extract : s.Sid => flatten([s.Resource]) if startswith(s.Sid, "Read") || startswith(s.Sid, "Write") && s.Sid != "WriteLogs"
      } == {
      ReadIncoming   = ["arn:aws:s3:::example-dev-import-111111111111/incoming/*"]
      WriteExtracted = ["arn:aws:s3:::example-dev-import-111111111111/extracted/*"]
    }
    error_message = "import-extract reads uploads under incoming/ and writes results under extracted/ only; the bucket name follows <project>-<env>-import-<account>"
  }

  assert {
    condition     = !anytrue(flatten([for s in local.statements.import_extract : [for a in s.Action : startswith(a, "secretsmanager:") || startswith(a, "kms:")]]))
    error_message = "import-extract never connects to the database, so it gets no secret and no key"
  }

  assert {
    condition     = flatten([for s in local.statements.import_extract : s.Action if s.Sid == "InvokeVectorModels"]) == ["bedrock:InvokeModel"] && alltrue([for a in flatten([for s in local.statements.import_extract : s.Resource if s.Sid == "InvokeVectorModels"]) : startswith(a, "arn:aws:bedrock:ap-northeast-1::foundation-model/")])
    error_message = "import-extract may invoke the two embedding foundation models only"
  }

  assert {
    condition     = flatten([for s in local.statements.import_extract : s.Resource if s.Sid == "WriteLogs"]) == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/example-dev-import-extract:*"]
    error_message = "Each function writes only to its own log group"
  }
}

run "import_load_reads_extracted_and_the_database_secret_and_can_write_nothing_else" {
  command = plan

  assert {
    condition     = toset(flatten([for s in local.statements.import_load : s.Resource if contains(["ReadExtracted", "ListExtracted"], s.Sid)])) == toset(["arn:aws:s3:::example-dev-import-111111111111/extracted/*", "arn:aws:s3:::example-dev-import-111111111111"])
    error_message = "import-load reads the objects under extracted/ only"
  }

  assert {
    condition     = !anytrue(flatten([for s in local.statements.import_load : [for a in s.Action : a == "s3:PutObject" || startswith(a, "bedrock:")]]))
    error_message = "import-load cannot write to the bucket or call a model"
  }

  assert {
    condition     = flatten([for s in local.statements.import_load : s.Resource if s.Sid == "ReadSecrets"]) == ["arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"]
    error_message = "import-load reads the database secret and no signing key"
  }

  assert {
    condition     = flatten([for s in local.statements.import_load : s.Resource if s.Sid == "WriteLogs"]) == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/example-dev-import-load:*"]
    error_message = "Each function writes only to its own log group"
  }
}

run "extract_writes_the_prefix_that_load_reads_and_nothing_else_overlaps" {
  command = plan

  assert {
    condition = length(setintersection(
      toset(flatten([for s in local.statements.import_extract : s.Resource if contains(["ReadIncoming", "WriteExtracted"], s.Sid)])),
      toset(flatten([for s in local.statements.import_load : s.Resource if s.Sid == "ReadExtracted"])),
    )) == 1
    error_message = "The only object path both functions touch is extracted/*, written by extract and read by load"
  }
}

run "eval_batch_reaches_its_bucket_and_model_only" {
  command = plan

  assert {
    condition = toset(flatten([for s in local.statements.eval_batch : s.Resource if contains(["ListEvalBucket", "ReadWriteEvalObjects"], s.Sid)])) == toset([
      "arn:aws:s3:::example-dev-eval-batch-111111111111",
      "arn:aws:s3:::example-dev-eval-batch-111111111111/*",
    ])
    error_message = "The eval-batch role touches its own bucket only"
  }

  assert {
    condition = flatten([for s in local.statements.eval_batch : s.Resource if s.Sid == "InvokeEvalModel"]) == [
      "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
    ]
    error_message = "The eval-batch role invokes the one configured model"
  }

  assert {
    condition     = alltrue([for s in local.statements.eval_batch : try(s.Condition.StringEquals["aws:ResourceAccount"], "111111111111") == "111111111111"])
    error_message = "Bucket access must be limited to resources of this account"
  }
}

run "without_runtimes_no_statement_has_an_empty_resource_list" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        agent_runtimes                 = "[]"
        ecr_repository_arns = jsonencode({
          api    = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api"
          worker = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-worker"
        })
      }
      lists = {}
    }
  }

  assert {
    condition = alltrue(flatten([
      for role, statements in local.statements : [for s in statements : length(flatten([s.Resource])) > 0]
    ]))
    error_message = "An IAM statement with an empty Resource list is invalid; statements for Runtimes must disappear with them"
  }

  assert {
    condition     = !anytrue(flatten([for s in local.statements.api_pod : s.Sid == "InvokeAgentRuntime"]))
    error_message = "The api has no Runtime to invoke"
  }
}

# ---- guards ----

run "a_missing_repository_is_reported_by_name" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        agent_runtimes                 = "[\"agent\"]"
        ecr_repository_arns            = jsonencode({ api = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api" })
      }
      lists = {}
    }
  }

  expect_failures = [terraform_data.repositories_exist]
}

# ---- publishing ----

run "publishes_the_ten_role_arns" {
  command = plan

  override_module {
    target  = module.role["import_extract"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-import-extract" }
  }
  override_module {
    target  = module.role["import_load"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-import-load" }
  }
  override_module {
    target  = module.role["agent_runtime"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-agent-runtime" }
  }
  override_module {
    target  = module.role["eval_batch"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-eval-batch" }
  }
  override_module {
    target  = module.role["eks_cluster"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-eks-cluster" }
  }
  override_module {
    target  = module.role["eks_node"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-eks-node" }
  }
  override_module {
    target  = module.role["api_pod"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-api-pod" }
  }
  override_module {
    target  = module.role["worker_pod"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-worker-pod" }
  }
  override_module {
    target  = module.role["lb_controller"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-lb-controller" }
  }
  override_module {
    target  = module.role["keda"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-keda" }
  }
  override_module {
    target  = module.role["cloudwatch_agent"]
    outputs = { arn = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent" }
  }

  assert {
    condition = local.published_strings == {
      import_extract_role_arn   = "arn:aws:iam::111111111111:role/example-dev-import-extract"
      import_load_role_arn      = "arn:aws:iam::111111111111:role/example-dev-import-load"
      agent_runtime_role_arn    = "arn:aws:iam::111111111111:role/example-dev-agent-runtime"
      eks_cluster_role_arn      = "arn:aws:iam::111111111111:role/example-dev-eks-cluster"
      eks_node_role_arn         = "arn:aws:iam::111111111111:role/example-dev-eks-node"
      api_pod_role_arn          = "arn:aws:iam::111111111111:role/example-dev-api-pod"
      worker_pod_role_arn       = "arn:aws:iam::111111111111:role/example-dev-worker-pod"
      lb_controller_role_arn    = "arn:aws:iam::111111111111:role/example-dev-lb-controller"
      keda_role_arn             = "arn:aws:iam::111111111111:role/example-dev-keda"
      cloudwatch_agent_role_arn = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent"
    }
    error_message = "Each published ARN must come from the matching role; eval_batch is not published"
  }

  assert {
    condition = module.ssm_publish.names == {
      import_extract_role_arn   = "/example/dev/iam/import_extract_role_arn"
      import_load_role_arn      = "/example/dev/iam/import_load_role_arn"
      agent_runtime_role_arn    = "/example/dev/iam/agent_runtime_role_arn"
      eks_cluster_role_arn      = "/example/dev/iam/eks_cluster_role_arn"
      eks_node_role_arn         = "/example/dev/iam/eks_node_role_arn"
      api_pod_role_arn          = "/example/dev/iam/api_pod_role_arn"
      worker_pod_role_arn       = "/example/dev/iam/worker_pod_role_arn"
      lb_controller_role_arn    = "/example/dev/iam/lb_controller_role_arn"
      keda_role_arn             = "/example/dev/iam/keda_role_arn"
      cloudwatch_agent_role_arn = "/example/dev/iam/cloudwatch_agent_role_arn"
    }
    error_message = "ssm-publish must write the ten role keys under the iam path"
  }
}

# ---- guardrails ----

run "the_roles_that_apply_guardrails_also_get_the_guardrail_profile" {
  command = plan

  assert {
    condition = alltrue([
      for r in ["api_pod", "agent_runtime"] :
      contains(flatten([for s in local.statements[r] : s.Resource if s.Sid == "ApplyGuardrail"]), "arn:aws:bedrock:*:111111111111:guardrail-profile/apac.guardrail.v1:0")
    ])
    error_message = "A STANDARD tier guardrail is evaluated through a cross-region profile, which needs its own resource in the ApplyGuardrail grant; the region is a wildcard because AWS picks it"
  }

  assert {
    condition = alltrue([
      for r in ["api_pod", "agent_runtime"] :
      contains(flatten([for s in local.statements[r] : s.Resource if s.Sid == "ApplyGuardrail"]), "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/*")
    ])
    error_message = "The guardrails themselves stay granted"
  }

  assert {
    condition     = !anytrue([for r in ["worker_pod", "import_extract", "import_load"] : anytrue([for s in local.statements[r] : s.Sid == "ApplyGuardrail"])])
    error_message = "Only the roles that call ApplyGuardrail get the grant"
  }
}

run "the_profile_id_is_a_variable_with_a_validated_shape" {
  command = plan

  variables {
    guardrail_cross_region_profile_id = "global.guardrail.v2:1"
  }

  assert {
    condition     = contains(flatten([for s in local.statements["agent_runtime"] : s.Resource if s.Sid == "ApplyGuardrail"]), "arn:aws:bedrock:*:111111111111:guardrail-profile/global.guardrail.v2:1")
    error_message = "Another profile id changes the resource"
  }
}

run "rejects_a_malformed_profile_id" {
  command = plan

  variables {
    guardrail_cross_region_profile_id = "not a profile"
  }

  expect_failures = [var.guardrail_cross_region_profile_id]
}

# ---- EKS (design v4 §4, §8.1) ----

run "pod_roles_trust_pod_identity_for_this_cluster_only" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["api_pod", "worker_pod", "lb_controller", "keda", "cloudwatch_agent"] :
      local.roles[k].trust.tag_session && local.roles[k].trust.source_arn == "arn:aws:eks:ap-northeast-1:111111111111:cluster/example-dev"
    ])
    error_message = "Pod Identity roles need sts:TagSession and are limited to this account's example-dev cluster"
  }
}

run "eks_cluster_and_node_roles_use_the_auto_mode_managed_policies" {
  command = plan

  assert {
    condition = toset(local.roles.eks_cluster.managed_policy_arns) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
      "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
      "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
    ]) && local.roles.eks_cluster.trust.tag_session
    error_message = "The Auto Mode cluster role gets the five EKS managed policies and sts:TagSession"
  }

  assert {
    condition = toset(local.roles.eks_node.managed_policy_arns) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    ])
    error_message = "The Auto Mode node role gets the minimal worker policy and ECR pull-only"
  }

  assert {
    condition     = toset(local.roles.cloudwatch_agent.managed_policy_arns) == toset(["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"])
    error_message = "The Container Insights collector (agent and Fluent Bit share one service account) gets CloudWatchAgentServerPolicy"
  }

  assert {
    condition     = alltrue([for k in ["eks_cluster", "eks_node", "cloudwatch_agent", "lb_controller", "keda"] : length(local.statements[k]) == 0])
    error_message = "These roles carry no statements of this stack; their permissions are managed policies or the eks-iam-policies documents"
  }
}

run "nothing_of_ecs_is_left" {
  command = plan

  assert {
    condition     = !anytrue([for k, r in local.roles : contains(r.trust.service_principals, "ecs-tasks.amazonaws.com")])
    error_message = "No role is trusted by ECS tasks any more (design v4 §8.1)"
  }

  assert {
    condition = !anytrue(flatten([
      for role, statements in local.statements : [for s in statements : [for a in s.Action : startswith(a, "ssmmessages:")]]
    ]))
    error_message = "ECS Exec is gone; kubectl exec is governed by the EKS access entries"
  }
}

run "controller_policies_come_from_eks_iam_policies" {
  command = plan

  assert {
    condition     = local.controller_policies.lb_controller == module.eks_policies.load_balancer_controller_policy_json && local.controller_policies.keda == module.eks_policies.keda_cloudwatch_policy_json
    error_message = "The LB Controller and KEDA roles use the eks-iam-policies documents unchanged"
  }

  assert {
    condition     = toset(keys(local.controller_policies)) == toset(["lb_controller", "keda"])
    error_message = "Only the LB Controller and KEDA roles get an eks-iam-policies document"
  }

  assert {
    condition     = module.eks_policies.policy_sizes.load_balancer_controller <= 10240
    error_message = "The LB Controller policy must fit the inline policy size limit of its role"
  }
}
