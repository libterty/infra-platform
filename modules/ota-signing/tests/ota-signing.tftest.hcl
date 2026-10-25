mock_provider "aws" {}

override_resource {
  target          = aws_signer_signing_profile.this
  override_during = plan
  values = {
    arn         = "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/alpha_dev_firmware"
    version_arn = "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/alpha_dev_firmware/abcde12345"
    version     = "abcde12345"
  }
}

variables {
  name            = "alpha_dev_firmware"
  platform_id     = "AmazonFreeRTOS-Default"
  certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "freertos_with_certificate" {
  command = plan

  variables {
    signing_parameters = { certname = "ota_signer_pub.pem" }
  }

  assert {
    condition     = aws_signer_signing_profile.this.platform_id == "AmazonFreeRTOS-Default"
    error_message = "platform_id must be passed through"
  }

  assert {
    condition     = aws_signer_signing_profile.this.name == "alpha_dev_firmware"
    error_message = "The profile name must be passed through"
  }

  assert {
    condition     = one(aws_signer_signing_profile.this.signing_material).certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The profile must sign with the given ACM certificate"
  }

  assert {
    condition     = aws_signer_signing_profile.this.signing_parameters == tomap({ certname = "ota_signer_pub.pem" })
    error_message = "signing_parameters must be passed through"
  }

  assert {
    condition     = length(aws_signer_signing_profile.this.signature_validity_period) == 0
    error_message = "Signature validity only applies to the Lambda and Notation platforms and must not be set"
  }

  assert {
    condition     = length(aws_signer_signing_profile_permission.start_job) == 0
    error_message = "No permission must be created without start_job_principals"
  }
}

run "freertos_ti_cc3220sf_platform" {
  command = plan

  variables {
    platform_id = "AmazonFreeRTOS-TI-CC3220SF"
  }

  assert {
    condition     = aws_signer_signing_profile.this.platform_id == "AmazonFreeRTOS-TI-CC3220SF"
    error_message = "The TI CC3220SF platform must be accepted"
  }
}

run "device_management_platform" {
  command = plan

  variables {
    platform_id = "AWSIoTDeviceManagement-SHA256-ECDSA"
  }

  assert {
    condition     = aws_signer_signing_profile.this.platform_id == "AWSIoTDeviceManagement-SHA256-ECDSA"
    error_message = "The Device Management platform must be accepted"
  }

  assert {
    condition     = length(aws_signer_signing_profile.this.signing_material) == 1
    error_message = "IoT platforms sign with an imported ACM certificate"
  }

  assert {
    condition     = aws_signer_signing_profile.this.signing_parameters == null
    error_message = "Empty signing_parameters must not be sent"
  }
}

run "start_job_permission" {
  command = plan

  variables {
    start_job_principals = [
      "arn:aws:iam::111111111111:role/alpha-dev-ci",
      "arn:aws:iam::111111111111:role/alpha-dev-release",
    ]
  }

  assert {
    condition     = length(aws_signer_signing_profile_permission.start_job) == 2
    error_message = "One permission per principal is expected"
  }

  assert {
    condition     = alltrue([for p in aws_signer_signing_profile_permission.start_job : p.action == "signer:StartSigningJob"])
    error_message = "Permissions must only grant signer:StartSigningJob"
  }

  assert {
    condition     = aws_signer_signing_profile_permission.start_job["arn:aws:iam::111111111111:role/alpha-dev-ci"].principal == "arn:aws:iam::111111111111:role/alpha-dev-ci"
    error_message = "The principal must be passed through"
  }

  assert {
    condition     = alltrue([for p in aws_signer_signing_profile_permission.start_job : p.profile_name == "alpha_dev_firmware"])
    error_message = "Permissions must target this profile"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_signer_signing_profile.this.tags["Project"] == "alpha" && aws_signer_signing_profile.this.tags["Name"] == "alpha_dev_firmware"
    error_message = "Name must be added to the given tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.profile_name == "alpha_dev_firmware"
    error_message = "profile_name output must be the profile name"
  }

  assert {
    condition     = output.profile_arn == "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/alpha_dev_firmware"
    error_message = "profile_arn output must be the profile ARN"
  }

  assert {
    condition     = output.profile_version_arn == "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/alpha_dev_firmware/abcde12345"
    error_message = "profile_version_arn output must be the versioned profile ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "lambda_platform_rejected" {
  command = plan

  variables {
    platform_id = "AWSLambda-SHA384-ECDSA"
  }

  expect_failures = [var.platform_id]
}

run "unknown_platform_rejected" {
  command = plan

  variables {
    platform_id = "AmazonFreeRTOS-Bogus"
  }

  expect_failures = [var.platform_id]
}

run "freertos_without_certificate_rejected" {
  command = plan

  variables {
    certificate_arn = null
  }

  expect_failures = [var.certificate_arn]
}

run "device_management_without_certificate_rejected" {
  command = plan

  variables {
    platform_id     = "AWSIoTDeviceManagement-SHA256-ECDSA"
    certificate_arn = null
  }

  expect_failures = [var.certificate_arn]
}

run "non_acm_certificate_arn_rejected" {
  command = plan

  variables {
    certificate_arn = "arn:aws:iam::111111111111:server-certificate/alpha-dev"
  }

  expect_failures = [var.certificate_arn]
}

run "pca_certificate_arn_rejected" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.certificate_arn]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha-dev-firmware"
  }

  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "a234567890123456789012345678901234567890123456789012345678901234x"
  }

  expect_failures = [var.name]
}

run "principal_not_a_role_arn_rejected" {
  command = plan

  variables {
    start_job_principals = ["111111111111"]
  }

  expect_failures = [var.start_job_principals]
}

run "wildcard_principal_rejected" {
  command = plan

  variables {
    start_job_principals = ["*"]
  }

  expect_failures = [var.start_job_principals]
}
