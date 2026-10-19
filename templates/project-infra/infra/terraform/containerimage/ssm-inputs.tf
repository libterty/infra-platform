locals {
  ssm_input_strings = {
    kms_key_arn = "foundation/kms_key_arn"
  }
  ssm_input_lists = {}
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
