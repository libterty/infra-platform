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

module "firmware_update" {
  source = "../.."

  job_template_id = "alpha-dev-firmware-update"
  description     = "Firmware update for non-Greengrass devices."

  document = {
    operation = "firmware-update"
    files     = [{ url = "$${aws:iot:s3-presigned-url:https://s3.amazonaws.com/alpha-dev-ota-artifacts/firmware/1.2.0.bin}" }]
  }

  presigned_url = {
    role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign"
    expires_in_sec = 900
  }

  rollout = { maximum_per_minute = 50 }
  abort = [
    { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
  ]
  retry           = [{ failure_type = "TIMED_OUT", number_of_retries = 2 }]
  timeout_minutes = 60

  tags = {
    Project     = "alpha"
    Environment = "dev"
  }
}

output "job_template_arn" {
  value = module.firmware_update.arn
}
