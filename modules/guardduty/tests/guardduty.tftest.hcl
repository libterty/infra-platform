mock_provider "aws" {}

override_resource {
  target          = aws_guardduty_detector.this
  override_during = plan
  values = {
    id  = "12abc34d567e8fa901bc2d34e56789f0"
    arn = "arn:aws:guardduty:ap-northeast-1:111111111111:detector/12abc34d567e8fa901bc2d34e56789f0"
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "default_features" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this.enable == true
    error_message = "The detector must be enabled"
  }

  assert {
    condition     = aws_guardduty_detector.this.finding_publishing_frequency == "FIFTEEN_MINUTES"
    error_message = "Findings must be published every 15 minutes by default"
  }

  assert {
    condition     = length(aws_guardduty_detector.this.datasources) == 0
    error_message = "The legacy datasources block must not be used; features are managed with detector_feature"
  }

  assert {
    condition = { for k, f in aws_guardduty_detector_feature.this : k => f.status } == {
      S3_DATA_EVENTS         = "ENABLED"
      EKS_AUDIT_LOGS         = "ENABLED"
      EBS_MALWARE_PROTECTION = "ENABLED"
      RDS_LOGIN_EVENTS       = "ENABLED"
      LAMBDA_NETWORK_LOGS    = "ENABLED"
      RUNTIME_MONITORING     = "DISABLED"
    }
    error_message = "Default features must follow K7: runtime monitoring off, the rest on"
  }

  assert {
    condition     = alltrue([for k, f in aws_guardduty_detector_feature.this : f.name == k && f.detector_id == "12abc34d567e8fa901bc2d34e56789f0"])
    error_message = "Each feature must use its key as the name and belong to the detector"
  }

  assert {
    condition     = length(aws_guardduty_organization_configuration.this) == 0 && length(aws_guardduty_organization_configuration_feature.this) == 0
    error_message = "No organization configuration without organization"
  }

  assert {
    condition     = output.detector_id == "12abc34d567e8fa901bc2d34e56789f0"
    error_message = "detector_id output must be the detector id"
  }

  assert {
    condition     = output.detector_arn == "arn:aws:guardduty:ap-northeast-1:111111111111:detector/12abc34d567e8fa901bc2d34e56789f0"
    error_message = "detector_arn output must be the detector ARN"
  }
}

run "runtime_monitoring_with_agent_management" {
  command = plan

  variables {
    region                       = "us-east-1"
    finding_publishing_frequency = "SIX_HOURS"
    features = {
      RUNTIME_MONITORING = {
        status = "ENABLED"
        additional_configuration = {
          EKS_ADDON_MANAGEMENT         = "ENABLED"
          ECS_FARGATE_AGENT_MANAGEMENT = "ENABLED"
          EC2_AGENT_MANAGEMENT         = "DISABLED"
        }
      }
    }
    tags = { Project = "alpha" }
  }

  assert {
    condition     = keys(aws_guardduty_detector_feature.this) == ["RUNTIME_MONITORING"]
    error_message = "Only the given features must be managed"
  }

  assert {
    condition = { for c in aws_guardduty_detector_feature.this["RUNTIME_MONITORING"].additional_configuration : c.name => c.status } == {
      EKS_ADDON_MANAGEMENT         = "ENABLED"
      ECS_FARGATE_AGENT_MANAGEMENT = "ENABLED"
      EC2_AGENT_MANAGEMENT         = "DISABLED"
    }
    error_message = "additional_configuration must be passed through"
  }

  assert {
    condition     = aws_guardduty_detector.this.region == "us-east-1" && aws_guardduty_detector_feature.this["RUNTIME_MONITORING"].region == "us-east-1"
    error_message = "region must be set on the detector and its features"
  }

  assert {
    condition     = aws_guardduty_detector.this.finding_publishing_frequency == "SIX_HOURS"
    error_message = "finding_publishing_frequency must be passed through"
  }

  assert {
    condition     = aws_guardduty_detector.this.tags["Project"] == "alpha"
    error_message = "tags must be passed through"
  }
}

run "organization_all" {
  command = plan

  variables {
    region = "ap-northeast-1"
    organization = {
      auto_enable = "ALL"
      features = {
        S3_DATA_EVENTS = { auto_enable = "ALL" }
        RUNTIME_MONITORING = {
          auto_enable              = "NONE"
          additional_configuration = { EKS_ADDON_MANAGEMENT = "NONE" }
        }
      }
    }
  }

  assert {
    condition     = aws_guardduty_organization_configuration.this[0].auto_enable_organization_members == "ALL"
    error_message = "auto_enable must be passed through"
  }

  assert {
    condition     = aws_guardduty_organization_configuration.this[0].detector_id == "12abc34d567e8fa901bc2d34e56789f0" && aws_guardduty_organization_configuration.this[0].region == "ap-northeast-1"
    error_message = "The organization configuration must use the detector and region"
  }

  assert {
    condition     = length(aws_guardduty_organization_configuration.this[0].datasources) == 0
    error_message = "The legacy datasources block must not be used"
  }

  assert {
    condition     = { for k, f in aws_guardduty_organization_configuration_feature.this : k => f.auto_enable } == { S3_DATA_EVENTS = "ALL", RUNTIME_MONITORING = "NONE" }
    error_message = "Organization features must be passed through"
  }

  assert {
    condition     = { for c in aws_guardduty_organization_configuration_feature.this["RUNTIME_MONITORING"].additional_configuration : c.name => c.auto_enable } == { EKS_ADDON_MANAGEMENT = "NONE" }
    error_message = "Organization additional_configuration must be passed through"
  }

  assert {
    condition     = alltrue([for k, f in aws_guardduty_organization_configuration_feature.this : f.name == k && f.detector_id == "12abc34d567e8fa901bc2d34e56789f0" && f.region == "ap-northeast-1"])
    error_message = "Organization features must use their key as the name, the detector and the region"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "unknown_feature_rejected" {
  command = plan

  variables {
    features = { EKS_RUNTIME_MONITORING = { status = "ENABLED" } }
  }

  expect_failures = [var.features]
}

run "invalid_status_rejected" {
  command = plan

  variables {
    features = { S3_DATA_EVENTS = { status = "ON" } }
  }

  expect_failures = [var.features]
}

run "unknown_additional_configuration_rejected" {
  command = plan

  variables {
    features = {
      RUNTIME_MONITORING = {
        status                   = "ENABLED"
        additional_configuration = { GKE_AGENT_MANAGEMENT = "ENABLED" }
      }
    }
  }

  expect_failures = [var.features]
}

run "additional_configuration_on_other_feature_rejected" {
  command = plan

  variables {
    features = {
      S3_DATA_EVENTS = {
        status                   = "ENABLED"
        additional_configuration = { EKS_ADDON_MANAGEMENT = "ENABLED" }
      }
    }
  }

  expect_failures = [var.features]
}

run "invalid_additional_configuration_status_rejected" {
  command = plan

  variables {
    features = {
      RUNTIME_MONITORING = {
        status                   = "ENABLED"
        additional_configuration = { EKS_ADDON_MANAGEMENT = "YES" }
      }
    }
  }

  expect_failures = [var.features]
}

run "invalid_frequency_rejected" {
  command = plan

  variables {
    finding_publishing_frequency = "FIVE_MINUTES"
  }

  expect_failures = [var.finding_publishing_frequency]
}

run "invalid_organization_auto_enable_rejected" {
  command = plan

  variables {
    organization = { auto_enable = "SOME" }
  }

  expect_failures = [var.organization]
}

run "unknown_organization_feature_rejected" {
  command = plan

  variables {
    organization = {
      auto_enable = "ALL"
      features    = { MACIE = { auto_enable = "ALL" } }
    }
  }

  expect_failures = [var.organization]
}

run "invalid_organization_feature_auto_enable_rejected" {
  command = plan

  variables {
    organization = {
      auto_enable = "ALL"
      features    = { S3_DATA_EVENTS = { auto_enable = "ENABLED" } }
    }
  }

  expect_failures = [var.organization]
}

run "invalid_organization_additional_configuration_rejected" {
  command = plan

  variables {
    organization = {
      auto_enable = "ALL"
      features = {
        RUNTIME_MONITORING = {
          auto_enable              = "ALL"
          additional_configuration = { EKS_ADDON_MANAGEMENT = "ENABLED" }
        }
      }
    }
  }

  expect_failures = [var.organization]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
