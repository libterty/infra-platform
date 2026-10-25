locals {
  alarm_topic_arns = [module.in.strings["alarm_topic_arn"]]

  stream_alarm_metric = {
    namespace  = "AWS/Kinesis"
    dimensions = { StreamName = local.stream.name }
  }

  # sqs-queue names the dead-letter queue <name>-dlq.
  sqs_metric = { for k, q in local.queues : k => { namespace = "AWS/SQS", dimensions = { QueueName = q.name } } }
  dlq_metric = { for k, q in local.queues : k => { namespace = "AWS/SQS", dimensions = { QueueName = "${q.name}-dlq" } } }

  # Thresholds and windows are starting points, not tuned against real traffic.
  stream_alarms = {
    stream_write_throughput_exceeded = {
      description = "IoT rules are putting records faster than the stream's shards allow, so records are being rejected. Add shards."
      threshold   = 1
      metric      = merge(local.stream_alarm_metric, { metric_name = "WriteProvisionedThroughputExceeded", statistic = "Sum", period = 900 })
    }
    stream_read_throughput_exceeded = {
      description = "Consumers are reading faster than the stream's shards allow. Check the Firehose streams sharing this stream."
      threshold   = 1
      metric      = merge(local.stream_alarm_metric, { metric_name = "ReadProvisionedThroughputExceeded", statistic = "Sum", period = 900 })
    }
    stream_iterator_age = {
      description = "The oldest unread record is over an hour old. Firehose is falling behind or has stopped; with 24 hours of retention, data is lost when this reaches a day."
      threshold   = 3600000
      metric      = merge(local.stream_alarm_metric, { metric_name = "GetRecords.IteratorAgeMilliseconds", statistic = "Maximum", period = 900 })
    }
  }

  queue_alarms = {
    rule_errors_received = {
      description = "An IoT rule action failed and the message went to the rule-errors queue. Read the queue to see which action and why."
      threshold   = 1
      metric      = merge(local.sqs_metric["rule_errors"], { metric_name = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", period = 900 })
    }
    rule_errors_dlq_not_empty = {
      description = "Messages of the rule-errors queue were received too often without being deleted and moved to its dead-letter queue."
      threshold   = 1
      metric      = merge(local.dlq_metric["rule_errors"], { metric_name = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", period = 900 })
    }
    model_approved_oldest_message_age = {
      description = "An approved model has waited over a day in the model-approved queue. The CI consumer is not running."
      threshold   = 86400
      metric      = merge(local.sqs_metric["model_approved"], { metric_name = "ApproximateAgeOfOldestMessage", statistic = "Maximum", period = 900 })
    }
    model_approved_dlq_not_empty = {
      description = "The CI consumer failed to process a model approval several times; it is in the model-approved dead-letter queue."
      threshold   = 1
      metric      = merge(local.dlq_metric["model_approved"], { metric_name = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", period = 900 })
    }
  }

  alarms = merge(local.stream_alarms, local.queue_alarms)
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"

  name_prefix    = local.name_prefix
  alarms         = local.alarms
  sns_topic_arns = local.alarm_topic_arns
}
