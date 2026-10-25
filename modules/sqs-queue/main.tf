locals {
  suffix     = var.fifo ? ".fifo" : ""
  queue_name = "${var.name}${local.suffix}"
  dlq_name   = "${var.name}-dlq${local.suffix}"
}

resource "aws_sqs_queue" "dlq" {
  name                        = local.dlq_name
  fifo_queue                  = var.fifo
  content_based_deduplication = var.fifo ? true : null
  message_retention_seconds   = var.dlq_retention_seconds

  # A customer managed key is required; SQS-managed SSE is never used.
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Name = local.dlq_name })
}

resource "aws_sqs_queue" "this" {
  name                        = local.queue_name
  fifo_queue                  = var.fifo
  content_based_deduplication = var.fifo ? true : null
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds

  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Name = local.queue_name })
}

resource "aws_sqs_queue_redrive_policy" "this" {
  queue_url = aws_sqs_queue.this.url
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.url
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

resource "aws_sqs_queue_policy" "this" {
  count = length(var.allowed_source_arns) == 0 ? 0 : 1

  queue_url = aws_sqs_queue.this.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeRules"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.this.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = var.allowed_source_arns }
      }
    }]
  })
}
