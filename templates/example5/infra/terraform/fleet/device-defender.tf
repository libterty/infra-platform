# Audit only: Detect is closed to new customers (design K8). The account audit configuration is account and region
# level, so a second project in the same account sets device_defender_audit = null (design K9); the weekly audit and
# the mitigation action of this project stay.
locals {
  audit_checks = [
    "LOGGING_DISABLED_CHECK",
    "CA_CERTIFICATE_EXPIRING_CHECK",
    "DEVICE_CERTIFICATE_EXPIRING_CHECK",
    "DEVICE_CERTIFICATE_SHARED_CHECK",
    "CONFLICTING_CLIENT_IDS_CHECK",
    "IOT_POLICY_OVERLY_PERMISSIVE_CHECK",
    "IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK",
    "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK",
  ]

  audit = var.device_defender_audit == null ? null : {
    role_arn = module.in.strings["role_iot_audit_arn"]
    checks   = local.audit_checks
    sns = {
      target_arn = module.in.strings["alarm_topic_arn"]
      role_arn   = module.in.strings["role_iot_audit_arn"]
    }
  }

  scheduled_audits = {
    "${local.name_prefix}-weekly" = { frequency = "WEEKLY", day_of_week = "MON", checks = local.audit_checks }
  }

  # The quarantine group is the one iam-base lets the mitigation role add things to.
  mitigation_actions = {
    "${local.name_prefix}-quarantine" = {
      role_arn                  = module.in.strings["role_iot_mitigation_arn"]
      add_things_to_thing_group = { thing_group_names = ["${local.name_prefix}-quarantine"], override_dynamic_groups = false }
    }
  }
}

module "device_defender" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iot-device-defender/aws"
  version = "~> 0.1.0"

  account_id         = local.audit == null ? null : var.expected_account_id
  audit              = local.audit
  scheduled_audits   = local.scheduled_audits
  mitigation_actions = local.mitigation_actions
  tags               = local.awscc_tags

  # The quarantine group must exist before an action that names it.
  depends_on = [module.fleet]
}
