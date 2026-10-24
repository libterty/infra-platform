mock_provider "aws" {}

# Computed ARNs are unknown at plan time; pin them per instance so the wiring between resources can be asserted.
override_resource {
  target          = aws_quicksight_data_source.athena["alpha-dev-athena"]
  override_during = plan
  values = {
    arn = "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-athena"
  }
}

override_resource {
  target          = aws_quicksight_data_source.redshift["alpha-dev-redshift"]
  override_during = plan
  values = {
    arn = "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-redshift"
  }
}

override_resource {
  target          = aws_quicksight_vpc_connection.this[0]
  override_during = plan
  values = {
    arn = "arn:aws:quicksight:ap-northeast-1:111111111111:vpcConnection/alpha-dev-redshift"
  }
}

override_resource {
  target          = aws_quicksight_data_set.this["alpha-dev-events"]
  override_during = plan
  values = {
    arn = "arn:aws:quicksight:ap-northeast-1:111111111111:dataset/alpha-dev-events"
  }
}

variables {
  aws_account_id = "111111111111"

  athena_sources = {
    alpha-dev-athena = {
      workgroup = "alpha-dev-analytics"
      role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-athena"
    }
  }

  datasets = {
    alpha-dev-events = {
      source_key = "alpha-dev-athena"
      sql        = "SELECT event_id, event_time FROM \"alpha_dev_curated\".\"events\""
      columns = [
        { name = "event_id", type = "STRING" },
        { name = "event_time", type = "DATETIME" },
      ]
    }
  }
}

# ---- positive: Athena source and dataset ----------------------------------------------------------------------

run "athena_source_uses_the_given_workgroup_and_role" {
  command = plan

  assert {
    condition     = aws_quicksight_data_source.athena["alpha-dev-athena"].type == "ATHENA"
    error_message = "The Athena source must have type ATHENA"
  }

  assert {
    condition     = one(one(aws_quicksight_data_source.athena["alpha-dev-athena"].parameters).athena).work_group == "alpha-dev-analytics"
    error_message = "The Athena source must query the given workgroup"
  }

  assert {
    condition     = one(one(aws_quicksight_data_source.athena["alpha-dev-athena"].parameters).athena).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-quicksight-athena"
    error_message = "The Athena source must assume the given role, not the account-wide default"
  }
}

run "athena_source_id_and_account_come_from_the_inputs" {
  command = plan

  assert {
    condition     = aws_quicksight_data_source.athena["alpha-dev-athena"].data_source_id == "alpha-dev-athena" && aws_quicksight_data_source.athena["alpha-dev-athena"].aws_account_id == "111111111111"
    error_message = "The data source id is the map key and the account is aws_account_id"
  }
}

run "athena_only_creates_no_redshift_source_and_no_vpc_connection" {
  command = plan

  assert {
    condition     = length(aws_quicksight_data_source.redshift) == 0
    error_message = "Without redshift_sources no Redshift data source may exist"
  }

  assert {
    condition     = length(aws_quicksight_vpc_connection.this) == 0
    error_message = "Without vpc_connection no VPC connection may exist"
  }

  assert {
    condition     = output.vpc_connection_arn == null
    error_message = "vpc_connection_arn must be null when no VPC connection exists"
  }
}

run "dataset_with_sql_becomes_a_custom_sql_table_on_the_athena_source" {
  command = plan

  assert {
    condition     = one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).custom_sql[0].data_source_arn == "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-athena"
    error_message = "The dataset must read from the data source named by source_key"
  }

  assert {
    condition     = one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).custom_sql[0].sql_query == "SELECT event_id, event_time FROM \"alpha_dev_curated\".\"events\""
    error_message = "The dataset must carry the given SQL"
  }

  assert {
    condition     = [for c in one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).custom_sql[0].columns : "${c.name}:${c.type}"] == ["event_id:STRING", "event_time:DATETIME"]
    error_message = "The dataset must carry the given columns in order"
  }

  assert {
    condition     = length(one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table) == 0
    error_message = "A SQL dataset must not also declare a relational table"
  }
}

run "dataset_defaults_to_direct_query" {
  command = plan

  assert {
    condition     = aws_quicksight_data_set.this["alpha-dev-events"].import_mode == "DIRECT_QUERY"
    error_message = "import_mode must default to DIRECT_QUERY"
  }
}

run "dataset_exposes_its_only_physical_table_as_one_logical_table" {
  command = plan

  assert {
    condition = (
      one(aws_quicksight_data_set.this["alpha-dev-events"].logical_table_map).alias == "alpha-dev-events" &&
      one(one(aws_quicksight_data_set.this["alpha-dev-events"].logical_table_map).source).physical_table_id == one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).physical_table_map_id
    )
    error_message = "The logical table must be built on the physical table of the same dataset"
  }
}

run "dataset_with_table_becomes_a_relational_table" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        table = {
          catalog = "AwsDataCatalog"
          schema  = "alpha_dev_curated"
          name    = "events"
        }
        columns = [{ name = "event_id", type = "STRING" }]
      }
    }
  }

  assert {
    condition = (
      one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].name == "events" &&
      one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].schema == "alpha_dev_curated" &&
      one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].catalog == "AwsDataCatalog" &&
      one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].data_source_arn == "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-athena"
    )
    error_message = "A table dataset must point at the given catalog, schema and table on the named source"
  }

  assert {
    condition     = length(one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).custom_sql) == 0
    error_message = "A table dataset must not also declare custom SQL"
  }

  assert {
    condition     = [for c in one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].input_columns : c.name] == ["event_id"]
    error_message = "A table dataset must carry the given columns as input_columns"
  }
}

run "dataset_can_opt_into_spice" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key  = "alpha-dev-athena"
        import_mode = "SPICE"
        sql         = "SELECT 1 AS one"
        columns     = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  assert {
    condition     = aws_quicksight_data_set.this["alpha-dev-events"].import_mode == "SPICE"
    error_message = "import_mode SPICE must be accepted"
  }
}

run "no_datasets_creates_no_dataset" {
  command = plan

  variables {
    datasets = {}
  }

  assert {
    condition     = length(aws_quicksight_data_set.this) == 0
    error_message = "An empty datasets map must create no dataset"
  }
}

# ---- positive: Redshift source and VPC connection ------------------------------------------------------------

run "redshift_source_authenticates_with_the_secret_only" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = aws_quicksight_data_source.redshift["alpha-dev-redshift"].type == "REDSHIFT"
    error_message = "The Redshift source must have type REDSHIFT"
  }

  assert {
    condition     = one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].credentials).secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
    error_message = "The Redshift source must authenticate with the given secret"
  }

  assert {
    condition     = length(one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].credentials).credential_pair) == 0
    error_message = "The Redshift source must never carry a username and password"
  }

  assert {
    condition     = one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].credentials).copy_source_arn == null
    error_message = "The Redshift source must not borrow credentials from another data source"
  }
}

run "redshift_source_endpoint_comes_from_the_input" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition = (
      one(one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].parameters).redshift).host == "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com" &&
      one(one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].parameters).redshift).database == "analytics" &&
      one(one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].parameters).redshift).port == 5439
    )
    error_message = "The Redshift source must connect to the given host and database, port 5439 by default"
  }
}

run "redshift_source_keeps_ssl_on" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].ssl_properties).disable_ssl == false
    error_message = "SSL must be explicitly enabled on the Redshift source"
  }
}

run "redshift_source_connects_through_the_vpc_connection" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = one(aws_quicksight_data_source.redshift["alpha-dev-redshift"].vpc_connection_properties).vpc_connection_arn == "arn:aws:quicksight:ap-northeast-1:111111111111:vpcConnection/alpha-dev-redshift"
    error_message = "The Redshift source must reach the cluster through the module's VPC connection"
  }

  assert {
    condition     = length(aws_quicksight_data_source.athena["alpha-dev-athena"].vpc_connection_properties) == 0
    error_message = "The Athena source must not use the VPC connection"
  }
}

run "vpc_connection_uses_the_given_role_subnets_and_security_groups" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition = (
      aws_quicksight_vpc_connection.this[0].vpc_connection_id == "alpha-dev-redshift" &&
      aws_quicksight_vpc_connection.this[0].name == "alpha-dev-redshift" &&
      aws_quicksight_vpc_connection.this[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc" &&
      aws_quicksight_vpc_connection.this[0].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]) &&
      aws_quicksight_vpc_connection.this[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    )
    error_message = "The VPC connection must use the given id, role, subnets and security groups"
  }

  assert {
    condition     = output.vpc_connection_arn == "arn:aws:quicksight:ap-northeast-1:111111111111:vpcConnection/alpha-dev-redshift"
    error_message = "vpc_connection_arn must expose the VPC connection ARN"
  }
}

run "vpc_connection_alone_is_created_without_redshift_sources" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = length(aws_quicksight_vpc_connection.this) == 1 && length(aws_quicksight_data_source.redshift) == 0
    error_message = "A given vpc_connection is created even when no Redshift source uses it yet"
  }
}

run "dataset_can_read_from_the_redshift_source" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-redshift"
        table      = { schema = "public", name = "events" }
        columns    = [{ name = "event_id", type = "STRING" }]
      }
    }
  }

  assert {
    condition     = one(aws_quicksight_data_set.this["alpha-dev-events"].physical_table_map).relational_table[0].data_source_arn == "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-redshift"
    error_message = "A dataset whose source_key names the Redshift source must read from it"
  }
}

run "outputs_expose_data_source_and_dataset_arns_by_key" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition = output.data_source_arns == {
      alpha-dev-athena   = "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-athena"
      alpha-dev-redshift = "arn:aws:quicksight:ap-northeast-1:111111111111:datasource/alpha-dev-redshift"
    }
    error_message = "data_source_arns must list both kinds of source by key"
  }

  assert {
    condition = output.data_set_arns == {
      alpha-dev-events = "arn:aws:quicksight:ap-northeast-1:111111111111:dataset/alpha-dev-events"
    }
    error_message = "data_set_arns must list the datasets by key"
  }
}

# ---- positive: permissions -----------------------------------------------------------------------------------

run "data_source_permissions_split_into_owner_and_reader_actions" {
  command = plan

  variables {
    owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"]
    reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-readers", "arn:aws:quicksight:ap-northeast-1:111111111111:user/default/alice"]
  }

  assert {
    condition = one([
      for p in aws_quicksight_data_source.athena["alpha-dev-athena"].permission : p.actions
      if p.principal == "arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"
      ]) == toset([
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ])
    error_message = "Data source owners get the six owner actions"
  }

  assert {
    condition = alltrue([
      for p in aws_quicksight_data_source.athena["alpha-dev-athena"].permission : p.actions == toset([
        "quicksight:DescribeDataSource",
        "quicksight:DescribeDataSourcePermissions",
        "quicksight:PassDataSource",
      ])
      if p.principal != "arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"
    ])
    error_message = "Data source readers get only describe and pass actions"
  }

  assert {
    condition     = length(aws_quicksight_data_source.athena["alpha-dev-athena"].permission) == 3
    error_message = "Every principal gets exactly one permission entry"
  }
}

run "dataset_permissions_split_into_owner_and_reader_actions" {
  command = plan

  variables {
    owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"]
    reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-readers"]
  }

  assert {
    condition = one([
      for p in aws_quicksight_data_set.this["alpha-dev-events"].permissions : p.actions
      if p.principal == "arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"
      ]) == toset([
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
      "quicksight:UpdateDataSetPermissions",
    ])
    error_message = "Dataset owners get the ten owner actions"
  }

  assert {
    condition = one([
      for p in aws_quicksight_data_set.this["alpha-dev-events"].permissions : p.actions
      if p.principal == "arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-readers"
      ]) == toset([
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
    ])
    error_message = "Dataset readers get only the five read actions"
  }
}

run "data_source_and_dataset_actions_never_cross" {
  command = plan

  variables {
    owner_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"]
  }

  assert {
    condition = alltrue(flatten([
      for p in aws_quicksight_data_source.athena["alpha-dev-athena"].permission : [for a in p.actions : strcontains(a, "DataSource")]
    ]))
    error_message = "A data source permission must only carry DataSource actions"
  }

  assert {
    condition = alltrue(flatten([
      for p in aws_quicksight_data_set.this["alpha-dev-events"].permissions : [for a in p.actions : strcontains(a, "DataSet") || strcontains(a, "Ingestion")]
    ]))
    error_message = "A dataset permission must only carry DataSet and ingestion actions"
  }
}

run "no_principals_means_no_permission_entries" {
  command = plan

  assert {
    condition     = length(aws_quicksight_data_source.athena["alpha-dev-athena"].permission) == 0 && length(aws_quicksight_data_set.this["alpha-dev-events"].permissions) == 0
    error_message = "Without principals no permission entry may be created"
  }
}

run "tags_are_applied_to_every_resource" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_quicksight_data_source.athena["alpha-dev-athena"].tags["Project"] == "alpha" && aws_quicksight_data_set.this["alpha-dev-events"].tags["Project"] == "alpha"
    error_message = "Given tags must reach the data source and the dataset"
  }
}

# ---- negative: aws_account_id ---------------------------------------------------------------------------------

run "aws_account_id_must_be_twelve_digits" {
  command = plan

  variables {
    aws_account_id = "1111"
  }

  expect_failures = [var.aws_account_id]
}

# ---- negative: athena_sources ---------------------------------------------------------------------------------

run "athena_source_key_with_a_space_is_rejected" {
  command = plan

  variables {
    athena_sources = {
      "alpha dev athena" = {
        workgroup = "alpha-dev-analytics"
        role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-athena"
      }
    }
    datasets = {}
  }

  expect_failures = [var.athena_sources]
}

run "athena_source_role_must_be_an_iam_role_arn" {
  command = plan

  variables {
    athena_sources = {
      alpha-dev-athena = {
        workgroup = "alpha-dev-analytics"
        role_arn  = "alpha-dev-quicksight-athena"
      }
    }
  }

  expect_failures = [var.athena_sources]
}

run "athena_source_workgroup_must_not_be_empty" {
  command = plan

  variables {
    athena_sources = {
      alpha-dev-athena = {
        workgroup = ""
        role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-athena"
      }
    }
  }

  expect_failures = [var.athena_sources]
}

# ---- negative: redshift_sources ---------------------------------------------------------------------------------

run "redshift_source_without_a_vpc_connection_is_rejected" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
  }

  expect_failures = [var.redshift_sources]
}

run "redshift_secret_arn_must_be_a_secrets_manager_secret" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.redshift_sources]
}

run "redshift_secret_arn_null_is_rejected" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = null
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.redshift_sources]
}

run "redshift_port_out_of_range_is_rejected" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        port       = 70000
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.redshift_sources]
}

run "redshift_host_must_not_be_empty" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-redshift = {
        host       = ""
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.redshift_sources]
}

run "redshift_source_key_must_not_collide_with_an_athena_source" {
  command = plan

  variables {
    redshift_sources = {
      alpha-dev-athena = {
        host       = "alpha-dev-wg.111111111111.ap-northeast-1.redshift-serverless.amazonaws.com"
        database   = "analytics"
        secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/quicksight-redshift-AbCdEf"
      }
    }
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.redshift_sources]
}

# ---- negative: vpc_connection ---------------------------------------------------------------------------------

run "vpc_connection_name_with_a_space_is_rejected" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha dev redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_role_must_be_an_iam_role_arn" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_with_a_single_subnet_is_rejected" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_needs_subnets" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = []
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_subnet_ids_must_look_like_subnets" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["vpc-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_with_more_than_fifteen_subnets_is_rejected" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = [for i in range(16) : "subnet-0123456789abcde${format("%02d", i)}"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_dns_resolvers_are_passed_through" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
      dns_resolvers      = ["10.30.0.2"]
    }
  }

  assert {
    condition     = aws_quicksight_vpc_connection.this[0].dns_resolvers == toset(["10.30.0.2"])
    error_message = "dns_resolvers must reach the VPC connection when given"
  }
}

run "vpc_connection_needs_security_groups" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = []
    }
  }

  expect_failures = [var.vpc_connection]
}

run "vpc_connection_security_group_ids_must_look_like_security_groups" {
  command = plan

  variables {
    vpc_connection = {
      name               = "alpha-dev-redshift"
      role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-vpc"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["subnet-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc_connection]
}

# ---- negative: datasets ---------------------------------------------------------------------------------------

run "dataset_pointing_at_a_missing_source_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-nowhere"
        sql        = "SELECT 1 AS one"
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_with_both_sql_and_table_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        sql        = "SELECT 1 AS one"
        table      = { schema = "alpha_dev_curated", name = "events" }
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_with_neither_sql_nor_table_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_with_blank_sql_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        sql        = "   "
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_with_an_unknown_import_mode_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key  = "alpha-dev-athena"
        import_mode = "DIRECT"
        sql         = "SELECT 1 AS one"
        columns     = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_without_columns_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        sql        = "SELECT 1 AS one"
        columns    = []
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_column_with_an_unknown_type_is_rejected" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        sql        = "SELECT 1 AS one"
        columns    = [{ name = "one", type = "VARCHAR" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_key_with_a_space_is_rejected" {
  command = plan

  variables {
    datasets = {
      "alpha dev events" = {
        source_key = "alpha-dev-athena"
        sql        = "SELECT 1 AS one"
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

run "dataset_table_name_must_not_be_empty" {
  command = plan

  variables {
    datasets = {
      alpha-dev-events = {
        source_key = "alpha-dev-athena"
        table      = { schema = "alpha_dev_curated", name = "" }
        columns    = [{ name = "one", type = "INTEGER" }]
      }
    }
  }

  expect_failures = [var.datasets]
}

# ---- negative: principals -------------------------------------------------------------------------------------

run "owner_principal_must_be_a_quicksight_user_or_group_arn" {
  command = plan

  variables {
    owner_principals = ["arn:aws:iam::111111111111:user/alice"]
  }

  expect_failures = [var.owner_principals]
}

run "reader_principal_must_be_a_quicksight_user_or_group_arn" {
  command = plan

  variables {
    reader_principals = ["alice"]
  }

  expect_failures = [var.reader_principals]
}

run "reader_principal_must_not_be_a_quicksight_namespace_or_other_resource" {
  command = plan

  variables {
    reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:namespace/default"]
  }

  expect_failures = [var.reader_principals]
}

run "a_principal_cannot_be_both_owner_and_reader" {
  command = plan

  variables {
    owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi"]
    reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi"]
  }

  expect_failures = [var.reader_principals]
}
