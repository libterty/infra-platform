mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_redshift_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_redshift_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-redshift" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

# The mock provider returns an empty endpoint list, which the modules index; fix their outputs instead.
override_module {
  target = module.serverless
  outputs = {
    endpoint_address = "example-dev-warehouse.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
    port             = 5439
    database_name    = "analytics"
    admin_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:serverless-admin"
  }
}

override_module {
  target = module.provisioned
  outputs = {
    endpoint_address = "example-dev-warehouse.abc.ap-northeast-1.redshift.amazonaws.com"
    port             = 5439
    database_name    = "analytics"
    admin_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cluster-admin"
  }
}

run "reads_only_what_earlier_stacks_publish" {
  command = plan

  variables {
    warehouse_mode = "serverless"
    serverless     = {}
  }

  assert {
    condition     = local.ssm_input_strings == { kms_key_arn = "foundation/kms_key_arn", sg_redshift_id = "network/sg_redshift_id", role_redshift_arn = "iam-base/role_redshift_arn" } && local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    error_message = "warehouse must read exactly the KMS key, the Redshift security group, the Redshift role and the data subnets"
  }
}

run "serverless_builds_only_the_serverless_module" {
  command = plan

  variables {
    warehouse_mode = "serverless"
    serverless = {
      base_capacity         = 4
      max_capacity          = 8
      usage_limit_rpu_hours = 100
    }
  }

  assert {
    condition     = length(module.serverless) == 1 && length(module.provisioned) == 0
    error_message = "serverless mode must create the serverless module and no cluster"
  }

  assert {
    condition     = terraform_data.warehouse_mode_guard.triggers_replace == var.warehouse_mode && var.warehouse_mode == "serverless"
    error_message = "the guard must be replaced exactly when warehouse_mode changes"
  }

  assert {
    condition     = local.warehouse.mode == "serverless"
    error_message = "the active mode must be reported as serverless"
  }

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["redshift_mode", "redshift_host", "redshift_port", "redshift_database", "redshift_admin_secret_arn"])
    error_message = "warehouse must publish exactly redshift_mode, redshift_host, redshift_port, redshift_database and redshift_admin_secret_arn"
  }
}

run "provisioned_builds_only_the_cluster_module" {
  command = plan

  variables {
    warehouse_mode = "provisioned"
    provisioned = {
      node_type       = "ra3.large"
      number_of_nodes = 1
    }
  }

  assert {
    condition     = length(module.serverless) == 0 && length(module.provisioned) == 1
    error_message = "provisioned mode must create the cluster module and no serverless namespace"
  }

  assert {
    condition     = terraform_data.warehouse_mode_guard.triggers_replace == var.warehouse_mode && var.warehouse_mode == "provisioned"
    error_message = "the guard must be replaced exactly when warehouse_mode changes"
  }

  assert {
    condition     = local.warehouse.mode == "provisioned"
    error_message = "the active mode must be reported as provisioned"
  }

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["redshift_mode", "redshift_host", "redshift_port", "redshift_database", "redshift_admin_secret_arn"])
    error_message = "provisioned mode must publish the same five keys as serverless mode"
  }
}

run "published_values_come_from_the_active_module" {
  command = plan

  variables {
    warehouse_mode = "serverless"
    serverless     = {}
  }

  assert {
    condition = (
      local.published_strings.redshift_mode == "serverless" &&
      local.published_strings.redshift_host == "example-dev-warehouse.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com" &&
      local.published_strings.redshift_port == "5439" &&
      local.published_strings.redshift_database == "analytics" &&
      local.published_strings.redshift_admin_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:serverless-admin"
    )
    error_message = "serverless mode must publish the serverless module's outputs"
  }
}

run "provisioned_values_come_from_the_cluster" {
  command = plan

  variables {
    warehouse_mode = "provisioned"
    provisioned    = {}
  }

  assert {
    condition = (
      local.published_strings.redshift_mode == "provisioned" &&
      local.published_strings.redshift_host == "example-dev-warehouse.abc.ap-northeast-1.redshift.amazonaws.com" &&
      local.published_strings.redshift_port == "5439" &&
      local.published_strings.redshift_database == "analytics" &&
      local.published_strings.redshift_admin_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cluster-admin"
    )
    error_message = "provisioned mode must publish the cluster module's outputs"
  }
}

run "unknown_mode_is_rejected" {
  command = plan

  variables {
    warehouse_mode = "redshift"
    serverless     = {}
  }

  expect_failures = [var.warehouse_mode]
}

run "serverless_mode_without_its_object_is_rejected" {
  command = plan

  variables {
    warehouse_mode = "serverless"
    provisioned    = {}
  }

  expect_failures = [var.serverless, var.provisioned]
}

run "serverless_mode_with_both_objects_is_rejected" {
  command = plan

  variables {
    warehouse_mode = "serverless"
    serverless     = {}
    provisioned    = {}
  }

  expect_failures = [var.provisioned]
}

run "provisioned_mode_without_its_object_is_rejected" {
  command = plan

  variables {
    warehouse_mode = "provisioned"
    serverless     = {}
  }

  expect_failures = [var.serverless, var.provisioned]
}
