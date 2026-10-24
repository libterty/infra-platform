locals {
  # Thresholds and windows are starting points, not tuned against real traffic. DataFreshness is the age in seconds of the
  # oldest record not yet delivered.
  alarms = {
    firehose_s3_data_freshness = {
      description = "The raw delivery is more than an hour behind; it buffers up to 900 seconds, so this is not normal buffering. Check the delivery stream logs, the raw bucket and the firehose role."
      threshold   = 3600
      metric = {
        namespace   = "AWS/Firehose"
        metric_name = "DeliveryToS3.DataFreshness"
        dimensions  = { DeliveryStreamName = local.firehose_s3.name }
        statistic   = "Maximum"
        period      = 300
      }
    }
    firehose_opensearch_data_freshness = {
      description = "The OpenSearch delivery is more than 10 minutes behind. Check the domain health, the FGAC mapping of the firehose role and the delivery stream logs."
      threshold   = 600
      metric = {
        namespace   = "AWS/Firehose"
        metric_name = "DeliveryToAmazonOpenSearchService.DataFreshness"
        dimensions  = { DeliveryStreamName = local.firehose_opensearch.name }
        statistic   = "Maximum"
        period      = 300
      }
    }
  }
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"

  name_prefix    = local.name_prefix
  alarms         = local.alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
