# Permissions of the roles that later stacks need the moment they create their resources. Every Resource is built from
# keys that foundation, network and storage publish, or from the naming rules in naming.tf. The action lists follow
# the AWS service documentation and are not yet verified against a real account (design section 11).
locals {
  kms_key_arn                     = module.in.strings["kms_key_arn"]
  greengrass_artifacts_bucket_arn = module.in.strings["greengrass_artifacts_bucket_arn"]
  ota_bucket_arn                  = module.in.strings["ota_bucket_arn"]
  ml_bucket_arn                   = module.in.strings["ml_bucket_arn"]

  # Actions that have no resource type, or (the IoT audit reads) must reach every certificate, policy and role alias
  # of the account. With ecr:GetAuthorizationToken they are the only ones allowed with Resource "*"; the tests pin them.
  ec2_describe_actions = ["ec2:DescribeNetworkInterfaces", "ec2:DescribeVpcs", "ec2:DescribeDhcpOptions", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"]
  iot_audit_read_actions = [
    "iot:GetLoggingOptions", "iot:GetV2LoggingOptions", "iot:ListCACertificates", "iot:ListCertificates", "iot:DescribeCACertificate",
    "iot:DescribeCertificate", "iot:ListPolicies", "iot:GetPolicy", "iot:GetEffectivePolicies", "iot:ListRoleAliases", "iot:DescribeRoleAlias",
  ]

  iot_rule_statements = [
    { Sid = "PutTelemetry", Effect = "Allow", Action = ["kinesis:PutRecord", "kinesis:PutRecords"], Resource = [module.in.strings["stream_arn"]] },
    { Sid = "SendRuleErrors", Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [module.in.strings["rule_errors_queue_arn"]] },
    # The stream and the queue are SSE-KMS with the shared key.
    { Sid = "UseSharedKey", Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = [local.kms_key_arn] },
  ]

  # Fleet provisioning by claim (design section 4.1): new things go to the unverified group only.
  iot_provisioning_statements = [
    {
      Sid      = "ManageThings"
      Effect   = "Allow"
      Action   = ["iot:CreateThing", "iot:DescribeThing", "iot:UpdateThing", "iot:AttachThingPrincipal", "iot:ListThingPrincipals", "iot:ListThingGroupsForThing"]
      Resource = [local.thing_arn_pattern]
    },
    { Sid = "DescribeThingTypes", Effect = "Allow", Action = ["iot:DescribeThingType"], Resource = [local.thing_type_arn_pattern] },
    {
      Sid      = "AddToUnverifiedGroup"
      Effect   = "Allow"
      Action   = ["iot:AddThingToThingGroup", "iot:DescribeThingGroup"]
      Resource = [local.thing_group_arns["unverified"], local.thing_arn_pattern]
    },
    { Sid = "AttachDevicePolicy", Effect = "Allow", Action = ["iot:AttachPolicy", "iot:GetPolicy"], Resource = [local.iot_policy_arn_pattern, local.iot_cert_arn_pattern] },
    { Sid = "ManageCertificates", Effect = "Allow", Action = ["iot:DescribeCertificate", "iot:UpdateCertificate"], Resource = [local.iot_cert_arn_pattern] },
  ]

  # AWS IoT v2 logging writes to this fixed log group name.
  iot_logging_statements = [{
    Sid      = "WriteIotLogs"
    Effect   = "Allow"
    Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:PutMetricFilter", "logs:PutRetentionPolicy"]
    Resource = ["${local.arn_prefix.logs}:log-group:AWSIotLogsV2", "${local.arn_prefix.logs}:log-group:AWSIotLogsV2:log-stream:*"]
  }]

  # Read side of the AWSIoTDeviceDefenderAudit managed policy, without Cognito (example5 has no identity pool).
  iot_audit_statements = [
    { Sid = "ReadIotConfiguration", Effect = "Allow", Action = local.iot_audit_read_actions, Resource = ["*"] },
    {
      Sid      = "ReadRolesOfRoleAliases"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetPolicy", "iam:GetPolicyVersion"]
      Resource = ["${local.arn_prefix.iam}:role/*", "${local.arn_prefix.iam}:policy/*"]
    },
    { Sid = "PublishFindings", Effect = "Allow", Action = ["sns:Publish"], Resource = [module.in.strings["alarm_topic_arn"]] },
    # The alarm topic is encrypted with the shared key.
    { Sid = "UseTopicKey", Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = [local.kms_key_arn] },
  ]

  iot_mitigation_statements = [
    { Sid = "AddToQuarantine", Effect = "Allow", Action = ["iot:AddThingToThingGroup"], Resource = [local.thing_group_arns["quarantine"], local.thing_arn_pattern] },
    { Sid = "UpdateCertificates", Effect = "Allow", Action = ["iot:UpdateCertificate", "iot:ListPrincipalThings"], Resource = [local.iot_cert_arn_pattern] },
  ]

  greengrass_log_group = "${local.arn_prefix.logs}:log-group:/aws/greengrass/*"
  greengrass_tes_statements = [
    { Sid = "ReadComponentArtifacts", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${local.greengrass_artifacts_bucket_arn}/artifacts/*"] },
    {
      Sid      = "WriteGreengrassLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = [local.greengrass_log_group, "${local.greengrass_log_group}:log-stream:*"]
    },
    {
      Sid      = "PutCameraVideo"
      Effect   = "Allow"
      Action   = ["kinesisvideo:DescribeStream", "kinesisvideo:GetDataEndpoint", "kinesisvideo:PutMedia"]
      Resource = [local.kvs_stream_arn_pattern]
    },
    # Artifacts are SSE-KMS and the KVS streams use the shared key.
    { Sid = "UseSharedKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = [local.kms_key_arn] },
  ]

  ota_presign_statements = [
    { Sid = "ReadSignedFirmware", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${local.ota_bucket_arn}/signed/*"] },
    { Sid = "DecryptWithSharedKey", Effect = "Allow", Action = ["kms:Decrypt"], Resource = [local.kms_key_arn] },
  ]

  # Shared by both SageMaker roles.
  sagemaker_log_group = "${local.arn_prefix.logs}:log-group:/aws/sagemaker/*"
  sagemaker_common_statements = [
    {
      # Images in this account's repositories named after the project.
      Sid      = "PullImages"
      Effect   = "Allow"
      Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
      Resource = ["${local.arn_prefix.ecr}:repository/${local.name_prefix}-*"]
    },
    { Sid = "GetEcrToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
    { Sid = "UseSharedKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"], Resource = [local.kms_key_arn] },
    {
      # Training, processing and endpoint volumes are encrypted through grants that SageMaker creates.
      Sid       = "GrantKeyToSageMaker"
      Effect    = "Allow"
      Action    = ["kms:CreateGrant"]
      Resource  = [local.kms_key_arn]
      Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
    },
    {
      Sid      = "WriteSageMakerLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = [local.sagemaker_log_group, "${local.sagemaker_log_group}:log-stream:*"]
    },
  ]

  sagemaker_pipeline_role_arn = "${local.arn_prefix.iam}:role/${local.name_prefix}-sagemaker-pipeline"
  sagemaker_pipeline_statements = concat([
    { Sid = "ReadWriteMlObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.ml_bucket_arn}/*"] },
    { Sid = "ListMlBucket", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = [local.ml_bucket_arn] },
    {
      # Pipelines generate job names, so jobs are scoped to the account and region.
      Sid    = "RunTrainingAndProcessingJobs"
      Effect = "Allow"
      Action = [
        "sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob",
        "sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:AddTags",
      ]
      Resource = ["${local.arn_prefix.sagemaker}:training-job/*", "${local.arn_prefix.sagemaker}:processing-job/*"]
    },
    {
      Sid      = "RegisterModels"
      Effect   = "Allow"
      Action   = ["sagemaker:CreateModelPackage", "sagemaker:DescribeModelPackage", "sagemaker:DescribeModelPackageGroup"]
      Resource = [local.model_package_group_arn, local.model_package_arn_pattern]
    },
    {
      Sid       = "PassOwnRoleToJobs"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = [local.sagemaker_pipeline_role_arn]
      Condition = { StringEquals = { "iam:PassedToService" = "sagemaker.amazonaws.com" } }
    },
  ], local.sagemaker_common_statements)

  sagemaker_endpoint_statements = concat([
    { Sid = "ReadModels", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${local.ml_bucket_arn}/models/*"] },
    {
      # Instance variants run in the VPC (design K19) with the SageMaker security group of network.
      Sid    = "CreateNetworkInterfaces"
      Effect = "Allow"
      Action = ["ec2:CreateNetworkInterface"]
      Resource = concat(
        ["${local.arn_prefix.ec2}:network-interface/*"],
        [for s in concat(module.in.lists["subnet_ids_app"], module.in.lists["subnet_ids_data"]) : "${local.arn_prefix.ec2}:subnet/${s}"],
        ["${local.arn_prefix.ec2}:security-group/${module.in.strings["sg_sagemaker_id"]}"],
      )
    },
    {
      Sid      = "ManageNetworkInterfaces"
      Effect   = "Allow"
      Action   = ["ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface", "ec2:DeleteNetworkInterfacePermission"]
      Resource = ["${local.arn_prefix.ec2}:network-interface/*"]
    },
    { Sid = "DescribeNetwork", Effect = "Allow", Action = local.ec2_describe_actions, Resource = ["*"] },
  ], local.sagemaker_common_statements)

  scheduler_statements = [
    { Sid = "StartTrainingPipeline", Effect = "Allow", Action = ["sagemaker:StartPipelineExecution"], Resource = [local.pipeline_arn] },
    # The schedules are encrypted with the shared key (scheduler-schedule requires a customer managed key).
    { Sid = "DecryptScheduleData", Effect = "Allow", Action = ["kms:Decrypt"], Resource = [local.kms_key_arn] },
  ]
}
