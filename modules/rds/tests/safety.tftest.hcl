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

run "no_password_all_modes_rds" {
  command = plan

  assert {
    condition     = aws_db_instance.this[0].manage_master_user_password == true && aws_db_instance.this[0].password == null && aws_db_instance.this[0].password_wo == null
    error_message = "rds must use the RDS-managed master password and never set one"
  }

  assert {
    condition     = aws_db_instance.this[0].username == "dbadmin"
    error_message = "master_username defaults to dbadmin"
  }
}

run "no_password_all_modes_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = aws_rds_cluster.this[0].manage_master_user_password == true && aws_rds_cluster.this[0].master_password == null && aws_rds_cluster.this[0].master_password_wo == null
    error_message = "aurora must use the RDS-managed master password and never set one"
  }

  assert {
    condition     = aws_rds_cluster.this[0].master_username == "dbadmin"
    error_message = "master_username defaults to dbadmin"
  }
}

run "no_password_all_modes_serverless" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = aws_rds_cluster.this[0].manage_master_user_password == true && aws_rds_cluster.this[0].master_password == null && aws_rds_cluster.this[0].master_password_wo == null
    error_message = "serverless must use the RDS-managed master password and never set one"
  }

  assert {
    condition     = aws_rds_cluster.this[0].master_username == "dbadmin"
    error_message = "master_username defaults to dbadmin"
  }
}

run "master_secret_and_storage_kms_rds" {
  command = plan

  variables {
    kms_key_arn                    = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-1111-1111-1111-111111111111"
    master_user_secret_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/22222222-2222-2222-2222-222222222222"
  }

  assert {
    condition     = aws_db_instance.this[0].kms_key_id == var.kms_key_arn && aws_db_instance.this[0].master_user_secret_kms_key_id == var.master_user_secret_kms_key_arn
    error_message = "storage and master secret use their own keys"
  }
}

run "master_secret_and_storage_kms_aurora" {
  command = plan

  variables {
    deployment                     = "aurora"
    rds                            = null
    aurora                         = { instance_class = "db.r7g.large" }
    kms_key_arn                    = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-1111-1111-1111-111111111111"
    master_user_secret_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/22222222-2222-2222-2222-222222222222"
  }

  assert {
    condition     = aws_rds_cluster.this[0].kms_key_id == var.kms_key_arn && aws_rds_cluster.this[0].master_user_secret_kms_key_id == var.master_user_secret_kms_key_arn
    error_message = "storage and master secret use their own keys"
  }
}

run "log_group_retention_and_kms" {
  command = plan

  variables {
    log_retention_days = 90
    log_kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/33333333-3333-3333-3333-333333333333"
  }

  assert {
    condition     = aws_cloudwatch_log_group.postgresql.retention_in_days == 90 && aws_cloudwatch_log_group.postgresql.kms_key_id == var.log_kms_key_arn
    error_message = "log group retention and KMS follow the inputs"
  }
}

run "final_snapshot_rds" {
  command = plan

  assert {
    condition     = aws_db_instance.this[0].skip_final_snapshot == false && aws_db_instance.this[0].deletion_protection == true
    error_message = "final snapshot and deletion protection are on by default"
  }

  assert {
    condition     = aws_db_instance.this[0].final_snapshot_identifier == "app-db-final-0a1b2c3d"
    error_message = "final snapshot name is <name>-final-<random hex>"
  }
}

run "final_snapshot_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = aws_rds_cluster.this[0].skip_final_snapshot == false && aws_rds_cluster.this[0].deletion_protection == true && aws_rds_cluster.this[0].final_snapshot_identifier == "app-db-final-0a1b2c3d"
    error_message = "aurora final snapshot is <name>-final-<random hex>, deletion protection on"
  }
}

run "skip_final_snapshot_has_no_name" {
  command = plan

  variables {
    skip_final_snapshot = true
    deletion_protection = false
  }

  assert {
    condition     = aws_db_instance.this[0].skip_final_snapshot == true && aws_db_instance.this[0].final_snapshot_identifier == null && aws_db_instance.this[0].deletion_protection == false
    error_message = "skipping the snapshot must not set a snapshot name"
  }
}

run "subnet_and_sg_from_inputs" {
  command = plan

  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(["subnet-aaa", "subnet-bbb"]) && aws_db_instance.this[0].vpc_security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "subnet group and DB SGs come from the inputs"
  }
}

run "subnet_and_sg_from_inputs_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(["subnet-aaa", "subnet-bbb"]) && aws_rds_cluster.this[0].vpc_security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "subnet group and cluster SGs come from the inputs"
  }
}
