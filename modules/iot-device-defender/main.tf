locals {
  # Audit check API names (used by scheduled audits) mapped to the awscc attribute names of the account configuration.
  # The CloudFormation property IoTPolicyPotentialMisConfigurationCheck becomes io_t_..., so a plain lower() is not enough.
  check_attributes = {
    AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK           = "authenticated_cognito_role_overly_permissive_check"
    CA_CERTIFICATE_EXPIRING_CHECK                                = "ca_certificate_expiring_check"
    CA_CERTIFICATE_KEY_QUALITY_CHECK                             = "ca_certificate_key_quality_check"
    CONFLICTING_CLIENT_IDS_CHECK                                 = "conflicting_client_ids_check"
    DEVICE_CERTIFICATE_AGE_CHECK                                 = "device_certificate_age_check"
    DEVICE_CERTIFICATE_EXPIRING_CHECK                            = "device_certificate_expiring_check"
    DEVICE_CERTIFICATE_KEY_QUALITY_CHECK                         = "device_certificate_key_quality_check"
    DEVICE_CERTIFICATE_SHARED_CHECK                              = "device_certificate_shared_check"
    INTERMEDIATE_CA_REVOKED_FOR_ACTIVE_DEVICE_CERTIFICATES_CHECK = "intermediate_ca_revoked_for_active_device_certificates_check"
    IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK                 = "io_t_policy_potential_mis_configuration_check"
    IOT_POLICY_OVERLY_PERMISSIVE_CHECK                           = "iot_policy_overly_permissive_check"
    IOT_ROLE_ALIAS_ALLOWS_ACCESS_TO_UNUSED_SERVICES_CHECK        = "iot_role_alias_allows_access_to_unused_services_check"
    IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK                       = "iot_role_alias_overly_permissive_check"
    LOGGING_DISABLED_CHECK                                       = "logging_disabled_check"
    REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK                    = "revoked_ca_certificate_still_active_check"
    REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK                = "revoked_device_certificate_still_active_check"
    UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK         = "unauthenticated_cognito_role_overly_permissive_check"
  }

  tag_list = { for name in distinct(concat(keys(var.scheduled_audits), keys(var.mitigation_actions))) : name => [
    for k, v in merge(var.tags, { Name = name }) : { key = k, value = v }
  ] }
}

resource "awscc_iot_account_audit_configuration" "this" {
  count = var.audit == null ? 0 : 1

  account_id = var.account_id
  role_arn   = var.audit.role_arn

  # Every known check is set explicitly so a check removed from the input is disabled, not left as it was.
  audit_check_configurations = {
    for check, attribute in local.check_attributes : attribute => { enabled = contains(var.audit.checks, check) }
  }

  audit_notification_target_configurations = var.audit.sns == null ? null : {
    sns = {
      enabled    = true
      target_arn = var.audit.sns.target_arn
      role_arn   = var.audit.sns.role_arn
    }
  }
}

resource "awscc_iot_scheduled_audit" "this" {
  for_each = var.scheduled_audits

  scheduled_audit_name = each.key
  frequency            = each.value.frequency
  day_of_week          = each.value.day_of_week
  day_of_month         = each.value.day_of_month
  target_check_names   = toset(each.value.checks)

  tags = local.tag_list[each.key]

  # A scheduled audit can only run checks that the account configuration has enabled.
  depends_on = [awscc_iot_account_audit_configuration.this]
}

resource "awscc_iot_mitigation_action" "this" {
  for_each = var.mitigation_actions

  action_name = each.key
  role_arn    = each.value.role_arn

  action_params = {
    add_things_to_thing_group_params = each.value.add_things_to_thing_group == null ? null : {
      thing_group_names       = toset(each.value.add_things_to_thing_group.thing_group_names)
      override_dynamic_groups = each.value.add_things_to_thing_group.override_dynamic_groups
    }
    update_device_certificate_params = each.value.update_device_certificate == null ? null : {
      action = each.value.update_device_certificate.action
    }
    publish_finding_to_sns_params = each.value.publish_finding_to_sns == null ? null : {
      topic_arn = each.value.publish_finding_to_sns.topic_arn
    }
    enable_io_t_logging_params = each.value.enable_iot_logging == null ? null : {
      role_arn_for_logging = each.value.enable_iot_logging.role_arn_for_logging
      log_level            = each.value.enable_iot_logging.log_level
    }
  }

  tags = local.tag_list[each.key]
}
