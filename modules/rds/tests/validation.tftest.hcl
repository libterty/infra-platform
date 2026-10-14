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

run "deployment_values_rejects_mysql" {
  command = plan

  variables {
    deployment = "mysql"
  }

  expect_failures = [var.deployment]
}

run "deployment_object_aurora_given_rds" {
  command = plan

  variables {
    deployment = "aurora"
  }

  expect_failures = [var.deployment]
}

run "deployment_object_aurora_extra_serverless" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
    serverless = { min_capacity = 0.5, max_capacity = 4 }
  }

  expect_failures = [var.deployment]
}

run "deployment_object_rds_extra_aurora" {
  command = plan

  variables {
    aurora = { instance_class = "db.r7g.large" }
  }

  expect_failures = [var.deployment]
}

run "deployment_object_serverless_given_none" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
  }

  expect_failures = [var.deployment]
}

run "deployment_object_rds_ok" {
  command = plan

  variables {
    deployment = "rds"
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "deployment_object_aurora_ok" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "deployment_object_serverless_ok" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "aurora_class_serverless_rejected" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.serverless" }
  }

  expect_failures = [var.aurora]
}

run "aurora_class_without_db_prefix_rejected" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "r7g.large" }
  }

  expect_failures = [var.aurora]
}

run "aurora_class_ok" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "acu_min_above_max" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 2, max_capacity = 1 }
  }

  expect_failures = [var.serverless]
}

run "acu_max_above_256" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 1, max_capacity = 257 }
  }

  expect_failures = [var.serverless]
}

run "acu_negative_min" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = -0.5, max_capacity = 4 }
  }

  expect_failures = [var.serverless]
}

run "acu_full_range_ok" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 0, max_capacity = 256 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "acu_step_min_rejected" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 0.75, max_capacity = 4 }
  }

  expect_failures = [var.serverless]
}

run "acu_step_max_ok" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 0.5, max_capacity = 1.5 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "reader_count_aurora_16" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 16 }
  }

  expect_failures = [var.aurora]
}

run "reader_count_aurora_15" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large", reader_count = 15 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "reader_count_serverless_16" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 1, max_capacity = 4, reader_count = 16 }
  }

  expect_failures = [var.serverless]
}

run "reader_count_serverless_15" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 1, max_capacity = 4, reader_count = 15 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "rds_rejects_cluster_parameters" {
  command = plan

  variables {
    cluster_parameters = { log_temp_files = "0" }
  }

  expect_failures = [var.cluster_parameters]
}

run "aurora_accepts_cluster_parameters" {
  command = plan

  variables {
    deployment         = "aurora"
    rds                = null
    aurora             = { instance_class = "db.r7g.large" }
    cluster_parameters = { log_temp_files = "0" }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "proxy_role_arn_required" {
  command = plan

  variables {
    proxy = { security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"] }
  }

  expect_failures = [var.proxy]
}

run "proxy_role_arn_format" {
  command = plan

  variables {
    proxy = { security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"], role_arn = "my-role" }
  }

  expect_failures = [var.proxy]
}

run "proxy_role_arn_ok" {
  command = plan

  variables {
    proxy = { security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"], role_arn = "arn:aws:iam::111111111111:role/app-db-proxy" }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "connections_threshold_required_rds" {
  command = plan

  variables {
    alarm_config = {}
  }

  expect_failures = [var.alarm_config]
}

run "connections_threshold_required_aurora" {
  command = plan

  variables {
    deployment   = "aurora"
    rds          = null
    aurora       = { instance_class = "db.r7g.large" }
    alarm_config = {}
  }

  expect_failures = [var.alarm_config]
}

run "connections_threshold_optional_serverless" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    alarm_config = {}
    serverless   = { min_capacity = 1, max_capacity = 4 }
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "sns_topic_required" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "sns_topic_must_be_arn" {
  command = plan

  variables {
    sns_topic_arns = ["alarms"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "name_format_uppercase" {
  command = plan

  variables {
    name = "App-Db"
  }

  expect_failures = [var.name]
}

run "name_format_double_hyphen" {
  command = plan

  variables {
    name = "app--db"
  }

  expect_failures = [var.name]
}

run "name_format_trailing_hyphen" {
  command = plan

  variables {
    name = "app-db-"
  }

  expect_failures = [var.name]
}

run "name_format_too_long" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }

  expect_failures = [var.name]
}

run "name_format_50_chars_ok" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "engine_version_12" {
  command = plan

  variables {
    engine_version = "12.1"
  }

  expect_failures = [var.engine_version]
}

run "engine_version_major_only" {
  command = plan

  variables {
    engine_version = "16"
  }

  expect_failures = [var.engine_version]
}

run "engine_version_ok" {
  command = plan

  variables {
    engine_version = "16.4"
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "database_name_format" {
  command = plan

  variables {
    database_name = "App-DB"
  }

  expect_failures = [var.database_name]
}

run "database_name_ok" {
  command = plan

  variables {
    database_name = "app"
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "backup_retention_0" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "backup_retention_36" {
  command = plan

  variables {
    backup_retention_days = 36
  }

  expect_failures = [var.backup_retention_days]
}

run "backup_retention_ok_1" {
  command = plan

  variables {
    backup_retention_days = 1
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "backup_retention_ok_35" {
  command = plan

  variables {
    backup_retention_days = 35
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}

run "subnet_count_one" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "subnet_count_duplicates" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaa", "subnet-aaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "monitoring_interval_invalid" {
  command = plan

  variables {
    monitoring = { interval = 20, role_arn = "arn:aws:iam::111111111111:role/m" }
  }

  expect_failures = [var.monitoring]
}

run "pi_retention_invalid" {
  command = plan

  variables {
    performance_insights_retention_days = 10
  }

  expect_failures = [var.performance_insights_retention_days]
}

run "pi_retention_731_ok" {
  command = plan

  variables {
    performance_insights_retention_days = 731
  }

  assert {
    condition     = output.port == 5432
    error_message = "valid input must plan"
  }
}
