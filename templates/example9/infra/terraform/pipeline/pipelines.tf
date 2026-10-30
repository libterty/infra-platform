# One pipeline per component (design 8.2, K4), all on the same repo and branch. The codepipeline module adds the
# Source stage with DetectChanges = "false" and no trigger, so a pipeline only runs when someone starts it (D7).
locals {
  # Must match pipeline_names in iam/naming.tf: the pipeline role trusts only <name_prefix>-* pipelines and its
  # Lambda deploy log group is named after the fn pipeline.
  pipeline_names = {
    api = "${local.name_prefix}-api"
    fn  = "${local.name_prefix}-fn"
    web = "${local.name_prefix}-web"
  }

  # K6: a second confirmation in the envs that need one, so nobody deploys to the wrong env by accident.
  approval_stages = var.approval_required ? [{
    name = "Approval"
    actions = [{
      name          = "Approve"
      category      = "Approval"
      provider      = "Manual"
      configuration = { CustomData = "部署到 ${var.env} 之前請確認" }
    }]
  }] : []

  # Every Build action exports its buildspec's exported-variables under this namespace.
  build_namespace = "BuildVariables"

  pipeline_stages = {
    api = concat(
      [{
        name = "Build"
        actions = [{
          name            = "Build"
          category        = "Build"
          provider        = "CodeBuild"
          configuration   = { ProjectName = module.build["api_build"].name }
          input_artifacts = ["SourceArtifact"]
          namespace       = local.build_namespace
        }]
      }],
      local.approval_stages,
      [{
        name = "Deploy"
        actions = [{
          name     = "Deploy"
          category = "Build"
          provider = "CodeBuild"
          configuration = {
            ProjectName          = module.build["api_deploy"].name
            EnvironmentVariables = jsonencode([{ name = "IMAGE_URI", value = "#{${local.build_namespace}.IMAGE_URI}", type = "PLAINTEXT" }])
          }
          # Only for the buildspec; the image comes from the variable.
          input_artifacts = ["SourceArtifact"]
        }]
      }],
    )

    fn = concat(
      [{
        name = "Build"
        actions = [{
          name            = "Build"
          category        = "Build"
          provider        = "CodeBuild"
          configuration   = { ProjectName = module.build["fn_build"].name }
          input_artifacts = ["SourceArtifact"]
          namespace       = local.build_namespace
        }]
      }],
      local.approval_stages,
      [{
        name = "Deploy"
        # The Build stage already published the version; this action only moves the alias to it, so it takes no
        # input artifact.
        actions = [{
          name     = "Deploy"
          category = "Deploy"
          provider = "Lambda"
          configuration = {
            FunctionName           = module.in.strings["fn_function_name"]
            FunctionAlias          = module.in.strings["fn_alias_name"]
            PublishedTargetVersion = "#{${local.build_namespace}.VERSION}"
            DeployStrategy         = var.fn_deploy_strategy
          }
        }]
      }],
    )

    web = concat(
      [{
        name = "Build"
        actions = [{
          name             = "Build"
          category         = "Build"
          provider         = "CodeBuild"
          configuration    = { ProjectName = module.build["web_build"].name }
          input_artifacts  = ["SourceArtifact"]
          output_artifacts = ["BuildArtifact"]
          namespace        = local.build_namespace
        }]
      }],
      local.approval_stages,
      [
        {
          name = "Deploy"
          actions = [{
            name            = "Deploy"
            category        = "Deploy"
            provider        = "S3"
            configuration   = { BucketName = module.in.strings["web_bucket_name"], Extract = "true" }
            input_artifacts = ["BuildArtifact"]
          }]
        },
        {
          # The S3 deploy action does not touch the CloudFront cache.
          name = "Invalidate"
          actions = [{
            name            = "Invalidate"
            category        = "Build"
            provider        = "CodeBuild"
            configuration   = { ProjectName = module.build["web_invalidate"].name }
            input_artifacts = ["SourceArtifact"]
          }]
        },
      ],
    )
  }

  git_source = {
    connection_arn = module.in.strings["connection_arn"]
    repository     = var.repository
    branch         = var.branch
  }
}

module "pipeline" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/codepipeline/aws"
  version  = "~> 0.1.0"
  for_each = local.pipeline_stages

  name                 = local.pipeline_names[each.key]
  role_arn             = module.in.strings["pipeline_role_arn"]
  artifact_bucket_name = module.in.strings["artifact_bucket_name"]
  artifact_kms_key_arn = module.in.strings["kms_key_arn"]
  git_source           = local.git_source
  stages               = each.value
}
