mock_provider "awscc" {}

variables {
  artifact_bucket_name = "alpha-dev-greengrass-artifacts"

  recipe = {
    RecipeFormatVersion  = "2020-01-25"
    ComponentName        = "com.example.Inference"
    ComponentVersion     = "1.0.0"
    ComponentDescription = "Runs the model on sensor data."
    ComponentPublisher   = "example.com"
    Manifests = [
      {
        Platform = { os = "linux" }
        Lifecycle = {
          Run = "python3 -u {artifacts:path}/inference.py"
        }
        Artifacts = [
          { Uri = "s3://alpha-dev-greengrass-artifacts/artifacts/com.example.Inference/1.0.0/inference.py" },
          { Uri = "s3://alpha-dev-greengrass-artifacts/artifacts/com.example.Inference/1.0.0/model.onnx" },
        ]
      },
    ]
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "object_recipe_is_json_encoded" {
  command = plan

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentName == "com.example.Inference"
    error_message = "The recipe object must be sent as the inline recipe"
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentVersion == "1.0.0"
    error_message = "The component version must come from the recipe"
  }

  assert {
    condition     = length(jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).Manifests[0].Artifacts) == 2
    error_message = "Artifacts must be passed through"
  }
}

run "json_string_recipe" {
  command = plan

  variables {
    recipe      = null
    recipe_json = <<-JSON
      {
        "RecipeFormatVersion": "2020-01-25",
        "ComponentName": "com.example.Collector",
        "ComponentVersion": "2.1.0-rc.1",
        "Manifests": [
          {
            "Platform": { "os": "linux" },
            "Lifecycle": { "Run": "{artifacts:path}/collector" },
            "Artifacts": [ { "Uri": "s3://alpha-dev-greengrass-artifacts/artifacts/com.example.Collector/2.1.0-rc.1/collector" } ]
          }
        ]
      }
    JSON
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentName == "com.example.Collector"
    error_message = "The JSON recipe must be sent as the inline recipe"
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentVersion == "2.1.0-rc.1"
    error_message = "A semver pre-release version must be accepted"
  }
}

run "recipe_without_artifacts_is_accepted" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Hello"
      ComponentVersion    = "0.1.0"
      Manifests = [
        { Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } },
      ]
    }
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentName == "com.example.Hello"
    error_message = "A recipe without artifacts must be accepted"
  }
}

run "generic_component_type_is_accepted" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Hello"
      ComponentVersion    = "0.1.0"
      ComponentType       = "aws.greengrass.generic"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_component_version.this.inline_recipe).ComponentType == "aws.greengrass.generic"
    error_message = "aws.greengrass.generic must be accepted"
  }
}

run "tags_are_a_map_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha", Environment = "dev" }
  }

  assert {
    condition     = awscc_greengrassv2_component_version.this.tags == tomap({ Project = "alpha", Environment = "dev", Name = "com.example.Inference" })
    error_message = "Tags must be a map of the given tags plus Name"
  }
}

run "outputs_after_apply" {
  override_resource {
    target = awscc_greengrassv2_component_version.this
    values = {
      arn               = "arn:aws:greengrass:ap-northeast-1:111111111111:components:com.example.Inference:versions:1.0.0"
      component_name    = "com.example.Inference"
      component_version = "1.0.0"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:greengrass:ap-northeast-1:111111111111:components:com.example.Inference:versions:1.0.0"
    error_message = "arn output must be the component version ARN"
  }

  assert {
    condition     = output.component_name == "com.example.Inference" && output.component_version == "1.0.0"
    error_message = "Name and version outputs must come from the component version"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "both_recipes_rejected" {
  command = plan

  variables {
    recipe_json = "{\"RecipeFormatVersion\":\"2020-01-25\",\"ComponentName\":\"com.example.Other\",\"ComponentVersion\":\"1.0.0\"}"
  }

  expect_failures = [var.recipe_json]
}

run "no_recipe_rejected" {
  command = plan

  variables {
    recipe = null
  }

  expect_failures = [var.recipe_json]
}

run "recipe_json_not_json_rejected" {
  command = plan

  variables {
    recipe      = null
    recipe_json = "ComponentName: com.example.Inference"
  }

  expect_failures = [var.recipe_json]
}

run "version_not_semver_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Hello"
      ComponentVersion    = "1.0"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "missing_component_name_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentVersion    = "1.0.0"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "invalid_component_name_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com example/hello"
      ComponentVersion    = "1.0.0"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "aws_greengrass_component_name_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "aws.greengrass.Nucleus"
      ComponentVersion    = "1.0.0"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "wrong_recipe_format_version_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2019-01-01"
      ComponentName       = "com.example.Hello"
      ComponentVersion    = "1.0.0"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = { Run = "echo hello" } }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "artifact_in_another_bucket_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Inference"
      ComponentVersion    = "1.0.0"
      Manifests = [
        {
          Platform  = { os = "linux" }
          Lifecycle = { Run = "python3 {artifacts:path}/inference.py" }
          Artifacts = [
            { Uri = "s3://alpha-dev-greengrass-artifacts/artifacts/com.example.Inference/1.0.0/inference.py" },
            { Uri = "s3://someone-else/inference.py" },
          ]
        },
      ]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "artifact_bucket_prefix_lookalike_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Inference"
      ComponentVersion    = "1.0.0"
      Manifests = [
        {
          Platform  = { os = "linux" }
          Lifecycle = { Run = "python3 {artifacts:path}/inference.py" }
          Artifacts = [{ Uri = "s3://alpha-dev-greengrass-artifacts-evil/inference.py" }]
        },
      ]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "non_s3_artifact_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Inference"
      ComponentVersion    = "1.0.0"
      Manifests = [
        {
          Platform  = { os = "linux" }
          Lifecycle = { Run = "docker run example" }
          Artifacts = [{ Uri = "docker:123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/example:latest" }]
        },
      ]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "lambda_component_rejected" {
  command = plan

  variables {
    recipe = {
      RecipeFormatVersion = "2020-01-25"
      ComponentName       = "com.example.Hello"
      ComponentVersion    = "1.0.0"
      ComponentType       = "aws.greengrass.lambda"
      Manifests           = [{ Platform = { os = "linux" }, Lifecycle = {} }]
    }
  }

  expect_failures = [awscc_greengrassv2_component_version.this]
}

run "invalid_bucket_name_rejected" {
  command = plan

  variables {
    artifact_bucket_name = "s3://alpha-dev-greengrass-artifacts"
  }

  expect_failures = [var.artifact_bucket_name]
}
