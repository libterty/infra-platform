mock_provider "aws" {}

variables {
  name               = "alpha-dev-api-build"
  service_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-api-build"
  encryption_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "defaults" {
  command = plan

  assert {
    condition     = aws_codebuild_project.this.name == "alpha-dev-api-build"
    error_message = "The project must keep the given name"
  }

  assert {
    condition     = aws_codebuild_project.this.service_role == "arn:aws:iam::111111111111:role/alpha-dev-api-build"
    error_message = "service_role must follow service_role_arn"
  }

  assert {
    condition     = aws_codebuild_project.this.encryption_key == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "encryption_key must follow encryption_key_arn"
  }

  assert {
    condition = (
      aws_codebuild_project.this.environment[0].compute_type == "BUILD_GENERAL1_SMALL" &&
      aws_codebuild_project.this.environment[0].type == "ARM_CONTAINER" &&
      aws_codebuild_project.this.environment[0].image == "aws/codebuild/amazonlinux-aarch64-standard:3.0" &&
      aws_codebuild_project.this.environment[0].privileged_mode == false
    )
    error_message = "The default environment must be ARM small with the Amazon Linux aarch64 image, not privileged"
  }

  assert {
    condition     = aws_codebuild_project.this.build_timeout == 30 && aws_codebuild_project.this.queued_timeout == 60
    error_message = "Default build_timeout must be 30 and queued_timeout 60"
  }

  assert {
    condition     = aws_codebuild_project.this.concurrent_build_limit == 1
    error_message = "Default concurrent_build_limit must be 1"
  }

  assert {
    condition     = length(aws_codebuild_project.this.cache) == 0
    error_message = "The default must leave the cache unset (NO_CACHE)"
  }

  assert {
    condition     = length(aws_codebuild_project.this.environment[0].environment_variable) == 0
    error_message = "Without environment_variables the project must not set any"
  }

  assert {
    condition     = aws_codebuild_project.this.source[0].buildspec == null
    error_message = "Without buildspec the project must use the repository default (buildspec.yml)"
  }

  assert {
    condition     = aws_codebuild_project.this.tags == tomap({ Name = "alpha-dev-api-build" })
    error_message = "Without tags input the only tag is Name"
  }
}

# K2: the project only runs from a pipeline; it never reaches the repository itself.
run "source_and_artifacts_are_codepipeline" {
  command = plan

  assert {
    condition     = aws_codebuild_project.this.source[0].type == "CODEPIPELINE"
    error_message = "source.type must be CODEPIPELINE"
  }

  assert {
    condition     = aws_codebuild_project.this.artifacts[0].type == "CODEPIPELINE"
    error_message = "artifacts.type must be CODEPIPELINE"
  }

  assert {
    condition     = aws_codebuild_project.this.source[0].location == null && length(aws_codebuild_project.this.source[0].auth) == 0
    error_message = "The source must not carry a repository location or credentials"
  }

  assert {
    condition     = length(aws_codebuild_project.this.secondary_sources) == 0 && length(aws_codebuild_project.this.vpc_config) == 0
    error_message = "The project must have no secondary sources and no VPC config"
  }
}

run "private_project_with_cloudwatch_logs_only" {
  command = plan

  assert {
    condition     = aws_codebuild_project.this.project_visibility == "PRIVATE"
    error_message = "project_visibility must be PRIVATE"
  }

  assert {
    condition = (
      aws_codebuild_project.this.logs_config[0].cloudwatch_logs[0].status == "ENABLED" &&
      aws_codebuild_project.this.logs_config[0].cloudwatch_logs[0].group_name == "/aws/codebuild/alpha-dev-api-build"
    )
    error_message = "CloudWatch Logs must be enabled and point at the module's log group"
  }

  assert {
    condition     = aws_codebuild_project.this.logs_config[0].s3_logs[0].status == "DISABLED"
    error_message = "S3 logs must be disabled"
  }
}

run "module_owns_the_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/codebuild/alpha-dev-api-build"
    error_message = "The default log group name must be /aws/codebuild/<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Default retention must be 30 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Without log_kms_key_arn the log group must not set a key"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Name = "/aws/codebuild/alpha-dev-api-build" })
    error_message = "The log group must be tagged with its own name"
  }
}

run "log_settings_follow_input" {
  command = plan

  variables {
    log_group_name     = "/alpha/dev/codebuild/api"
    log_retention_days = 365
    log_kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/alpha/dev/codebuild/api" && aws_codebuild_project.this.logs_config[0].cloudwatch_logs[0].group_name == "/alpha/dev/codebuild/api"
    error_message = "log_group_name must name the log group and the project's log destination"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "log_retention_days must follow the input"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
    error_message = "log_kms_key_arn must be set on the log group"
  }
}

run "image_build_is_privileged" {
  command = plan

  variables {
    environment = {
      privileged_mode = true
    }
  }

  assert {
    condition     = aws_codebuild_project.this.environment[0].privileged_mode == true
    error_message = "privileged_mode must follow the input"
  }

  assert {
    condition     = aws_codebuild_project.this.environment[0].type == "ARM_CONTAINER" && aws_codebuild_project.this.environment[0].compute_type == "BUILD_GENERAL1_SMALL"
    error_message = "Unset environment fields must keep their defaults"
  }
}

run "inline_buildspec" {
  command = plan

  variables {
    buildspec = <<-YAML
      version: 0.2
      phases:
        build:
          commands:
            - echo build
    YAML
  }

  assert {
    condition     = startswith(aws_codebuild_project.this.source[0].buildspec, "version: 0.2")
    error_message = "An inline buildspec must be passed through"
  }
}

run "buildspec_path" {
  command = plan

  variables {
    buildspec = "ci/api/buildspec.yml"
  }

  assert {
    condition     = aws_codebuild_project.this.source[0].buildspec == "ci/api/buildspec.yml"
    error_message = "A buildspec path must be passed through"
  }
}

run "three_variable_types" {
  command = plan

  variables {
    environment_variables = {
      AWS_ACCOUNT_ID = { value = "111111111111" }
      IMAGE_REPO     = { value = "alpha/api", type = "PLAINTEXT" }
      DB_PASSWORD    = { value = "alpha-dev-db:password", type = "SECRETS_MANAGER" }
      API_TOKEN      = { value = "/alpha/dev/api-token", type = "PARAMETER_STORE" }
    }
  }

  assert {
    condition     = length(aws_codebuild_project.this.environment[0].environment_variable) == 4
    error_message = "Every environment variable must be set"
  }

  assert {
    condition = toset([for v in aws_codebuild_project.this.environment[0].environment_variable : "${v.name}=${v.type}=${v.value}"]) == toset([
      "AWS_ACCOUNT_ID=PLAINTEXT=111111111111",
      "IMAGE_REPO=PLAINTEXT=alpha/api",
      "DB_PASSWORD=SECRETS_MANAGER=alpha-dev-db:password",
      "API_TOKEN=PARAMETER_STORE=/alpha/dev/api-token",
    ])
    error_message = "Each variable must keep its name, value and type; type defaults to PLAINTEXT"
  }
}

run "x86_environment" {
  command = plan

  variables {
    environment = {
      compute_type = "BUILD_GENERAL1_MEDIUM"
      image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
      type         = "LINUX_CONTAINER"
    }
  }

  assert {
    condition = (
      aws_codebuild_project.this.environment[0].compute_type == "BUILD_GENERAL1_MEDIUM" &&
      aws_codebuild_project.this.environment[0].image == "aws/codebuild/amazonlinux-x86_64-standard:5.0" &&
      aws_codebuild_project.this.environment[0].type == "LINUX_CONTAINER"
    )
    error_message = "environment must follow the input"
  }
}

run "custom_image_on_arm" {
  command = plan

  variables {
    environment = {
      image = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/builder:v1.0.0"
    }
  }

  assert {
    condition     = aws_codebuild_project.this.environment[0].image == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/builder:v1.0.0"
    error_message = "A custom image must be accepted on ARM_CONTAINER"
  }
}

run "timeouts_limits_and_description_follow_input" {
  command = plan

  variables {
    description            = "alpha dev api image build"
    build_timeout          = 2160
    queued_timeout         = 480
    concurrent_build_limit = 2
  }

  assert {
    condition     = aws_codebuild_project.this.description == "alpha dev api image build"
    error_message = "description must follow the input"
  }

  assert {
    condition     = aws_codebuild_project.this.build_timeout == 2160 && aws_codebuild_project.this.queued_timeout == 480
    error_message = "build_timeout and queued_timeout must follow the input"
  }

  assert {
    condition     = aws_codebuild_project.this.concurrent_build_limit == 2
    error_message = "concurrent_build_limit must follow the input"
  }
}

run "accepts_build_timeout_5" {
  command = plan

  variables {
    build_timeout = 5
  }

  assert {
    condition     = aws_codebuild_project.this.build_timeout == 5
    error_message = "5 minutes must be accepted"
  }
}

run "no_cache_when_cache_modes_is_empty" {
  command = plan

  variables {
    cache_modes = []
  }

  assert {
    condition     = length(aws_codebuild_project.this.cache) == 0
    error_message = "Empty cache_modes must leave the cache unset (NO_CACHE)"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_codebuild_project.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-api-build" })
    error_message = "Input tags must be kept and Name added"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Project = "alpha", Name = "/aws/codebuild/alpha-dev-api-build" })
    error_message = "The log group must carry the input tags and its own name"
  }
}

run "region_on_every_resource" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = aws_codebuild_project.this.region == "us-east-1" && aws_cloudwatch_log_group.this.region == "us-east-1"
    error_message = "region must be set on every resource"
  }
}

run "outputs" {
  command = apply

  override_resource {
    target = aws_codebuild_project.this
    values = {
      arn = "arn:aws:codebuild:ap-northeast-1:111111111111:project/alpha-dev-api-build"
    }
  }

  assert {
    condition     = output.name == "alpha-dev-api-build"
    error_message = "name must be the project name"
  }

  assert {
    condition     = output.arn == "arn:aws:codebuild:ap-northeast-1:111111111111:project/alpha-dev-api-build"
    error_message = "arn must be the project ARN"
  }

  assert {
    condition     = output.log_group_name == "/aws/codebuild/alpha-dev-api-build"
    error_message = "log_group_name must be the module log group"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "rejects_plaintext_password" {
  command = plan

  variables {
    environment_variables = {
      DB_PASSWORD = { value = "hunter2" }
    }
  }

  expect_failures = [var.environment_variables]
}

run "rejects_plaintext_secret_token_and_key_names" {
  command = plan

  variables {
    environment_variables = {
      CLIENT_SECRET = { value = "x", type = "PLAINTEXT" }
      github_token  = { value = "x", type = "PLAINTEXT" }
      API_KEY       = { value = "x", type = "PLAINTEXT" }
    }
  }

  expect_failures = [var.environment_variables]
}

run "rejects_unknown_variable_type" {
  command = plan

  variables {
    environment_variables = {
      IMAGE_REPO = { value = "alpha/api", type = "SECRET" }
    }
  }

  expect_failures = [var.environment_variables]
}

run "rejects_malformed_variable_name" {
  command = plan

  variables {
    environment_variables = {
      "IMAGE-REPO" = { value = "alpha/api" }
    }
  }

  expect_failures = [var.environment_variables]
}

run "rejects_arm_image_on_x86_container" {
  command = plan

  variables {
    environment = {
      type = "LINUX_CONTAINER"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_x86_image_on_arm_container" {
  command = plan

  variables {
    environment = {
      image = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_ubuntu_standard_image_on_arm_container" {
  command = plan

  variables {
    environment = {
      image = "aws/codebuild/standard:7.0"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_lambda_compute_type" {
  command = plan

  variables {
    environment = {
      compute_type = "BUILD_LAMBDA_1GB"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_unknown_environment_type" {
  command = plan

  variables {
    environment = {
      type = "ARM_LAMBDA_CONTAINER"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_kms_alias" {
  command = plan

  variables {
    encryption_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev-build"
  }

  expect_failures = [var.encryption_key_arn]
}

run "rejects_bare_kms_key_id" {
  command = plan

  variables {
    encryption_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.encryption_key_arn]
}

run "rejects_log_kms_alias" {
  command = plan

  variables {
    log_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev-logs"
  }

  expect_failures = [var.log_kms_key_arn]
}

run "rejects_role_arn_that_is_not_a_role" {
  command = plan

  variables {
    service_role_arn = "arn:aws:iam::111111111111:user/alpha"
  }

  expect_failures = [var.service_role_arn]
}

run "rejects_build_timeout_4" {
  command = plan

  variables {
    build_timeout = 4
  }

  expect_failures = [var.build_timeout]
}

run "rejects_build_timeout_2161" {
  command = plan

  variables {
    build_timeout = 2161
  }

  expect_failures = [var.build_timeout]
}

run "rejects_queued_timeout_481" {
  command = plan

  variables {
    queued_timeout = 481
  }

  expect_failures = [var.queued_timeout]
}

run "rejects_concurrent_build_limit_0" {
  command = plan

  variables {
    concurrent_build_limit = 0
  }

  expect_failures = [var.concurrent_build_limit]
}

run "rejects_unknown_cache_mode" {
  command = plan

  variables {
    cache_modes = ["S3"]
  }

  expect_failures = [var.cache_modes]
}

run "rejects_name_with_space" {
  command = plan

  variables {
    name = "alpha dev build"
  }

  expect_failures = [var.name]
}

run "rejects_name_of_one_char" {
  command = plan

  variables {
    name = "a"
  }

  expect_failures = [var.name]
}

run "rejects_unsupported_log_retention" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_malformed_log_group_name" {
  command = plan

  variables {
    log_group_name = "alpha dev logs"
  }

  expect_failures = [var.log_group_name]
}

run "rejects_empty_buildspec" {
  command = plan

  variables {
    buildspec = "  "
  }

  expect_failures = [var.buildspec]
}

run "rejects_description_longer_than_255" {
  command = plan

  variables {
    description = join("", [for i in range(256) : "a"])
  }

  expect_failures = [var.description]
}

run "rejects_malformed_region" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}

run "docker_layer_cache_with_privileged_mode" {
  command = plan

  variables {
    environment = { privileged_mode = true }
    cache_modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  assert {
    condition     = aws_codebuild_project.this.cache[0].type == "LOCAL" && aws_codebuild_project.this.cache[0].modes == tolist(["LOCAL_DOCKER_LAYER_CACHE"])
    error_message = "A privileged project must accept the docker layer cache"
  }
}

run "rejects_docker_layer_cache_without_privileged_mode" {
  command = plan

  variables {
    cache_modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  expect_failures = [var.cache_modes]
}
