locals {
  # The error action is a single object per type; dynamic blocks want a list, so turn each into zero or one item.
  error_action = { for kind, a in var.error_action : kind => a == null ? [] : [a] }
}

resource "aws_iot_topic_rule" "this" {
  for_each = var.rules

  name        = each.key
  description = each.value.description
  enabled     = each.value.enabled
  sql         = each.value.sql
  # AWS recommends 2016-03-23; older versions behave differently for nested objects and arrays.
  sql_version = "2016-03-23"

  dynamic "kinesis" {
    for_each = each.value.actions.kinesis
    content {
      stream_name   = kinesis.value.stream_name
      role_arn      = kinesis.value.role_arn
      partition_key = kinesis.value.partition_key
    }
  }

  dynamic "firehose" {
    for_each = each.value.actions.firehose
    content {
      delivery_stream_name = firehose.value.delivery_stream_name
      role_arn             = firehose.value.role_arn
      separator            = firehose.value.separator
      batch_mode           = firehose.value.batch_mode
    }
  }

  dynamic "s3" {
    for_each = each.value.actions.s3
    content {
      bucket_name = s3.value.bucket_name
      key         = s3.value.key
      role_arn    = s3.value.role_arn
    }
  }

  dynamic "sqs" {
    for_each = each.value.actions.sqs
    content {
      queue_url  = sqs.value.queue_url
      role_arn   = sqs.value.role_arn
      use_base64 = sqs.value.use_base64
    }
  }

  dynamic "lambda" {
    for_each = each.value.actions.lambda
    content {
      function_arn = lambda.value.function_arn
    }
  }

  dynamic "dynamodbv2" {
    for_each = each.value.actions.dynamodbv2
    content {
      role_arn = dynamodbv2.value.role_arn

      put_item {
        table_name = dynamodbv2.value.table_name
      }
    }
  }

  dynamic "republish" {
    for_each = each.value.actions.republish
    content {
      topic    = republish.value.topic
      role_arn = republish.value.role_arn
      qos      = republish.value.qos
    }
  }

  dynamic "cloudwatch_logs" {
    for_each = each.value.actions.cloudwatch_logs
    content {
      log_group_name = cloudwatch_logs.value.log_group_name
      role_arn       = cloudwatch_logs.value.role_arn
      batch_mode     = cloudwatch_logs.value.batch_mode
    }
  }

  dynamic "cloudwatch_metric" {
    for_each = each.value.actions.cloudwatch_metric
    content {
      metric_name      = cloudwatch_metric.value.metric_name
      metric_namespace = cloudwatch_metric.value.metric_namespace
      metric_unit      = cloudwatch_metric.value.metric_unit
      metric_value     = cloudwatch_metric.value.metric_value
      metric_timestamp = cloudwatch_metric.value.metric_timestamp
      role_arn         = cloudwatch_metric.value.role_arn
    }
  }

  dynamic "sns" {
    for_each = each.value.actions.sns
    content {
      target_arn     = sns.value.target_arn
      role_arn       = sns.value.role_arn
      message_format = sns.value.message_format
    }
  }

  error_action {
    dynamic "kinesis" {
      for_each = local.error_action.kinesis
      content {
        stream_name   = kinesis.value.stream_name
        role_arn      = kinesis.value.role_arn
        partition_key = kinesis.value.partition_key
      }
    }

    dynamic "firehose" {
      for_each = local.error_action.firehose
      content {
        delivery_stream_name = firehose.value.delivery_stream_name
        role_arn             = firehose.value.role_arn
        separator            = firehose.value.separator
        batch_mode           = firehose.value.batch_mode
      }
    }

    dynamic "s3" {
      for_each = local.error_action.s3
      content {
        bucket_name = s3.value.bucket_name
        key         = s3.value.key
        role_arn    = s3.value.role_arn
      }
    }

    dynamic "sqs" {
      for_each = local.error_action.sqs
      content {
        queue_url  = sqs.value.queue_url
        role_arn   = sqs.value.role_arn
        use_base64 = sqs.value.use_base64
      }
    }

    dynamic "lambda" {
      for_each = local.error_action.lambda
      content {
        function_arn = lambda.value.function_arn
      }
    }

    dynamic "dynamodbv2" {
      for_each = local.error_action.dynamodbv2
      content {
        role_arn = dynamodbv2.value.role_arn

        put_item {
          table_name = dynamodbv2.value.table_name
        }
      }
    }

    dynamic "republish" {
      for_each = local.error_action.republish
      content {
        topic    = republish.value.topic
        role_arn = republish.value.role_arn
        qos      = republish.value.qos
      }
    }

    dynamic "cloudwatch_logs" {
      for_each = local.error_action.cloudwatch_logs
      content {
        log_group_name = cloudwatch_logs.value.log_group_name
        role_arn       = cloudwatch_logs.value.role_arn
        batch_mode     = cloudwatch_logs.value.batch_mode
      }
    }

    dynamic "cloudwatch_metric" {
      for_each = local.error_action.cloudwatch_metric
      content {
        metric_name      = cloudwatch_metric.value.metric_name
        metric_namespace = cloudwatch_metric.value.metric_namespace
        metric_unit      = cloudwatch_metric.value.metric_unit
        metric_value     = cloudwatch_metric.value.metric_value
        metric_timestamp = cloudwatch_metric.value.metric_timestamp
        role_arn         = cloudwatch_metric.value.role_arn
      }
    }

    dynamic "sns" {
      for_each = local.error_action.sns
      content {
        target_arn     = sns.value.target_arn
        role_arn       = sns.value.role_arn
        message_format = sns.value.message_format
      }
    }
  }

  tags = merge(var.tags, { Name = each.key })
}
