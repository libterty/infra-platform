mock_provider "aws" {
  mock_resource "aws_codepipeline" {
    defaults = {
      arn = "arn:aws:codepipeline:ap-northeast-1:111111111111:alpha-dev-api"
    }
  }
}

variables {
  name                 = "alpha-dev-api"
  role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-api-pipeline"
  artifact_bucket_name = "alpha-dev-pipeline-artifacts"
  artifact_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"

  git_source = {
    connection_arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/11111111-2222-3333-4444-555555555555"
    repository     = "example-org/example-app"
    branch         = "develop"
  }

  stages = [
    {
      name = "Build"
      actions = [
        {
          name             = "api-build"
          category         = "Build"
          provider         = "CodeBuild"
          configuration    = { ProjectName = "alpha-dev-api-build" }
          input_artifacts  = ["SourceArtifact"]
          output_artifacts = ["BuildArtifact"]
          namespace        = "BuildVariables"
        }
      ]
    },
    {
      name = "Deploy"
      actions = [
        {
          name     = "api-deploy"
          category = "Build"
          provider = "CodeBuild"
          configuration = {
            ProjectName          = "alpha-dev-api-deploy"
            EnvironmentVariables = "[{\"name\":\"IMAGE_URI\",\"value\":\"#{BuildVariables.IMAGE_URI}\",\"type\":\"PLAINTEXT\"}]"
          }
          input_artifacts = ["SourceArtifact"]
        }
      ]
    }
  ]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "source_build_deploy" {
  command = plan

  assert {
    condition     = aws_codepipeline.this.pipeline_type == "V2"
    error_message = "The pipeline must be V2"
  }

  assert {
    condition     = length(aws_codepipeline.this.trigger) == 0
    error_message = "The pipeline must not have a trigger; it only runs manually"
  }

  assert {
    condition     = aws_codepipeline.this.execution_mode == "QUEUED"
    error_message = "execution_mode must default to QUEUED"
  }

  assert {
    condition     = aws_codepipeline.this.name == "alpha-dev-api" && aws_codepipeline.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-api-pipeline"
    error_message = "name and role_arn must be passed through"
  }

  assert {
    condition     = one(aws_codepipeline.this.artifact_store).type == "S3" && one(aws_codepipeline.this.artifact_store).location == "alpha-dev-pipeline-artifacts"
    error_message = "The artifact store must be the given S3 bucket"
  }

  assert {
    condition = one(one(aws_codepipeline.this.artifact_store).encryption_key) == {
      id   = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
      type = "KMS"
    }
    error_message = "Artifacts must be encrypted with the given KMS key"
  }

  assert {
    condition     = [for s in aws_codepipeline.this.stage : s.name] == ["Source", "Build", "Deploy"]
    error_message = "The module must prepend the Source stage to the given stages"
  }

  assert {
    condition     = length(aws_codepipeline.this.stage[0].action) == 1
    error_message = "The Source stage must have exactly one action"
  }

  assert {
    condition = (
      aws_codepipeline.this.stage[0].action[0].name == "Source" &&
      aws_codepipeline.this.stage[0].action[0].category == "Source" &&
      aws_codepipeline.this.stage[0].action[0].owner == "AWS" &&
      aws_codepipeline.this.stage[0].action[0].provider == "CodeStarSourceConnection" &&
      aws_codepipeline.this.stage[0].action[0].version == "1"
    )
    error_message = "The Source action must be an AWS CodeStarSourceConnection action, version 1"
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration["DetectChanges"] == "false"
    error_message = "DetectChanges must be false so a push does not start the pipeline"
  }

  assert {
    condition = aws_codepipeline.this.stage[0].action[0].configuration == tomap({
      ConnectionArn        = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/11111111-2222-3333-4444-555555555555"
      FullRepositoryId     = "example-org/example-app"
      BranchName           = "develop"
      DetectChanges        = "false"
      OutputArtifactFormat = "CODE_ZIP"
    })
    error_message = "The Source action configuration must be exactly the connection, repository, branch, DetectChanges and CODE_ZIP"
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].output_artifacts == tolist(["SourceArtifact"]) && aws_codepipeline.this.stage[0].action[0].namespace == "SourceVariables"
    error_message = "The Source action must output SourceArtifact in the SourceVariables namespace"
  }

  assert {
    condition = (
      aws_codepipeline.this.stage[1].action[0].name == "api-build" &&
      aws_codepipeline.this.stage[1].action[0].category == "Build" &&
      aws_codepipeline.this.stage[1].action[0].provider == "CodeBuild" &&
      aws_codepipeline.this.stage[1].action[0].configuration == tomap({ ProjectName = "alpha-dev-api-build" }) &&
      aws_codepipeline.this.stage[1].action[0].input_artifacts == tolist(["SourceArtifact"]) &&
      aws_codepipeline.this.stage[1].action[0].output_artifacts == tolist(["BuildArtifact"]) &&
      aws_codepipeline.this.stage[1].action[0].namespace == "BuildVariables"
    )
    error_message = "Build action fields must be passed through"
  }

  assert {
    condition     = alltrue(flatten([for s in aws_codepipeline.this.stage : [for a in s.action : a.owner == "AWS" && a.version == "1"]]))
    error_message = "Every action must be owner AWS, version 1"
  }

  assert {
    condition     = aws_codepipeline.this.stage[2].action[0].configuration["EnvironmentVariables"] == "[{\"name\":\"IMAGE_URI\",\"value\":\"#{BuildVariables.IMAGE_URI}\",\"type\":\"PLAINTEXT\"}]"
    error_message = "Variable references in configuration must be passed through unchanged"
  }

  assert {
    condition     = length(aws_codepipeline.this.stage[2].action[0].output_artifacts) == 0 && aws_codepipeline.this.stage[2].action[0].namespace == null
    error_message = "Optional action fields must stay unset when not given"
  }

  assert {
    condition     = length(aws_codepipeline.this.variable) == 0
    error_message = "No pipeline variables by default"
  }

  assert {
    condition     = aws_codepipeline.this.tags == tomap({ Name = "alpha-dev-api" })
    error_message = "Name tag must be added"
  }
}

run "manual_approval_and_lambda_deploy" {
  command = plan

  variables {
    name = "alpha-sit-fn"
    git_source = {
      connection_arn = "arn:aws:codestar-connections:ap-northeast-1:222222222222:connection/11111111-2222-3333-4444-555555555555"
      repository     = "example-org/example-app"
      branch         = "main"
    }
    stages = [
      {
        name = "Build"
        actions = [
          {
            name             = "fn-build"
            category         = "Build"
            provider         = "CodeBuild"
            configuration    = { ProjectName = "alpha-sit-fn-build" }
            input_artifacts  = ["SourceArtifact"]
            output_artifacts = ["BuildArtifact"]
            namespace        = "BuildVariables"
          }
        ]
      },
      {
        name = "Approval"
        actions = [
          {
            name     = "approve"
            category = "Approval"
            provider = "Manual"
            configuration = {
              CustomData = "Deploy #{SourceVariables.CommitId} to sit"
            }
          }
        ]
      },
      {
        name = "Deploy"
        actions = [
          {
            name     = "fn-deploy"
            category = "Deploy"
            provider = "Lambda"
            configuration = {
              FunctionName           = "alpha-sit-fn"
              FunctionAlias          = "live"
              PublishedTargetVersion = "#{BuildVariables.VERSION}"
              DeployStrategy         = "Canary10Percent5Minutes"
            }
            run_order = 2
          }
        ]
      }
    ]
  }

  assert {
    condition     = [for s in aws_codepipeline.this.stage : s.name] == ["Source", "Build", "Approval", "Deploy"]
    error_message = "Stages must keep the given order after Source"
  }

  assert {
    condition     = aws_codepipeline.this.stage[2].action[0].category == "Approval" && aws_codepipeline.this.stage[2].action[0].provider == "Manual" && aws_codepipeline.this.stage[2].action[0].owner == "AWS"
    error_message = "The approval action must be an AWS Manual approval"
  }

  assert {
    condition     = length(aws_codepipeline.this.stage[2].action[0].input_artifacts) == 0
    error_message = "An approval action has no input artifacts"
  }

  assert {
    condition     = aws_codepipeline.this.stage[3].action[0].configuration["PublishedTargetVersion"] == "#{BuildVariables.VERSION}" && aws_codepipeline.this.stage[3].action[0].run_order == 2
    error_message = "Lambda deploy configuration and run_order must be passed through"
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration["BranchName"] == "main" && aws_codepipeline.this.stage[0].action[0].configuration["ConnectionArn"] == "arn:aws:codestar-connections:ap-northeast-1:222222222222:connection/11111111-2222-3333-4444-555555555555"
    error_message = "A codestar-connections ARN and the branch must be passed through"
  }

  assert {
    condition     = aws_codepipeline.this.stage[0].action[0].configuration["DetectChanges"] == "false" && length(aws_codepipeline.this.trigger) == 0
    error_message = "Change detection must stay off"
  }
}

run "pipeline_variables" {
  command = plan

  variables {
    variables = {
      DEPLOY_NOTE = {
        default_value = "manual"
        description   = "Free text shown in the execution"
      }
      TARGET = {}
    }
  }

  assert {
    condition     = length(aws_codepipeline.this.variable) == 2
    error_message = "Every pipeline variable must be declared"
  }

  assert {
    condition = [for v in aws_codepipeline.this.variable : v if v.name == "DEPLOY_NOTE"][0].default_value == "manual" && [
      for v in aws_codepipeline.this.variable : v if v.name == "DEPLOY_NOTE"
    ][0].description == "Free text shown in the execution"
    error_message = "Variable default_value and description must be passed through"
  }

  assert {
    condition     = [for v in aws_codepipeline.this.variable : v if v.name == "TARGET"][0].default_value == null
    error_message = "A variable without a default keeps it unset"
  }
}

run "region_execution_mode_and_tags" {
  command = plan

  variables {
    region         = "ap-northeast-1"
    execution_mode = "SUPERSEDED"
    tags           = { Project = "alpha" }
  }

  assert {
    condition     = aws_codepipeline.this.region == "ap-northeast-1"
    error_message = "The pipeline must be placed in the given region"
  }

  assert {
    condition     = aws_codepipeline.this.execution_mode == "SUPERSEDED"
    error_message = "execution_mode must be passed through"
  }

  assert {
    condition     = aws_codepipeline.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-api" })
    error_message = "Given tags must be merged with Name"
  }
}

run "apply_outputs" {
  command = apply

  assert {
    condition     = output.name == "alpha-dev-api" && output.arn == "arn:aws:codepipeline:ap-northeast-1:111111111111:alpha-dev-api"
    error_message = "Outputs must expose the pipeline name and ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "source_category_in_stages_rejected" {
  command = plan

  variables {
    stages = [
      {
        name = "Source2"
        actions = [
          {
            name             = "extra-source"
            category         = "Source"
            provider         = "CodeStarSourceConnection"
            output_artifacts = ["Other"]
          }
        ]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "unknown_category_rejected" {
  command = plan

  variables {
    stages = [
      {
        name = "Build"
        actions = [
          {
            name     = "run"
            category = "Compute"
            provider = "Commands"
          }
        ]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "duplicate_stage_names_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Build"
        actions = [{ name = "a", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" } }]
      },
      {
        name    = "Build"
        actions = [{ name = "b", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "b" } }]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "stage_named_source_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Source"
        actions = [{ name = "a", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" } }]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "no_stages_rejected" {
  command = plan

  variables {
    stages = []
  }

  expect_failures = [var.stages]
}

run "stage_without_actions_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Build"
        actions = []
      }
    ]
  }

  expect_failures = [var.stages]
}

run "duplicate_action_names_rejected" {
  command = plan

  variables {
    stages = [
      {
        name = "Build"
        actions = [
          { name = "a", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" } },
          { name = "a", category = "Test", provider = "CodeBuild", configuration = { ProjectName = "b" } }
        ]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "repository_format_rejected" {
  command = plan

  variables {
    git_source = {
      connection_arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/11111111-2222-3333-4444-555555555555"
      repository     = "example-app"
      branch         = "develop"
    }
  }

  expect_failures = [var.git_source]
}

run "connection_arn_format_rejected" {
  command = plan

  variables {
    git_source = {
      connection_arn = "11111111-2222-3333-4444-555555555555"
      repository     = "example-org/example-app"
      branch         = "develop"
    }
  }

  expect_failures = [var.git_source]
}

run "empty_branch_rejected" {
  command = plan

  variables {
    git_source = {
      connection_arn = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/11111111-2222-3333-4444-555555555555"
      repository     = "example-org/example-app"
      branch         = ""
    }
  }

  expect_failures = [var.git_source]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    artifact_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.artifact_kms_key_arn]
}

run "role_arn_format_rejected" {
  command = plan

  variables {
    role_arn = "alpha-dev-api-pipeline"
  }

  expect_failures = [var.role_arn]
}

run "bucket_name_format_rejected" {
  command = plan

  variables {
    artifact_bucket_name = "arn:aws:s3:::alpha-dev-pipeline-artifacts"
  }

  expect_failures = [var.artifact_bucket_name]
}

run "pipeline_name_format_rejected" {
  command = plan

  variables {
    name = "alpha dev api"
  }

  expect_failures = [var.name]
}

run "execution_mode_rejected" {
  command = plan

  variables {
    execution_mode = "SERIAL"
  }

  expect_failures = [var.execution_mode]
}

run "variable_name_rejected" {
  command = plan

  variables {
    variables = {
      "BAD NAME" = {}
    }
  }

  expect_failures = [var.variables]
}

run "region_format_rejected" {
  command = plan

  variables {
    region = "tokyo"
  }

  expect_failures = [var.region]
}

run "stage_name_format_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Build stage"
        actions = [{ name = "a", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" } }]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "action_name_format_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Build"
        actions = [{ name = "api build", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" } }]
      }
    ]
  }

  expect_failures = [var.stages]
}

run "run_order_rejected" {
  command = plan

  variables {
    stages = [
      {
        name    = "Build"
        actions = [{ name = "a", category = "Build", provider = "CodeBuild", configuration = { ProjectName = "a" }, run_order = 0 }]
      }
    ]
  }

  expect_failures = [var.stages]
}
