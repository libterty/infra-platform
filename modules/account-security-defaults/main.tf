resource "aws_s3_account_public_access_block" "this" {
  count = var.s3_public_access_block ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  count = var.ebs_encryption_by_default ? 1 : 0

  region  = var.region
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  count = var.ebs_default_kms_key_arn == null ? 0 : 1

  region  = var.region
  key_arn = var.ebs_default_kms_key_arn
}

resource "aws_ec2_instance_metadata_defaults" "this" {
  count = var.imdsv2_default ? 1 : 0

  region = var.region
  # 2 hops so containers on the instance (docker bridge, EKS pods) still reach IMDS.
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
}

resource "aws_iam_account_password_policy" "this" {
  count = var.password_policy == null ? 0 : 1

  minimum_password_length        = var.password_policy.minimum_length
  require_symbols                = var.password_policy.require_symbols
  require_numbers                = var.password_policy.require_numbers
  require_uppercase_characters   = var.password_policy.require_uppercase
  require_lowercase_characters   = var.password_policy.require_lowercase
  max_password_age               = var.password_policy.max_age_days
  password_reuse_prevention      = var.password_policy.reuse_prevention
  allow_users_to_change_password = var.password_policy.allow_users_to_change
}
