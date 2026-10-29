# Multi-region trail of management events only, encrypted with the governance key (design K5). The log file validation
# is fixed on inside the cloudtrail module. Events also go to CloudWatch Logs so the alarms in alarms.tf can match them.
locals {
  # Must equal the naming rule in iam/naming.tf: the trail log role may only write to a group of this name.
  trail_log_group_name = "/aws/cloudtrail/${local.name_prefix}"

  trail_log_group = {
    name           = local.trail_log_group_name
    retention_days = var.trail_log_retention_days
    kms_key_arn    = module.in.strings["kms_key_arn"]
  }

  trail = {
    name                  = "${local.name_prefix}-trail"
    s3_bucket_name        = module.in.strings["trail_bucket_name"]
    kms_key_arn           = module.in.strings["kms_key_arn"]
    is_multi_region_trail = true
    # CloudTrail wants the log stream wildcard on the group ARN; log-group returns the ARN without it.
    cloudwatch_logs = {
      log_group_arn = "${module.trail_log_group.arn}:*"
      role_arn      = module.in.strings["trail_logs_role_arn"]
    }
  }
}

module "trail_log_group" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-group/aws"
  version = "~> 0.1.1"

  name           = local.trail_log_group.name
  retention_days = local.trail_log_group.retention_days
  kms_key_arn    = local.trail_log_group.kms_key_arn
}

module "trail" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/cloudtrail/aws"
  version = "~> 0.1.0"

  name                  = local.trail.name
  s3_bucket_name        = local.trail.s3_bucket_name
  kms_key_arn           = local.trail.kms_key_arn
  is_multi_region_trail = local.trail.is_multi_region_trail
  cloudwatch_logs       = local.trail.cloudwatch_logs
}
