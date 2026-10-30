mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/artifact_bucket_name"]
  values = { insecure_value = "cicd-dev-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/connection_arn"]
  values = { insecure_value = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/fn_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn" }
}

# The role ARNs are unknown at plan time; PassRole and the published keys are checked with these values.
override_module {
  target  = module.role["api_execution"]
  outputs = { arn = "arn:aws:iam::111111111111:role/cicd-dev-api-execution", name = "cicd-dev-api-execution" }
}

override_module {
  target  = module.role["api_task"]
  outputs = { arn = "arn:aws:iam::111111111111:role/cicd-dev-api-task", name = "cicd-dev-api-task" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn          = "foundation/kms_key_arn"
      artifact_bucket_name = "foundation/artifact_bucket_name"
      connection_arn       = "foundation/connection_arn"
      api_repository_url   = "containerimage/api_repository_url"
      fn_repository_url    = "containerimage/fn_repository_url"
    } && local.ssm_input_lists == {}
    error_message = "iam may read only the foundation and containerimage keys it needs (design 8.3); later stacks are named by rule"
  }
}

# The later stacks name their resources exactly like this; their tests must pin the same strings.
run "naming_rules_of_the_later_stacks" {
  command = plan

  assert {
    condition = (
      local.api_service_arn == "arn:aws:ecs:ap-northeast-1:111111111111:service/cicd-dev/cicd-dev-api" &&
      local.api_task_family_arn == "arn:aws:ecs:ap-northeast-1:111111111111:task-definition/cicd-dev-api:*" &&
      local.api_log_group == "/ecs/cicd-dev-api"
    )
    error_message = "application must name the cluster <name_prefix> and the api service and family <name_prefix>-api"
  }

  assert {
    condition     = local.fn_function_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:cicd-dev-fn"
    error_message = "application must name the function <name_prefix>-fn"
  }

  assert {
    condition     = local.web_bucket_arn == "arn:aws:s3:::cicd-dev-web-111111111111"
    error_message = "web must name the SPA bucket <name_prefix>-web-<account>"
  }

  assert {
    condition = local.build_project_names == {
      api_build      = "cicd-dev-api-build"
      api_deploy     = "cicd-dev-api-deploy"
      fn_build       = "cicd-dev-fn-build"
      web_build      = "cicd-dev-web-build"
      web_invalidate = "cicd-dev-web-invalidate"
    } && local.pipeline_names == { api = "cicd-dev-api", fn = "cicd-dev-fn", web = "cicd-dev-web" }
    error_message = "pipeline must name the build projects and pipelines like this"
  }

  assert {
    condition     = local.repository_arns == { api = "arn:aws:ecr:ap-northeast-1:111111111111:repository/cicd-dev-api", fn = "arn:aws:ecr:ap-northeast-1:111111111111:repository/cicd-dev-fn" }
    error_message = "The repository ARNs must be built from the URLs containerimage publishes"
  }
}

run "one_role_per_component_and_build_project" {
  command = plan

  assert {
    condition     = toset(keys(local.roles)) == toset(["api_execution", "api_task", "fn", "api_build", "api_deploy", "fn_build", "web_build", "web_invalidate", "pipeline"])
    error_message = "design 8.1: ECS execution and task roles, the Lambda role, one role per build project and the pipeline role"
  }

  assert {
    condition     = length(distinct([for r in values(local.roles) : r.name])) == length(local.roles)
    error_message = "No two components may share a role (design 4.1)"
  }

  assert {
    condition = (
      local.roles.api_execution.service == "ecs-tasks.amazonaws.com" && local.roles.api_task.service == "ecs-tasks.amazonaws.com" &&
      local.roles.fn.service == "lambda.amazonaws.com" && local.roles.pipeline.service == "codepipeline.amazonaws.com" &&
      alltrue([for k in keys(local.build_project_names) : local.roles[k].service == "codebuild.amazonaws.com"])
    )
    error_message = "Each role must trust only the service that uses it"
  }
}

run "build_roles_trust_only_their_own_project" {
  command = plan

  assert {
    condition = alltrue([
      for k, n in local.build_project_names : local.roles[k].source_arn == "arn:aws:codebuild:ap-northeast-1:111111111111:project/${n}" && local.roles[k].name == "${n}-codebuild"
    ])
    error_message = "Each CodeBuild role must pin aws:SourceArn to its own project"
  }

  assert {
    condition     = local.roles.pipeline.source_arn == "arn:aws:codepipeline:ap-northeast-1:111111111111:cicd-dev-*"
    error_message = "The pipeline role must only be assumable by this env's pipelines"
  }
}

run "api_task_role_has_no_permissions" {
  command = plan

  assert {
    condition     = !contains(keys(local.role_policies), "api_task")
    error_message = "The api task role must stay empty until the API calls an AWS service"
  }

  assert {
    condition     = toset(keys(local.role_policies)) == setsubtract(toset(keys(local.roles)), ["api_task"])
    error_message = "Every other role must get exactly one permissions policy"
  }
}

run "execution_and_function_roles_touch_only_their_component" {
  command = plan

  assert {
    condition = (
      local.statements.api_execution["PullApiImage"].Resource == ["arn:aws:ecr:ap-northeast-1:111111111111:repository/cicd-dev-api"] &&
      local.statements.api_execution["WriteServiceLogs"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/ecs/cicd-dev-api:*"]
    )
    error_message = "The execution role may pull only the api image and write only the api log group"
  }

  assert {
    condition     = keys(local.statements.fn) == ["WriteOwnLogs"] && local.statements.fn["WriteOwnLogs"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/cicd-dev-fn:*"]
    error_message = "The Lambda role may only write its own log group"
  }
}

run "build_roles_share_only_logs_artifacts_and_key" {
  command = plan

  assert {
    condition = alltrue([
      for k, n in local.build_project_names : local.statements[k]["WriteOwnLogs"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/codebuild/${n}:*"]
    ])
    error_message = "Each build role may write only its own project's log group"
  }

  assert {
    condition = alltrue([
      for k in keys(local.build_project_names) : (
        local.statements[k]["ArtifactObjects"].Resource == ["arn:aws:s3:::cicd-dev-artifacts-111111111111/*"] &&
        local.statements[k]["ArtifactObjects"].Condition == { StringEquals = { "aws:ResourceAccount" = "111111111111" } } &&
        local.statements[k]["UseSharedKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
      )
    ])
    error_message = "Artifact access is the artifact bucket of this account and the shared key only"
  }

  assert {
    condition = (
      !contains(local.statements.api_deploy["ArtifactObjects"].Action, "s3:PutObject") &&
      !contains(local.statements.web_invalidate["ArtifactObjects"].Action, "s3:PutObject") &&
      !contains(local.statements.api_deploy["UseSharedKey"].Action, "kms:GenerateDataKey") &&
      contains(local.statements.web_build["ArtifactObjects"].Action, "s3:PutObject")
    )
    error_message = "Only the build projects write artifacts; api-deploy and web-invalidate only read"
  }

  assert {
    condition = alltrue(flatten([
      for k in keys(local.build_project_names) : [for s in values(local.statements[k]) : !anytrue([for a in s.Action : startswith(a, "secretsmanager:")])]
    ]))
    error_message = "Build roles must not read Secrets Manager (design 4.1); grant one secret explicitly when a build needs it"
  }
}

run "image_builds_push_only_their_own_repository" {
  command = plan

  assert {
    condition = (
      local.statements.api_build["PushApiImage"].Resource == ["arn:aws:ecr:ap-northeast-1:111111111111:repository/cicd-dev-api"] &&
      local.statements.fn_build["PushFnImage"].Resource == ["arn:aws:ecr:ap-northeast-1:111111111111:repository/cicd-dev-fn"]
    )
    error_message = "api-build may push only to the api repository and fn-build only to the fn repository (design 4)"
  }

  assert {
    condition     = toset(keys(local.statements.api_build)) == toset(["WriteOwnLogs", "ArtifactBucket", "ArtifactObjects", "UseSharedKey", "EcrLoginToken", "PushApiImage"])
    error_message = "api-build must not get anything beyond building and pushing the api image"
  }

  assert {
    condition     = toset(keys(local.statements.web_build)) == toset(["WriteOwnLogs", "ArtifactBucket", "ArtifactObjects", "UseSharedKey"])
    error_message = "web-build only builds; the pipeline's S3 deploy action writes the web bucket"
  }
}

run "fn_build_updates_only_the_fn_function" {
  command = plan

  assert {
    condition = (
      toset(local.statements.fn_build["UpdateFnCode"].Action) == toset(["lambda:UpdateFunctionCode", "lambda:PublishVersion", "lambda:GetFunction"]) &&
      local.statements.fn_build["UpdateFnCode"].Resource == ["arn:aws:lambda:ap-northeast-1:111111111111:function:cicd-dev-fn"]
    )
    error_message = "fn-build may update the code, publish a version and read only the fn function (design 4); the alias is the pipeline's"
  }

  assert {
    condition     = toset(keys(local.statements.fn_build)) == toset(["WriteOwnLogs", "ArtifactBucket", "ArtifactObjects", "UseSharedKey", "EcrLoginToken", "PushFnImage", "UpdateFnCode"])
    error_message = "fn-build must not get anything beyond the fn image and function"
  }
}

run "api_deploy_follows_the_three_steps_of_design_5_4" {
  command = plan

  assert {
    condition     = local.statements.api_deploy["RegisterApiTaskDefinition"].Resource == ["arn:aws:ecs:ap-northeast-1:111111111111:task-definition/cicd-dev-api:*"]
    error_message = "api-deploy may register revisions of the api family only"
  }

  assert {
    condition = (
      local.statements.api_deploy["UpdateApiService"].Resource == ["arn:aws:ecs:ap-northeast-1:111111111111:service/cicd-dev/cicd-dev-api"] &&
      local.statements.api_deploy["UpdateApiService"].Condition == { ArnLike = { "ecs:task-definition" = "arn:aws:ecs:ap-northeast-1:111111111111:task-definition/cicd-dev-api:*" } } &&
      local.statements.api_deploy["DescribeApiService"].Resource == ["arn:aws:ecs:ap-northeast-1:111111111111:service/cicd-dev/cicd-dev-api"]
    )
    error_message = "api-deploy may update and describe only the api service, and only to a revision of the api family"
  }

  assert {
    condition     = local.statements.api_deploy["TagOnRegister"].Condition == { StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" } }
    error_message = "ecs:TagResource is allowed only while registering a revision"
  }

  assert {
    condition     = toset(keys(local.statements.api_deploy)) == toset(["WriteOwnLogs", "ArtifactBucket", "ArtifactObjects", "UseSharedKey", "DescribeTaskDefinition", "RegisterApiTaskDefinition", "TagOnRegister", "UpdateApiService", "DescribeApiService", "PassApiTaskRoles"])
    error_message = "api-deploy must not get anything beyond design 5.4; in particular no ECR push"
  }
}

run "pass_role_is_limited_to_the_api_task_roles_and_ecs_tasks" {
  command = plan

  assert {
    condition = (
      local.statements.api_deploy["PassApiTaskRoles"].Action == ["iam:PassRole"] &&
      local.statements.api_deploy["PassApiTaskRoles"].Resource == ["arn:aws:iam::111111111111:role/cicd-dev-api-execution", "arn:aws:iam::111111111111:role/cicd-dev-api-task"]
    )
    error_message = "api-deploy may pass only the api execution and task roles (design 4)"
  }

  assert {
    condition = alltrue(flatten([
      for role, ss in local.statements : [
        for s in values(ss) : lookup(lookup(s, "Condition", {}), "StringEquals", {}) == { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } if contains(s.Action, "iam:PassRole")
      ]
    ]))
    error_message = "Every iam:PassRole must carry iam:PassedToService = ecs-tasks.amazonaws.com"
  }

  assert {
    condition     = length(flatten([for role, ss in local.statements : [for s in values(ss) : s if contains(s.Action, "iam:PassRole")]])) == 1
    error_message = "api-deploy is the only role that may pass a role"
  }
}

run "web_invalidate_is_scoped_to_the_web_distribution_tags" {
  command = plan

  assert {
    condition = (
      toset(local.statements.web_invalidate["InvalidateWebDistribution"].Action) == toset(["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]) &&
      local.statements.web_invalidate["InvalidateWebDistribution"].Resource == ["arn:aws:cloudfront::111111111111:distribution/*"]
    )
    error_message = "web-invalidate may only create and read invalidations"
  }

  assert {
    condition = local.statements.web_invalidate["InvalidateWebDistribution"].Condition == {
      StringEquals = {
        "aws:ResourceTag/Project"     = "cicd"
        "aws:ResourceTag/Environment" = "dev"
        "aws:ResourceTag/Managed"     = "terraform"
        "aws:ResourceTag/Stack"       = "web"
      }
    }
    error_message = "The distribution must be this env's web stack distribution, matched by the provider default tags"
  }
}

run "pipeline_role_touches_only_its_connection_projects_function_and_buckets" {
  command = plan

  assert {
    condition = (
      toset(local.statements.pipeline["UseGitHubConnection"].Action) == toset(["codeconnections:UseConnection", "codestar-connections:UseConnection"]) &&
      toset(local.statements.pipeline["UseGitHubConnection"].Resource) == toset([
        "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000",
        "arn:aws:codestar-connections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000",
      ])
    )
    error_message = "UseConnection must be granted on the one connection foundation publishes (design 4)"
  }

  assert {
    condition = (
      toset(local.statements.pipeline["RunBuildProjects"].Action) == toset(["codebuild:StartBuild", "codebuild:BatchGetBuilds"]) &&
      toset(local.statements.pipeline["RunBuildProjects"].Resource) == toset([
        "arn:aws:codebuild:ap-northeast-1:111111111111:project/cicd-dev-api-build",
        "arn:aws:codebuild:ap-northeast-1:111111111111:project/cicd-dev-api-deploy",
        "arn:aws:codebuild:ap-northeast-1:111111111111:project/cicd-dev-fn-build",
        "arn:aws:codebuild:ap-northeast-1:111111111111:project/cicd-dev-web-build",
        "arn:aws:codebuild:ap-northeast-1:111111111111:project/cicd-dev-web-invalidate",
      ])
    )
    error_message = "The pipeline role may start and read builds of exactly these five projects (design 4)"
  }

  assert {
    condition = (
      toset(local.statements.pipeline["LambdaDeployFn"].Resource) == toset(["arn:aws:lambda:ap-northeast-1:111111111111:function:cicd-dev-fn", "arn:aws:lambda:ap-northeast-1:111111111111:function:cicd-dev-fn:*"]) &&
      toset(local.statements.pipeline["LambdaDeployFn"].Action) == toset(["lambda:GetAlias", "lambda:GetFunctionConfiguration", "lambda:GetProvisionedConcurrencyConfig", "lambda:PublishVersion", "lambda:UpdateAlias", "lambda:UpdateFunctionCode"])
    )
    error_message = "The Lambda deploy action may act on the fn function and its alias and versions only"
  }

  assert {
    condition = (
      local.statements.pipeline["LambdaDeployLogGroup"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/ap-northeast-1/codepipeline/cicd-dev-fn", "arn:aws:logs:ap-northeast-1:111111111111:log-group:/ap-northeast-1/codepipeline/cicd-dev-fn:*"] &&
      local.statements.pipeline["LambdaDeployLogEvents"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/ap-northeast-1/codepipeline/cicd-dev-fn:log-stream:*"]
    )
    error_message = "The Lambda deploy action may log only to the fn pipeline's log group"
  }

  assert {
    condition = (
      local.statements.pipeline["DeployWebBucket"].Resource == ["arn:aws:s3:::cicd-dev-web-111111111111", "arn:aws:s3:::cicd-dev-web-111111111111/*"] &&
      local.statements.pipeline["DeployWebBucket"].Condition == { StringEquals = { "aws:ResourceAccount" = "111111111111" } }
    )
    error_message = "The S3 deploy action may write only the SPA bucket of this account"
  }

  assert {
    condition = (
      local.statements.pipeline["ArtifactObjects"].Resource == ["arn:aws:s3:::cicd-dev-artifacts-111111111111/*"] &&
      local.statements.pipeline["ArtifactBucket"].Resource == ["arn:aws:s3:::cicd-dev-artifacts-111111111111"] &&
      local.statements.pipeline["UseSharedKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
    )
    error_message = "Artifact access is the artifact bucket and the shared key only"
  }

  assert {
    condition     = toset(keys(local.statements.pipeline)) == toset(["ArtifactBucket", "ArtifactObjects", "UseSharedKey", "UseGitHubConnection", "RunBuildProjects", "LambdaDeployFn", "LambdaDeployLogGroup", "LambdaDeployLogEvents", "DeployWebBucket"])
    error_message = "A new pipeline statement must come with a test; the pipeline role has no ECS, ECR or PassRole"
  }
}

# Resource "*" only where the action has no resource type in the service authorization reference.
run "wildcard_resources_only_where_aws_requires_them" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for role, ss in local.statements : [
        for sid, s in ss : [
          for res in s.Resource : res != "*" || s.Action == ["ecr:GetAuthorizationToken"] || s.Action == ["ecs:DescribeTaskDefinition"]
        ]
      ]
    ]))
    error_message = "Resource * is allowed only for ecr:GetAuthorizationToken and ecs:DescribeTaskDefinition, each alone in its statement"
  }

  assert {
    condition = alltrue(flatten([
      for role, ss in local.statements : [
        for s in values(ss) : [for res in s.Resource : res == "*" || (!startswith(res, "*") && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res)))]
      ]
    ]))
    error_message = "No Resource may be an account-wide wildcard"
  }

  assert {
    condition = alltrue(flatten([
      for p in values(local.role_policies) : [
        for doc in values(p) : [
          for s in jsondecode(doc).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
        ]
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "policies_are_attached_to_their_roles" {
  command = plan

  assert {
    condition = (
      length(regexall("(?m)^\\s*role_arn\\s*=\\s*module\\.role\\[each\\.key\\]\\.arn\\s*$", file("${path.module}/policies.tf"))) == 1 &&
      length(regexall("(?m)^\\s*for_each\\s*=\\s*local\\.role_policies\\s*$", file("${path.module}/policies.tf"))) == 1
    )
    error_message = "iam-role-policy must attach each role's policy to that role"
  }

  assert {
    condition     = alltrue([for p in values(local.role_policies) : keys(p) == ["permissions"]])
    error_message = "Each role has exactly one inline policy named permissions"
  }
}

run "publishes_every_role_arn" {
  command = plan

  override_module {
    target  = module.role["fn"]
    outputs = { arn = "arn:aws:iam::111111111111:role/cicd-dev-fn-lambda" }
  }

  override_module {
    target  = module.role["pipeline"]
    outputs = { arn = "arn:aws:iam::111111111111:role/cicd-dev-pipeline" }
  }

  assert {
    condition     = toset(keys(local.published_strings)) == toset([for k in keys(local.roles) : "${k}_role_arn"])
    error_message = "iam must publish <role>_role_arn for every role and nothing else (design 8.3)"
  }

  assert {
    condition = (
      local.published_strings.api_execution_role_arn == "arn:aws:iam::111111111111:role/cicd-dev-api-execution" &&
      local.published_strings.fn_role_arn == "arn:aws:iam::111111111111:role/cicd-dev-fn-lambda" &&
      local.published_strings.pipeline_role_arn == "arn:aws:iam::111111111111:role/cicd-dev-pipeline"
    )
    error_message = "Each published key must be the ARN of the matching role"
  }

  assert {
    condition     = module.ssm_publish.names.pipeline_role_arn == "/cicd/dev/iam/pipeline_role_arn" && module.ssm_publish.names.api_deploy_role_arn == "/cicd/dev/iam/api_deploy_role_arn"
    error_message = "ssm-publish must write the keys under the iam path"
  }
}

run "sit_follows_env_and_account" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition = (
      local.roles.pipeline.name == "cicd-sit-pipeline" &&
      local.roles.api_build.source_arn == "arn:aws:codebuild:ap-northeast-1:222222222222:project/cicd-sit-api-build" &&
      local.api_service_arn == "arn:aws:ecs:ap-northeast-1:222222222222:service/cicd-sit/cicd-sit-api" &&
      local.web_bucket_arn == "arn:aws:s3:::cicd-sit-web-222222222222"
    )
    error_message = "Names and ARNs must follow the env and account"
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
