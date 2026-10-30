mock_provider "aws" {}

variables {
  name = "alpha-dev-eks-cluster"
  trust = {
    service_principals = ["eks.amazonaws.com"]
  }
}

run "default_has_no_attachments" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 0
    error_message = "No managed policy must be attached by default"
  }
}

run "allowlisted_policies_attached" {
  command = plan

  variables {
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2",
    ]
  }

  assert {
    condition = toset(keys(aws_iam_role_policy_attachment.this)) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2",
    ])
    error_message = "Every allowlisted ARN must produce one attachment"
  }

  assert {
    condition     = alltrue([for a in aws_iam_role_policy_attachment.this : a.role == "alpha-dev-eks-cluster"])
    error_message = "Attachments must bind to the created role"
  }
}

run "every_allowlisted_name_accepted" {
  command = plan

  variables {
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
      "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
      "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicyV2",
      "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
      "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 14
    error_message = "All 14 allowlist entries must be accepted"
  }
}

run "cloudwatch_agent_server_policy_accepted" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  }

  assert {
    condition     = aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"].policy_arn == "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    error_message = "CloudWatchAgentServerPolicy is allowlisted for the Container Insights collector (design v4 W2)"
  }
}

run "administrator_access_rejected" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "customer_managed_policy_rejected" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::111111111111:policy/x"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "wrong_path_for_service_role_policy_rejected" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "one_bad_entry_rejects_the_set" {
  command = plan

  variables {
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/PowerUserAccess",
    ]
  }

  expect_failures = [var.managed_policy_arns]
}

run "account_baseline_service_role_policies_accepted" {
  command = plan

  variables {
    trust = {
      service_principals = ["config.amazonaws.com"]
    }
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 3
    error_message = "The Config and Backup service role policies must be allowlisted"
  }
}

run "ecs_load_balancer_infrastructure_policy_accepted" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs.amazonaws.com"]
    }
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"]
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.this)) == toset(["arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"])
    error_message = "The ECS infrastructure policy for load balancers must be allowlisted"
  }
}

run "ecs_load_balancer_policy_wrong_path_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs.amazonaws.com"]
    }
    managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForLoadBalancers"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "other_ecs_managed_policy_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs.amazonaws.com"]
    }
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonECS_FullAccess"]
  }

  expect_failures = [var.managed_policy_arns]
}
