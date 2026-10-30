# Permissions of every role (design 4 and 4.1): each touches only its own component. Every Resource comes from a key
# foundation or containerimage publishes, or from the naming rules in naming.tf. The action lists follow the AWS
# service authorization reference and the CodePipeline action references; they are not yet verified against a real
# account.
locals {
  kms_key_arn         = module.in.strings["kms_key_arn"]
  artifact_bucket_arn = "arn:aws:s3:::${module.in.strings["artifact_bucket_name"]}"
  connection_arn      = module.in.strings["connection_arn"]
  repository_arns = {
    api = "${local.arn.ecr}:repository/${split("/", module.in.strings["api_repository_url"])[1]}"
    fn  = "${local.arn.ecr}:repository/${split("/", module.in.strings["fn_repository_url"])[1]}"
  }
  same_account = { StringEquals = { "aws:ResourceAccount" = var.expected_account_id } }

  # ecr:GetAuthorizationToken has no resource type; AWS requires Resource "*" for it.
  ecr_login_statement = {
    Sid      = "EcrLoginToken"
    Effect   = "Allow"
    Action   = ["ecr:GetAuthorizationToken"]
    Resource = ["*"]
  }
  push_actions = [
    "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
    "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
  ]

  # What every build project needs: its own log group, the pipeline artifacts and the shared key. Only the projects
  # that build (and may hand an output artifact to the next stage) write artifacts; api-deploy and web-invalidate read.
  artifact_writers = ["api_build", "fn_build", "web_build"]
  build_base_statements = {
    for k in keys(local.build_project_names) : k => [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.build_log_group_arns[k]}:*"]
      },
      {
        Sid       = "ArtifactBucket"
        Effect    = "Allow"
        Action    = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource  = [local.artifact_bucket_arn]
        Condition = local.same_account
      },
      {
        Sid       = "ArtifactObjects"
        Effect    = "Allow"
        Action    = contains(local.artifact_writers, k) ? ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"] : ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = ["${local.artifact_bucket_arn}/*"]
        Condition = local.same_account
      },
      {
        # The artifacts are encrypted with the shared key, which is also the projects' encryption key.
        Sid      = "UseSharedKey"
        Effect   = "Allow"
        Action   = contains(local.artifact_writers, k) ? ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"] : ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [local.kms_key_arn]
      },
    ]
  }

  statement_lists = {
    api_execution = [
      {
        Sid      = "PullApiImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = [local.repository_arns["api"]]
      },
      local.ecr_login_statement,
      {
        Sid      = "WriteServiceLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.arn.logs}:log-group:${local.api_log_group}:*"]
      },
    ]

    fn = [
      {
        # lambda-function creates the log group, so the role only creates streams and writes events in it.
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.arn.logs}:log-group:${local.fn_log_group}:*"]
      },
    ]

    api_build = concat(local.build_base_statements["api_build"], [
      local.ecr_login_statement,
      {
        Sid      = "PushApiImage"
        Effect   = "Allow"
        Action   = local.push_actions
        Resource = [local.repository_arns["api"]]
      },
    ])

    # Design 5.4: read the latest revision of the family, register it again with the new image, update the service
    # and wait until it is stable.
    api_deploy = concat(local.build_base_statements["api_deploy"], [
      {
        # ecs:DescribeTaskDefinition has no resource type; AWS requires Resource "*" for it.
        Sid      = "DescribeTaskDefinition"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition"]
        Resource = ["*"]
      },
      {
        Sid      = "RegisterApiTaskDefinition"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition"]
        Resource = [local.api_task_family_arn]
      },
      {
        # Registering with the tags copied from the previous revision needs TagResource, only as part of the register.
        Sid       = "TagOnRegister"
        Effect    = "Allow"
        Action    = ["ecs:TagResource"]
        Resource  = [local.api_task_family_arn]
        Condition = { StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" } }
      },
      {
        # Only to a revision of the api family: otherwise the role could point the service at another family's task
        # role without needing iam:PassRole.
        Sid       = "UpdateApiService"
        Effect    = "Allow"
        Action    = ["ecs:UpdateService"]
        Resource  = [local.api_service_arn]
        Condition = { ArnLike = { "ecs:task-definition" = local.api_task_family_arn } }
      },
      {
        Sid      = "DescribeApiService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices"]
        Resource = [local.api_service_arn]
      },
      {
        Sid       = "PassApiTaskRoles"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = [module.role["api_execution"].arn, module.role["api_task"].arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
    ])

    fn_build = concat(local.build_base_statements["fn_build"], [
      local.ecr_login_statement,
      {
        Sid      = "PushFnImage"
        Effect   = "Allow"
        Action   = local.push_actions
        Resource = [local.repository_arns["fn"]]
      },
      {
        # Design 8.2: point $LATEST at the new image and publish a version; the pipeline's Lambda action moves the alias.
        Sid      = "UpdateFnCode"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:PublishVersion", "lambda:UpdateFunctionCode"]
        Resource = [local.fn_function_arn]
      },
    ])

    web_build = local.build_base_statements["web_build"]

    web_invalidate = concat(local.build_base_statements["web_invalidate"], [
      {
        # The distribution ID is random and the web stack comes after iam, so the scope is the tags the web stack's
        # provider sets on it: this project, this env, the web stack.
        Sid      = "InvalidateWebDistribution"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = ["${local.arn.cloudfront}:distribution/*"]
        Condition = {
          StringEquals = { for k, v in local.web_distribution_tags : "aws:ResourceTag/${k}" => v }
        }
      },
    ])

    pipeline = [
      {
        Sid       = "ArtifactBucket"
        Effect    = "Allow"
        Action    = ["s3:GetBucketAcl", "s3:GetBucketLocation", "s3:GetBucketVersioning"]
        Resource  = [local.artifact_bucket_arn]
        Condition = local.same_account
      },
      {
        Sid    = "ArtifactObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:GetObjectTagging", "s3:GetObjectVersion", "s3:GetObjectVersionTagging", "s3:PutObject",
          "s3:PutObjectAcl", "s3:PutObjectTagging",
        ]
        Resource  = ["${local.artifact_bucket_arn}/*"]
        Condition = local.same_account
      },
      {
        Sid      = "UseSharedKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = [local.kms_key_arn]
      },
      {
        # The CodeStarSourceConnection action reference requires both prefixes; the codestar-connections form of the
        # same ARN is listed too, since the module creates the connection under codeconnections.
        Sid      = "UseGitHubConnection"
        Effect   = "Allow"
        Action   = ["codeconnections:UseConnection", "codestar-connections:UseConnection"]
        Resource = distinct([local.connection_arn, replace(local.connection_arn, ":codeconnections:", ":codestar-connections:")])
      },
      {
        Sid      = "RunBuildProjects"
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = values(local.build_project_arns)
      },
      {
        # Lambda deploy action (fn pipeline): the list of its action reference, on the fn function and its alias and
        # versions. cloudwatch:DescribeAlarms is left out because the action has no Alarms configured.
        Sid    = "LambdaDeployFn"
        Effect = "Allow"
        Action = [
          "lambda:GetAlias", "lambda:GetFunctionConfiguration", "lambda:GetProvisionedConcurrencyConfig",
          "lambda:PublishVersion", "lambda:UpdateAlias", "lambda:UpdateFunctionCode",
        ]
        Resource = [local.fn_function_arn, "${local.fn_function_arn}:*"]
      },
      {
        # The Lambda deploy action logs to /<region>/codepipeline/<pipeline> (its action reference).
        Sid      = "LambdaDeployLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = [local.lambda_deploy_log_group_arn, "${local.lambda_deploy_log_group_arn}:*"]
      },
      {
        Sid      = "LambdaDeployLogEvents"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.lambda_deploy_log_group_arn}:log-stream:*"]
      },
      {
        # S3 deploy action (web pipeline): the list of its action reference, on the SPA bucket only.
        Sid    = "DeployWebBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl", "s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:PutObject", "s3:PutObjectAcl",
          "s3:PutObjectVersionAcl",
        ]
        Resource  = [local.web_bucket_arn, "${local.web_bucket_arn}/*"]
        Condition = local.same_account
      },
    ]
  }

  lambda_deploy_log_group_arn = "${local.arn.logs}:log-group:/${var.aws_region}/codepipeline/${local.pipeline_names["fn"]}"

  # Keyed by Sid so the tests can address one statement; the policy documents list them in Sid order.
  statements = { for role, list in local.statement_lists : role => { for s in list : s.Sid => s } }

  # The api task role has no permissions: the template's API calls no AWS service. Add a policy here when it does.
  role_policies = {
    for role, s in local.statements : role => { permissions = jsonencode({ Version = "2012-10-17", Statement = values(s) }) }
  }
}

module "policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role-policy/aws"
  version  = "~> 0.1.1"
  for_each = local.role_policies

  role_arn = module.role[each.key].arn
  policies = each.value
}
