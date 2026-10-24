locals {
  aws_account_id = var.expected_account_id

  # Athena is always built. The source role is the data-source-only role of iam-app, not the VPC connection role.
  athena_sources = {
    athena = {
      workgroup = module.in.strings["athena_workgroup_name"]
      role_arn  = module.in.strings["role_quicksight_athena_arn"]
    }
  }

  # Redshift only with a reader secret (design D10). Host, port and database come from warehouse for both modes.
  redshift_sources = var.redshift_reader_secret_arn == null ? {} : {
    redshift = {
      host       = module.in.strings["redshift_host"]
      port       = tonumber(module.in.strings["redshift_port"])
      database   = module.in.strings["redshift_database"]
      secret_arn = var.redshift_reader_secret_arn
    }
  }

  # Redshift sits in the data tier, so the connection's ENIs go to the data subnets with the quicksight security group.
  vpc_connection = var.redshift_reader_secret_arn == null ? null : {
    name               = "${local.name_prefix}-quicksight"
    role_arn           = module.in.strings["role_quicksight_vpc_arn"]
    subnet_ids         = module.in.lists["subnet_ids_data"]
    security_group_ids = [module.in.strings["sg_quicksight_id"]]
  }

  datasets = {
    for k, d in var.datasets : k => {
      source_key  = d.source
      import_mode = "DIRECT_QUERY"
      sql         = null
      table = {
        name    = d.table
        schema  = d.schema != null ? d.schema : (d.source == "athena" ? module.in.strings["curated_database_name"] : "public")
        catalog = d.source == "athena" ? "AwsDataCatalog" : null
      }
      columns = d.columns
    }
  }

  owner_principals  = var.owner_principals
  reader_principals = var.reader_principals
}

module "quicksight" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/quicksight-data/aws"
  version = "~> 0.1.0"

  aws_account_id    = local.aws_account_id
  athena_sources    = local.athena_sources
  redshift_sources  = local.redshift_sources
  vpc_connection    = local.vpc_connection
  datasets          = local.datasets
  owner_principals  = local.owner_principals
  reader_principals = local.reader_principals

  tags = local.common_tags
}
