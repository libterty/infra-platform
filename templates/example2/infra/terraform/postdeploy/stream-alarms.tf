locals {
  # <Project>/<env>: the namespace the worker publishes its stream metrics into.
  metric_namespace  = "${title(var.project)}/${var.env}"
  stream_length_cap = tonumber(module.in.strings["stream_length_cap"])
  stream_dims       = { Env = var.env }

  stream_alarms = {
    backlog_high = {
      description         = "The stream backlog stayed above half of its length cap for five minutes. At the cap the oldest entries are trimmed, including ones not yet persisted, so this is the point to act. Check the consumer count first, then add worker tasks."
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = local.stream_length_cap / 2
      evaluation_periods  = 5
      datapoints_to_alarm = 5
      treat_missing_data  = "notBreaching"
      metric = {
        namespace   = local.metric_namespace
        metric_name = "StreamBacklogMax"
        dimensions  = local.stream_dims
        statistic   = "Maximum"
        period      = 60
      }
    }
    no_consumers = {
      description         = "No consumer is reading the stream. Writes do not fail, so nothing else shows it. Missing data counts as a breach because the metrics reporter is gone too. Check that the worker tasks are running."
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "breaching"
      metric = {
        namespace   = local.metric_namespace
        metric_name = "StreamConsumers"
        dimensions  = local.stream_dims
        statistic   = "Maximum"
        period      = 60
      }
    }
  }
}

module "stream_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.0"

  count = var.stream_alarms_enabled ? 1 : 0

  name_prefix    = "${local.name_prefix}-stream"
  alarms         = local.stream_alarms
  sns_topic_arns = local.alarm_topic_arns
}
