locals {
  source_stage = {
    name = "Source"
    actions = [{
      name     = "Source"
      category = "Source"
      provider = "CodeStarSourceConnection"
      configuration = {
        ConnectionArn    = var.git_source.connection_arn
        FullRepositoryId = var.git_source.repository
        BranchName       = var.git_source.branch
        # D7: the pipeline only runs manually; DetectChanges defaults to true and would start it on every push.
        DetectChanges        = "false"
        OutputArtifactFormat = "CODE_ZIP"
      }
      input_artifacts  = []
      output_artifacts = ["SourceArtifact"]
      namespace        = "SourceVariables"
      run_order        = null
    }]
  }
}

resource "aws_codepipeline" "this" {
  name           = var.name
  role_arn       = var.role_arn
  pipeline_type  = "V2"
  execution_mode = var.execution_mode
  region         = var.region

  artifact_store {
    type     = "S3"
    location = var.artifact_bucket_name

    encryption_key {
      type = "KMS"
      id   = var.artifact_kms_key_arn
    }
  }

  dynamic "stage" {
    for_each = concat([local.source_stage], var.stages)
    content {
      name = stage.value.name

      dynamic "action" {
        for_each = stage.value.actions
        content {
          name             = action.value.name
          category         = action.value.category
          owner            = "AWS"
          provider         = action.value.provider
          version          = "1"
          configuration    = action.value.configuration
          input_artifacts  = action.value.input_artifacts
          output_artifacts = action.value.output_artifacts
          namespace        = action.value.namespace
          run_order        = action.value.run_order
        }
      }
    }
  }

  dynamic "variable" {
    for_each = var.variables
    content {
      name          = variable.key
      default_value = variable.value.default_value
      description   = variable.value.description
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
