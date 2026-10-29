# Config records every supported type continuously. Global types (IAM) are recorded here only: this is the primary
# region, and a recorder in another region must set include_global_resource_types = false (infra/REFERENCE.md).
locals {
  config_recorder = {
    name                = "default"
    role_arn            = module.in.strings["config_role_arn"]
    s3_bucket_name      = module.in.strings["config_bucket_name"]
    s3_kms_key_arn      = module.in.strings["kms_key_arn"]
    recording           = { include_global_resource_types = true, exclusion_types = [] }
    recording_frequency = "CONTINUOUS"
    retention_days      = 2557
  }
}

module "config_recorder" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/config-recorder/aws"
  version = "~> 0.1.0"

  name                = local.config_recorder.name
  role_arn            = local.config_recorder.role_arn
  s3_bucket_name      = local.config_recorder.s3_bucket_name
  s3_kms_key_arn      = local.config_recorder.s3_kms_key_arn
  recording           = local.config_recorder.recording
  recording_frequency = local.config_recorder.recording_frequency
  retention_days      = local.config_recorder.retention_days
}
