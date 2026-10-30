terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "api_pipeline" {
  source = "../.."

  name                 = "alpha-sit-api"
  role_arn             = "arn:aws:iam::222222222222:role/alpha-sit-api-pipeline"
  artifact_bucket_name = "alpha-sit-pipeline-artifacts"
  artifact_kms_key_arn = "arn:aws:kms:ap-northeast-1:222222222222:key/11111111-2222-3333-4444-555555555555"

  git_source = {
    connection_arn = "arn:aws:codeconnections:ap-northeast-1:222222222222:connection/11111111-2222-3333-4444-555555555555"
    repository     = "example-org/example-app"
    branch         = "main"
  }

  stages = [
    {
      name = "Build"
      actions = [{
        name             = "api-build"
        category         = "Build"
        provider         = "CodeBuild"
        configuration    = { ProjectName = "alpha-sit-api-build" }
        input_artifacts  = ["SourceArtifact"]
        output_artifacts = ["BuildArtifact"]
        namespace        = "BuildVariables"
      }]
    },
    {
      name = "Approval"
      actions = [{
        name          = "approve"
        category      = "Approval"
        provider      = "Manual"
        configuration = { CustomData = "Deploy #{SourceVariables.CommitId} to sit" }
      }]
    },
    {
      name = "Deploy"
      actions = [{
        name     = "api-deploy"
        category = "Build"
        provider = "CodeBuild"
        configuration = {
          ProjectName = "alpha-sit-api-deploy"
          EnvironmentVariables = jsonencode([
            { name = "IMAGE_URI", value = "#{BuildVariables.IMAGE_URI}", type = "PLAINTEXT" }
          ])
        }
        input_artifacts = ["SourceArtifact"]
      }]
    }
  ]

  tags = {
    Project = "alpha"
  }
}

output "pipeline_name" {
  value = module.api_pipeline.name
}
