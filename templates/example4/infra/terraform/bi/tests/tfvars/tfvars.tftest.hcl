mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/curated_database_name"]
  values = { insecure_value = "example_dev_curated" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["analytics/athena_workgroup_name"]
  values = { insecure_value = "example-dev-analytics" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-app/role_quicksight_athena_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-quicksight-athena" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_quicksight_vpc_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-quicksight-vpc" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_quicksight_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["warehouse/redshift_host"]
  values = { insecure_value = "example-dev.abc123.ap-northeast-1.redshift-serverless.amazonaws.com" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["warehouse/redshift_port"]
  values = { insecure_value = "5439" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["warehouse/redshift_database"]
  values = { insecure_value = "dev" }
}
run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

# Design D10: without a secret ARN only the Athena source is built.
run "tfvars_build_only_the_athena_source" {
  command = plan

  assert {
    condition     = var.redshift_reader_secret_arn == null && length(local.redshift_sources) == 0 && local.vpc_connection == null
    error_message = "dev and sit tfvars must not give a Redshift secret ARN"
  }

  assert {
    condition     = keys(module.quicksight.data_source_arns) == ["athena"]
    error_message = "dev and sit must plan the Athena data source only"
  }
}

run "tfvars_have_one_dataset_on_the_curated_database" {
  command = plan

  assert {
    condition     = length(local.datasets) == 1 && alltrue([for _, d in local.datasets : d.source_key == "athena" && d.table.schema == "example_dev_curated"])
    error_message = "dev and sit must have a dataset on the curated database through the Athena source"
  }
}

run "tfvars_principals_are_in_the_env_account_and_separate" {
  command = plan

  assert {
    condition     = alltrue([for p in concat(var.owner_principals, var.reader_principals) : startswith(p, "arn:aws:quicksight:ap-northeast-1:${var.expected_account_id}:")]) && length(setintersection(toset(var.owner_principals), toset(var.reader_principals))) == 0
    error_message = "Principals must be QuickSight ARNs of the env account, and nobody is both owner and reader"
  }
}
