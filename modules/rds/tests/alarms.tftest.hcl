mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      address  = "app-db.abc123.ap-northeast-1.rds.amazonaws.com"
      endpoint = "app-db.abc123.ap-northeast-1.rds.amazonaws.com:5432"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint        = "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint = "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }
}

mock_provider "random" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_db_instance.this[0]
  override_during = plan
  values = {
    address     = "app-db.abc123.ap-northeast-1.rds.amazonaws.com"
    endpoint    = "app-db.abc123.ap-northeast-1.rds.amazonaws.com:5432"
    arn         = "arn:aws:rds:ap-northeast-1:111111111111:db:app-db"
    resource_id = "db-ABCDEFG"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
      kms_key_id    = "k"
      secret_status = "active"
    }]
  }
}

override_resource {
  target          = aws_rds_cluster.this[0]
  override_during = plan
  values = {
    id                  = "app-db"
    endpoint            = "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com"
    reader_endpoint     = "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
    arn                 = "arn:aws:rds:ap-northeast-1:111111111111:cluster:app-db"
    cluster_resource_id = "cluster-ABCDEFG"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x"
      kms_key_id    = "k"
      secret_status = "active"
    }]
  }
}

override_resource {
  target          = aws_db_proxy.this[0]
  override_during = plan
  values = {
    endpoint = "app-db.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
  }
}

override_resource {
  target          = aws_db_proxy_endpoint.read_only[0]
  override_during = plan
  values = {
    endpoint = "app-db-ro.endpoint.proxy-abc123.ap-northeast-1.rds.amazonaws.com"
  }
}

override_resource {
  target          = random_id.final_snapshot
  override_during = plan
  values          = { hex = "0a1b2c3d" }
}

variables {
  name           = "app-db"
  deployment     = "rds"
  engine_version = "16.4"
  database_name  = "app"
  rds            = { instance_class = "db.t4g.small" }
  subnet_ids     = ["subnet-aaa", "subnet-bbb"]

  security_group_ids = ["sg-0123456789abcdef0"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alarms"]
  alarm_config       = { connections_threshold = 100 }
}

run "alarms_rds_no_proxy" {
  command = plan

  assert {
    condition     = toset(keys(output.alarm_arns)) == toset(["cpu_high_writer", "freeable_memory_low_writer", "connections_high"])
    error_message = "rds without Proxy has exactly three alarms"
  }
}

run "alarms_aurora_with_reader" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 1 }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 2 && length(aws_cloudwatch_metric_alarm.freeable_memory_low) == 2 && length(aws_cloudwatch_metric_alarm.replica_lag_high) == 1
    error_message = "aurora with one reader: per-instance alarms for two instances and a replica lag alarm"
  }

  assert {
    condition     = length(output.alarm_arns) == 6
    error_message = "aurora with one reader and no Proxy has six alarms"
  }
}

run "alarms_aurora_with_reader_and_proxy" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 1 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = length(output.alarm_arns) == 8 && contains(keys(output.alarm_arns), "proxy_borrowed_high") && contains(keys(output.alarm_arns), "proxy_pinned_high")
    error_message = "Proxy adds the borrowed and pinned alarms"
  }
}

run "alarms_serverless_no_reader" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = length(output.alarm_arns) == 3 && length(aws_cloudwatch_metric_alarm.replica_lag_high) == 0
    error_message = "serverless without readers has no replica lag alarm"
  }
}

run "alarm_actions_equal_ok_actions" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alarms", "arn:aws:sns:ap-northeast-1:111111111111:oncall"]
    deployment     = "aurora"
    rds            = null
    aurora         = { instance_class = "db.r7g.large", reader_count = 1 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition = alltrue(flatten([
      [for a in aws_cloudwatch_metric_alarm.cpu_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
      [for a in aws_cloudwatch_metric_alarm.freeable_memory_low : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
      [for a in [aws_cloudwatch_metric_alarm.connections_high] : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
      [for a in aws_cloudwatch_metric_alarm.replica_lag_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
      [for a in aws_cloudwatch_metric_alarm.proxy_borrowed_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
      [for a in aws_cloudwatch_metric_alarm.proxy_pinned_high : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)],
    ]))
    error_message = "every alarm sends alarm_actions and ok_actions to all sns_topic_arns"
  }
}

run "alarm_defaults" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 1 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["writer"].threshold == 80 && aws_cloudwatch_metric_alarm.cpu_high["writer"].period == 300 && aws_cloudwatch_metric_alarm.cpu_high["writer"].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.cpu_high["writer"].datapoints_to_alarm == 3 && aws_cloudwatch_metric_alarm.cpu_high["writer"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "cpu_high: >= 80, 300 s x 3"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.freeable_memory_low["writer"].threshold == 209715200 && aws_cloudwatch_metric_alarm.freeable_memory_low["writer"].period == 60 && aws_cloudwatch_metric_alarm.freeable_memory_low["writer"].evaluation_periods == 15 && aws_cloudwatch_metric_alarm.freeable_memory_low["writer"].datapoints_to_alarm == 15 && aws_cloudwatch_metric_alarm.freeable_memory_low["writer"].comparison_operator == "LessThanOrEqualToThreshold"
    error_message = "freeable_memory_low: <= 200 MiB, 60 s x 15"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.period == 300 && aws_cloudwatch_metric_alarm.connections_high.evaluation_periods == 3 && aws_cloudwatch_metric_alarm.connections_high.datapoints_to_alarm == 2
    error_message = "connections_high: 300 s, 2 of 3"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.replica_lag_high[0].threshold == 1000 && aws_cloudwatch_metric_alarm.replica_lag_high[0].period == 300 && aws_cloudwatch_metric_alarm.replica_lag_high[0].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.replica_lag_high[0].datapoints_to_alarm == 2
    error_message = "replica_lag_high: >= 1000 ms, 300 s, 2 of 3"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].threshold == 80 && aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].evaluation_periods == 5 && aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].comparison_operator == "GreaterThanThreshold"
    error_message = "proxy_borrowed_high: > 80, 5 periods"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.proxy_pinned_high[0].threshold == 20 && aws_cloudwatch_metric_alarm.proxy_pinned_high[0].evaluation_periods == 5 && aws_cloudwatch_metric_alarm.proxy_pinned_high[0].comparison_operator == "GreaterThanThreshold"
    error_message = "proxy_pinned_high: > 20, 5 periods"
  }

  assert {
    condition     = alltrue([for q in aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].metric_query : one(q.metric).period == 60 if q.id != "pct"])
    error_message = "proxy metric queries use 60 s periods"
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].metric_query : q.expression if q.id == "pct"]) == "100 * borrowed / MAX(allowed)" && one([for q in aws_cloudwatch_metric_alarm.proxy_pinned_high[0].metric_query : q.expression if q.id == "pct"]) == "100 * pinned / MAX(allowed)"
    error_message = "proxy alarms compute a percentage of MaxDatabaseConnectionsAllowed"
  }
}

run "alarm_thresholds_override" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 1 }
    proxy = {
      security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      role_arn           = "arn:aws:iam::111111111111:role/app-db-proxy"
    }
    alarm_config = {
      cpu_threshold            = 90
      freeable_memory_bytes    = 1000
      connections_threshold    = 250
      replica_lag_threshold_ms = 500
      proxy_borrowed_percent   = 70
      proxy_pinned_percent     = 10
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["reader-1"].threshold == 90 && aws_cloudwatch_metric_alarm.freeable_memory_low["reader-1"].threshold == 1000 && aws_cloudwatch_metric_alarm.connections_high.threshold == 250
    error_message = "per-instance and connection thresholds follow alarm_config"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.replica_lag_high[0].threshold == 500 && aws_cloudwatch_metric_alarm.proxy_borrowed_high[0].threshold == 70 && aws_cloudwatch_metric_alarm.proxy_pinned_high[0].threshold == 10
    error_message = "replica lag and Proxy thresholds follow alarm_config"
  }
}

run "serverless_connections_formula" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 16 }
    alarm_config = {}
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == floor(min(16 * 2 * 1073741824 / 9531392, 5000) * 0.8)
    error_message = "serverless connection threshold is 80% of max_connections derived from max_capacity"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == 2883
    error_message = "16 ACU gives 2883 (guards against a wrong formula in the assertion itself)"
  }
}

run "serverless_connections_formula_cap" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 64 }
    alarm_config = {}
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == 4000
    error_message = "max_connections is capped at 5000, so the threshold caps at 4000"
  }
}

run "connections_threshold_override_all_modes" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 16 }
    alarm_config = { connections_threshold = 123 }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == 123
    error_message = "an explicit connections_threshold wins over the serverless formula"
  }
}

run "connections_threshold_override_rds" {
  command = plan

  variables {
    alarm_config = { connections_threshold = 321 }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == 321
    error_message = "rds uses the given connections_threshold"
  }
}

run "connections_threshold_override_aurora" {
  command = plan

  variables {
    deployment   = "aurora"
    rds          = null
    aurora       = { instance_class = "db.r7g.large" }
    alarm_config = { connections_threshold = 456 }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.threshold == 456
    error_message = "aurora uses the given connections_threshold"
  }
}

run "connections_dimension_rds" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.dimensions == tomap({ DBInstanceIdentifier = "app-db" })
    error_message = "rds connections alarm uses DBInstanceIdentifier"
  }
}

run "connections_dimension_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connections_high.dimensions == tomap({ DBClusterIdentifier = "app-db" })
    error_message = "aurora connections alarm uses DBClusterIdentifier"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.replica_lag_high[0].dimensions == tomap({ DBClusterIdentifier = "app-db" })
    error_message = "replica lag alarm uses DBClusterIdentifier"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["reader-1"].dimensions == tomap({ DBInstanceIdentifier = "app-db-reader-1" })
    error_message = "per-instance alarms use that instance's DBInstanceIdentifier"
  }
}
