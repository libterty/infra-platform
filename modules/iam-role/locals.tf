locals {
  # Allowlist of AWS managed policies this module may attach (design v3 section 4.1, D8).
  # Sources: EKS cluster/node/Auto Mode/Fargate/add-on IAM docs, the SSM managed instance docs and the
  # CloudWatch Observability (Container Insights) install docs (design v4 W2).
  # The exact ARN paths (plain "policy/" vs "policy/service-role/") and the BlockStorage policy name
  # (AmazonEKSBlockStoragePolicy vs AmazonEKSBlockStoragePolicyV2) must be verified in a real
  # environment before first use (design section 6); both BlockStorage names are listed until then.
  managed_policy_allowlist = toset([
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
    # Account baseline service roles (design v10 section 8.1): the Config recorder and AWS Backup.
    "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    # ECS native blue/green: the role ECS uses to shift ALB listener rule weights (design v11 section 5.6).
    "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers",
  ])
}
