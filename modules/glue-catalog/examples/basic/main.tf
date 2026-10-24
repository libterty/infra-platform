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

module "catalog" {
  source = "../.."

  databases = {
    alpha_dev_raw = {
      description  = "Raw zone, crawled from the raw bucket"
      location_uri = "s3://alpha-dev-raw/raw/"
    }
    alpha_dev_curated = {
      description  = "Curated zone, written by the ETL jobs"
      location_uri = "s3://alpha-dev-curated/curated/"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "database_arns" {
  value = module.catalog.database_arns
}
