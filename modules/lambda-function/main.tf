locals {
  function = one(concat(aws_lambda_function.this, aws_lambda_function.pipeline_managed))
  alias    = one(concat(aws_lambda_alias.this, aws_lambda_alias.pipeline_managed))
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "/aws/lambda/${var.name}" })
}

# Container image only: no handler, runtime or zip package settings.
resource "aws_lambda_function" "this" {
  count = var.pipeline_managed ? 0 : 1

  function_name = var.name
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = var.role_arn
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout
  publish       = var.alias != null ? true : null

  reserved_concurrent_executions = var.reserved_concurrent_executions

  logging_config {
    log_format = var.log_format
    log_group  = aws_cloudwatch_log_group.this.name
  }

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [var.environment] : []
    content {
      variables = environment.value
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc == null ? [] : [var.vpc]
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

# lifecycle.ignore_changes cannot depend on a variable, so the pipeline-managed variant is a separate block.
resource "aws_lambda_function" "pipeline_managed" {
  count = var.pipeline_managed ? 1 : 0

  function_name = var.name
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = var.role_arn
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout
  publish       = true

  reserved_concurrent_executions = var.reserved_concurrent_executions

  logging_config {
    log_format = var.log_format
    log_group  = aws_cloudwatch_log_group.this.name
  }

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [var.environment] : []
    content {
      variables = environment.value
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc == null ? [] : [var.vpc]
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = merge(var.tags, { Name = var.name })

  # The pipeline deploys new images; image_uri only seeds the first version.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

moved {
  from = aws_lambda_function.this
  to   = aws_lambda_function.this[0]
}

resource "aws_lambda_alias" "this" {
  count = var.alias != null && !var.pipeline_managed ? 1 : 0

  name             = var.alias
  function_name    = local.function.function_name
  function_version = local.function.version
}

# The pipeline shifts the alias to new versions, so Terraform only sets the first one.
resource "aws_lambda_alias" "pipeline_managed" {
  count = var.pipeline_managed ? 1 : 0

  name             = var.alias
  function_name    = local.function.function_name
  function_version = local.function.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

resource "aws_lambda_permission" "this" {
  for_each = var.permissions

  statement_id   = each.key
  action         = each.value.action
  function_name  = local.function.function_name
  principal      = each.value.principal
  source_arn     = each.value.source_arn
  source_account = each.value.source_account
}
