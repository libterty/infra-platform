# Run by scripts/validate.sh once per file in envs/examples/ with -var-file, so the examples cannot rot.
# Assertions hold for any valid example; do not set variables here, they would hide the example values.
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

run "example_object_matches_deployment" {
  command = plan

  assert {
    condition     = var.db.deployment == "rds" ? (var.db.rds != null && var.db.aurora == null && var.db.serverless == null) : (var.db.deployment == "aurora" ? (var.db.aurora != null && var.db.rds == null && var.db.serverless == null) : (var.db.serverless != null && var.db.rds == null && var.db.aurora == null))
    error_message = "Exactly the object matching deployment must be set"
  }

  assert {
    condition     = length(module.db) == 1
    error_message = "The example must create a database through the rds module"
  }
}

run "example_sets_connections_threshold_for_rds_and_aurora" {
  command = plan

  assert {
    condition     = var.db.deployment == "aurora_serverless" || var.db.alarm_config.connections_threshold != null
    error_message = "rds and aurora cannot derive connections_threshold offline; the example must set it"
  }
}

run "example_works_with_a_proxy_too" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/db_proxy"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  assert {
    condition     = local.db_wiring.proxy != null
    error_message = "An example must also plan with a Proxy decided by the network stack"
  }
}
