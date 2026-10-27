locals {
  # Names follow the naming rules of iam-base (naming.tf): its provisioning, mitigation and TES policies were written
  # for exactly these names before this stack existed.
  thing_types = {
    "${local.name_prefix}-device" = { description = "Devices of ${local.name_prefix}", searchable_attributes = ["serial"] }
  }

  # All top level: a Greengrass deployment to a group also reaches its child groups, and only core devices run Greengrass.
  thing_groups = {
    "${local.name_prefix}-fleet"      = { parent = null, description = "Verified devices that receive deployments" }
    "${local.name_prefix}-unverified" = { parent = null, description = "Newly provisioned devices waiting for verification" }
    "${local.name_prefix}-core"       = { parent = null, description = "Greengrass core devices" }
    "${local.name_prefix}-quarantine" = { parent = null, description = "Devices isolated by a Device Defender mitigation action" }
  }

  provisioning_template_name = "${local.name_prefix}-fleet"
  role_alias_name            = "${local.name_prefix}-greengrass-tes"
  thing_name                 = "$${iot:Connection.Thing.ThingName}"
  core_name_pattern          = "${local.name_prefix}-core-*"

  policies = {
    # Ordinary devices: their own client id and topics only (design K25).
    "${local.name_prefix}-device" = {
      Version = "2012-10-17"
      Statement = [
        { Effect = "Allow", Action = ["iot:Connect"], Resource = ["${local.iot_arn_prefix}:client/${local.thing_name}"] },
        { Effect = "Allow", Action = ["iot:Publish"], Resource = ["${local.iot_arn_prefix}:topic/${local.name_prefix}/telemetry/${local.thing_name}"] },
        {
          Effect   = "Allow"
          Action   = ["iot:Subscribe"]
          Resource = ["${local.iot_arn_prefix}:topicfilter/${local.name_prefix}/cmd/${local.thing_name}", "${local.iot_arn_prefix}:topicfilter/$aws/things/${local.thing_name}/jobs/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["iot:Receive"]
          Resource = ["${local.iot_arn_prefix}:topic/${local.name_prefix}/cmd/${local.thing_name}", "${local.iot_arn_prefix}:topic/$aws/things/${local.thing_name}/jobs/*"]
        },
        # OTA through IoT Jobs: the device reports job progress on its own jobs topics.
        { Effect = "Allow", Action = ["iot:Publish"], Resource = ["${local.iot_arn_prefix}:topic/$aws/things/${local.thing_name}/jobs/*"] },
      ]
    }
    # Core devices: thing policy variables are not supported, so the naming rule client/<name_prefix>-core-* scopes them
    # (design section 2 item 11, K25).
    "${local.name_prefix}-core" = {
      Version = "2012-10-17"
      Statement = [
        { Effect = "Allow", Action = ["iot:Connect"], Resource = ["${local.iot_arn_prefix}:client/${local.core_name_pattern}"] },
        {
          # Shadow, jobs and Greengrass health topics of the core devices.
          Effect   = "Allow"
          Action   = ["iot:Publish", "iot:Receive"]
          Resource = ["${local.iot_arn_prefix}:topic/$aws/things/${local.core_name_pattern}/*"]
        },
        { Effect = "Allow", Action = ["iot:Subscribe"], Resource = ["${local.iot_arn_prefix}:topicfilter/$aws/things/${local.core_name_pattern}/*"] },
        # The inference component reads sensor telemetry and publishes results (design section 7.3).
        { Effect = "Allow", Action = ["iot:Subscribe"], Resource = ["${local.iot_arn_prefix}:topicfilter/${local.name_prefix}/telemetry/*"] },
        { Effect = "Allow", Action = ["iot:Receive"], Resource = ["${local.iot_arn_prefix}:topic/${local.name_prefix}/telemetry/*"] },
        { Effect = "Allow", Action = ["iot:Publish"], Resource = ["${local.iot_arn_prefix}:topic/${local.name_prefix}/inference/*"] },
        { Effect = "Allow", Action = ["iot:AssumeRoleWithCertificate"], Resource = ["${local.iot_arn_prefix}:rolealias/${local.role_alias_name}"] },
        {
          # Greengrass data plane; these actions are granted on "*" in the Greengrass minimal policy.
          Effect   = "Allow"
          Action   = ["greengrass:GetComponentVersionArtifact", "greengrass:ResolveComponentCandidates", "greengrass:GetDeploymentConfiguration", "greengrass:ListThingGroupsForCoreDevice"]
          Resource = ["*"]
        },
      ]
    }
    # Claim certificate: only the two provisioning topic sets of this template (design section 4.1).
    "${local.name_prefix}-claim" = {
      Version = "2012-10-17"
      Statement = [
        # The claim certificate connects before the device has a thing name.
        { Effect = "Allow", Action = ["iot:Connect"], Resource = ["${local.iot_arn_prefix}:client/*"] },
        {
          Effect = "Allow"
          Action = ["iot:Publish", "iot:Receive"]
          Resource = [
            "${local.iot_arn_prefix}:topic/$aws/certificates/create/*",
            "${local.iot_arn_prefix}:topic/$aws/provisioning-templates/${local.provisioning_template_name}/provision/*",
          ]
        },
        {
          Effect = "Allow"
          Action = ["iot:Subscribe"]
          Resource = [
            "${local.iot_arn_prefix}:topicfilter/$aws/certificates/create/*",
            "${local.iot_arn_prefix}:topicfilter/$aws/provisioning-templates/${local.provisioning_template_name}/provision/*",
          ]
        },
      ]
    }
  }

  role_alias = {
    alias               = local.role_alias_name
    role_arn            = module.in.strings["role_greengrass_tes_arn"]
    credential_duration = 3600
  }

  # Fleet provisioning by claim without a pre-provisioning hook (design K16, section 4.1). The thing name is built from
  # the serial number, so a second provisioning of the same serial fails; new things join the unverified group only.
  # Provisioning template parameters take only Type and Default, so the serial format is not checked here.
  provisioning_template = {
    name                  = local.provisioning_template_name
    description           = "Fleet provisioning by claim of ${local.name_prefix}"
    provisioning_role_arn = module.in.strings["role_iot_provisioning_arn"]
    enabled               = true
    pre_provisioning_hook = null
    template_body = {
      Parameters = {
        SerialNumber                = { Type = "String" }
        "AWS::IoT::Certificate::Id" = { Type = "String" }
      }
      Resources = {
        thing = {
          Type = "AWS::IoT::Thing"
          Properties = {
            ThingName        = { "Fn::Join" = ["", ["${local.name_prefix}-", { Ref = "SerialNumber" }]] }
            ThingTypeName    = "${local.name_prefix}-device"
            ThingGroups      = ["${local.name_prefix}-unverified"]
            AttributePayload = { serial = { Ref = "SerialNumber" } }
          }
        }
        certificate = {
          Type       = "AWS::IoT::Certificate"
          Properties = { CertificateId = { Ref = "AWS::IoT::Certificate::Id" }, Status = "Active" }
        }
        policy = {
          Type       = "AWS::IoT::Policy"
          Properties = { PolicyName = "${local.name_prefix}-device" }
        }
      }
    }
  }

  # The pki CA, when it is on, is registered in SNI_ONLY mode (design K18).
  pki_ca         = jsondecode(module.in.strings["ca"])
  ca_certificate = local.pki_ca.enabled ? { pem = local.pki_ca.certificate_pem, mode = "SNI_ONLY" } : null
}

module "fleet" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iot-fleet/aws"
  version = "~> 0.1.0"

  thing_types           = local.thing_types
  thing_groups          = local.thing_groups
  policies              = local.policies
  role_alias            = local.role_alias
  provisioning_template = local.provisioning_template
  ca_certificate        = local.ca_certificate
}
