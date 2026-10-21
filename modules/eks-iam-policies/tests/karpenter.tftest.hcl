mock_provider "aws" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"
  karpenter = {
    node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
    interruption_queue_name = "alpha-dev-karpenter"
  }
}

run "null_karpenter_gives_null_output" {
  command = plan

  variables {
    karpenter = null
  }

  assert {
    condition     = output.karpenter_controller_policy_json == null
    error_message = "karpenter = null must give a null policy output"
  }
}

run "valid_json_with_all_official_statements" {
  command = plan

  assert {
    condition     = jsondecode(output.karpenter_controller_policy_json).Version == "2012-10-17"
    error_message = "Policy Version must be 2012-10-17"
  }

  # v1.15.0 CloudFormation: NodeLifecycle 6, IAMIntegration 4, EKSIntegration 1, Interruption 1, ZonalShift 1, ResourceDiscovery 5.
  assert {
    condition     = length(jsondecode(output.karpenter_controller_policy_json).Statement) == 18
    error_message = "All 18 statements of the official v1.15.0 controller policies must be present"
  }
}

run "sids_match_official_template" {
  command = plan

  assert {
    condition = toset([for s in jsondecode(output.karpenter_controller_policy_json).Statement : s.Sid]) == toset([
      "AllowScopedEC2InstanceAccessActions",
      "AllowScopedEC2LaunchTemplateAccessActions",
      "AllowScopedEC2InstanceActionsWithTags",
      "AllowScopedResourceCreationTagging",
      "AllowScopedResourceTagging",
      "AllowScopedDeletion",
      "AllowPassingInstanceRole",
      "AllowScopedInstanceProfileCreationActions",
      "AllowScopedInstanceProfileTagActions",
      "AllowScopedInstanceProfileActions",
      "AllowAPIServerEndpointDiscovery",
      "AllowInterruptionQueueActions",
      "AllowZonalShiftStatusReadOnly",
      "AllowRegionalReadActions",
      "AllowSSMReadActions",
      "AllowPricingReadActions",
      "AllowUnscopedInstanceProfileListAction",
      "AllowInstanceProfileReadActions",
    ])
    error_message = "Statement Sids must match the official CloudFormation template"
  }
}

run "sids_are_unique" {
  command = plan

  assert {
    condition     = length(toset([for s in jsondecode(output.karpenter_controller_policy_json).Statement : s.Sid])) == length(jsondecode(output.karpenter_controller_policy_json).Statement)
    error_message = "Sids must be unique"
  }
}

run "pass_role_only_node_role" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement : s
      if contains(flatten([s.Action]), "iam:PassRole")
    ]) == 1
    error_message = "Exactly one statement may grant iam:PassRole"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement :
      s.Resource == "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      if contains(flatten([s.Action]), "iam:PassRole")
    ])
    error_message = "iam:PassRole must be limited to node_role_arn"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement :
      s.Condition.StringEquals["iam:PassedToService"] == ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
      if contains(flatten([s.Action]), "iam:PassRole")
    ])
    error_message = "iam:PassRole must keep the official iam:PassedToService condition"
  }
}

run "sqs_actions_only_queue_arn" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement : s
      if anytrue([for a in flatten([s.Action]) : startswith(a, "sqs:")])
    ]) == 1
    error_message = "Exactly one statement may grant sqs actions"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement :
      s.Resource == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-karpenter" && toset(s.Action) == toset(["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"])
      if anytrue([for a in flatten([s.Action]) : startswith(a, "sqs:")])
    ])
    error_message = "sqs actions must be limited to the interruption queue ARN and the three official actions"
  }
}

run "eks_describe_cluster_limited_to_cluster" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement :
      s.Resource == "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
      if contains(flatten([s.Action]), "eks:DescribeCluster")
    ])
    error_message = "eks:DescribeCluster must be limited to this cluster"
  }
}

run "cluster_tag_conditions_use_cluster_name" {
  command = plan

  assert {
    condition     = jsondecode(output.karpenter_controller_policy_json).Statement[1].Condition.StringEquals["aws:ResourceTag/kubernetes.io/cluster/alpha-dev"] == "owned"
    error_message = "Scoped statements must key on the cluster name tag"
  }

  assert {
    condition     = jsondecode(output.karpenter_controller_policy_json).Statement[2].Condition.StringEquals["aws:RequestTag/eks:eks-cluster-name"] == "alpha-dev"
    error_message = "Request tag conditions must carry the cluster name"
  }
}

run "region_and_account_substituted" {
  command = plan

  assert {
    condition     = !strcontains(output.karpenter_controller_policy_json, "$${") && !strcontains(output.karpenter_controller_policy_json, "AWS::")
    error_message = "No CloudFormation placeholder may remain"
  }

  assert {
    condition     = jsondecode(output.karpenter_controller_policy_json).Statement[13].Condition.StringEquals["aws:RequestedRegion"] == "ap-northeast-1"
    error_message = "aws:RequestedRegion must be the region input"
  }
}

run "partition_substituted" {
  command = plan

  variables {
    partition = "aws-cn"
    karpenter = {
      node_role_arn           = "arn:aws-cn:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  assert {
    condition     = !strcontains(output.karpenter_controller_policy_json, "arn:aws:") && strcontains(output.karpenter_controller_policy_json, "arn:aws-cn:ec2:")
    error_message = "ARNs built by the module must use the partition input"
  }
}

run "no_wildcard_allow_actions" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(output.karpenter_controller_policy_json).Statement : [
        for a in flatten([s.Action]) : a != "*" && !endswith(a, ":*")
      ] if s.Effect == "Allow"
    ]))
    error_message = "No Allow statement may use * or service:* actions"
  }
}

run "version_explicit_supported_accepted" {
  command = plan

  variables {
    karpenter = {
      version                 = "1.15.0"
      node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  assert {
    condition     = length(jsondecode(output.karpenter_controller_policy_json).Statement) == 18
    error_message = "version 1.15.0 must be accepted"
  }
}

run "unsupported_version_rejected" {
  command = plan

  variables {
    karpenter = {
      version                 = "1.14.0"
      node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  expect_failures = [var.karpenter]
}

run "node_role_arn_must_be_role_arn" {
  command = plan

  variables {
    karpenter = {
      node_role_arn           = "arn:aws:iam::111111111111:user/alpha-dev"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  expect_failures = [var.karpenter]
}

run "node_role_arn_wildcard_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn           = "arn:aws:iam::111111111111:role/*"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  expect_failures = [var.karpenter]
}

run "queue_name_with_wildcard_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = "alpha-*"
    }
  }

  expect_failures = [var.karpenter]
}

run "queue_name_too_long_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = join("", [for i in range(81) : "a"])
    }
  }

  expect_failures = [var.karpenter]
}
