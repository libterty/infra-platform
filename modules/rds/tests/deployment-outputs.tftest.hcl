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

run "deployment_output_rds" {
  command = plan

  assert {
    condition     = output.deployment == "rds"
    error_message = "deployment output must equal the input for rds"
  }

  assert {
    condition     = output.database_name == "app"
    error_message = "database_name output must equal the input for rds"
  }
}

run "deployment_output_aurora" {
  command = plan

  variables {
    deployment = "aurora"
    rds        = null
    aurora     = { instance_class = "db.r7g.large" }
  }

  assert {
    condition     = output.deployment == "aurora"
    error_message = "deployment output must equal the input for aurora"
  }

  assert {
    condition     = output.database_name == "app"
    error_message = "database_name output must equal the input for aurora"
  }
}

run "deployment_output_serverless" {
  command = plan

  variables {
    deployment   = "aurora_serverless"
    rds          = null
    serverless   = { min_capacity = 0.5, max_capacity = 4 }
    alarm_config = {}
  }

  assert {
    condition     = output.deployment == "aurora_serverless"
    error_message = "deployment output must equal the input for aurora_serverless"
  }

  assert {
    condition     = output.database_name == "app"
    error_message = "database_name output must equal the input for aurora_serverless"
  }
}

# A value other than the shared default, so a hard-coded output cannot pass.
run "database_name_output_follows_input" {
  command = plan

  variables {
    database_name = "kb"
  }

  assert {
    condition     = output.database_name == "kb"
    error_message = "database_name output must follow the input"
  }
}
