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

run "defaults_keep_only_shared_preload_libraries_static" {
  command = plan

  variables {
    instance_parameters = { "log_statement" = "ddl", "cron.database_name" = "app" }
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.apply_method } == { shared_preload_libraries = "pending-reboot", log_min_duration_statement = "immediate", log_lock_waits = "immediate", "rds.force_ssl" = "immediate", log_statement = "immediate", "cron.database_name" = "immediate" }
    error_message = "Without static_parameter_names only shared_preload_libraries is pending-reboot"
  }
}

run "listed_parameter_uses_pending_reboot_on_rds" {
  command = plan

  variables {
    static_parameter_names = ["cron.database_name"]
    instance_parameters    = { "log_statement" = "ddl", "cron.database_name" = "app" }
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.apply_method }["cron.database_name"] == "pending-reboot"
    error_message = "A listed parameter must use pending-reboot"
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.apply_method }["log_statement"] == "immediate"
    error_message = "A parameter outside the list must stay immediate"
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.apply_method }["shared_preload_libraries"] == "pending-reboot"
    error_message = "shared_preload_libraries must stay pending-reboot (union with the built-in list)"
  }
}

run "listed_parameter_uses_pending_reboot_on_aurora_cluster_and_instance" {
  command = plan

  variables {
    deployment             = "aurora"
    rds                    = null
    aurora                 = { instance_class = "db.r7g.large" }
    static_parameter_names = ["cron.database_name", "max_connections"]
    cluster_parameters     = { "cron.database_name" = "app", "log_statement" = "ddl" }
    instance_parameters    = { "max_connections" = "200", "log_temp_files" = "0" }
  }

  assert {
    condition     = { for p in aws_rds_cluster_parameter_group.this[0].parameter : p.name => p.apply_method }["cron.database_name"] == "pending-reboot"
    error_message = "Listed cluster parameter must use pending-reboot"
  }

  assert {
    condition     = { for p in aws_rds_cluster_parameter_group.this[0].parameter : p.name => p.apply_method }["log_statement"] == "immediate"
    error_message = "Unlisted cluster parameter must stay immediate"
  }

  assert {
    condition     = { for p in aws_db_parameter_group.aurora_instance[0].parameter : p.name => p.apply_method } == { max_connections = "pending-reboot", log_temp_files = "immediate" }
    error_message = "Instance parameter group must follow the same list"
  }
}

run "listed_name_not_in_parameters_is_ignored" {
  command = plan

  variables {
    static_parameter_names = ["cron.database_name"]
  }

  assert {
    condition     = length(aws_db_parameter_group.rds[0].parameter) == 4
    error_message = "A listed name that is not a parameter must not create one"
  }
}

run "duplicate_of_builtin_is_harmless" {
  command = plan

  variables {
    static_parameter_names = ["shared_preload_libraries"]
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.apply_method }["shared_preload_libraries"] == "pending-reboot"
    error_message = "Listing the built-in static parameter must work"
  }
}

run "log_group_name_for_rds" {
  command = plan

  assert {
    condition     = output.log_group_name == "/aws/rds/instance/app-db/postgresql"
    error_message = "rds log group name must be /aws/rds/instance/<name>/postgresql"
  }

  assert {
    condition     = output.log_group_name == aws_cloudwatch_log_group.postgresql.name
    error_message = "log_group_name must be the log group the module creates"
  }
}

run "log_group_name_for_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = output.log_group_name == "/aws/rds/cluster/app-db/postgresql"
    error_message = "aurora log group name must be /aws/rds/cluster/<name>/postgresql"
  }
}
