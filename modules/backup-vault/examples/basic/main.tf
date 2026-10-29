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

module "backup_vault" {
  source = "../.."

  name        = "alpha-dev-backup"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  lock = {
    min_retention_days = 7
    max_retention_days = 35
  }

  notifications = {
    sns_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
    events        = ["BACKUP_JOB_COMPLETED", "COPY_JOB_FAILED", "RESTORE_JOB_COMPLETED"]
  }

  tags = {
    Project = "alpha"
  }
}

output "vault_arn" {
  value = module.backup_vault.arn
}
