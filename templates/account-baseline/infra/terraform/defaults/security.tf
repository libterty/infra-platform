# Account-level security defaults (design K14). The S3 public access block and the password policy are global to the
# account, so only this stack in the main region manages them. EBS uses the AWS managed aws/ebs key: the governance key
# of foundation does not grant EC2 or Auto Scaling, and a key mistake here would stop instances from launching.
locals {
  security_defaults = {
    s3_public_access_block    = true
    ebs_encryption_by_default = true
    imdsv2_default            = true
    password_policy = {
      minimum_length        = 14
      require_symbols       = true
      require_numbers       = true
      require_uppercase     = true
      require_lowercase     = true
      max_age_days          = 90
      reuse_prevention      = 24
      allow_users_to_change = true
    }
  }
}

module "security_defaults" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/account-security-defaults/aws"
  version = "~> 0.1.0"

  s3_public_access_block    = local.security_defaults.s3_public_access_block
  ebs_encryption_by_default = local.security_defaults.ebs_encryption_by_default
  imdsv2_default            = local.security_defaults.imdsv2_default
  password_policy           = local.security_defaults.password_policy
}
