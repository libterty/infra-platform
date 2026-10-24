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

module "etl" {
  source = "../.."

  name        = "alpha-dev-etl"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  crawlers = {
    alpha-dev-raw = {
      role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
      database_name = "alpha_dev_raw"
      s3_paths      = ["s3://alpha-dev-raw/raw/"]
      schedule      = "cron(0 18 * * ? *)"
    }
  }

  jobs = {
    alpha-dev-raw-to-curated = {
      role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
      script_location   = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
      execution_class   = "FLEX"
      worker_type       = "G.1X"
      number_of_workers = 2
      default_arguments = {
        "--job-bookmark-option" = "job-bookmark-enable"
      }
    }
  }

  workflow = {
    name        = "alpha-dev-raw-to-curated"
    description = "Convert new raw objects to curated Parquet"
  }

  # S3 "Object Created" events of the raw bucket (EventBridge notifications on) start the workflow in batches.
  event_trigger = {
    bucket_name          = "alpha-dev-raw"
    key_prefix           = "raw/"
    role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
    actions              = [{ job = "alpha-dev-raw-to-curated" }]
    batch_size           = 100
    batch_window_seconds = 900
  }

  tags = {
    Project = "alpha"
  }
}

output "workflow_arn" {
  value = module.etl.workflow_arn
}

output "event_rule_arn" {
  value = module.etl.event_rule_arn
}
