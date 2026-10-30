mock_provider "aws" {}

variables {
  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"
}

run "default_has_no_alias_and_no_publish" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.this) == 1 && length(aws_lambda_function.pipeline_managed) == 0
    error_message = "Without pipeline_managed only the default function may exist"
  }

  assert {
    condition     = aws_lambda_function.this[0].publish == null
    error_message = "Without an alias the function must not publish versions"
  }

  assert {
    condition     = length(aws_lambda_alias.this) == 0 && length(aws_lambda_alias.pipeline_managed) == 0
    error_message = "Without an alias no aws_lambda_alias may exist"
  }

  assert {
    condition     = output.alias_arn == null && output.alias_name == null
    error_message = "alias outputs must be null without an alias"
  }
}

run "alias_publishes_and_points_at_the_version" {
  command = apply

  variables {
    alias = "live"
  }

  assert {
    condition     = length(aws_lambda_function.this) == 1 && length(aws_lambda_function.pipeline_managed) == 0
    error_message = "An alias without pipeline_managed keeps the default function"
  }

  assert {
    condition     = aws_lambda_function.this[0].publish == true
    error_message = "An alias needs a published version"
  }

  assert {
    condition     = length(aws_lambda_alias.this) == 1 && length(aws_lambda_alias.pipeline_managed) == 0
    error_message = "Exactly the default alias must exist"
  }

  assert {
    condition     = aws_lambda_alias.this[0].name == "live" && aws_lambda_alias.this[0].function_name == "alpha-dev-worker"
    error_message = "The alias must be named live on this function"
  }

  assert {
    condition     = aws_lambda_alias.this[0].function_version == aws_lambda_function.this[0].version
    error_message = "The alias must point at the published version"
  }

  assert {
    condition     = output.alias_name == "live" && output.alias_arn == aws_lambda_alias.this[0].arn
    error_message = "alias outputs must come from the alias"
  }

  assert {
    condition     = output.version == aws_lambda_function.this[0].version
    error_message = "version must be the latest published version"
  }
}

run "pipeline_managed_uses_the_ignoring_variants" {
  command = apply

  variables {
    alias            = "live"
    pipeline_managed = true
  }

  assert {
    condition     = length(aws_lambda_function.this) == 0 && length(aws_lambda_function.pipeline_managed) == 1
    error_message = "pipeline_managed must create only the pipeline-managed function"
  }

  assert {
    condition     = length(aws_lambda_alias.this) == 0 && length(aws_lambda_alias.pipeline_managed) == 1
    error_message = "pipeline_managed must create only the pipeline-managed alias"
  }

  assert {
    condition     = aws_lambda_function.pipeline_managed[0].publish == true && aws_lambda_function.pipeline_managed[0].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
    error_message = "The pipeline-managed function starts from image_uri and publishes"
  }

  assert {
    condition     = aws_lambda_alias.pipeline_managed[0].function_version == aws_lambda_function.pipeline_managed[0].version
    error_message = "The first alias version must be the published version"
  }

  assert {
    condition     = output.function_name == "alpha-dev-worker" && output.function_arn == aws_lambda_function.pipeline_managed[0].arn && output.alias_arn == aws_lambda_alias.pipeline_managed[0].arn
    error_message = "Outputs must follow the pipeline-managed variants"
  }
}

run "permissions_follow_the_pipeline_managed_function" {
  command = plan

  variables {
    alias            = "live"
    pipeline_managed = true
    permissions = {
      schedule = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["schedule"].function_name == "alpha-dev-worker"
    error_message = "Permissions must target the function"
  }
}

run "rejects_pipeline_managed_without_alias" {
  command = plan

  variables {
    pipeline_managed = true
  }

  expect_failures = [var.pipeline_managed]
}

run "rejects_numeric_alias" {
  command = plan

  variables {
    alias = "123"
  }

  expect_failures = [var.alias]
}

run "rejects_alias_with_invalid_characters" {
  command = plan

  variables {
    alias = "live.v1"
  }

  expect_failures = [var.alias]
}

run "rejects_alias_longer_than_128" {
  command = plan

  variables {
    alias = "a${join("", [for i in range(128) : "b"])}"
  }

  expect_failures = [var.alias]
}

run "rejects_latest_as_alias" {
  command = plan

  variables {
    alias = "$LATEST"
  }

  expect_failures = [var.alias]
}
