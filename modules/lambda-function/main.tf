resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "/aws/lambda/${var.name}" })
}

# Container image only: no handler, runtime or zip package settings.
resource "aws_lambda_function" "this" {
  function_name = var.name
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = var.role_arn
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout

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

resource "aws_lambda_permission" "this" {
  for_each = var.permissions

  statement_id   = each.key
  action         = each.value.action
  function_name  = aws_lambda_function.this.function_name
  principal      = each.value.principal
  source_arn     = each.value.source_arn
  source_account = each.value.source_account
}
