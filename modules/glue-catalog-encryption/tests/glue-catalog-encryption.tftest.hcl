mock_provider "aws" {}

override_resource {
  target          = aws_glue_data_catalog_encryption_settings.this
  override_during = plan
  values = {
    id = "111111111111"
  }
}

variables {
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "catalog_metadata_is_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).encryption_at_rest).catalog_encryption_mode == "SSE-KMS"
    error_message = "Catalog metadata must use SSE-KMS"
  }

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).encryption_at_rest).sse_aws_kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Catalog metadata must be encrypted with the key given as input"
  }

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).encryption_at_rest).catalog_encryption_service_role == null
    error_message = "No service role may be delegated; callers use their own KMS permissions"
  }
}

run "connection_passwords_use_the_same_key_and_stay_encrypted" {
  command = plan

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).connection_password_encryption).aws_kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Connection passwords must be encrypted with the key given as input"
  }

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).connection_password_encryption).return_connection_password_encrypted == true
    error_message = "Connection passwords must stay encrypted in GetConnection responses"
  }
}

run "multi_region_key_arn_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  assert {
    condition     = one(one(aws_glue_data_catalog_encryption_settings.this.data_catalog_encryption_settings).encryption_at_rest).sse_aws_kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-1234abcd12ab34cd56ef1234567890ab"
    error_message = "A multi-Region key ARN is a valid key"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.catalog_id == "111111111111"
    error_message = "catalog_id must be the ID of the catalog the settings apply to"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_id_without_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}
