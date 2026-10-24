locals {
  stream_alarm_metric = {
    namespace  = "AWS/Kinesis"
    dimensions = { StreamName = local.stream.name }
  }

  # Thresholds and windows are starting points, not tuned against real traffic.
  stream_alarms = {
    stream_write_throughput_exceeded = {
      description = "Writers are putting records faster than the stream's shards allow, so records are being rejected. Add shards or slow the writers."
      threshold   = 1
      metric      = merge(local.stream_alarm_metric, { metric_name = "WriteProvisionedThroughputExceeded", statistic = "Sum", period = 900 })
    }
    stream_read_throughput_exceeded = {
      description = "Consumers are reading faster than the stream's shards allow. Check the consumers sharing this stream."
      threshold   = 1
      metric      = merge(local.stream_alarm_metric, { metric_name = "ReadProvisionedThroughputExceeded", statistic = "Sum", period = 900 })
    }
    stream_iterator_age = {
      description = "The oldest unread record is over an hour old. Firehose is falling behind or has stopped; with 24 hours of retention, data is lost when this reaches a day."
      threshold   = 3600000
      metric      = merge(local.stream_alarm_metric, { metric_name = "GetRecords.IteratorAgeMilliseconds", statistic = "Maximum", period = 900 })
    }
  }

  table_alarms = merge([
    for k, t in local.tables : {
      "table_${k}_write_throttled" = {
        description = "Writes to ${t.name} are being throttled. Check the access pattern and any hot partition key."
        threshold   = 1
        metric      = { namespace = "AWS/DynamoDB", metric_name = "WriteThrottleEvents", dimensions = { TableName = t.name }, statistic = "Sum", period = 900 }
      }
      "table_${k}_read_throttled" = {
        description = "Reads from ${t.name} are being throttled. Check the access pattern and any hot partition key."
        threshold   = 1
        metric      = { namespace = "AWS/DynamoDB", metric_name = "ReadThrottleEvents", dimensions = { TableName = t.name }, statistic = "Sum", period = 900 }
      }
    }
  ]...)

  alarms = merge(local.stream_alarms, local.table_alarms)
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"

  name_prefix    = local.name_prefix
  alarms         = local.alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
