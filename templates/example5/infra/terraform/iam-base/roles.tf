locals {
  trust = { source_account = var.expected_account_id, source_arn = null }

  roles = {
    # IoT rules of the ingest stack; ArnLike on the rule naming rule.
    iot_rule = {
      name     = "${local.name_prefix}-iot-rule"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"], source_arn = local.iot_rule_arn_pattern })
      policies = { put-stream-and-errors = jsonencode({ Version = "2012-10-17", Statement = local.iot_rule_statements }) }
    }
    iot_provisioning = {
      name     = "${local.name_prefix}-iot-provisioning"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"] })
      policies = { register-things = jsonencode({ Version = "2012-10-17", Statement = local.iot_provisioning_statements }) }
    }
    iot_logging = {
      name     = "${local.name_prefix}-iot-logging"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"] })
      policies = { write-iot-logs = jsonencode({ Version = "2012-10-17", Statement = local.iot_logging_statements }) }
    }
    iot_audit = {
      name     = "${local.name_prefix}-iot-audit"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"] })
      policies = { audit-read-and-notify = jsonencode({ Version = "2012-10-17", Statement = local.iot_audit_statements }) }
    }
    iot_mitigation = {
      name     = "${local.name_prefix}-iot-mitigation"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"] })
      policies = { quarantine-things = jsonencode({ Version = "2012-10-17", Statement = local.iot_mitigation_statements }) }
    }
    # Core devices get credentials through the role alias of the fleet stack. Whether the credentials provider sends
    # aws:SourceAccount is not verified against a real account (design section 11).
    greengrass_tes = {
      name     = "${local.name_prefix}-greengrass-tes"
      trust    = merge(local.trust, { service_principals = ["credentials.iot.amazonaws.com"] })
      policies = { core-device-access = jsonencode({ Version = "2012-10-17", Statement = local.greengrass_tes_statements }) }
    }
    ota_presign = {
      name     = "${local.name_prefix}-ota-presign"
      trust    = merge(local.trust, { service_principals = ["iot.amazonaws.com"] })
      policies = { read-signed-firmware = jsonencode({ Version = "2012-10-17", Statement = local.ota_presign_statements }) }
    }
    # Trust only. The policy needs the OpenSearch domain ARN, which exists after the search stack; iam-app attaches it.
    firehose = {
      name     = "${local.name_prefix}-firehose"
      trust    = merge(local.trust, { service_principals = ["firehose.amazonaws.com"] })
      policies = {}
    }
    sagemaker_pipeline = {
      name     = "${local.name_prefix}-sagemaker-pipeline"
      trust    = merge(local.trust, { service_principals = ["sagemaker.amazonaws.com"] })
      policies = { train-and-register = jsonencode({ Version = "2012-10-17", Statement = local.sagemaker_pipeline_statements }) }
    }
    sagemaker_endpoint = {
      name     = "${local.name_prefix}-sagemaker-endpoint"
      trust    = merge(local.trust, { service_principals = ["sagemaker.amazonaws.com"] })
      policies = { serve-model = jsonencode({ Version = "2012-10-17", Statement = local.sagemaker_endpoint_statements }) }
    }
    scheduler = {
      name     = "${local.name_prefix}-scheduler"
      trust    = merge(local.trust, { service_principals = ["scheduler.amazonaws.com"] })
      policies = { start-training-pipeline = jsonencode({ Version = "2012-10-17", Statement = local.scheduler_statements }) }
    }
  }
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.4.1"
  for_each = local.roles

  name            = each.value.name
  trust           = each.value.trust
  inline_policies = each.value.policies
}
