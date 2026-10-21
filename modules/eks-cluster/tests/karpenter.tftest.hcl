# Karpenter AWS resources: interruption queue, EventBridge rules (Karpenter v1.15.0 CloudFormation), node role access entry, controller Pod Identity.

mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
      endpoint              = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      certificate_authority = [{ data = "Y2VydGlmaWNhdGU=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABCDEF0123456789" }] }]
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

variables {
  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  cluster_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"

  managed_node_groups = {
    system = {
      node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      instance_types = ["m7i.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  addons = {
    vpc-cni                = { version = "v1.20.0-eksbuild.1" }
    kube-proxy             = { version = "v1.34.0-eksbuild.1" }
    coredns                = { version = "v1.12.0-eksbuild.1" }
    eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
  }

  karpenter = {
    node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
    controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
  }

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
  }
}

run "interruption_queue_settings" {
  command = plan

  assert {
    condition     = length(aws_sqs_queue.karpenter) == 1 && aws_sqs_queue.karpenter[0].name == "alpha-dev"
    error_message = "The queue is named after the cluster, as in the Karpenter CloudFormation"
  }

  assert {
    condition     = aws_sqs_queue.karpenter[0].message_retention_seconds == 300
    error_message = "message_retention_seconds must be 300"
  }

  assert {
    condition     = aws_sqs_queue.karpenter[0].sqs_managed_sse_enabled == true
    error_message = "SQS managed SSE must be on"
  }

  assert {
    condition     = aws_sqs_queue.karpenter[0].tags["Name"] == "alpha-dev"
    error_message = "The queue must carry the Name tag"
  }
}

run "queue_policy_allows_senders_and_denies_plain_http" {
  command = apply

  override_resource {
    target = aws_cloudwatch_event_rule.karpenter["health"]
    values = { arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-karpenter-health" }
  }
  override_resource {
    target = aws_cloudwatch_event_rule.karpenter["spot"]
    values = { arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-karpenter-spot" }
  }
  override_resource {
    target = aws_cloudwatch_event_rule.karpenter["rebalance"]
    values = { arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-karpenter-rebalance" }
  }
  override_resource {
    target = aws_cloudwatch_event_rule.karpenter["state"]
    values = { arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-karpenter-state" }
  }
  override_resource {
    target = aws_cloudwatch_event_rule.karpenter["capacity"]
    values = { arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-karpenter-capacity" }
  }
  override_resource {
    target = aws_sqs_queue.karpenter[0]
    values = {
      arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev"
      url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev"
    }
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_sqs_queue_policy.karpenter[0].policy).Statement :
      try(s.Effect == "Allow" && s.Action == "sqs:SendMessage" && s.Principal.Service == "events.amazonaws.com" &&
      s.Resource == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev", false)
    ])
    error_message = "events.amazonaws.com must be allowed to send messages"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_sqs_queue_policy.karpenter[0].policy).Statement :
      try(s.Effect == "Allow" && s.Action == "sqs:SendMessage" && s.Principal.Service == "sqs.amazonaws.com", false)
    ])
    error_message = "sqs.amazonaws.com must be allowed to send messages"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_sqs_queue_policy.karpenter[0].policy).Statement :
      try(s.Effect == "Deny" && s.Action == "sqs:*" && s.Principal == "*" && s.Condition.Bool["aws:SecureTransport"] == "false", false)
    ])
    error_message = "Non-TLS requests must be denied"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_sqs_queue_policy.karpenter[0].policy).Statement :
      try(length(s.Condition.ArnEquals["aws:SourceArn"]) == 5, false)
    ])
    error_message = "The events principal must be limited to the five Karpenter rules"
  }
}

run "five_eventbridge_rules" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.karpenter) == 5
    error_message = "Exactly five rules"
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_event_rule.karpenter)) == toset(["health", "spot", "rebalance", "state", "capacity"])
    error_message = "Rule keys"
  }
}

run "event_patterns_match_the_karpenter_cloudformation" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.karpenter["health"].event_pattern) == {
      source        = ["aws.health"]
      "detail-type" = ["AWS Health Event"]
    }
    error_message = "ScheduledChangeRule pattern"
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.karpenter["spot"].event_pattern) == {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Spot Instance Interruption Warning"]
    }
    error_message = "SpotInterruptionRule pattern"
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.karpenter["rebalance"].event_pattern) == {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Instance Rebalance Recommendation"]
    }
    error_message = "RebalanceRule pattern"
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.karpenter["state"].event_pattern) == {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Instance State-change Notification"]
    }
    error_message = "InstanceStateChangeRule pattern"
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.karpenter["capacity"].event_pattern) == {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Capacity Reservation Instance Interruption Warning"]
    }
    error_message = "CapacityReservationInterruptionRule pattern"
  }
}

run "rule_names_are_prefixed_and_short_enough" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_cloudwatch_event_rule.karpenter : startswith(r.name, "alpha-dev-karpenter-") && length(r.name) <= 64])
    error_message = "Rule names are <cluster>-karpenter-<key> and fit the 64 character limit"
  }
}

run "every_rule_targets_the_queue" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_target.karpenter) == 5
    error_message = "One target per rule"
  }

  assert {
    condition     = alltrue([for t in aws_cloudwatch_event_target.karpenter : t.target_id == "KarpenterInterruptionQueueTarget"])
    error_message = "Target id as in the CloudFormation"
  }
}

run "node_role_access_entry_is_ec2_linux" {
  command = plan

  assert {
    condition = (
      aws_eks_access_entry.karpenter_node[0].type == "EC2_LINUX" &&
      aws_eks_access_entry.karpenter_node[0].principal_arn == "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node" &&
      aws_eks_access_entry.karpenter_node[0].cluster_name == "alpha-dev"
    )
    error_message = "The Karpenter node role needs an EC2_LINUX access entry"
  }
}

run "controller_pod_identity_association" {
  command = plan

  assert {
    condition = (
      aws_eks_pod_identity_association.karpenter[0].cluster_name == "alpha-dev" &&
      aws_eks_pod_identity_association.karpenter[0].namespace == "kube-system" &&
      aws_eks_pod_identity_association.karpenter[0].service_account == "karpenter" &&
      aws_eks_pod_identity_association.karpenter[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    )
    error_message = "Controller association defaults to kube-system/karpenter"
  }
}

run "controller_namespace_and_service_account_overrides" {
  command = plan

  variables {
    karpenter = {
      node_role_arn              = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
      controller_namespace       = "karpenter"
      controller_service_account = "karpenter-controller"
    }
  }

  assert {
    condition = (
      aws_eks_pod_identity_association.karpenter[0].namespace == "karpenter" &&
      aws_eks_pod_identity_association.karpenter[0].service_account == "karpenter-controller"
    )
    error_message = "Namespace and service account must follow the input"
  }
}

run "queue_name_output" {
  command = apply

  assert {
    condition     = output.karpenter_interruption_queue_name == "alpha-dev"
    error_message = "karpenter_interruption_queue_name must be the queue name"
  }
}

run "nothing_without_karpenter" {
  command = plan

  variables {
    karpenter = null
  }

  assert {
    condition = (
      length(aws_sqs_queue.karpenter) == 0 &&
      length(aws_sqs_queue_policy.karpenter) == 0 &&
      length(aws_cloudwatch_event_rule.karpenter) == 0 &&
      length(aws_cloudwatch_event_target.karpenter) == 0 &&
      length(aws_eks_access_entry.karpenter_node) == 0 &&
      length(aws_eks_pod_identity_association.karpenter) == 0
    )
    error_message = "No Karpenter resource when karpenter is null"
  }

  assert {
    condition     = output.karpenter_interruption_queue_name == null
    error_message = "The queue name output must be null"
  }
}

run "node_role_equal_to_managed_node_group_role_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    }
  }

  expect_failures = [var.karpenter]
}

run "bad_node_role_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn       = "alpha-dev-karpenter-node"
      controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    }
  }

  expect_failures = [var.karpenter]
}

run "bad_controller_role_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn = "alpha-dev-karpenter-controller"
    }
  }

  expect_failures = [var.karpenter]
}

run "bad_controller_namespace_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
      controller_namespace = "Kube System"
    }
  }

  expect_failures = [var.karpenter]
}

run "bad_controller_service_account_rejected" {
  command = plan

  variables {
    karpenter = {
      node_role_arn              = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
      controller_service_account = "Karpenter"
    }
  }

  expect_failures = [var.karpenter]
}
