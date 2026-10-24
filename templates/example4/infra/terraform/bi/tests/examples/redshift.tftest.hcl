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
run "example_builds_both_sources_and_the_vpc_connection" {
  command = plan

  assert {
    condition     = tolist(keys(local.athena_sources)) == tolist(["athena"]) && tolist(keys(local.redshift_sources)) == tolist(["redshift"]) && local.vpc_connection != null
    error_message = "The example must build the Athena source, the Redshift source and the VPC connection"
  }

  assert {
    condition     = length(module.quicksight.data_source_arns) == 2
    error_message = "The example must plan two data sources and one VPC connection"
  }
}

run "example_redshift_uses_a_secret_and_the_data_subnets" {
  command = plan

  assert {
    condition     = can(regex("^arn:aws:secretsmanager:", local.redshift_sources["redshift"].secret_arn)) && local.redshift_sources["redshift"].host == "example-dev.abc123.ap-northeast-1.redshift-serverless.amazonaws.com" && local.redshift_sources["redshift"].port == 5439 && local.redshift_sources["redshift"].database == "dev"
    error_message = "The Redshift source must use the secret from tfvars and the warehouse host, port and database"
  }

  assert {
    condition     = tolist(local.vpc_connection.subnet_ids) == tolist(["subnet-0dda0001", "subnet-0dda0002"]) && tolist(local.vpc_connection.security_group_ids) == tolist(["sg-0aaaaaaa00000004"]) && local.vpc_connection.role_arn == "arn:aws:iam::111111111111:role/example-dev-quicksight-vpc"
    error_message = "The VPC connection must use the data subnets, the quicksight security group and the quicksight-vpc role"
  }
}

run "example_athena_still_uses_the_athena_role" {
  command = plan

  assert {
    condition     = local.athena_sources["athena"].role_arn == "arn:aws:iam::111111111111:role/example-dev-quicksight-athena" && local.athena_sources["athena"].workgroup == "example-dev-analytics"
    error_message = "The Athena source must keep the analytics workgroup and the quicksight-athena role"
  }
}
