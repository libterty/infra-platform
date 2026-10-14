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

run "rds_basic" {
  command = plan

  assert {
    condition     = length(aws_db_parameter_group.rds) == 1 && length(aws_db_instance.this) == 1
    error_message = "rds creates one parameter group and one instance"
  }

  assert {
    condition     = aws_db_parameter_group.rds[0].family == "postgres16"
    error_message = "rds parameter group family is postgres<major>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.postgresql.name == "/aws/rds/instance/app-db/postgresql"
    error_message = "rds log group is /aws/rds/instance/<name>/postgresql"
  }

  assert {
    condition     = length(aws_rds_cluster.this) == 0 && length(aws_rds_cluster_instance.this) == 0 && length(aws_rds_cluster_parameter_group.this) == 0 && length(aws_db_parameter_group.aurora_instance) == 0
    error_message = "rds must not create any Aurora resource"
  }

  assert {
    condition     = aws_db_instance.this[0].allocated_storage == 20 && aws_db_instance.this[0].storage_type == "gp3" && aws_db_instance.this[0].multi_az == false && aws_db_instance.this[0].max_allocated_storage == null
    error_message = "rds defaults: 20 GiB gp3, single AZ, no storage autoscaling"
  }

  assert {
    condition     = aws_db_instance.this[0].instance_class == "db.t4g.small" && aws_db_instance.this[0].engine == "postgres"
    error_message = "rds instance class and engine come from inputs"
  }
}

run "rds_storage_overrides" {
  command = plan

  variables {
    rds = {
      instance_class        = "db.m7g.large"
      allocated_storage     = 100
      max_allocated_storage = 500
      multi_az              = true
      storage_type          = "io2"
    }
  }

  assert {
    condition     = aws_db_instance.this[0].allocated_storage == 100 && aws_db_instance.this[0].max_allocated_storage == 500 && aws_db_instance.this[0].multi_az == true && aws_db_instance.this[0].storage_type == "io2"
    error_message = "rds storage settings must follow the rds object"
  }
}

run "aurora_basic" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = length(aws_rds_cluster.this) == 1 && length(aws_rds_cluster_parameter_group.this) == 1 && length(aws_rds_cluster_instance.this) == 2
    error_message = "aurora with the default reader_count (1) creates one cluster, one parameter group and two instances"
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.this[0].family == "aurora-postgresql16"
    error_message = "aurora cluster parameter group family is aurora-postgresql<major>"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.instance_class == "db.r7g.large"])
    error_message = "every aurora instance uses the given class"
  }

  assert {
    condition     = aws_cloudwatch_log_group.postgresql.name == "/aws/rds/cluster/app-db/postgresql"
    error_message = "aurora log group is /aws/rds/cluster/<name>/postgresql"
  }

  assert {
    condition     = length(aws_db_instance.this) == 0 && length(aws_db_parameter_group.rds) == 0
    error_message = "aurora must not create rds resources"
  }

  assert {
    condition     = length(aws_rds_cluster.this[0].serverlessv2_scaling_configuration) == 0
    error_message = "provisioned aurora has no serverlessv2_scaling_configuration"
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].promotion_tier == 0 && aws_rds_cluster_instance.this[1].promotion_tier == 1
    error_message = "index 0 is the writer with the highest promotion priority"
  }
}

run "serverless_basic" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = length(aws_rds_cluster.this[0].serverlessv2_scaling_configuration) == 1 && one(aws_rds_cluster.this[0].serverlessv2_scaling_configuration).min_capacity == 0.5 && one(aws_rds_cluster.this[0].serverlessv2_scaling_configuration).max_capacity == 4
    error_message = "serverless scaling configuration must equal min/max capacity"
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 1 && aws_rds_cluster_instance.this[0].instance_class == "db.serverless"
    error_message = "serverless defaults to a single db.serverless instance"
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.this[0].family == "aurora-postgresql16"
    error_message = "serverless shares the aurora cluster parameter group address and family"
  }
}

run "serverless_with_readers" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 1, max_capacity = 8, reader_count = 2 }
    alarm_config = {}
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 3 && alltrue([for i in aws_rds_cluster_instance.this : i.instance_class == "db.serverless"])
    error_message = "reader_count adds db.serverless readers"
  }
}

run "aurora_instance_param_group_absent_when_empty" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = length(aws_db_parameter_group.aurora_instance) == 0
    error_message = "no instance parameter group without instance_parameters"
  }
}

run "aurora_instance_param_group_present_when_set" {
  command = plan

  variables {
    deployment          = "aurora"
    rds                 = null
    aurora              = { instance_class = "db.r7g.large" }
    instance_parameters = { "idle_in_transaction_session_timeout" = "60000" }
  }

  assert {
    condition     = length(aws_db_parameter_group.aurora_instance) == 1 && aws_db_parameter_group.aurora_instance[0].family == "aurora-postgresql16"
    error_message = "non-empty instance_parameters create one aurora-postgresql<major> parameter group"
  }

  assert {
    condition     = { for p in aws_db_parameter_group.aurora_instance[0].parameter : p.name => p.value } == { "idle_in_transaction_session_timeout" = "60000" }
    error_message = "the aurora instance group carries only instance_parameters"
  }
}

run "engine_major_selects_family" {
  command = plan

  variables {
    engine_version = "17.2"
  }

  assert {
    condition     = aws_db_parameter_group.rds[0].family == "postgres17"
    error_message = "family follows the major part of engine_version"
  }
}

run "fixed_settings_rds" {
  command = plan

  assert {
    condition     = aws_db_instance.this[0].storage_encrypted == true && aws_db_instance.this[0].publicly_accessible == false && aws_db_instance.this[0].copy_tags_to_snapshot == true
    error_message = "rds is encrypted, private and copies tags to snapshots"
  }

  assert {
    condition     = aws_db_instance.this[0].performance_insights_enabled == true && aws_db_instance.this[0].performance_insights_retention_period == 7
    error_message = "Performance Insights is on with 7 days by default"
  }

  assert {
    condition     = aws_db_instance.this[0].enabled_cloudwatch_logs_exports == toset(["postgresql"])
    error_message = "only the postgresql log is exported"
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.value } == { log_min_duration_statement = "500", log_lock_waits = "1", "rds.force_ssl" = "1", shared_preload_libraries = "pg_stat_statements" }
    error_message = "the four default parameters must be set"
  }
}

run "fixed_settings_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = aws_rds_cluster.this[0].storage_encrypted == true && aws_rds_cluster.this[0].copy_tags_to_snapshot == true && aws_rds_cluster.this[0].enabled_cloudwatch_logs_exports == toset(["postgresql"])
    error_message = "aurora cluster is encrypted, copies tags and exports only the postgresql log"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.publicly_accessible == false && i.performance_insights_enabled == true && i.performance_insights_retention_period == 7])
    error_message = "aurora instances are private with Performance Insights on"
  }

  assert {
    condition     = { for p in aws_rds_cluster_parameter_group.this[0].parameter : p.name => p.value } == { log_min_duration_statement = "500", log_lock_waits = "1", "rds.force_ssl" = "1", shared_preload_libraries = "pg_stat_statements" }
    error_message = "the four default parameters must be set in the cluster parameter group"
  }
}

run "fixed_settings_serverless" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = aws_rds_cluster.this[0].storage_encrypted == true && aws_rds_cluster.this[0].copy_tags_to_snapshot == true && aws_rds_cluster.this[0].enabled_cloudwatch_logs_exports == toset(["postgresql"])
    error_message = "serverless cluster is encrypted, copies tags and exports only the postgresql log"
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].publicly_accessible == false && aws_rds_cluster_instance.this[0].performance_insights_enabled == true
    error_message = "serverless instances are private with Performance Insights on"
  }
}

run "caller_parameters_override_defaults" {
  command = plan

  variables {
    instance_parameters = { log_min_duration_statement = "1000", work_mem = "8192" }
  }

  assert {
    condition     = { for p in aws_db_parameter_group.rds[0].parameter : p.name => p.value } == { log_min_duration_statement = "1000", log_lock_waits = "1", "rds.force_ssl" = "1", shared_preload_libraries = "pg_stat_statements", work_mem = "8192" }
    error_message = "caller parameters override defaults of the same name and add new ones"
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.rds[0].parameter : p.apply_method if p.name == "shared_preload_libraries"]) == "pending-reboot"
    error_message = "shared_preload_libraries is static and needs pending-reboot"
  }
}

run "caller_cluster_parameters_override_defaults" {
  command = plan

  variables {
    deployment         = "aurora"
    rds                = null
    aurora             = { instance_class = "db.r7g.large" }
    cluster_parameters = { "rds.force_ssl" = "0", log_temp_files = "0" }
  }

  assert {
    condition     = { for p in aws_rds_cluster_parameter_group.this[0].parameter : p.name => p.value } == { log_min_duration_statement = "500", log_lock_waits = "1", "rds.force_ssl" = "0", shared_preload_libraries = "pg_stat_statements", log_temp_files = "0" }
    error_message = "cluster_parameters override defaults of the same name and add new ones"
  }
}

run "backup_and_windows_rds" {
  command = plan

  assert {
    condition     = aws_db_instance.this[0].backup_retention_period == 7 && aws_db_instance.this[0].backup_window == "18:00-19:00" && aws_db_instance.this[0].maintenance_window == "sun:19:00-sun:20:00"
    error_message = "rds backup and maintenance defaults"
  }
}

run "backup_and_windows_aurora" {
  command = plan

  variables {
    deployment            = "aurora"
    rds                   = null
    aurora                = { instance_class = "db.r7g.large" }
    backup_retention_days = 14
    backup_window         = "17:00-18:00"
    maintenance_window    = "mon:18:00-mon:19:00"
  }

  assert {
    condition     = aws_rds_cluster.this[0].backup_retention_period == 14 && aws_rds_cluster.this[0].preferred_backup_window == "17:00-18:00" && aws_rds_cluster.this[0].preferred_maintenance_window == "mon:18:00-mon:19:00"
    error_message = "aurora backup and maintenance settings follow the inputs"
  }
}

run "tags_and_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_db_instance.this[0].tags == tomap({ Project = "alpha", Name = "app-db" })
    error_message = "input tags are kept and Name is added"
  }
}

run "outputs_rds" {
  command = plan

  assert {
    condition     = output.writer_endpoint == "app-db.abc123.ap-northeast-1.rds.amazonaws.com" && output.reader_endpoint == output.writer_endpoint
    error_message = "rds writer is the address without port and the reader equals it"
  }

  assert {
    condition     = output.has_reader == false && output.port == 5432 && output.identifier_type == "instance" && output.cluster_id == null
    error_message = "rds outputs: no reader, port 5432, instance, no cluster id"
  }

  assert {
    condition     = length(output.instance_ids) == 1 && output.db_identifier == "app-db" && output.instance_ids[0] == "app-db"
    error_message = "rds has one instance named after the module"
  }

  assert {
    condition     = output.cloudwatch_dimension.name == "DBInstanceIdentifier" && output.cloudwatch_dimension.value == "app-db"
    error_message = "rds dimension is DBInstanceIdentifier"
  }

  assert {
    condition     = output.master_user_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x" && output.arn == "arn:aws:rds:ap-northeast-1:111111111111:db:app-db" && output.resource_id == "db-ABCDEFG"
    error_message = "rds secret ARN, ARN and resource id come from the instance"
  }
}

run "outputs_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = output.writer_endpoint == "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com" && output.reader_endpoint == "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
    error_message = "aurora endpoints are the cluster writer and reader endpoints"
  }

  assert {
    condition     = output.has_reader == true && output.identifier_type == "cluster" && output.cluster_id == "app-db"
    error_message = "aurora with a reader: has_reader, cluster type, cluster id"
  }

  assert {
    condition     = output.instance_ids == tolist(["app-db-writer", "app-db-reader-1"])
    error_message = "instance_ids are ordered with the writer first"
  }

  assert {
    condition     = output.cloudwatch_dimension.name == "DBClusterIdentifier" && output.cloudwatch_dimension.value == "app-db"
    error_message = "aurora dimension is DBClusterIdentifier"
  }

  assert {
    condition     = output.master_user_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x" && output.resource_id == "cluster-ABCDEFG"
    error_message = "aurora secret ARN and resource id come from the cluster"
  }
}

run "outputs_serverless_no_reader" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = output.has_reader == false && output.reader_endpoint == "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com" && length(output.instance_ids) == 1
    error_message = "without readers has_reader is false but reader_endpoint is still the cluster RO endpoint"
  }
}
