locals {
  # Cluster-level metrics of the AWS/ES namespace use the per-domain, per-client dimensions; ClientId is the account id.
  alarm_dimensions = { DomainName = local.domain.name, ClientId = var.expected_account_id }

  # Thresholds follow the AWS recommended alarms for OpenSearch Service (developer guide, "Recommended CloudWatch
  # alarms"); they are starting points, not tuned against real traffic. The JVM alarms read the Maximum over three
  # minutes, which replaces the documented "3 consecutive minutes".
  data_alarms = {
    cluster_status_red = {
      description = "At least one primary shard and its replicas are not allocated to a node, so some indexes are unavailable. See the red cluster status page of the OpenSearch Service guide."
      threshold   = 1
      metric      = { namespace = "AWS/ES", metric_name = "ClusterStatus.red", dimensions = local.alarm_dimensions, statistic = "Maximum", period = 60 }
    }
    free_storage_space = {
      description         = "A data node is down to 25 percent free space on its volume. The cluster blocks writes at 0. Delete or move indexes, or add storage."
      comparison_operator = "LessThanOrEqualToThreshold"
      # The metric is in MiB: 25 percent of the volume size (GiB).
      threshold = var.hot.ebs.volume_size * 1024 / 4
      metric    = { namespace = "AWS/ES", metric_name = "FreeStorageSpace", dimensions = local.alarm_dimensions, statistic = "Minimum", period = 60 }
    }
    jvm_memory_pressure = {
      description = "Java heap use of the data nodes is at 95 percent or more; the cluster may hit out-of-memory errors. Scale vertically."
      threshold   = 95
      metric      = { namespace = "AWS/ES", metric_name = "JVMMemoryPressure", dimensions = local.alarm_dimensions, statistic = "Maximum", period = 180 }
    }
  }

  warm_alarms = var.warm == null ? {} : {
    warm_jvm_memory_pressure = {
      description = "Java heap use of the UltraWarm nodes is at 95 percent or more; the cluster may hit out-of-memory errors. Scale vertically."
      threshold   = 95
      metric      = { namespace = "AWS/ES", metric_name = "WarmJVMMemoryPressure", dimensions = local.alarm_dimensions, statistic = "Maximum", period = 180 }
    }
    hot_to_warm_migration_failed = {
      description = "An index failed to move from hot to UltraWarm. Common causes are node failures, S3 connectivity and lack of disk space; check the ISM policy status of the index."
      threshold   = 1
      metric      = { namespace = "AWS/ES", metric_name = "HotToWarmMigrationFailureCount", dimensions = local.alarm_dimensions, statistic = "Sum", period = 60 }
    }
  }

  cold_alarms = var.warm != null && var.cold_storage ? {
    warm_to_cold_migration_failed = {
      description = "An index failed to move from UltraWarm to cold storage. Check that the index has the timestamp field the ISM policy names, and the ISM policy status of the index."
      threshold   = 1
      metric      = { namespace = "AWS/ES", metric_name = "WarmToColdMigrationFailureCount", dimensions = local.alarm_dimensions, statistic = "Sum", period = 60 }
    }
  } : {}

  alarms = merge(local.data_alarms, local.warm_alarms, local.cold_alarms)
}

module "alarms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/metric-alarm/aws"
  version = "~> 0.1.1"

  name_prefix    = local.name_prefix
  alarms         = local.alarms
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
