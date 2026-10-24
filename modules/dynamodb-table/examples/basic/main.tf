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

module "orders" {
  source = "../.."

  name        = "alpha-dev-orders"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  hash_key  = "customer_id"
  range_key = "order_id"

  attributes = {
    customer_id = "S"
    order_id    = "S"
    status      = "S"
    created_at  = "N"
  }

  global_secondary_indexes = {
    by-status = { hash_key = "status", range_key = "created_at" }
  }

  ttl_attribute    = "expires_at"
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery_days = 7

  tags = {
    Project = "alpha"
  }
}

output "table_name" {
  value = module.orders.table_name
}
