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

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"

  datasets = {
    events = {
      table   = "events"
      columns = [{ name = "event_id", type = "STRING" }, { name = "event_time", type = "DATETIME" }]
    }
  }
  owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-owners"]
  reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-readers"]
}

run "reads_only_keys_of_earlier_stacks" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      curated_database_name      = "storage/curated_database_name"
      athena_workgroup_name      = "analytics/athena_workgroup_name"
      role_quicksight_athena_arn = "iam-app/role_quicksight_athena_arn"
      role_quicksight_vpc_arn    = "iam-base/role_quicksight_vpc_arn"
      sg_quicksight_id           = "network/sg_quicksight_id"
      redshift_host              = "warehouse/redshift_host"
      redshift_port              = "warehouse/redshift_port"
      redshift_database          = "warehouse/redshift_database"
      } && local.ssm_input_lists == {
      subnet_ids_data = "network/subnet_ids_data"
    }
    error_message = "bi must read exactly these keys; redshift_mode and the admin secret are not its business (design 7.3)"
  }
}

run "secret_defaults_to_null" {
  command = plan

  assert {
    condition     = var.redshift_reader_secret_arn == null
    error_message = "redshift_reader_secret_arn must default to null: Athena only (design D10)"
  }
}

run "without_secret_only_the_athena_source_is_built" {
  command = plan

  assert {
    condition     = length(local.redshift_sources) == 0 && local.vpc_connection == null
    error_message = "Without a secret ARN there must be no Redshift source and no VPC connection"
  }

  assert {
    condition     = keys(module.quicksight.data_source_arns) == ["athena"] && module.quicksight.vpc_connection_arn == null
    error_message = "Only the athena data source may exist when no secret is given"
  }
}

run "athena_source_uses_the_analytics_workgroup_and_the_quicksight_athena_role" {
  command = plan

  assert {
    condition = local.athena_sources == {
      athena = {
        workgroup = "example-dev-analytics"
        role_arn  = "arn:aws:iam::111111111111:role/example-dev-quicksight-athena"
      }
    }
    error_message = "The Athena source must use the analytics workgroup and the iam-app quicksight-athena role, not the quicksight-vpc role"
  }
}

run "dataset_points_at_the_curated_database" {
  command = plan

  assert {
    condition     = local.datasets["events"].source_key == "athena" && local.datasets["events"].table == { name = "events", schema = "example_dev_curated", catalog = "AwsDataCatalog" }
    error_message = "An Athena dataset must read table events of the curated database through AwsDataCatalog"
  }

  assert {
    condition     = local.datasets["events"].import_mode == "DIRECT_QUERY" && length(local.datasets["events"].columns) == 2
    error_message = "A dataset must be DIRECT_QUERY and carry the columns given in tfvars"
  }
}

run "owner_and_reader_principals_stay_separate" {
  command = plan

  assert {
    condition     = tolist(local.owner_principals) == tolist(["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-owners"]) && tolist(local.reader_principals) == tolist(["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/data-readers"])
    error_message = "Owners and readers must be passed to the module as two separate lists"
  }
}

run "aws_account_id_is_the_expected_account" {
  command = plan

  assert {
    condition     = local.aws_account_id == "111111111111"
    error_message = "QuickSight resources must live in expected_account_id"
  }
}

run "secret_builds_the_redshift_source_and_vpc_connection" {
  command = plan

  variables {
    redshift_reader_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-quicksight-reader-AbCdEf"
    datasets = {
      events = {
        table   = "events"
        columns = [{ name = "event_id", type = "STRING" }]
      }
      events_dw = {
        source  = "redshift"
        schema  = "public"
        table   = "events"
        columns = [{ name = "event_id", type = "STRING" }]
      }
    }
  }

  assert {
    condition = jsonencode(local.redshift_sources) == jsonencode({
      redshift = {
        host       = "example-dev.abc123.ap-northeast-1.redshift-serverless.amazonaws.com"
        port       = 5439
        database   = "dev"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-quicksight-reader-AbCdEf"
      }
    })
    error_message = "The Redshift source must take host, port and database from warehouse and the secret from tfvars"
  }

  assert {
    condition = jsonencode(local.vpc_connection) == jsonencode({
      name               = "example-dev-quicksight"
      role_arn           = "arn:aws:iam::111111111111:role/example-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0dda0001", "subnet-0dda0002"]
      security_group_ids = ["sg-0aaaaaaa00000004"]
    })
    error_message = "The VPC connection must use the data subnets, the quicksight security group and the iam-base quicksight-vpc role"
  }

  assert {
    condition     = local.datasets["events"].source_key == "athena" && local.datasets["events_dw"].source_key == "redshift" && local.datasets["events_dw"].table.name == "events" && local.datasets["events_dw"].table.schema == "public" && local.datasets["events_dw"].table.catalog == null
    error_message = "A Redshift dataset must point at the redshift source with the schema from tfvars and no catalog"
  }

  assert {
    condition     = length(module.quicksight.data_source_arns) == 2
    error_message = "Both data sources and the VPC connection must be planned"
  }
}

run "redshift_dataset_without_secret_is_rejected" {
  command = plan

  variables {
    datasets = {
      events_dw = {
        source  = "redshift"
        schema  = "public"
        table   = "events"
        columns = [{ name = "event_id", type = "STRING" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "malformed_secret_arn_is_rejected" {
  command = plan

  variables {
    redshift_reader_secret_arn = "not-an-arn"
  }

  expect_failures = [var.redshift_reader_secret_arn]
}

run "unknown_dataset_source_is_rejected" {
  command = plan

  variables {
    datasets = {
      events = {
        source  = "mysql"
        table   = "events"
        columns = [{ name = "event_id", type = "STRING" }]
      }
    }
  }

  expect_failures = [var.datasets]
}
