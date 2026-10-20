locals {
  metric_namespace = "${title(var.project)}/${var.env}"

  # The patterns are a contract with the SQL that pg_cron runs: that job must write exactly these terms to the
  # PostgreSQL log (for example with RAISE LOG).
  partition_alarms = {
    partition_maintenance_failed = {
      pattern             = "\"partition_maintenance_failed\""
      metric_name         = "PartitionMaintenanceFailed"
      description         = "The daily partition job could not create the next partition. If writes reach the default partition before it is fixed, that range can no longer be created without locking the table. Check cron.job_run_details and the PostgreSQL log."
      period              = 86400
      evaluation_periods  = 1
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
    }
    partition_maintenance_not_running = {
      pattern     = "\"partition_maintenance_heartbeat\""
      metric_name = "PartitionMaintenanceHeartbeat"
      description = "No heartbeat from the partition job for two days, so pg_cron is not running it at all and the runway of partitions shrinks silently. Check cron.job and that cron.database_name matches the application database."
      period      = 86400
      # Two days, so one late run does not alarm.
      evaluation_periods  = 2
      threshold           = 1
      comparison_operator = "LessThanThreshold"
      treat_missing_data  = "breaching"
    }
    default_partition_not_empty = {
      pattern             = "\"default_partition_not_empty\""
      metric_name         = "DefaultPartitionNotEmpty"
      description         = "Rows landed in the default partition, so a partition was missing when writes arrived. That range can no longer be created by the job; repair needs a supervised step that locks the table."
      period              = 86400
      evaluation_periods  = 1
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
    }
  }
}

module "partition_alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.0"

  name_prefix    = local.name_prefix
  log_group_name = module.db.log_group_name
  namespace      = local.metric_namespace
  alarms         = local.partition_alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
