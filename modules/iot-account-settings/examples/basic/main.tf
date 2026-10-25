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

# Call once per account and region; a second project in the same account passes null for every input.
module "iot_account_settings" {
  source = "../.."

  indexing = {
    thing_indexing_mode              = "REGISTRY_AND_SHADOW"
    thing_connectivity_indexing_mode = "STATUS"
    device_defender_indexing_mode    = "VIOLATIONS"
  }

  logging = {
    role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
  }

  event_configurations = {
    THING                  = true
    THING_GROUP_MEMBERSHIP = true
    JOB_EXECUTION          = true
  }
}
