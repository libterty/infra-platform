mock_provider "aws" {}

mock_provider "random" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"

  db = {
    deployment     = "aurora_serverless"
    engine_version = "16.4"
    database_name  = "app"
    serverless     = { min_capacity = 0.5, max_capacity = 4 }
  }
}

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

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == {
        kms_key_arn             = "foundation/kms_key_arn"
        alarm_topic_arn         = "foundation/alarm_topic_arn"
        sg_db_id                = "network/sg_db_id"
        sg_db_proxy_id          = "network/sg_db_proxy_id"
        db_proxy                = "network/db_proxy"
        role_rds_proxy_arn      = "iam-base/role_rds_proxy_arn"
        role_rds_monitoring_arn = "iam-base/role_rds_monitoring_arn"
      } &&
      local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    )
    error_message = "data must read the data subnets, the database and Proxy security groups, the Proxy decision, the two RDS roles, the key and the alarm topic"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition     = module.ssm_publish.names == { database = "/alpha/dev/data/database" }
    error_message = "ssm-publish must write only the database key under the data path"
  }
}

run "database_json_shape" {
  command = plan

  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      app_endpoint           = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      app_reader_endpoint    = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      writer_endpoint        = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint        = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      proxy_endpoint         = null
      has_reader             = false
      deployment             = "aurora_serverless"
      database_name          = "app"
      arn                    = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    }
  }

  assert {
    condition = toset(keys(jsondecode(local.database))) == toset([
      "enabled", "deployment", "port", "name", "secret_arn",
      "app_endpoint", "app_reader_endpoint", "writer_endpoint", "reader_endpoint", "proxy_endpoint", "has_reader",
      "cluster_arn", "data_api",
    ])
    error_message = "The database JSON must have every field of the SSM contract"
  }

  assert {
    condition = jsondecode(local.database) == {
      enabled             = true
      deployment          = "aurora_serverless"
      port                = 5432
      name                = "app"
      secret_arn          = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      app_endpoint        = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      app_reader_endpoint = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      writer_endpoint     = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint     = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      proxy_endpoint      = null
      has_reader          = false
      cluster_arn         = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      data_api            = false
    }
    error_message = "The values must come from the rds module outputs and the db variable; proxy_endpoint is null without a Proxy"
  }

  assert {
    condition     = local.published_strings["database"] == local.database
    error_message = "The JSON must be published as the database key"
  }
}

run "database_json_with_proxy" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/db_proxy"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      app_endpoint           = "alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      app_reader_endpoint    = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      writer_endpoint        = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint        = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      proxy_endpoint         = "alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      has_reader             = false
    }
  }

  assert {
    condition     = jsondecode(local.database).app_endpoint == jsondecode(local.database).proxy_endpoint && jsondecode(local.database).proxy_endpoint == "alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
    error_message = "With a Proxy the application endpoint is the Proxy endpoint"
  }
}

run "disabled_database" {
  command = plan

  variables {
    db = null
  }

  assert {
    condition     = length(module.db) == 0
    error_message = "db = null must not call the rds module"
  }

  assert {
    condition     = jsondecode(local.database) == { enabled = false } && local.published_strings["database"] == "{\"enabled\":false}"
    error_message = "A missing database must be published as {\"enabled\":false}"
  }
}

run "proxy_follows_network_disabled" {
  command = plan

  assert {
    condition     = local.proxy_enabled == false && local.db_wiring.proxy == null
    error_message = "db_proxy false must pass no proxy to rds"
  }
}

run "proxy_follows_network_enabled" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/db_proxy"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  assert {
    condition     = local.proxy_enabled && local.db_wiring.proxy.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy"
    error_message = "db_proxy true must pass the Proxy role from iam-base"
  }

  assert {
    condition     = local.db_wiring.proxy.security_group_ids == ["sg-0123456789abcdef1"]
    error_message = "db_proxy true must pass the Proxy security group from network"
  }
}

run "wired_from_upstream" {
  command = plan

  assert {
    condition = (
      tolist(local.db_wiring.subnet_ids) == tolist(["subnet-0dat1", "subnet-0dat2"]) &&
      local.db_wiring.security_group_ids == ["sg-0123456789abcdef0"] &&
      local.db_wiring.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/0000" &&
      local.db_wiring.master_user_secret_kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/0000" &&
      local.db_wiring.monitoring.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-rds-monitoring" &&
      local.db_wiring.sns_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    )
    error_message = "Subnets, security group, key, monitoring role and alarm topic must all come from the upstream stacks"
  }
}

run "deployment_rds_passes" {
  command = plan

  variables {
    db = {
      deployment     = "rds"
      engine_version = "16.4"
      database_name  = "app"
      rds            = { instance_class = "db.t4g.micro" }
      alarm_config   = { connections_threshold = 80 }
    }
  }

  assert {
    condition     = module.db[0].identifier_type == "instance" && module.db[0].has_reader == false
    error_message = "deployment rds must create a single instance"
  }
}

run "deployment_aurora_passes" {
  command = plan

  variables {
    db = {
      deployment     = "aurora"
      engine_version = "16.4"
      database_name  = "app"
      aurora         = { instance_class = "db.r7g.large", reader_count = 1 }
      alarm_config   = { connections_threshold = 800 }
    }
  }

  assert {
    condition     = module.db[0].identifier_type == "cluster" && module.db[0].has_reader == true
    error_message = "deployment aurora must create a cluster with a reader"
  }
}

run "deployment_serverless_passes" {
  command = plan

  assert {
    condition     = module.db[0].identifier_type == "cluster" && module.db[0].has_reader == false
    error_message = "deployment aurora_serverless must create a cluster; reader_count defaults to 0"
  }
}

run "optional_settings_fall_back_to_module_defaults" {
  command = plan

  variables {
    db = {
      deployment     = "aurora_serverless"
      engine_version = "16.4"
      database_name  = "app"
      serverless     = { min_capacity = 0.5, max_capacity = 4, reader_count = 2 }
      alarm_config   = {}
    }
  }

  assert {
    condition     = module.db[0].has_reader == true
    error_message = "reader_count must reach the module"
  }
}

run "data_api_off_by_default" {
  command = plan

  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      deployment             = "aurora_serverless"
      database_name          = "app"
      arn                    = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    }
  }

  assert {
    condition     = local.data_api == false && jsondecode(local.database).data_api == false
    error_message = "Without db.data_api the Data API must stay off and the JSON must say so"
  }
}

run "data_api_passed_and_published" {
  command = plan

  variables {
    db = {
      deployment     = "aurora_serverless"
      engine_version = "16.4"
      database_name  = "app"
      serverless     = { min_capacity = 0.5, max_capacity = 4 }
      data_api       = true
    }
  }

  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      deployment             = "aurora_serverless"
      database_name          = "app"
      arn                    = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    }
  }

  assert {
    condition     = local.data_api == true
    error_message = "db.data_api must be passed to the rds module"
  }

  assert {
    condition     = jsondecode(local.database).data_api == true && jsondecode(local.database).cluster_arn == "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    error_message = "The JSON must carry data_api and the cluster ARN from the rds arn output"
  }
}

run "database_json_from_rds_outputs" {
  command = plan

  # Values that differ from var.db prove the JSON is built from the module outputs, not from the variable.
  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      deployment             = "aurora"
      database_name          = "kb"
      arn                    = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    }
  }

  assert {
    condition     = jsondecode(local.database).deployment == "aurora" && jsondecode(local.database).name == "kb"
    error_message = "deployment and name must come from the rds outputs deployment and database_name"
  }
}

run "cluster_arn_null_for_rds" {
  command = plan

  variables {
    db = {
      deployment     = "rds"
      engine_version = "16.4"
      database_name  = "app"
      rds            = { instance_class = "db.t4g.micro" }
      alarm_config   = { connections_threshold = 80 }
    }
  }

  override_module {
    target = module.db[0]
    outputs = {
      port                   = 5432
      master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-0000"
      deployment             = "rds"
      database_name          = "app"
      arn                    = "arn:aws:rds:ap-northeast-1:111111111111:db:alpha-dev-db"
    }
  }

  assert {
    condition     = jsondecode(local.database).cluster_arn == null && jsondecode(local.database).data_api == false
    error_message = "A single RDS instance has no cluster ARN"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
