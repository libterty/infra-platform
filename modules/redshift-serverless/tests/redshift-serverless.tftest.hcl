mock_provider "aws" {}

override_resource {
  target          = aws_redshiftserverless_workgroup.this
  override_during = plan
  values = {
    arn      = "arn:aws:redshift-serverless:ap-northeast-1:111111111111:workgroup/11111111-2222-3333-4444-555555555555"
    endpoint = [{ address = "alpha-dev-wh.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com", port = 5439, vpc_endpoint = [] }]
  }
}

variables {
  name               = "alpha-dev-wh"
  db_name            = "analytics"
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  subnet_ids         = ["subnet-0a1b2c3d", "subnet-1a2b3c4d", "subnet-2a3b4c5d"]
  security_group_ids = ["sg-0a1b2c3d4e5f60718"]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "defaults_use_the_smallest_capacity" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_workgroup.this.base_capacity == 4
    error_message = "base_capacity must default to 4 RPU"
  }

  assert {
    condition     = aws_redshiftserverless_workgroup.this.max_capacity == null
    error_message = "max_capacity must be unset unless given"
  }

  assert {
    condition     = aws_redshiftserverless_namespace.this.namespace_name == "alpha-dev-wh" && aws_redshiftserverless_workgroup.this.workgroup_name == "alpha-dev-wh"
    error_message = "Namespace and workgroup must both take var.name"
  }

  assert {
    condition     = aws_redshiftserverless_namespace.this.db_name == "analytics" && aws_redshiftserverless_namespace.this.admin_username == "dbadmin"
    error_message = "db_name and admin_username must be passed through"
  }
}

run "base_8_with_max_is_accepted" {
  command = plan

  variables {
    base_capacity = 8
    max_capacity  = 16
  }

  assert {
    condition     = aws_redshiftserverless_workgroup.this.base_capacity == 8 && aws_redshiftserverless_workgroup.this.max_capacity == 16
    error_message = "Capacities must be passed through"
  }
}

run "base_512_is_the_upper_bound" {
  command = plan

  variables {
    base_capacity = 512
  }

  assert {
    condition     = aws_redshiftserverless_workgroup.this.base_capacity == 512
    error_message = "512 RPU must be accepted"
  }
}

run "enhanced_vpc_routing_is_on_by_default" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_workgroup.this.enhanced_vpc_routing == true
    error_message = "enhanced_vpc_routing must default to true"
  }
}

run "two_subnets_are_enough_without_evr" {
  command = plan

  variables {
    enhanced_vpc_routing = false
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-1a2b3c4d"]
  }

  assert {
    condition     = aws_redshiftserverless_workgroup.this.enhanced_vpc_routing == false && length(aws_redshiftserverless_workgroup.this.subnet_ids) == 2
    error_message = "Two subnets must be accepted when enhanced VPC routing is off"
  }
}

run "usage_limit_is_monthly_and_deactivates" {
  command = plan

  variables {
    usage_limit_rpu_hours = 100
  }

  assert {
    condition     = length(aws_redshiftserverless_usage_limit.this) == 1
    error_message = "A usage limit must be created when usage_limit_rpu_hours is set"
  }

  assert {
    condition     = aws_redshiftserverless_usage_limit.this[0].amount == 100 && aws_redshiftserverless_usage_limit.this[0].usage_type == "serverless-compute" && aws_redshiftserverless_usage_limit.this[0].period == "monthly" && aws_redshiftserverless_usage_limit.this[0].breach_action == "deactivate"
    error_message = "The limit must be 100 serverless-compute RPU-hours per month with breach_action deactivate"
  }
}

run "no_usage_limit_by_default" {
  command = plan

  assert {
    condition     = length(aws_redshiftserverless_usage_limit.this) == 0
    error_message = "No usage limit unless requested"
  }
}

run "admin_password_is_managed_with_the_given_kms_key" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_namespace.this.manage_admin_password == true
    error_message = "manage_admin_password must be true"
  }

  assert {
    condition     = aws_redshiftserverless_namespace.this.admin_password_secret_kms_key_id == var.kms_key_arn
    error_message = "The admin secret must be encrypted with the given KMS key"
  }

  assert {
    condition     = aws_redshiftserverless_namespace.this.admin_user_password == null && aws_redshiftserverless_namespace.this.admin_user_password_wo == null
    error_message = "No password may be passed to the namespace"
  }
}

run "workgroup_is_never_public" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_workgroup.this.publicly_accessible == false
    error_message = "publicly_accessible must be false"
  }
}

run "namespace_is_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_namespace.this.kms_key_id == var.kms_key_arn
    error_message = "kms_key_id must be the given key"
  }
}

run "all_logs_go_to_cloudwatch_by_default" {
  command = plan

  assert {
    condition     = aws_redshiftserverless_namespace.this.log_exports == toset(["connectionlog", "userlog", "useractivitylog"])
    error_message = "log_exports must default to all three log types"
  }
}

run "require_ssl_and_user_activity_logging_are_set" {
  command = plan

  assert {
    condition     = contains([for p in aws_redshiftserverless_workgroup.this.config_parameter : "${p.parameter_key}=${p.parameter_value}"], "require_ssl=true")
    error_message = "config_parameter must carry require_ssl = true"
  }

  assert {
    condition     = contains([for p in aws_redshiftserverless_workgroup.this.config_parameter : "${p.parameter_key}=${p.parameter_value}"], "enable_user_activity_logging=true")
    error_message = "useractivitylog needs enable_user_activity_logging = true"
  }
}

run "extra_config_parameters_are_added" {
  command = plan

  variables {
    config_parameters = { datestyle = "ISO, MDY" }
  }

  assert {
    condition     = contains([for p in aws_redshiftserverless_workgroup.this.config_parameter : "${p.parameter_key}=${p.parameter_value}"], "datestyle=ISO, MDY")
    error_message = "User config parameters must be passed through"
  }

  assert {
    condition     = contains([for p in aws_redshiftserverless_workgroup.this.config_parameter : "${p.parameter_key}=${p.parameter_value}"], "require_ssl=true")
    error_message = "require_ssl must stay"
  }
}

run "without_useractivitylog_the_parameter_is_not_set" {
  command = plan

  variables {
    log_exports = ["connectionlog"]
  }

  assert {
    condition     = !contains([for p in aws_redshiftserverless_workgroup.this.config_parameter : p.parameter_key], "enable_user_activity_logging")
    error_message = "enable_user_activity_logging only goes with useractivitylog"
  }
}

run "iam_roles_and_default_role" {
  command = plan

  variables {
    iam_role_arns        = ["arn:aws:iam::111111111111:role/alpha-dev-redshift"]
    default_iam_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-redshift"
  }

  assert {
    condition     = aws_redshiftserverless_namespace.this.default_iam_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-redshift" && length(aws_redshiftserverless_namespace.this.iam_roles) == 1
    error_message = "IAM roles must be attached with the default role"
  }
}

run "outputs_are_published" {
  command = apply

  override_resource {
    target = aws_redshiftserverless_workgroup.this
    values = {
      arn      = "arn:aws:redshift-serverless:ap-northeast-1:111111111111:workgroup/11111111-2222-3333-4444-555555555555"
      endpoint = [{ address = "alpha-dev-wh.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com", port = 5439, vpc_endpoint = [] }]
    }
  }

  override_resource {
    target = aws_redshiftserverless_namespace.this
    values = {
      admin_password_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:redshift!alpha-dev-wh-dbadmin-AbCdEf"
    }
  }

  assert {
    condition     = output.endpoint_address == "alpha-dev-wh.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com" && output.port == 5439
    error_message = "endpoint_address and port must come from the workgroup endpoint"
  }

  assert {
    condition     = output.database_name == "analytics" && output.namespace_name == "alpha-dev-wh" && output.workgroup_name == "alpha-dev-wh"
    error_message = "database_name, namespace_name and workgroup_name must be published"
  }

  assert {
    condition     = output.admin_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:redshift!alpha-dev-wh-dbadmin-AbCdEf"
    error_message = "admin_secret_arn must be the managed secret"
  }

  assert {
    condition     = output.workgroup_arn == "arn:aws:redshift-serverless:ap-northeast-1:111111111111:workgroup/11111111-2222-3333-4444-555555555555"
    error_message = "workgroup_arn must be published"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "base_6_rejected" {
  command = plan

  variables {
    base_capacity = 6
  }

  expect_failures = [var.base_capacity]
}

run "base_520_rejected" {
  command = plan

  variables {
    base_capacity = 520
  }

  expect_failures = [var.base_capacity]
}

run "base_0_rejected" {
  command = plan

  variables {
    base_capacity = 0
  }

  expect_failures = [var.base_capacity]
}

run "max_below_base_rejected" {
  command = plan

  variables {
    base_capacity = 16
    max_capacity  = 8
  }

  expect_failures = [var.max_capacity]
}

run "max_above_512_rejected" {
  command = plan

  variables {
    max_capacity = 520
  }

  expect_failures = [var.max_capacity]
}

run "one_subnet_rejected" {
  command = plan

  variables {
    enhanced_vpc_routing = false
    subnet_ids           = ["subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "two_subnets_rejected_with_evr" {
  command = plan

  variables {
    enhanced_vpc_routing = true
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-1a2b3c4d"]
  }

  expect_failures = [var.subnet_ids]
}

run "duplicate_subnets_do_not_count_twice" {
  command = plan

  variables {
    enhanced_vpc_routing = false
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "malformed_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d", "subnet-1a2b3c4d", "not-a-subnet"]
  }

  expect_failures = [var.subnet_ids]
}

run "usage_limit_0_rejected" {
  command = plan

  variables {
    usage_limit_rpu_hours = 0
  }

  expect_failures = [var.usage_limit_rpu_hours]
}

run "usage_limit_negative_rejected" {
  command = plan

  variables {
    usage_limit_rpu_hours = -5
  }

  expect_failures = [var.usage_limit_rpu_hours]
}

run "alias_kms_key_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/alpha"
  }

  expect_failures = [var.kms_key_arn]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "Alpha_WH"
  }

  expect_failures = [var.name]
}

run "invalid_db_name_rejected" {
  command = plan

  variables {
    db_name = "1-bad"
  }

  expect_failures = [var.db_name]
}

run "invalid_admin_username_rejected" {
  command = plan

  variables {
    admin_username = "Admin User"
  }

  expect_failures = [var.admin_username]
}

run "unknown_log_export_rejected" {
  command = plan

  variables {
    log_exports = ["connectionlog", "auditlog"]
  }

  expect_failures = [var.log_exports]
}

run "empty_log_exports_rejected" {
  command = plan

  variables {
    log_exports = []
  }

  expect_failures = [var.log_exports]
}

run "overriding_require_ssl_rejected" {
  command = plan

  variables {
    config_parameters = { require_ssl = "false" }
  }

  expect_failures = [var.config_parameters]
}

run "overriding_user_activity_logging_rejected" {
  command = plan

  variables {
    config_parameters = { enable_user_activity_logging = "false" }
  }

  expect_failures = [var.config_parameters]
}

run "default_role_must_be_attached" {
  command = plan

  variables {
    iam_role_arns        = ["arn:aws:iam::111111111111:role/a"]
    default_iam_role_arn = "arn:aws:iam::111111111111:role/b"
  }

  expect_failures = [var.default_iam_role_arn]
}

run "malformed_role_arn_rejected" {
  command = plan

  variables {
    iam_role_arns = ["role/a"]
  }

  expect_failures = [var.iam_role_arns]
}

run "malformed_security_group_rejected" {
  command = plan

  variables {
    security_group_ids = ["sg-nope"]
  }

  expect_failures = [var.security_group_ids]
}

run "empty_security_groups_rejected" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}
