mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
  repository          = "example-org/example-app"
  branch              = "develop"
  approval_required   = false
  fn_deploy_strategy  = "AllAtOnce"
  log_retention_days  = 30
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
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts" }
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

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_deploy_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-deploy-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/fn_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-fn-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/web_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-web-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/web_invalidate_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-web-invalidate-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/pipeline_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-pipeline" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["application/cluster_name"]
  values = { insecure_value = "cicd-dev" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["application/api_service_name"]
  values = { insecure_value = "cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["application/api_task_family"]
  values = { insecure_value = "cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["application/fn_function_name"]
  values = { insecure_value = "cicd-dev-fn" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["application/fn_alias_name"]
  values = { insecure_value = "live" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["web/web_bucket_name"]
  values = { insecure_value = "cicd-dev-web-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["web/distribution_id"]
  values = { insecure_value = "E0000000000001" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn             = "foundation/kms_key_arn"
      artifact_bucket_name    = "foundation/artifact_bucket_name"
      alert_topic_arn         = "foundation/alert_topic_arn"
      connection_arn          = "foundation/connection_arn"
      api_repository_url      = "containerimage/api_repository_url"
      fn_repository_url       = "containerimage/fn_repository_url"
      api_build_role_arn      = "iam/api_build_role_arn"
      api_deploy_role_arn     = "iam/api_deploy_role_arn"
      fn_build_role_arn       = "iam/fn_build_role_arn"
      web_build_role_arn      = "iam/web_build_role_arn"
      web_invalidate_role_arn = "iam/web_invalidate_role_arn"
      pipeline_role_arn       = "iam/pipeline_role_arn"
      cluster_name            = "application/cluster_name"
      api_service_name        = "application/api_service_name"
      api_task_family         = "application/api_task_family"
      fn_function_name        = "application/fn_function_name"
      fn_alias_name           = "application/fn_alias_name"
      web_bucket_name         = "web/web_bucket_name"
      distribution_id         = "web/distribution_id"
    } && local.ssm_input_lists == {}
    error_message = "pipeline may read only the keys it needs from the earlier stacks (design 8.3)"
  }
}

# iam/naming.tf scopes every role to these names; iam's naming test pins the same strings.
run "names_match_the_iam_naming_rules" {
  command = plan

  assert {
    condition = local.build_project_names == {
      api_build      = "cicd-dev-api-build"
      api_deploy     = "cicd-dev-api-deploy"
      fn_build       = "cicd-dev-fn-build"
      web_build      = "cicd-dev-web-build"
      web_invalidate = "cicd-dev-web-invalidate"
    } && { for k, m in module.build : k => m.name } == local.build_project_names
    error_message = "The build projects must be named <name_prefix>-<project>, as iam/naming.tf expects"
  }

  assert {
    condition     = alltrue([for k, m in module.build : m.log_group_name == "/aws/codebuild/${local.build_project_names[k]}"])
    error_message = "Each build project must log to /aws/codebuild/<name>, the log group its role may write"
  }

  assert {
    condition = (
      local.pipeline_names == { api = "cicd-dev-api", fn = "cicd-dev-fn", web = "cicd-dev-web" } &&
      { for k, m in module.pipeline : k => m.name } == local.pipeline_names
    )
    error_message = "The pipelines must be named <name_prefix>-api, -fn and -web, as iam/naming.tf expects"
  }
}

# Design 4.1: each project runs with its own role and its buildspec comes from the application repo (K5).
run "each_project_uses_its_own_role_and_buildspec" {
  command = plan

  assert {
    condition = { for k, p in local.build_projects : k => p.service_role_arn } == {
      api_build      = "arn:aws:iam::111111111111:role/cicd-dev-api-build-codebuild"
      api_deploy     = "arn:aws:iam::111111111111:role/cicd-dev-api-deploy-codebuild"
      fn_build       = "arn:aws:iam::111111111111:role/cicd-dev-fn-build-codebuild"
      web_build      = "arn:aws:iam::111111111111:role/cicd-dev-web-build-codebuild"
      web_invalidate = "arn:aws:iam::111111111111:role/cicd-dev-web-invalidate-codebuild"
    }
    error_message = "Every build project must use the role iam made for it; no two projects share one"
  }

  assert {
    condition = { for k, p in local.build_projects : k => p.buildspec } == {
      api_build      = "buildspec/api-build.yml"
      api_deploy     = "buildspec/api-deploy.yml"
      fn_build       = "buildspec/fn-build.yml"
      web_build      = "buildspec/web-build.yml"
      web_invalidate = "buildspec/web-invalidate.yml"
    }
    error_message = "The buildspecs must be the paths in the application repo that REFERENCE documents"
  }

  assert {
    condition     = [for k, p in local.build_projects : k if p.privileged] == ["api_build", "fn_build"]
    error_message = "Only the two image builds may run docker (privileged_mode)"
  }

  assert {
    condition     = alltrue([for p in values(local.build_projects) : p.cache_modes == (p.privileged ? ["LOCAL_DOCKER_LAYER_CACHE"] : [])])
    error_message = "Only the privileged projects use the docker layer cache"
  }
}

# The values the buildspecs need; plain names and values, never a secret.
run "projects_get_their_targets_as_variables" {
  command = plan

  assert {
    condition = { for k, p in local.build_projects : k => { for n, v in p.environment_variables : n => v.value } } == {
      api_build = { REPOSITORY_URI = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api" }
      api_deploy = {
        CLUSTER_NAME   = "cicd-dev"
        SERVICE_NAME   = "cicd-dev-api"
        TASK_FAMILY    = "cicd-dev-api"
        CONTAINER_NAME = "app"
      }
      fn_build = {
        REPOSITORY_URI = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn"
        FUNCTION_NAME  = "cicd-dev-fn"
      }
      web_build      = {}
      web_invalidate = { DISTRIBUTION_ID = "E0000000000001" }
    }
    error_message = "Each project must get exactly the names of its own targets"
  }

  assert {
    condition     = alltrue(flatten([for p in values(local.build_projects) : [for v in values(p.environment_variables) : v.type == "PLAINTEXT"]]))
    error_message = "The build variables are names, not secrets; secrets need PARAMETER_STORE or SECRETS_MANAGER and an iam grant"
  }
}

# Design 8.2.
run "dev_stage_order_has_no_approval" {
  command = plan

  assert {
    condition = { for k, s in local.pipeline_stages : k => [for stage in s : stage.name] } == {
      api = ["Build", "Deploy"]
      fn  = ["Build", "Deploy"]
      web = ["Build", "Deploy", "Invalidate"]
    }
    error_message = "dev pipelines must run Build, Deploy (and Invalidate for web) without an Approval stage"
  }
}

run "sit_stage_order_has_approval_before_deploy" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
    branch              = "main"
    approval_required   = true
    fn_deploy_strategy  = "Canary10Percent5Minutes"
  }

  assert {
    condition = { for k, s in local.pipeline_stages : k => [for stage in s : stage.name] } == {
      api = ["Build", "Approval", "Deploy"]
      fn  = ["Build", "Approval", "Deploy"]
      web = ["Build", "Approval", "Deploy", "Invalidate"]
    }
    error_message = "sit pipelines must have a manual Approval right before Deploy (K6)"
  }

  assert {
    condition     = alltrue([for s in values(local.pipeline_stages) : [for a in s[1].actions : { category = a.category, provider = a.provider }] == [{ category = "Approval", provider = "Manual" }]])
    error_message = "The Approval stage must hold one manual approval action"
  }
}

# D7: the module generates the only Source stage, with DetectChanges = "false" and no trigger (locked by the
# codepipeline module tests); the stack must not add another source or a pipeline the module did not build.
run "pipelines_only_start_manually" {
  command = plan

  assert {
    condition     = alltrue(flatten([for s in values(local.pipeline_stages) : [for stage in s : stage.name != "Source" && alltrue([for a in stage.actions : a.category != "Source"])]]))
    error_message = "The stack must not add a Source stage or action; the module's Source never detects changes"
  }

  assert {
    condition     = local.git_source == { connection_arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000", repository = "example-org/example-app", branch = "develop" }
    error_message = "The pipelines must read the repo through foundation's connection, on the branch from tfvars"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*source\\s*=\\s*\"app.terraform.io/libterty/codepipeline/aws\"\\s*\\n\\s*version\\s*=\\s*\"~> 0\\.1\\.0\"", file("${path.module}/pipelines.tf"))) == 1
    error_message = "The pipelines must come from codepipeline 0.1, whose tests lock DetectChanges = false and no trigger"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*(DetectChanges|trigger)\\s*=", file("${path.module}/pipelines.tf"))) == 0
    error_message = "The stack must not touch DetectChanges or add a trigger"
  }
}

run "build_actions_export_build_variables" {
  command = plan

  assert {
    condition = alltrue([for s in values(local.pipeline_stages) : (
      s[0].actions[0].provider == "CodeBuild" && s[0].actions[0].namespace == "BuildVariables" &&
      s[0].actions[0].input_artifacts == ["SourceArtifact"]
    )])
    error_message = "Every Build action must build from SourceArtifact and export its variables as BuildVariables"
  }

  assert {
    condition = (
      local.pipeline_stages["api"][0].actions[0].configuration == { ProjectName = "cicd-dev-api-build" } &&
      local.pipeline_stages["fn"][0].actions[0].configuration == { ProjectName = "cicd-dev-fn-build" } &&
      local.pipeline_stages["web"][0].actions[0].configuration == { ProjectName = "cicd-dev-web-build" }
    )
    error_message = "Each pipeline must build with its own project"
  }
}

# K3 and design 5.4: the api is deployed by the api-deploy project with the image the build pushed.
run "api_deploys_with_the_deploy_project" {
  command = plan

  assert {
    condition = local.pipeline_stages["api"][1].actions[0] == {
      name     = "Deploy"
      category = "Build"
      provider = "CodeBuild"
      configuration = {
        ProjectName          = "cicd-dev-api-deploy"
        EnvironmentVariables = "[{\"name\":\"IMAGE_URI\",\"type\":\"PLAINTEXT\",\"value\":\"#{BuildVariables.IMAGE_URI}\"}]"
      }
      input_artifacts = ["SourceArtifact"]
    }
    error_message = "api Deploy must run api-deploy with IMAGE_URI = #{BuildVariables.IMAGE_URI}"
  }
}

run "fn_deploys_the_published_version_to_live" {
  command = plan

  assert {
    condition = local.pipeline_stages["fn"][1].actions[0] == {
      name     = "Deploy"
      category = "Deploy"
      provider = "Lambda"
      configuration = {
        FunctionName           = "cicd-dev-fn"
        FunctionAlias          = "live"
        PublishedTargetVersion = "#{BuildVariables.VERSION}"
        DeployStrategy         = "AllAtOnce"
      }
    }
    error_message = "fn Deploy must move the live alias of cicd-dev-fn to #{BuildVariables.VERSION}, AllAtOnce in dev, with no input artifact"
  }
}

run "fn_deploys_canary_in_sit" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
    branch              = "main"
    approval_required   = true
    fn_deploy_strategy  = "Canary10Percent5Minutes"
  }

  assert {
    condition     = local.pipeline_stages["fn"][2].actions[0].configuration.DeployStrategy == "Canary10Percent5Minutes"
    error_message = "fn Deploy must shift traffic Canary10Percent5Minutes in sit"
  }
}

run "web_deploys_to_the_bucket_then_invalidates" {
  command = plan

  assert {
    condition     = local.pipeline_stages["web"][0].actions[0].output_artifacts == ["BuildArtifact"]
    error_message = "web Build must hand its output to the S3 deploy action"
  }

  assert {
    condition = local.pipeline_stages["web"][1].actions[0] == {
      name            = "Deploy"
      category        = "Deploy"
      provider        = "S3"
      configuration   = { BucketName = "cicd-dev-web-111111111111", Extract = "true" }
      input_artifacts = ["BuildArtifact"]
    }
    error_message = "web Deploy must extract BuildArtifact into the web bucket"
  }

  assert {
    condition = local.pipeline_stages["web"][2].actions[0] == {
      name            = "Invalidate"
      category        = "Build"
      provider        = "CodeBuild"
      configuration   = { ProjectName = "cicd-dev-web-invalidate" }
      input_artifacts = ["SourceArtifact"]
    }
    error_message = "web Invalidate must run web-invalidate after Deploy"
  }
}

run "pipelines_use_the_shared_role_bucket_and_key" {
  command = plan

  assert {
    condition = (
      length(local.pipeline_stages) == 3 &&
      length(regexall("(?m)^\\s*role_arn\\s*=\\s*module\\.in\\.strings\\[\"pipeline_role_arn\"\\]\\s*$", file("${path.module}/pipelines.tf"))) == 1 &&
      length(regexall("(?m)^\\s*artifact_kms_key_arn\\s*=\\s*module\\.in\\.strings\\[\"kms_key_arn\"\\]\\s*$", file("${path.module}/pipelines.tf"))) == 1
    )
    error_message = "The three pipelines must use iam's pipeline role and the shared key"
  }
}

# K7: one rule, only FAILED runs of these three pipelines, to the alert topic.
run "failures_go_to_the_alert_topic" {
  command = plan

  assert {
    condition = jsonencode(local.failure_rule.event_pattern) == jsonencode({
      detail        = { pipeline = ["cicd-dev-api", "cicd-dev-fn", "cicd-dev-web"], state = ["FAILED"] }
      "detail-type" = ["CodePipeline Pipeline Execution State Change"]
      source        = ["aws.codepipeline"]
    })
    error_message = "The rule must match only FAILED executions of the three pipelines"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*targets\\s*=\\s*\\{\\s*alerts\\s*=\\s*\\{\\s*arn\\s*=\\s*module\\.in\\.strings\\[\"alert_topic_arn\"\\]\\s*\\}\\s*\\}\\s*$", file("${path.module}/alerts.tf"))) == 1
    error_message = "The rule's only target must be foundation's alert topic"
  }
}

run "build_logs_follow_the_env_retention" {
  command = plan

  assert {
    condition     = length(regexall("(?m)^\\s*log_retention_days\\s*=\\s*var\\.log_retention_days\\s*$", file("${path.module}/builds.tf"))) == 1
    error_message = "The build projects must keep their logs var.log_retention_days"
  }
}

run "publishes_the_pipeline_names" {
  command = plan

  assert {
    condition = local.published_strings == {
      api_pipeline_name = "cicd-dev-api"
      fn_pipeline_name  = "cicd-dev-fn"
      web_pipeline_name = "cicd-dev-web"
    }
    error_message = "pipeline must publish the three pipeline names"
  }
}

run "fn_deploy_strategy_rejects_unknown_values" {
  command = plan

  variables {
    fn_deploy_strategy = "Rolling"
  }

  expect_failures = [var.fn_deploy_strategy]
}

run "repository_must_be_owner_and_name" {
  command = plan

  variables {
    repository = "https://github.com/example-org/example-app"
  }

  expect_failures = [var.repository]
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
