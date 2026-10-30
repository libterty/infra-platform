# One role per component and per build project (design 4.1): no two of them share a role. Each trusts one service of
# this account; the CodeBuild roles also pin the project ARN, so another project cannot borrow them. The roles carry
# the trust policy only; iam-role-policy attaches the permissions.
locals {
  roles = merge(
    {
      api_execution = { name = "${local.name_prefix}-api-execution", service = "ecs-tasks.amazonaws.com", source_arn = null }
      api_task      = { name = "${local.name_prefix}-api-task", service = "ecs-tasks.amazonaws.com", source_arn = null }
      fn            = { name = "${local.name_prefix}-fn-lambda", service = "lambda.amazonaws.com", source_arn = null }
      # One role for the three pipelines; the trust allows only pipelines named with this prefix.
      pipeline = {
        name       = "${local.name_prefix}-pipeline"
        service    = "codepipeline.amazonaws.com"
        source_arn = "${local.arn.pipeline}:${local.name_prefix}-*"
      }
    },
    {
      for k, n in local.build_project_names : k => {
        name       = "${n}-codebuild"
        service    = "codebuild.amazonaws.com"
        source_arn = local.build_project_arns[k]
      }
    },
  )
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.5.0"
  for_each = local.roles

  name  = each.value.name
  trust = { service_principals = [each.value.service], source_account = var.expected_account_id, source_arn = each.value.source_arn }
}
