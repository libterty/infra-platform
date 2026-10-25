terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.107, < 2.0"
    }
  }
}

provider "awscc" {
  region = "ap-northeast-1"
}

module "fleet" {
  source = "../.."

  name       = "alpha-dev-fleet"
  target_arn = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet"

  components = {
    "aws.greengrass.Nucleus" = { version = "2.14.3" }
    "com.example.Inference" = {
      version  = "1.0.0"
      merge    = { threshold = 0.8, topic = "alpha/dev/inference" }
      run_with = { posix_user = "ggc_user:ggc_group" }
    }
  }

  rollout = {
    exponential = { base_rate_per_minute = 5, increment_factor = 2, number_of_succeeded_things = 10 }
  }

  abort = [
    { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
    { failure_type = "TIMED_OUT", threshold_percentage = 20, min_number_of_executed_things = 5 },
  ]

  in_progress_timeout_minutes = 60

  tags = {
    Project     = "alpha"
    Environment = "dev"
  }
}

output "deployment_id" {
  value = module.fleet.deployment_id
}
