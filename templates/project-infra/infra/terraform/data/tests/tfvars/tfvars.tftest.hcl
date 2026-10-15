# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, network and iam-base publish.
mock_provider "aws" {}

mock_provider "random" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_db_id"]
  values = { insecure_value = "sg-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_db_proxy_id"]
  values = { insecure_value = "sg-0123456789abcdef1" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/db_proxy"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_rds_proxy_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_rds_monitoring_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-rds-monitoring" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

run "tfvars_create_the_database" {
  command = plan

  assert {
    condition     = var.db != null && length(module.db) == 1
    error_message = "tfvars must describe a database; with db unset the plan would delete an existing one"
  }

  assert {
    condition     = var.db.deployment == "rds" ? var.db.rds != null : (var.db.deployment == "aurora" ? var.db.aurora != null : var.db.serverless != null)
    error_message = "The object matching deployment must be set"
  }
}

run "tfvars_set_a_connections_threshold_where_required" {
  command = plan

  assert {
    condition     = var.db.deployment == "aurora_serverless" || var.db.alarm_config.connections_threshold != null
    error_message = "rds and aurora need alarm_config.connections_threshold"
  }
}
