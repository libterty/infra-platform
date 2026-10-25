mock_provider "aws" {}

override_resource {
  target          = aws_sagemaker_pipeline.this
  override_during = plan
  values = {
    arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
  }
}

variables {
  name     = "alpha-dev-train"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-pipeline"
  definition = jsonencode({
    Version    = "2020-12-01"
    Parameters = [{ Name = "InputDataUrl", Type = "String", DefaultValue = "s3://alpha-dev-ml-artifacts/data/" }]
    Steps = [{
      Name      = "Train"
      Type      = "Training"
      Arguments = { RoleArn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-pipeline" }
    }]
  })
}

# ---- positive -------------------------------------------------------------------------------------------------

run "definition_and_role" {
  command = plan

  assert {
    condition     = aws_sagemaker_pipeline.this.pipeline_name == "alpha-dev-train"
    error_message = "The pipeline name must be passed through"
  }

  assert {
    condition     = jsondecode(aws_sagemaker_pipeline.this.pipeline_definition).Steps[0].Name == "Train"
    error_message = "The definition must be passed through"
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-pipeline"
    error_message = "The role must be passed through"
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.pipeline_display_name == "alpha-dev-train"
    error_message = "The display name must default to the pipeline name"
  }

  assert {
    condition     = length(aws_sagemaker_pipeline.this.parallelism_configuration) == 0
    error_message = "No parallelism configuration unless max_parallel_steps is given"
  }

  assert {
    condition     = length(aws_sagemaker_pipeline.this.pipeline_definition_s3_location) == 0
    error_message = "The definition must never be read from S3"
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.tags["Name"] == "alpha-dev-train"
    error_message = "Name must be added to the tags"
  }
}

run "display_name_description_parallelism" {
  command = plan

  variables {
    display_name       = "alpha-dev-train-weekly"
    description        = "Weekly retraining"
    max_parallel_steps = 2
    tags               = { Project = "alpha" }
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.pipeline_display_name == "alpha-dev-train-weekly"
    error_message = "display_name must be passed through"
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.pipeline_description == "Weekly retraining"
    error_message = "description must be passed through"
  }

  assert {
    condition     = one(aws_sagemaker_pipeline.this.parallelism_configuration).max_parallel_execution_steps == 2
    error_message = "max_parallel_steps must be passed through"
  }

  assert {
    condition     = aws_sagemaker_pipeline.this.tags["Project"] == "alpha" && aws_sagemaker_pipeline.this.tags["Name"] == "alpha-dev-train"
    error_message = "Name must be merged into the given tags"
  }
}

run "steps_with_different_shapes_are_accepted" {
  command = plan

  variables {
    definition = jsonencode({
      Version = "2020-12-01"
      Steps = [
        { Name = "Train", Type = "Training", Arguments = { RoleArn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-pipeline" } },
        { Name = "Register", Type = "RegisterModel", Arguments = { ModelPackageGroupName = "alpha-dev-detector" }, DependsOn = ["Train"] },
      ]
    })
  }

  assert {
    condition     = length(jsondecode(aws_sagemaker_pipeline.this.pipeline_definition).Steps) == 2
    error_message = "A definition whose steps have different shapes must be accepted"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.pipeline_name == "alpha-dev-train"
    error_message = "pipeline_name output must be the pipeline name"
  }

  assert {
    condition     = output.pipeline_arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
    error_message = "pipeline_arn output must be the pipeline ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "definition_not_json_rejected" {
  command = plan

  variables {
    definition = "Version: 2020-12-01"
  }

  expect_failures = [var.definition]
}

run "definition_without_steps_rejected" {
  command = plan

  variables {
    definition = jsonencode({ Version = "2020-12-01" })
  }

  expect_failures = [var.definition]
}

run "definition_with_empty_steps_rejected" {
  command = plan

  variables {
    definition = jsonencode({ Version = "2020-12-01", Steps = [] })
  }

  expect_failures = [var.definition]
}

run "definition_without_version_rejected" {
  command = plan

  variables {
    definition = jsonencode({ Steps = [{ Name = "Train", Type = "Training", Arguments = {} }] })
  }

  expect_failures = [var.definition]
}

run "definition_with_object_steps_rejected" {
  command = plan

  variables {
    definition = jsonencode({ Version = "2020-12-01", Steps = { Name = "Train" } })
  }

  expect_failures = [var.definition]
}

run "role_arn_format_rejected" {
  command = plan

  variables {
    role_arn = "alpha-dev-sagemaker-pipeline"
  }

  expect_failures = [var.role_arn]
}

run "zero_parallel_steps_rejected" {
  command = plan

  variables {
    max_parallel_steps = 0
  }

  expect_failures = [var.max_parallel_steps]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha_dev_train"
  }

  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "alpha-dev-train-${format("%0242d", 0)}"
  }

  expect_failures = [var.name]
}

run "invalid_display_name_rejected" {
  command = plan

  variables {
    display_name = "alpha dev train"
  }

  expect_failures = [var.display_name]
}
