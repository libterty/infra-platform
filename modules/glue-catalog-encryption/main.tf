# One settings object per account and region. Encryption is not optional here: the module exists to turn it on,
# and the key is a required input. No service role is delegated, so every caller needs its own KMS permissions.
resource "aws_glue_data_catalog_encryption_settings" "this" {
  data_catalog_encryption_settings {
    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = var.kms_key_arn
    }

    connection_password_encryption {
      aws_kms_key_id                       = var.kms_key_arn
      return_connection_password_encrypted = true
    }
  }
}
