terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.107, < 2.0"
    }
  }
}

provider "awscc" {
  region = "ap-northeast-1"
}

module "inference" {
  source = "../.."

  artifact_bucket_name = "alpha-dev-greengrass-artifacts"

  recipe = {
    RecipeFormatVersion  = "2020-01-25"
    ComponentName        = "com.example.Inference"
    ComponentVersion     = "1.0.0"
    ComponentDescription = "Runs the model on sensor data."
    ComponentPublisher   = "example.com"
    Manifests = [
      {
        Platform  = { os = "linux" }
        Lifecycle = { Run = "python3 -u {artifacts:path}/inference.py" }
        Artifacts = [
          { Uri = "s3://alpha-dev-greengrass-artifacts/artifacts/com.example.Inference/1.0.0/inference.py" },
        ]
      },
    ]
  }

  tags = {
    Project     = "alpha"
    Environment = "dev"
  }
}

output "component_arn" {
  value = module.inference.arn
}
