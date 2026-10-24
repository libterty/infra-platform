terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "bi" {
  source = "../.."

  aws_account_id = "111111111111"

  # Athena source: its own role, one workgroup.
  athena_sources = {
    alpha-dev-athena = {
      workgroup = "alpha-dev-analytics"
      role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-quicksight-athena"
    }
  }

  # Redshift source: only when the read-only DB user's secret exists (created outside this repo and authorized to
  # QuickSight in the console). Leave the map empty to create the Athena source only.
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
      source_key = "alpha-dev-athena"
      sql        = "SELECT event_id, event_time FROM \"alpha_dev_curated\".\"events\""
      columns = [
        { name = "event_id", type = "STRING" },
        { name = "event_time", type = "DATETIME" },
      ]
    }
    alpha-dev-events-warehouse = {
      source_key = "alpha-dev-redshift"
      table      = { schema = "public", name = "events" }
      columns = [
        { name = "event_id", type = "STRING" },
        { name = "event_time", type = "DATETIME" },
      ]
    }
  }

  owner_principals  = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-owners"]
  reader_principals = ["arn:aws:quicksight:ap-northeast-1:111111111111:group/default/alpha-dev-bi-readers"]

  tags = {
    Project = "alpha"
  }
}

output "data_source_arns" {
  value = module.bi.data_source_arns
}

output "data_set_arns" {
  value = module.bi.data_set_arns
}
