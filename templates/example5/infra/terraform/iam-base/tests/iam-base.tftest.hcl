mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_sagemaker_id"]
  values = { insecure_value = "sg-0aaaaaaa00000003" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/rule_errors_queue_arn"]
  values = { insecure_value = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/greengrass_artifacts_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-greengrass-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ota_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ota-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ml-artifacts-111111111111" }
}

run "reads_only_foundation_network_and_storage_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                     = "foundation/kms_key_arn"
      alarm_topic_arn                 = "foundation/alarm_topic_arn"
      sg_sagemaker_id                 = "network/sg_sagemaker_id"
      stream_arn                      = "storage/stream_arn"
      rule_errors_queue_arn           = "storage/rule_errors_queue_arn"
      greengrass_artifacts_bucket_arn = "storage/greengrass_artifacts_bucket_arn"
      ota_bucket_arn                  = "storage/ota_bucket_arn"
      ml_bucket_arn                   = "storage/ml_bucket_arn"
      } && local.ssm_input_lists == {
      subnet_ids_app  = "network/subnet_ids_app"
      subnet_ids_data = "network/subnet_ids_data"
    }
    error_message = "iam-base must read exactly the keys of earlier stacks that its policies need (design section 8)"
  }
}

run "eleven_roles_named_after_the_prefix" {
  command = plan

  assert {
    condition = toset(keys(local.roles)) == toset([
      "iot_rule", "iot_provisioning", "iot_logging", "iot_audit", "iot_mitigation", "greengrass_tes", "ota_presign",
      "firehose", "sagemaker_pipeline", "sagemaker_endpoint", "scheduler",
    ])
    error_message = "iam-base must create exactly the eleven roles of design section 8"
  }

  assert {
    condition     = alltrue([for k, r in local.roles : r.name == "example-dev-${replace(k, "_", "-")}"])
    error_message = "Role names must be <name_prefix>-<role with hyphens>"
  }
}

run "role_module_receives_name_trust_and_policies" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "trust", "inline_policies"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*each\\.value\\.${f == "inline_policies" ? "policies" : f}\\s*$", file("${path.module}/roles.tf"))) == 1
    ])
    error_message = "The role module call must take name, trust and inline_policies from the role spec"
  }
}

run "every_role_trusts_one_service_in_this_account" {
  command = plan

  assert {
    condition     = alltrue([for k, r in local.roles : r.trust.source_account == "111111111111" && length(r.trust.service_principals) == 1])
    error_message = "Every trust policy must name one service and carry source_account (the confused deputy guard)"
  }

  assert {
    condition = { for k, r in local.roles : k => one(r.trust.service_principals) } == {
      iot_rule           = "iot.amazonaws.com"
      iot_provisioning   = "iot.amazonaws.com"
      iot_logging        = "iot.amazonaws.com"
      iot_audit          = "iot.amazonaws.com"
      iot_mitigation     = "iot.amazonaws.com"
      greengrass_tes     = "credentials.iot.amazonaws.com"
      ota_presign        = "iot.amazonaws.com"
      firehose           = "firehose.amazonaws.com"
      sagemaker_pipeline = "sagemaker.amazonaws.com"
      sagemaker_endpoint = "sagemaker.amazonaws.com"
      scheduler          = "scheduler.amazonaws.com"
    }
    error_message = "Each role must trust the service that uses it"
  }
}

run "firehose_has_trust_only_and_no_inline_policy" {
  command = plan

  assert {
    condition     = length(local.roles["firehose"].policies) == 0 && local.roles["firehose"].trust.source_arn == null
    error_message = "The firehose role has trust only in iam-base; iam-app attaches its policy (design section 8)"
  }

  assert {
    condition     = alltrue([for k, r in local.roles : length(r.policies) == 1 if k != "firehose"])
    error_message = "Every other role has exactly one inline policy"
  }
}

# ---- naming rules: resources of later stacks, pinned as exact strings (the later stacks pin the same ones) ----

run "naming_rules_for_later_stacks" {
  command = plan

  assert {
    condition = local.thing_group_arns == {
      fleet      = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-fleet"
      unverified = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-unverified"
      core       = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-core"
      quarantine = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-quarantine"
    }
    error_message = "Thing groups of the fleet stack must be <name_prefix>-fleet, -unverified, -core and -quarantine"
  }

  assert {
    condition = (
      local.thing_arn_pattern == "arn:aws:iot:ap-northeast-1:111111111111:thing/example-dev-*" &&
      local.thing_type_arn_pattern == "arn:aws:iot:ap-northeast-1:111111111111:thingtype/example-dev-*" &&
      local.iot_policy_arn_pattern == "arn:aws:iot:ap-northeast-1:111111111111:policy/example-dev-*" &&
      local.iot_rule_arn_pattern == "arn:aws:iot:ap-northeast-1:111111111111:rule/example_dev_*"
    )
    error_message = "Things, thing types and IoT policies are named <name_prefix>-*, IoT rules <name_prefix with underscores>_*"
  }

  assert {
    condition = (
      local.model_package_group_arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/example-dev-models" &&
      local.model_package_arn_pattern == "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/*" &&
      local.pipeline_arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/example-dev-training"
    )
    error_message = "The ml stack's model package group is <name_prefix>-models and its pipeline <name_prefix>-training"
  }

  assert {
    condition     = local.kvs_stream_arn_pattern == "arn:aws:kinesisvideo:ap-northeast-1:111111111111:stream/example-dev-cam-*/*"
    error_message = "KVS streams of the edge stack are named <name_prefix>-cam-<camera id>"
  }
}

run "naming_rules_for_sit" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition = (
      local.pipeline_arn == "arn:aws:sagemaker:ap-northeast-1:222222222222:pipeline/example-sit-training" &&
      local.thing_group_arns["unverified"] == "arn:aws:iot:ap-northeast-1:222222222222:thinggroup/example-sit-unverified" &&
      local.iot_rule_arn_pattern == "arn:aws:iot:ap-northeast-1:222222222222:rule/example_sit_*"
    )
    error_message = "The naming rules must follow the env and account"
  }
}

# ---- global policy rules ----

# Resource "*" is only allowed for actions that cannot be scoped; each one is listed here with the reason.
#   ec2:Describe*: Describe actions do not support resource-level permissions.
#   ecr:GetAuthorizationToken: the token is account-wide and has no resource type.
#   iot audit reads: the audit inspects every certificate, policy and role alias of the account; the List actions have
#   no resource type and the Describe/Get actions must reach all of them.
run "no_policy_uses_a_bare_wildcard_resource_except_the_allow_list" {
  command = plan


  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement :
          !contains(s.Resource, "*") || (length(s.Resource) == 1 && alltrue([for a in s.Action : contains(["ec2:DescribeNetworkInterfaces", "ec2:DescribeVpcs", "ec2:DescribeDhcpOptions", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ecr:GetAuthorizationToken", "iot:GetLoggingOptions", "iot:GetV2LoggingOptions", "iot:ListCACertificates", "iot:ListCertificates", "iot:DescribeCACertificate", "iot:DescribeCertificate", "iot:ListPolicies", "iot:GetPolicy", "iot:GetEffectivePolicies", "iot:ListRoleAliases", "iot:DescribeRoleAlias"], a)]))
        ]
      ]
    ]))
    error_message = "Only the allow-listed actions may use Resource *, alone in their statement"
  }


  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : [
            for res in s.Resource : res == "*" || (!startswith(res, "*") && res != "arn:aws:s3:::*" && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res)))
          ]
        ]
      ]
    ]))
    error_message = "No Resource may start with a wildcard or be an account-wide wildcard such as arn:aws:s3:::*"
  }

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
        ]
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "only_audit_and_sagemaker_roles_use_the_wildcard_resource" {
  command = plan

  assert {
    condition = toset([
      for k, r in local.roles : k if anytrue(flatten([for p in values(r.policies) : [for s in jsondecode(p).Statement : contains(s.Resource, "*")]]))
    ]) == toset(["iot_audit", "sagemaker_pipeline", "sagemaker_endpoint"])
    error_message = "Only iot_audit, sagemaker_pipeline and sagemaker_endpoint may have a Resource * statement"
  }
}

run "policies_never_name_a_foreign_bucket_or_key" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : [
            for res in s.Resource : !startswith(res, "arn:aws:s3:::") || anytrue([
              for b in ["example-dev-greengrass-artifacts-111111111111", "example-dev-ota-artifacts-111111111111", "example-dev-ml-artifacts-111111111111"] : res == "arn:aws:s3:::${b}" || startswith(res, "arn:aws:s3:::${b}/")
            ])
          ]
        ]
      ]
    ]))
    error_message = "S3 resources must be one of the three artifact buckets published by storage"
  }

  assert {
    condition = alltrue(flatten([
      for k, r in local.roles : [
        for p in values(r.policies) : [
          for s in jsondecode(p).Statement : [
            for res in s.Resource : !startswith(res, "arn:aws:kms:") || res == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
          ]
        ]
      ]
    ]))
    error_message = "KMS resources must be the shared key of foundation"
  }
}

# ---- per role ----

run "iot_rule_puts_to_the_single_stream_and_error_queue" {
  command = plan

  assert {
    condition     = local.roles["iot_rule"].trust.source_arn == "arn:aws:iot:ap-northeast-1:111111111111:rule/example_dev_*"
    error_message = "The IoT rule trust must be limited to the project's rules (ArnLike on the naming rule)"
  }

  assert {
    condition = jsondecode(one(values(local.roles["iot_rule"].policies))).Statement == [
      { Sid = "PutTelemetry", Effect = "Allow", Action = ["kinesis:PutRecord", "kinesis:PutRecords"], Resource = ["arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry"] },
      { Sid = "SendRuleErrors", Effect = "Allow", Action = ["sqs:SendMessage"], Resource = ["arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors"] },
      { Sid = "UseSharedKey", Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"] },
    ]
    error_message = "iot_rule may only put to the telemetry stream, send to rule-errors and use the shared key"
  }
}

run "iot_provisioning_only_touches_project_things_and_the_unverified_group" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(one(values(local.roles["iot_provisioning"].policies))).Statement : alltrue([
        for res in s.Resource : contains([
          "arn:aws:iot:ap-northeast-1:111111111111:thing/example-dev-*",
          "arn:aws:iot:ap-northeast-1:111111111111:thingtype/example-dev-*",
          "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-unverified",
          "arn:aws:iot:ap-northeast-1:111111111111:policy/example-dev-*",
          "arn:aws:iot:ap-northeast-1:111111111111:cert/*",
        ], res)
      ])
    ])
    error_message = "Provisioning may only touch project things, thing types and IoT policies, certificates, and the unverified group (design section 4.1)"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["iot_provisioning"].policies))).Statement :
      contains(s.Action, "iot:AddThingToThingGroup") && s.Resource == ["arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-unverified", "arn:aws:iot:ap-northeast-1:111111111111:thing/example-dev-*"]
    ])
    error_message = "New things may only be added to the unverified group"
  }
}

run "iot_logging_writes_only_the_iot_log_group" {
  command = plan

  assert {
    condition = jsondecode(one(values(local.roles["iot_logging"].policies))).Statement == [{
      Sid      = "WriteIotLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:PutMetricFilter", "logs:PutRetentionPolicy"]
      Resource = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:AWSIotLogsV2", "arn:aws:logs:ap-northeast-1:111111111111:log-group:AWSIotLogsV2:log-stream:*"]
    }]
    error_message = "iot_logging may only write the AWSIotLogsV2 log group"
  }
}

run "iot_audit_reads_and_notifies_the_alarm_topic" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["iot_audit"].policies))).Statement :
      s.Action == ["sns:Publish"] && s.Resource == ["arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"]
    ])
    error_message = "iot_audit may publish only to the alarm topic of foundation"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(one(values(local.roles["iot_audit"].policies))).Statement :
      alltrue([for a in s.Action : startswith(a, "iot:Get") || startswith(a, "iot:List") || startswith(a, "iot:Describe") || startswith(a, "iam:Get") || startswith(a, "iam:List") || a == "sns:Publish" || startswith(a, "kms:")])
    ])
    error_message = "iot_audit may only read, publish its findings and use the key of the topic"
  }
}

run "iot_mitigation_quarantines_project_things" {
  command = plan

  assert {
    condition = jsondecode(one(values(local.roles["iot_mitigation"].policies))).Statement == [
      { Sid = "AddToQuarantine", Effect = "Allow", Action = ["iot:AddThingToThingGroup"], Resource = ["arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-quarantine", "arn:aws:iot:ap-northeast-1:111111111111:thing/example-dev-*"] },
      { Sid = "UpdateCertificates", Effect = "Allow", Action = ["iot:UpdateCertificate", "iot:ListPrincipalThings"], Resource = ["arn:aws:iot:ap-northeast-1:111111111111:cert/*"] },
    ]
    error_message = "iot_mitigation may only add project things to the quarantine group and update certificates"
  }
}

run "greengrass_tes_reads_artifacts_writes_logs_and_kvs" {
  command = plan

  assert {
    condition = jsondecode(one(values(local.roles["greengrass_tes"].policies))).Statement == [
      { Sid = "ReadComponentArtifacts", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["arn:aws:s3:::example-dev-greengrass-artifacts-111111111111/artifacts/*"] },
      { Sid = "WriteGreengrassLogs", Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/greengrass/*", "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/greengrass/*:log-stream:*"] },
      { Sid = "PutCameraVideo", Effect = "Allow", Action = ["kinesisvideo:DescribeStream", "kinesisvideo:GetDataEndpoint", "kinesisvideo:PutMedia"], Resource = ["arn:aws:kinesisvideo:ap-northeast-1:111111111111:stream/example-dev-cam-*/*"] },
      { Sid = "UseSharedKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"] },
    ]
    error_message = "greengrass_tes may only read artifacts/, write Greengrass logs, put video to project cameras and use the shared key (design section 4)"
  }
}

run "ota_presign_reads_only_signed_firmware" {
  command = plan

  assert {
    condition = jsondecode(one(values(local.roles["ota_presign"].policies))).Statement == [
      { Sid = "ReadSignedFirmware", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["arn:aws:s3:::example-dev-ota-artifacts-111111111111/signed/*"] },
      { Sid = "DecryptWithSharedKey", Effect = "Allow", Action = ["kms:Decrypt"], Resource = ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"] },
    ]
    error_message = "ota_presign may only read the signed/ prefix of the OTA bucket"
  }
}

run "sagemaker_pipeline_registers_to_the_single_group_and_passes_only_itself" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["sagemaker_pipeline"].policies))).Statement :
      s.Sid == "RegisterModels" && s.Resource == ["arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/example-dev-models", "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/example-dev-models/*"]
    ])
    error_message = "The pipeline may register models only to the single model package group"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["sagemaker_pipeline"].policies))).Statement :
      s.Action == ["iam:PassRole"] && s.Resource == ["arn:aws:iam::111111111111:role/example-dev-sagemaker-pipeline"] && s.Condition == { StringEquals = { "iam:PassedToService" = "sagemaker.amazonaws.com" } }
    ])
    error_message = "The pipeline may pass only its own role, and only to SageMaker"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["sagemaker_pipeline"].policies))).Statement :
      s.Sid == "ReadWriteMlObjects" && s.Resource == ["arn:aws:s3:::example-dev-ml-artifacts-111111111111/*"]
    ])
    error_message = "The pipeline reads and writes the ml bucket"
  }
}

run "sagemaker_endpoint_reads_models_and_creates_enis_in_the_vpc" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["sagemaker_endpoint"].policies))).Statement :
      s.Sid == "ReadModels" && s.Action == ["s3:GetObject"] && s.Resource == ["arn:aws:s3:::example-dev-ml-artifacts-111111111111/models/*"]
    ])
    error_message = "The endpoint may only read the models/ prefix of the ml bucket"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(one(values(local.roles["sagemaker_endpoint"].policies))).Statement :
      s.Sid == "CreateNetworkInterfaces" && s.Action == ["ec2:CreateNetworkInterface"] && toset(s.Resource) == toset([
        "arn:aws:ec2:ap-northeast-1:111111111111:network-interface/*",
        "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app1", "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0app2",
        "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat1", "arn:aws:ec2:ap-northeast-1:111111111111:subnet/subnet-0dat2",
        "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0aaaaaaa00000003",
      ])
    ])
    error_message = "Endpoint network interfaces may only be created in the VPC subnets with the SageMaker security group"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(one(values(local.roles["sagemaker_endpoint"].policies))).Statement :
      !contains(s.Action, "sagemaker:CreateModelPackage") && !contains(s.Action, "iam:PassRole")
    ])
    error_message = "The endpoint role must not register models or pass roles"
  }
}

run "scheduler_starts_only_the_training_pipeline" {
  command = plan

  assert {
    condition = jsondecode(one(values(local.roles["scheduler"].policies))).Statement == [
      { Sid = "StartTrainingPipeline", Effect = "Allow", Action = ["sagemaker:StartPipelineExecution"], Resource = ["arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/example-dev-training"] },
      { Sid = "DecryptScheduleData", Effect = "Allow", Action = ["kms:Decrypt"], Resource = ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"] },
    ]
    error_message = "The scheduler may only start the single training pipeline and decrypt the schedule data encrypted with the shared key"
  }
}

run "publishes_exactly_the_iam_base_keys" {
  command = plan

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "role_iot_rule_arn", "role_iot_provisioning_arn", "role_iot_logging_arn", "role_iot_audit_arn", "role_iot_mitigation_arn",
      "role_greengrass_tes_arn", "role_ota_presign_arn", "role_firehose_arn", "role_firehose_name",
      "role_sagemaker_pipeline_arn", "role_sagemaker_endpoint_arn", "role_scheduler_arn",
    ])
    error_message = "iam-base must publish exactly the twelve String keys of design section 7.2"
  }

  assert {
    condition = alltrue([
      for k in keys(local.roles) : length(regexall("(?m)^\\s*role_${k}_arn\\s*=\\s*module\\.role\\[\"${k}\"\\]\\.arn\\s*$", file("${path.module}/ssm-outputs.tf"))) == 1
    ]) && length(regexall("(?m)^\\s*role_firehose_name\\s*=\\s*module\\.role\\[\"firehose\"\\]\\.name\\s*$", file("${path.module}/ssm-outputs.tf"))) == 1
    error_message = "Each role_<key>_arn must come from the matching role, and role_firehose_name from the firehose role"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition     = module.ssm_publish.names == { for k in keys(local.published_strings) : k => "/example/dev/iam-base/${k}" }
    error_message = "ssm-publish must write the contract keys under the iam-base stack path"
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
