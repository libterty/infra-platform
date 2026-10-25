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

module "defender" {
  source = "../.."

  account_id = "111111111111"

  audit = {
    role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
    checks = [
      "LOGGING_DISABLED_CHECK",
      "DEVICE_CERTIFICATE_EXPIRING_CHECK",
      "DEVICE_CERTIFICATE_SHARED_CHECK",
      "IOT_POLICY_OVERLY_PERMISSIVE_CHECK",
      "CONFLICTING_CLIENT_IDS_CHECK",
    ]
    sns = {
      target_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit"
      role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit-sns"
    }
  }

  scheduled_audits = {
    alpha-dev-weekly = {
      frequency   = "WEEKLY"
      day_of_week = "MON"
      checks      = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    }
  }

  mitigation_actions = {
    alpha-dev-quarantine = {
      role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
      add_things_to_thing_group = { thing_group_names = ["alpha-dev-quarantine"] }
    }
  }

  tags = {
    Project     = "alpha"
    Environment = "dev"
  }
}

output "scheduled_audit_arns" {
  value = module.defender.scheduled_audit_arns
}
