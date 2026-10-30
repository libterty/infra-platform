# Naming rules shared with the stacks applied after iam (application, web, pipeline). Those resources do not exist
# when iam is applied, so their ARNs are built from these names; the later stacks must use exactly the same names, and
# their tests pin the same strings.
#   application: ECS cluster <name_prefix>, service and task definition family <name_prefix>-api (ecs-service names
#                the family after the service and creates the log group /ecs/<name>); Lambda <name_prefix>-fn
#                (lambda-function creates /aws/lambda/<name>), whose alias is covered by <function ARN>:*.
#   web:         the SPA bucket <name_prefix>-web-<account>; the distribution ID is random, so web-invalidate is
#                scoped by the tags the web stack's provider puts on it (see policies.tf).
#   pipeline:    CodeBuild projects <name_prefix>-<project key> with the log group /aws/codebuild/<name> (the
#                codebuild-project default), and the pipelines <name_prefix>-api, -fn and -web.
locals {
  arn = {
    logs       = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}"
    ecs        = "arn:aws:ecs:${var.aws_region}:${var.expected_account_id}"
    lambda     = "arn:aws:lambda:${var.aws_region}:${var.expected_account_id}"
    codebuild  = "arn:aws:codebuild:${var.aws_region}:${var.expected_account_id}"
    pipeline   = "arn:aws:codepipeline:${var.aws_region}:${var.expected_account_id}"
    ecr        = "arn:aws:ecr:${var.aws_region}:${var.expected_account_id}"
    cloudfront = "arn:aws:cloudfront::${var.expected_account_id}"
  }

  ecs_cluster_name = local.name_prefix
  api_service_name = "${local.name_prefix}-api"
  api_task_family  = local.api_service_name
  api_log_group    = "/ecs/${local.api_service_name}"

  fn_function_name = "${local.name_prefix}-fn"
  fn_log_group     = "/aws/lambda/${local.fn_function_name}"

  web_bucket_name = "${local.name_prefix}-web-${var.expected_account_id}"
  # Tags the web stack's provider puts on the distribution (common.tf common_tags plus Stack).
  web_distribution_tags = merge(local.common_tags, { Stack = "web" })

  build_project_names = {
    api_build      = "${local.name_prefix}-api-build"
    api_deploy     = "${local.name_prefix}-api-deploy"
    fn_build       = "${local.name_prefix}-fn-build"
    web_build      = "${local.name_prefix}-web-build"
    web_invalidate = "${local.name_prefix}-web-invalidate"
  }
  pipeline_names = {
    api = "${local.name_prefix}-api"
    fn  = "${local.name_prefix}-fn"
    web = "${local.name_prefix}-web"
  }

  api_service_arn     = "${local.arn.ecs}:service/${local.ecs_cluster_name}/${local.api_service_name}"
  api_task_family_arn = "${local.arn.ecs}:task-definition/${local.api_task_family}:*"
  fn_function_arn     = "${local.arn.lambda}:function:${local.fn_function_name}"
  web_bucket_arn      = "arn:aws:s3:::${local.web_bucket_name}"
  build_project_arns  = { for k, n in local.build_project_names : k => "${local.arn.codebuild}:project/${n}" }
  build_log_group_arns = {
    for k, n in local.build_project_names : k => "${local.arn.logs}:log-group:/aws/codebuild/${n}"
  }
}
