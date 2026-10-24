# Action sets for the two permission levels. Owner sets match the lists the AWS Quick Sight guide gives for
# create-data-source; reader sets are the describe/pass subset needed to build analyses on the resource.
locals {
  data_source_actions = {
    owner = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
    reader = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
    ]
  }

  data_set_actions = {
    owner = [
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
    ]
    reader = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
    ]
  }

  # One entry per principal; validation keeps a principal out of both lists.
  data_source_permissions = concat(
    [for p in var.owner_principals : { principal = p, actions = local.data_source_actions.owner }],
    [for p in var.reader_principals : { principal = p, actions = local.data_source_actions.reader }],
  )

  data_set_permissions = concat(
    [for p in var.owner_principals : { principal = p, actions = local.data_set_actions.owner }],
    [for p in var.reader_principals : { principal = p, actions = local.data_set_actions.reader }],
  )

  data_source_arns = merge(
    { for k, s in aws_quicksight_data_source.athena : k => s.arn },
    { for k, s in aws_quicksight_data_source.redshift : k => s.arn },
  )
}

# The Athena source assumes its own role and queries one workgroup.
resource "aws_quicksight_data_source" "athena" {
  for_each = var.athena_sources

  aws_account_id = var.aws_account_id
  data_source_id = each.key
  name           = each.key
  type           = "ATHENA"

  parameters {
    athena {
      work_group = each.value.workgroup
      role_arn   = each.value.role_arn
    }
  }

  dynamic "permission" {
    for_each = local.data_source_permissions

    content {
      principal = permission.value.principal
      actions   = permission.value.actions
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

# Redshift only supports Secrets Manager credentials here (the provider has no IAM option), always over SSL and
# always through the VPC connection. There is no username or password input.
resource "aws_quicksight_data_source" "redshift" {
  for_each = var.redshift_sources

  aws_account_id = var.aws_account_id
  data_source_id = each.key
  name           = each.key
  type           = "REDSHIFT"

  parameters {
    redshift {
      host     = each.value.host
      port     = each.value.port
      database = each.value.database
    }
  }

  credentials {
    secret_arn = each.value.secret_arn
  }

  ssl_properties {
    disable_ssl = false
  }

  vpc_connection_properties {
    vpc_connection_arn = one(aws_quicksight_vpc_connection.this[*].arn)
  }

  dynamic "permission" {
    for_each = local.data_source_permissions

    content {
      principal = permission.value.principal
      actions   = permission.value.actions
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_quicksight_vpc_connection" "this" {
  count = var.vpc_connection == null ? 0 : 1

  aws_account_id     = var.aws_account_id
  vpc_connection_id  = var.vpc_connection.name
  name               = var.vpc_connection.name
  role_arn           = var.vpc_connection.role_arn
  subnet_ids         = var.vpc_connection.subnet_ids
  security_group_ids = var.vpc_connection.security_group_ids
  dns_resolvers      = length(var.vpc_connection.dns_resolvers) == 0 ? null : var.vpc_connection.dns_resolvers

  tags = merge(var.tags, { Name = var.vpc_connection.name })
}

# Each dataset is one physical table (custom SQL or a relational table) exposed as one logical table.
resource "aws_quicksight_data_set" "this" {
  for_each = var.datasets

  aws_account_id = var.aws_account_id
  data_set_id    = each.key
  name           = each.key
  import_mode    = each.value.import_mode

  physical_table_map {
    physical_table_map_id = each.key

    dynamic "custom_sql" {
      for_each = each.value.sql == null ? [] : [each.value.sql]

      content {
        data_source_arn = local.data_source_arns[each.value.source_key]
        name            = each.key
        sql_query       = custom_sql.value

        dynamic "columns" {
          for_each = each.value.columns

          content {
            name = columns.value.name
            type = columns.value.type
          }
        }
      }
    }

    dynamic "relational_table" {
      for_each = each.value.table == null ? [] : [each.value.table]

      content {
        data_source_arn = local.data_source_arns[each.value.source_key]
        name            = relational_table.value.name
        schema          = relational_table.value.schema
        catalog         = relational_table.value.catalog

        dynamic "input_columns" {
          for_each = each.value.columns

          content {
            name = input_columns.value.name
            type = input_columns.value.type
          }
        }
      }
    }
  }

  logical_table_map {
    logical_table_map_id = each.key
    alias                = each.key

    source {
      physical_table_id = each.key
    }
  }

  dynamic "permissions" {
    for_each = local.data_set_permissions

    content {
      principal = permissions.value.principal
      actions   = permissions.value.actions
    }
  }

  tags = merge(var.tags, { Name = each.key })
}
