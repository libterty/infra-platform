locals {
  log_group_name = coalesce(var.log_group_name, "/aws/codebuild/${var.name}")
}

resource "aws_cloudwatch_log_group" "this" {
  region            = var.region
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

# Runs only as a CodePipeline action: no webhook and no repository credentials on the project (K2).
resource "aws_codebuild_project" "this" {
  region                 = var.region
  name                   = var.name
  description            = var.description
  service_role           = var.service_role_arn
  encryption_key         = var.encryption_key_arn
  build_timeout          = var.build_timeout
  queued_timeout         = var.queued_timeout
  concurrent_build_limit = var.concurrent_build_limit
  project_visibility     = "PRIVATE"

  source {
    type      = "CODEPIPELINE"
    buildspec = var.buildspec
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = var.environment.compute_type
    image           = var.environment.image
    type            = var.environment.type
    privileged_mode = var.environment.privileged_mode

    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  dynamic "cache" {
    for_each = length(var.cache_modes) > 0 ? [var.cache_modes] : []
    content {
      type  = "LOCAL"
      modes = cache.value
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.this.name
    }

    s3_logs {
      status = "DISABLED"
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
