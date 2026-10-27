mock_provider "aws" {}
mock_provider "awscc" {}

variables {
  project                     = "example"
  env                         = "dev"
  expected_account_id         = "111111111111"
  account_settings            = { log_level = "WARN" }
  device_defender_audit       = {}
  ota_signing_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
  ota_rollout                 = { maximum_per_minute = 10, abort_threshold_percentage = 10 }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["pki/ca"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ota_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ota-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_provisioning_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-provisioning" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_logging_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-logging" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_audit_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-audit" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_mitigation_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-mitigation" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_greengrass_tes_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-greengrass-tes" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_ota_presign_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-ota-presign" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      alarm_topic_arn           = "foundation/alarm_topic_arn"
      ca                        = "pki/ca"
      ota_bucket_arn            = "storage/ota_bucket_arn"
      role_iot_provisioning_arn = "iam-base/role_iot_provisioning_arn"
      role_iot_logging_arn      = "iam-base/role_iot_logging_arn"
      role_iot_audit_arn        = "iam-base/role_iot_audit_arn"
      role_iot_mitigation_arn   = "iam-base/role_iot_mitigation_arn"
      role_greengrass_tes_arn   = "iam-base/role_greengrass_tes_arn"
      role_ota_presign_arn      = "iam-base/role_ota_presign_arn"
    } && local.ssm_input_lists == {}
    error_message = "fleet must read exactly the keys of earlier stacks it needs"
  }
}

# ---- awscc provider (design K4) ----

run "awscc_provider_uses_the_aws_region_and_role" {
  command = plan

  assert {
    condition     = length(regexall("(?s)provider \"aws\" \\{\\s*region\\s*=\\s*var\\.aws_region\\b.*?for_each = var\\.deploy_role_arn != \"\" \\? \\[var\\.deploy_role_arn\\] : \\[\\]", file("${path.module}/providers.tf"))) == 1
    error_message = "provider aws must use var.aws_region and assume var.deploy_role_arn"
  }

  assert {
    condition     = length(regexall("provider \"awscc\" \\{\\s*region\\s*=\\s*var\\.aws_region\\s*assume_role\\s*=\\s*var\\.deploy_role_arn != \"\" \\? \\{ role_arn = var\\.deploy_role_arn \\} : null\\s*\\}", file("${path.module}/providers.tf"))) == 1
    error_message = "provider awscc must use the same var.aws_region and var.deploy_role_arn as provider aws (design K4)"
  }

  assert {
    condition     = length(regexall("provider \"", file("${path.module}/providers.tf"))) == 2 && length(regexall("allowed_account_ids\\s*=\\s*\\[var\\.expected_account_id\\]", file("${path.module}/providers.tf"))) == 1
    error_message = "There are exactly the aws and awscc providers, and the aws one keeps the account guard"
  }
}

run "awscc_modules_receive_the_common_tags" {
  command = plan

  assert {
    condition     = local.awscc_tags == { Project = "example", Environment = "dev", Managed = "terraform", Stack = "fleet" }
    error_message = "awscc has no default_tags, so its modules get the common tags plus Stack = fleet (design K3)"
  }

  assert {
    condition = alltrue([
      for f in ["device-defender.tf", "ota.tf"] : length(regexall("(?m)^\\s*tags\\s*=\\s*local\\.awscc_tags\\s*$", file("${path.module}/${f}"))) >= 1
    ])
    error_message = "Every awscc module call must pass tags = local.awscc_tags"
  }
}

# ---- iot-fleet ----

run "thing_groups_follow_the_iam_base_naming_rule" {
  command = plan

  assert {
    condition = local.thing_groups == {
      "example-dev-fleet"      = { parent = null, description = "Verified devices that receive deployments" }
      "example-dev-unverified" = { parent = null, description = "Newly provisioned devices waiting for verification" }
      "example-dev-core"       = { parent = null, description = "Greengrass core devices" }
      "example-dev-quarantine" = { parent = null, description = "Devices isolated by a Device Defender mitigation action" }
    }
    error_message = "Thing groups must be <name_prefix>-fleet, -unverified, -core and -quarantine (the iam-base naming rule)"
  }

  assert {
    condition     = keys(local.thing_types) == ["example-dev-device"]
    error_message = "There is one thing type, <name_prefix>-device"
  }
}

run "device_policy_is_scoped_to_the_thing_name" {
  command = plan

  assert {
    condition = alltrue([
      for s in local.policies["example-dev-device"].Statement : alltrue([
        for r in flatten([s.Resource]) : strcontains(r, "$${iot:Connection.Thing.ThingName}")
      ])
    ])
    error_message = "Every device policy Resource must contain $${iot:Connection.Thing.ThingName}"
  }

  assert {
    condition = local.policies["example-dev-device"].Statement[0] == {
      Effect   = "Allow"
      Action   = ["iot:Connect"]
      Resource = ["arn:aws:iot:ap-northeast-1:111111111111:client/$${iot:Connection.Thing.ThingName}"]
    }
    error_message = "A device may only connect with its own thing name as client id"
  }

  assert {
    condition = anytrue([
      for s in local.policies["example-dev-device"].Statement :
      s.Action == ["iot:Publish"] && contains(s.Resource, "arn:aws:iot:ap-northeast-1:111111111111:topic/example-dev/telemetry/$${iot:Connection.Thing.ThingName}")
    ])
    error_message = "A device publishes telemetry to <name_prefix>/telemetry/<thing name>, the topic the ingest rule reads"
  }
}

# Thing policy variables are not supported for core devices (design section 2 item 11, K25).
run "core_policy_uses_the_naming_rule_and_greengrass_actions" {
  command = plan

  assert {
    condition     = !strcontains(jsonencode(local.policies["example-dev-core"]), "iot:Connection.Thing")
    error_message = "The core device policy must not use thing policy variables"
  }

  assert {
    condition = local.policies["example-dev-core"].Statement[0] == {
      Effect   = "Allow"
      Action   = ["iot:Connect"]
      Resource = ["arn:aws:iot:ap-northeast-1:111111111111:client/example-dev-core-*"]
    }
    error_message = "Core devices connect with client ids client/<name_prefix>-core-*"
  }

  assert {
    condition = anytrue([
      for s in local.policies["example-dev-core"].Statement :
      toset(s.Action) == toset(["greengrass:GetComponentVersionArtifact", "greengrass:ResolveComponentCandidates", "greengrass:GetDeploymentConfiguration", "greengrass:ListThingGroupsForCoreDevice"])
    ])
    error_message = "The core policy grants the four Greengrass data plane actions"
  }

  assert {
    condition = anytrue([
      for s in local.policies["example-dev-core"].Statement :
      s.Action == ["iot:AssumeRoleWithCertificate"] && s.Resource == ["arn:aws:iot:ap-northeast-1:111111111111:rolealias/example-dev-greengrass-tes"]
    ])
    error_message = "Core devices may assume only the TES role alias"
  }

  assert {
    condition = alltrue([
      for s in local.policies["example-dev-core"].Statement : alltrue([
        for r in flatten([s.Resource]) : r != "*" || alltrue([for a in s.Action : startswith(a, "greengrass:")])
      ])
    ])
    error_message = "Only the Greengrass data plane actions may use Resource *"
  }
}

run "claim_policy_touches_only_the_provisioning_topics" {
  command = plan

  assert {
    condition = toset(flatten([for s in local.policies["example-dev-claim"].Statement : s.Resource if s.Action != ["iot:Connect"]])) == toset([
      "arn:aws:iot:ap-northeast-1:111111111111:topic/$aws/certificates/create/*",
      "arn:aws:iot:ap-northeast-1:111111111111:topic/$aws/provisioning-templates/example-dev-fleet/provision/*",
      "arn:aws:iot:ap-northeast-1:111111111111:topicfilter/$aws/certificates/create/*",
      "arn:aws:iot:ap-northeast-1:111111111111:topicfilter/$aws/provisioning-templates/example-dev-fleet/provision/*",
    ])
    error_message = "The claim policy may only use the certificate creation and provisioning topics of this template (design section 4.1)"
  }

  assert {
    condition     = alltrue([for s in local.policies["example-dev-claim"].Statement : alltrue([for a in s.Action : contains(["iot:Connect", "iot:Publish", "iot:Receive", "iot:Subscribe"], a)])])
    error_message = "The claim policy may only connect, publish, subscribe and receive"
  }
}

run "role_alias_points_to_the_tes_role" {
  command = plan

  assert {
    condition     = local.role_alias == { alias = "example-dev-greengrass-tes", role_arn = "arn:aws:iam::111111111111:role/example-dev-greengrass-tes", credential_duration = 3600 }
    error_message = "The role alias must be <name_prefix>-greengrass-tes for the iam-base TES role with one-hour credentials"
  }
}

run "provisioning_template_puts_new_things_into_unverified" {
  command = plan

  assert {
    condition     = local.provisioning_template.name == "example-dev-fleet" && local.provisioning_template.enabled && local.provisioning_template.provisioning_role_arn == "arn:aws:iam::111111111111:role/example-dev-iot-provisioning"
    error_message = "The template is <name_prefix>-fleet, enabled, with the iam-base provisioning role"
  }

  assert {
    condition     = local.provisioning_template.pre_provisioning_hook == null
    error_message = "No pre-provisioning hook in example5 (design K16, section 4.1)"
  }

  assert {
    condition = (
      local.provisioning_template.template_body.Resources.thing.Properties.ThingGroups == ["example-dev-unverified"] &&
      local.provisioning_template.template_body.Resources.thing.Properties.ThingName == { "Fn::Join" = ["", ["example-dev-", { Ref = "SerialNumber" }]] } &&
      local.provisioning_template.template_body.Parameters.SerialNumber == { Type = "String" } &&
      local.provisioning_template.template_body.Resources.policy.Properties.PolicyName == "example-dev-device"
    )
    error_message = "New things are named <name_prefix>-<SerialNumber>, join only the unverified group and get the device policy"
  }
}

run "ca_is_not_registered_while_pki_is_off" {
  command = plan

  assert {
    condition     = local.ca_certificate == null
    error_message = "With pki publishing {\"enabled\":false}, no CA may be registered"
  }
}

run "ca_from_pki_is_registered_in_sni_only_mode" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["pki/ca"]
    values = { insecure_value = "{\"enabled\":true,\"arn\":\"arn:aws:acm-pca:ap-northeast-1:111111111111:certificate-authority/11111111-2222-3333-4444-555555555555\",\"certificate_pem\":\"-----BEGIN CERTIFICATE-----\\nMIIB\\n-----END CERTIFICATE-----\"}" }
  }

  assert {
    condition     = local.ca_certificate == { pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----", mode = "SNI_ONLY" }
    error_message = "The pki CA must be registered in SNI_ONLY mode (design K18)"
  }
}

# ---- account-level settings (design K9) ----

run "account_settings_object_calls_the_module" {
  command = plan

  assert {
    condition     = length(module.account_settings) == 1
    error_message = "An account_settings object must call iot-account-settings"
  }

  assert {
    condition     = local.account_settings.logging == { role_arn = "arn:aws:iam::111111111111:role/example-dev-iot-logging", default_log_level = "WARN" }
    error_message = "Logging must use the iam-base logging role and the given level"
  }
}

run "account_settings_null_calls_no_module" {
  command = plan

  variables {
    account_settings = null
  }

  assert {
    condition     = length(module.account_settings) == 0
    error_message = "account_settings = null must not call the module (a second project in the same account sets null)"
  }
}

run "account_settings_log_level_rejected" {
  command = plan

  variables {
    account_settings = { log_level = "VERBOSE" }
  }

  expect_failures = [var.account_settings]
}

run "account_level_objects_default_to_null" {
  command = plan

  assert {
    condition = alltrue([
      for v in ["account_settings", "device_defender_audit"] :
      length(regexall("(?s)variable \"${v}\" \\{.*?default\\s*=\\s*null", file("${path.module}/variables.tf"))) == 1
    ])
    error_message = "account_settings and device_defender_audit must default to null: account-level settings are opt-in per stack"
  }
}

# ---- Device Defender ----

run "audit_object_configures_the_account_audit" {
  command = plan

  assert {
    condition = (
      local.audit.role_arn == "arn:aws:iam::111111111111:role/example-dev-iot-audit" &&
      local.audit.sns == { target_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms", role_arn = "arn:aws:iam::111111111111:role/example-dev-iot-audit" } &&
      toset(local.audit.checks) == toset(local.audit_checks)
    )
    error_message = "The account audit uses the iam-base audit role, sends findings to the alarm topic and enables the scheduled checks"
  }
}

run "audit_null_keeps_schedule_and_mitigation" {
  command = plan

  variables {
    device_defender_audit = null
  }

  assert {
    condition     = local.audit == null && length(local.scheduled_audits) == 1 && length(local.mitigation_actions) == 1
    error_message = "device_defender_audit = null leaves the account audit to another project but keeps this project's schedule and mitigation"
  }
}

run "weekly_audit_and_quarantine_mitigation" {
  command = plan

  assert {
    condition     = local.scheduled_audits == { "example-dev-weekly" = { frequency = "WEEKLY", day_of_week = "MON", checks = local.audit_checks } }
    error_message = "One weekly audit on Monday runs every enabled check (design section 7.5)"
  }

  assert {
    condition = local.mitigation_actions == {
      "example-dev-quarantine" = {
        role_arn                  = "arn:aws:iam::111111111111:role/example-dev-iot-mitigation"
        add_things_to_thing_group = { thing_group_names = ["example-dev-quarantine"], override_dynamic_groups = false }
      }
    }
    error_message = "The mitigation action moves things into the quarantine group with the iam-base mitigation role"
  }
}

# ---- OTA ----

run "ota_signing_profile" {
  command = plan

  assert {
    condition = (
      local.ota_signing.name == "example_dev_ota" &&
      local.ota_signing.platform_id == "AWSIoTDeviceManagement-SHA256-ECDSA" &&
      local.ota_signing.certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
    )
    error_message = "The signing profile is <name_prefix with underscores>_ota on the IoT Device Management platform with the tfvars certificate"
  }
}

run "ota_job_template_uses_presigned_signed_firmware" {
  command = plan

  assert {
    condition     = local.ota_job.job_template_id == "example-dev-ota" && local.ota_job.presigned_url == { role_arn = "arn:aws:iam::111111111111:role/example-dev-ota-presign", expires_in_sec = 3600 }
    error_message = "The job template is <name_prefix>-ota and signs URLs with the iam-base ota-presign role"
  }

  assert {
    condition     = local.ota_job.document.files[0].url == "$${aws:iot:s3-presigned-url:https://s3.amazonaws.com/example-dev-ota-artifacts-111111111111/signed/current/firmware.bin}"
    error_message = "The job document must download the signed firmware from the signed/ prefix of the OTA bucket"
  }

  assert {
    condition = (
      local.ota_job.rollout == { maximum_per_minute = 10 } &&
      local.ota_job.abort == [{ failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 10 }] &&
      local.ota_job.timeout_minutes == 60
    )
    error_message = "The job template rolls out at the tfvars rate and aborts at the tfvars failure percentage"
  }
}

run "ota_rollout_rejected" {
  command = plan

  variables {
    ota_rollout = { maximum_per_minute = 0, abort_threshold_percentage = 10 }
  }

  expect_failures = [var.ota_rollout]
}

# ---- SSM contract ----

run "publishes_exactly_the_fleet_keys" {
  command = plan

  override_module {
    target = module.fleet
    outputs = {
      thing_type_arns = {}
      thing_group_arns = {
        "example-dev-fleet"      = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-fleet"
        "example-dev-unverified" = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-unverified"
        "example-dev-core"       = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-core"
        "example-dev-quarantine" = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-quarantine"
      }
      policy_names               = {}
      role_alias_arn             = "arn:aws:iot:ap-northeast-1:111111111111:rolealias/example-dev-greengrass-tes"
      provisioning_template_name = "example-dev-fleet"
      ca_certificate_id          = null
    }
  }

  override_module {
    target  = module.ota_signing
    outputs = { profile_name = "example_dev_ota", profile_arn = "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/example_dev_ota", profile_version_arn = "arn:aws:signer:ap-northeast-1:111111111111:/signing-profiles/example_dev_ota/abc" }
  }

  override_module {
    target  = module.ota_job
    outputs = { arn = "arn:aws:iot:ap-northeast-1:111111111111:jobtemplate/example-dev-ota", job_template_id = "example-dev-ota" }
  }

  assert {
    condition = local.published_strings == {
      thing_group_fleet_arn      = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-fleet"
      thing_group_unverified_arn = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-unverified"
      thing_group_core_arn       = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-core"
      role_alias_arn             = "arn:aws:iot:ap-northeast-1:111111111111:rolealias/example-dev-greengrass-tes"
      provisioning_template_name = "example-dev-fleet"
      ota_signing_profile_name   = "example_dev_ota"
      ota_job_template_arn       = "arn:aws:iot:ap-northeast-1:111111111111:jobtemplate/example-dev-ota"
    }
    error_message = "fleet must publish exactly the seven String keys of design section 7.2"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition     = module.ssm_publish.names == { for k in keys(local.published_strings) : k => "/example/dev/fleet/${k}" }
    error_message = "ssm-publish must write the contract keys under the fleet stack path"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
