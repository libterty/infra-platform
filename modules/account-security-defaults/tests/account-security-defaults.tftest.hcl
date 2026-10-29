mock_provider "aws" {}

# ---- positive -------------------------------------------------------------------------------------------------

run "all_defaults" {
  command = plan

  assert {
    condition = (
      aws_s3_account_public_access_block.this[0].block_public_acls &&
      aws_s3_account_public_access_block.this[0].block_public_policy &&
      aws_s3_account_public_access_block.this[0].ignore_public_acls &&
      aws_s3_account_public_access_block.this[0].restrict_public_buckets
    )
    error_message = "The account public access block must turn on all four settings"
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this[0].enabled
    error_message = "EBS encryption by default must be on"
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.this) == 0
    error_message = "Without ebs_default_kms_key_arn the AWS managed EBS key stays the default"
  }

  assert {
    condition     = aws_ec2_instance_metadata_defaults.this[0].http_tokens == "required"
    error_message = "New instances must default to IMDSv2"
  }

  assert {
    condition     = aws_ec2_instance_metadata_defaults.this[0].http_put_response_hop_limit == 2
    error_message = "The IMDS hop limit must default to 2 so containers on the instance still reach IMDS"
  }

  assert {
    condition = (
      aws_iam_account_password_policy.this[0].minimum_password_length == 14 &&
      aws_iam_account_password_policy.this[0].require_symbols &&
      aws_iam_account_password_policy.this[0].require_numbers &&
      aws_iam_account_password_policy.this[0].require_uppercase_characters &&
      aws_iam_account_password_policy.this[0].require_lowercase_characters &&
      aws_iam_account_password_policy.this[0].max_password_age == 90 &&
      aws_iam_account_password_policy.this[0].password_reuse_prevention == 24 &&
      aws_iam_account_password_policy.this[0].allow_users_to_change_password
    )
    error_message = "The password policy must default to 14 chars, all classes, 90 days and 24 remembered"
  }
}

run "password_policy_not_managed" {
  command = plan

  variables {
    password_policy = null
  }

  assert {
    condition     = length(aws_iam_account_password_policy.this) == 0
    error_message = "password_policy = null must leave the password policy unmanaged"
  }

  assert {
    condition     = length(aws_s3_account_public_access_block.this) == 1 && length(aws_ebs_encryption_by_default.this) == 1
    error_message = "Leaving out the password policy must not affect the other settings"
  }
}

run "second_region_manages_only_regional_settings" {
  command = plan

  variables {
    region                  = "us-east-1"
    s3_public_access_block  = false
    password_policy         = null
    ebs_default_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = length(aws_s3_account_public_access_block.this) == 0 && length(aws_iam_account_password_policy.this) == 0
    error_message = "Account-wide settings must be skippable in a second region"
  }

  assert {
    condition = (
      aws_ebs_encryption_by_default.this[0].region == "us-east-1" &&
      aws_ebs_default_kms_key.this[0].region == "us-east-1" &&
      aws_ec2_instance_metadata_defaults.this[0].region == "us-east-1"
    )
    error_message = "Regional settings must be placed in the given region"
  }

  assert {
    condition     = aws_ebs_default_kms_key.this[0].key_arn == "arn:aws:kms:us-east-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The EBS default key must be the given CMK"
  }
}

run "custom_password_policy" {
  command = plan

  variables {
    password_policy = { minimum_length = 20, max_age_days = 365, reuse_prevention = 1 }
  }

  assert {
    condition = (
      aws_iam_account_password_policy.this[0].minimum_password_length == 20 &&
      aws_iam_account_password_policy.this[0].max_password_age == 365 &&
      aws_iam_account_password_policy.this[0].password_reuse_prevention == 1 &&
      aws_iam_account_password_policy.this[0].require_symbols
    )
    error_message = "Given fields must override the defaults and the rest keep theirs"
  }
}

run "settings_can_be_left_unmanaged" {
  command = plan

  variables {
    ebs_encryption_by_default = false
    imdsv2_default            = false
  }

  assert {
    condition     = length(aws_ebs_encryption_by_default.this) == 0 && length(aws_ec2_instance_metadata_defaults.this) == 0
    error_message = "false must leave the setting unmanaged, never switch it off"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "password_length_8_rejected" {
  command = plan

  variables {
    password_policy = { minimum_length = 8 }
  }

  expect_failures = [var.password_policy]
}

run "password_length_129_rejected" {
  command = plan

  variables {
    password_policy = { minimum_length = 129 }
  }

  expect_failures = [var.password_policy]
}

run "reuse_25_rejected" {
  command = plan

  variables {
    password_policy = { reuse_prevention = 25 }
  }

  expect_failures = [var.password_policy]
}

run "reuse_0_rejected" {
  command = plan

  variables {
    password_policy = { reuse_prevention = 0 }
  }

  expect_failures = [var.password_policy]
}

run "max_age_1096_rejected" {
  command = plan

  variables {
    password_policy = { max_age_days = 1096 }
  }

  expect_failures = [var.password_policy]
}

run "max_age_0_rejected" {
  command = plan

  variables {
    password_policy = { max_age_days = 0 }
  }

  expect_failures = [var.password_policy]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    ebs_default_kms_key_arn = "alias/aws/ebs"
  }

  expect_failures = [var.ebs_default_kms_key_arn]
}

run "kms_key_without_encryption_rejected" {
  command = plan

  variables {
    ebs_encryption_by_default = false
    ebs_default_kms_key_arn   = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.ebs_default_kms_key_arn]
}

run "bad_region_rejected" {
  command = plan

  variables {
    region = "tokyo"
  }

  expect_failures = [var.region]
}
