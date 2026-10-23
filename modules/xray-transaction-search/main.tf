data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  spans_log_group               = "aws/spans"
  application_signals_log_group = "/aws/application-signals/data"
  log_arn_prefix                = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group"
}

# X-Ray writes spans to these two log groups once the destination is CloudWatchLogs.
resource "aws_cloudwatch_log_resource_policy" "xray" {
  policy_name = var.resource_policy_name
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "TransactionSearchXRayAccess"
      Effect    = "Allow"
      Principal = { Service = "xray.amazonaws.com" }
      Action    = "logs:PutLogEvents"
      Resource = [
        "${local.log_arn_prefix}:${local.spans_log_group}:*",
        "${local.log_arn_prefix}:${local.application_signals_log_group}:*",
      ]
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:xray:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*" }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_xray_trace_segment_destination" "this" {
  destination = "CloudWatchLogs"

  depends_on = [aws_cloudwatch_log_resource_policy.xray]
}

# Default is the only indexing rule X-Ray has; it can be updated but not created or deleted.
resource "aws_xray_indexing_rule" "default" {
  name = "Default"

  rule {
    probabilistic {
      desired_sampling_percentage = var.indexing_percentage
    }
  }

  depends_on = [aws_xray_trace_segment_destination.this]
}
