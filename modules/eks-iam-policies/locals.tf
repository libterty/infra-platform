locals {
  # Official AWS Load Balancer Controller policies, vendored unchanged. To add a version, add the file
  # under policies/aws-load-balancer-controller/ and one entry here.
  load_balancer_controller_policies = {
    "3.6.0" = file("${path.module}/policies/aws-load-balancer-controller/v3.6.0.json")
  }

  # Versions for which karpenter_policy_statements below is a translation of the official CloudFormation
  # template kept in policies/karpenter/<version>/. Keep in sync with the version map in karpenter_controller_policy_json.
  karpenter_supported_versions = ["1.15.0"]

  load_balancer_controller_policy_json = jsonencode(jsondecode(local.load_balancer_controller_policies[var.load_balancer_controller_version]))

  # cloudwatch:GetMetricData does not support resource-level permissions: the CloudWatch permissions
  # reference says to give "*" as the resource.
  argo_rollouts_cloudwatch_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:GetMetricData"]
      Resource = "*"
    }]
  })

  # Placeholders of the official CloudFormation template, resolved from the inputs.
  cluster_arn     = "arn:${var.partition}:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}"
  ec2_arn_prefix  = "arn:${var.partition}:ec2:${var.region}"
  iam_arn_prefix  = "arn:${var.partition}:iam::${var.account_id}"
  cluster_tag_key = "kubernetes.io/cluster/${var.cluster_name}"

  # Translation of the six controller managed policies in the Karpenter v1.15.0 CloudFormation template
  # (policies/karpenter/v1.15.0/cloudformation.yaml), in template order:
  # NodeLifecyclePolicy, IAMIntegrationPolicy, EKSIntegrationPolicy, InterruptionPolicy, ZonalShiftPolicy,
  # ResourceDiscoveryPolicy. Evaluated only when var.karpenter is set.
  karpenter_v1_15_0_statements = var.karpenter == null ? null : [
    # NodeLifecyclePolicy
    {
      Sid    = "AllowScopedEC2InstanceAccessActions"
      Effect = "Allow"
      Resource = [
        "arn:${var.partition}:ec2:${var.region}::image/*",
        "arn:${var.partition}:ec2:${var.region}::snapshot/*",
        "${local.ec2_arn_prefix}:*:security-group/*",
        "${local.ec2_arn_prefix}:*:subnet/*",
        "${local.ec2_arn_prefix}:*:capacity-reservation/*",
        "${local.ec2_arn_prefix}:*:placement-group/*",
      ]
      Action = ["ec2:RunInstances", "ec2:CreateFleet"]
    },
    {
      Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
      Effect   = "Allow"
      Resource = "${local.ec2_arn_prefix}:*:launch-template/*"
      Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.cluster_tag_key}" = "owned"
        }
        StringLike = {
          "aws:ResourceTag/karpenter.sh/nodepool" = "*"
        }
      }
    },
    {
      Sid    = "AllowScopedEC2InstanceActionsWithTags"
      Effect = "Allow"
      Resource = [
        "${local.ec2_arn_prefix}:*:fleet/*",
        "${local.ec2_arn_prefix}:*:instance/*",
        "${local.ec2_arn_prefix}:*:volume/*",
        "${local.ec2_arn_prefix}:*:network-interface/*",
        "${local.ec2_arn_prefix}:*:launch-template/*",
        "${local.ec2_arn_prefix}:*:spot-instances-request/*",
      ]
      Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.cluster_tag_key}" = "owned"
          "aws:RequestTag/eks:eks-cluster-name"     = var.cluster_name
        }
        StringLike = {
          "aws:RequestTag/karpenter.sh/nodepool" = "*"
        }
      }
    },
    {
      Sid    = "AllowScopedResourceCreationTagging"
      Effect = "Allow"
      Resource = [
        "${local.ec2_arn_prefix}:*:fleet/*",
        "${local.ec2_arn_prefix}:*:instance/*",
        "${local.ec2_arn_prefix}:*:volume/*",
        "${local.ec2_arn_prefix}:*:network-interface/*",
        "${local.ec2_arn_prefix}:*:launch-template/*",
        "${local.ec2_arn_prefix}:*:spot-instances-request/*",
      ]
      Action = "ec2:CreateTags"
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.cluster_tag_key}" = "owned"
          "aws:RequestTag/eks:eks-cluster-name"     = var.cluster_name
          "ec2:CreateAction"                        = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
        }
        StringLike = {
          "aws:RequestTag/karpenter.sh/nodepool" = "*"
        }
      }
    },
    {
      Sid      = "AllowScopedResourceTagging"
      Effect   = "Allow"
      Resource = "${local.ec2_arn_prefix}:*:instance/*"
      Action   = "ec2:CreateTags"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.cluster_tag_key}" = "owned"
        }
        StringLike = {
          "aws:ResourceTag/karpenter.sh/nodepool" = "*"
        }
        StringEqualsIfExists = {
          "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
        }
        "ForAllValues:StringEquals" = {
          "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
        }
      }
    },
    {
      Sid    = "AllowScopedDeletion"
      Effect = "Allow"
      Resource = [
        "${local.ec2_arn_prefix}:*:instance/*",
        "${local.ec2_arn_prefix}:*:launch-template/*",
      ]
      Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.cluster_tag_key}" = "owned"
        }
        StringLike = {
          "aws:ResourceTag/karpenter.sh/nodepool" = "*"
        }
      }
    },

    # IAMIntegrationPolicy
    {
      Sid      = "AllowPassingInstanceRole"
      Effect   = "Allow"
      Resource = var.karpenter.node_role_arn
      Action   = "iam:PassRole"
      Condition = {
        StringEquals = {
          "iam:PassedToService" = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
        }
      }
    },
    {
      Sid      = "AllowScopedInstanceProfileCreationActions"
      Effect   = "Allow"
      Resource = "${local.iam_arn_prefix}:instance-profile/*"
      Action   = ["iam:CreateInstanceProfile"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.cluster_tag_key}"      = "owned"
          "aws:RequestTag/eks:eks-cluster-name"          = var.cluster_name
          "aws:RequestTag/topology.kubernetes.io/region" = var.region
        }
        StringLike = {
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
        }
      }
    },
    {
      Sid      = "AllowScopedInstanceProfileTagActions"
      Effect   = "Allow"
      Resource = "${local.iam_arn_prefix}:instance-profile/*"
      Action   = ["iam:TagInstanceProfile"]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.cluster_tag_key}"      = "owned"
          "aws:ResourceTag/topology.kubernetes.io/region" = var.region
          "aws:RequestTag/${local.cluster_tag_key}"       = "owned"
          "aws:RequestTag/eks:eks-cluster-name"           = var.cluster_name
          "aws:RequestTag/topology.kubernetes.io/region"  = var.region
        }
        StringLike = {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
        }
      }
    },
    {
      Sid      = "AllowScopedInstanceProfileActions"
      Effect   = "Allow"
      Resource = "${local.iam_arn_prefix}:instance-profile/*"
      Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.cluster_tag_key}"      = "owned"
          "aws:ResourceTag/topology.kubernetes.io/region" = var.region
        }
        StringLike = {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
        }
      }
    },

    # EKSIntegrationPolicy
    {
      Sid      = "AllowAPIServerEndpointDiscovery"
      Effect   = "Allow"
      Resource = local.cluster_arn
      Action   = "eks:DescribeCluster"
    },

    # InterruptionPolicy
    {
      Sid      = "AllowInterruptionQueueActions"
      Effect   = "Allow"
      Resource = "arn:${var.partition}:sqs:${var.region}:${var.account_id}:${var.karpenter.interruption_queue_name}"
      Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    },

    # ZonalShiftPolicy
    {
      Sid      = "AllowZonalShiftStatusReadOnly"
      Effect   = "Allow"
      Resource = "*"
      Action   = ["arc-zonal-shift:GetManagedResource"]
      Condition = {
        StringEquals = {
          "arc-zonal-shift:ResourceIdentifier" = local.cluster_arn
        }
      }
    },

    # ResourceDiscoveryPolicy
    {
      Sid      = "AllowRegionalReadActions"
      Effect   = "Allow"
      Resource = "*"
      Action = [
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribePlacementGroups",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
      ]
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.region
        }
      }
    },
    {
      Sid      = "AllowSSMReadActions"
      Effect   = "Allow"
      Resource = "arn:${var.partition}:ssm:${var.region}::parameter/aws/service/*"
      Action   = "ssm:GetParameter"
    },
    {
      Sid      = "AllowPricingReadActions"
      Effect   = "Allow"
      Resource = "*"
      Action   = "pricing:GetProducts"
    },
    {
      Sid      = "AllowUnscopedInstanceProfileListAction"
      Effect   = "Allow"
      Resource = "*"
      Action   = "iam:ListInstanceProfiles"
    },
    {
      Sid      = "AllowInstanceProfileReadActions"
      Effect   = "Allow"
      Resource = "${local.iam_arn_prefix}:instance-profile/*"
      Action   = "iam:GetInstanceProfile"
    },
  ]

  karpenter_controller_policy_json = var.karpenter == null ? null : jsonencode({
    Version   = "2012-10-17"
    Statement = { "1.15.0" = local.karpenter_v1_15_0_statements }[var.karpenter.version]
  })

  policy_sizes = merge(
    {
      load_balancer_controller = length(replace(local.load_balancer_controller_policy_json, "/\\s/", ""))
      argo_rollouts_cloudwatch = length(replace(local.argo_rollouts_cloudwatch_policy_json, "/\\s/", ""))
    },
    local.karpenter_controller_policy_json == null ? {} : {
      karpenter_controller = length(replace(local.karpenter_controller_policy_json, "/\\s/", ""))
    }
  )
}
