# Cluster settings: fixed values (design J3), encryption, endpoint access, logging and the input validations around them.

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

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
  }
}

run "fixed_values_and_defaults" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.bootstrap_self_managed_addons == false
    error_message = "bootstrap_self_managed_addons must be false"
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "authentication_mode must be API"
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "bootstrap_cluster_creator_admin_permissions must be false"
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == true
    error_message = "deletion_protection must default to true"
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "EXTENDED"
    error_message = "support_type must default to EXTENDED"
  }

  assert {
    condition = (
      aws_eks_cluster.this.name == "alpha-dev" &&
      aws_eks_cluster.this.version == "1.34" &&
      aws_eks_cluster.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"
    )
    error_message = "name, version and role must follow the input"
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit", "authenticator"])
    error_message = "Default control plane log types must be api, audit and authenticator"
  }

  assert {
    condition     = aws_eks_cluster.this.zonal_shift_config[0].enabled == false
    error_message = "zonal_shift must default to false"
  }

  assert {
    condition     = aws_eks_cluster.this.tags["Name"] == "alpha-dev"
    error_message = "The cluster must carry the Name tag"
  }
}

run "secrets_encryption" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "Only secrets are encrypted"
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == var.kms_key_arn
    error_message = "The encryption provider must use kms_key_arn"
  }
}

run "endpoint_is_private_by_default" {
  command = plan

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true &&
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    )
    error_message = "Default access must be private only"
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].subnet_ids == toset(var.subnet_ids)
    error_message = "Cluster subnets must follow the input"
  }

  assert {
    condition     = length(aws_eks_cluster.this.vpc_config[0].security_group_ids) == 0
    error_message = "No extra security group by default"
  }
}

run "overrides_are_applied" {
  command = plan

  variables {
    support_type        = "STANDARD"
    deletion_protection = false
    enabled_log_types   = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    zonal_shift         = true
    security_group_ids  = ["sg-0123456789abcdef0"]
    tags                = { Project = "alpha" }
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "support_type must follow the input"
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == false
    error_message = "deletion_protection must follow the input"
  }

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "All five log types must be enabled"
  }

  assert {
    condition     = aws_eks_cluster.this.zonal_shift_config[0].enabled == true
    error_message = "zonal_shift must follow the input"
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Extra security groups must follow the input"
  }

  assert {
    condition     = aws_eks_cluster.this.tags["Project"] == "alpha" && aws_eks_cluster.this.tags["Name"] == "alpha-dev"
    error_message = "tags must merge with Name"
  }
}

run "public_endpoint_with_cidrs" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.0/24", "198.51.100.7/32"]
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true &&
      aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24", "198.51.100.7/32"])
    )
    error_message = "Public access must carry the given CIDRs"
  }
}

run "public_endpoint_without_cidrs_rejected" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_world_rejected" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_world_among_others_rejected" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.0/24", "0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_open_to_world_ipv6_rejected" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["::/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "public_endpoint_malformed_cidr_rejected" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "private_endpoint_ignores_cidrs" {
  command = plan

  variables {
    public_access_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "CIDRs alone must not open the public endpoint"
  }
}

run "control_plane_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.cluster.name == "/aws/eks/alpha-dev/cluster"
    error_message = "Log group must be /aws/eks/<name>/cluster"
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.retention_in_days == 30
    error_message = "Default retention is 30 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.kms_key_id == null
    error_message = "No KMS key by default"
  }

  assert {
    condition     = output.log_group_name == "/aws/eks/alpha-dev/cluster"
    error_message = "log_group_name output must be the log group name"
  }
}

run "control_plane_log_group_with_kms_and_retention" {
  command = plan

  variables {
    log_retention_days = 90
    log_kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/99999999-2222-3333-4444-555555555555"
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.cluster.retention_in_days == 90 &&
      aws_cloudwatch_log_group.cluster.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/99999999-2222-3333-4444-555555555555"
    )
    error_message = "Retention and KMS key must follow the input"
  }
}

run "never_expire_retention_rejected" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

run "unsupported_retention_rejected" {
  command = plan

  variables {
    log_retention_days = 31
  }

  expect_failures = [var.log_retention_days]
}

run "log_kms_alias_rejected" {
  command = plan

  variables {
    log_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/logs"
  }

  expect_failures = [var.log_kms_key_arn]
}

run "unknown_log_type_rejected" {
  command = plan

  variables {
    enabled_log_types = ["api", "everything"]
  }

  expect_failures = [var.enabled_log_types]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/eks"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "cluster_role_must_be_a_role_arn" {
  command = plan

  variables {
    cluster_role_arn = "arn:aws:iam::111111111111:user/someone"
  }

  expect_failures = [var.cluster_role_arn]
}

run "uppercase_name_rejected" {
  command = plan

  variables {
    name = "Alpha-Dev"
  }

  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "alpha-dev-with-a-name-that-is-far-too-long-for-derived-names"
  }

  expect_failures = [var.name]
}

run "kubernetes_version_with_prefix_rejected" {
  command = plan

  variables {
    kubernetes_version = "v1.34"
  }

  expect_failures = [var.kubernetes_version]
}

run "kubernetes_version_patch_rejected" {
  command = plan

  variables {
    kubernetes_version = "1.34.1"
  }

  expect_failures = [var.kubernetes_version]
}

run "unknown_support_type_rejected" {
  command = plan

  variables {
    support_type = "PREMIUM"
  }

  expect_failures = [var.support_type]
}

run "single_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "malformed_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0", "not-a-subnet"]
  }

  expect_failures = [var.subnet_ids]
}

run "malformed_security_group_rejected" {
  command = plan

  variables {
    security_group_ids = ["not-a-sg"]
  }

  expect_failures = [var.security_group_ids]
}

run "outputs_after_apply" {
  command = apply

  assert {
    condition     = output.cluster_name == "alpha-dev"
    error_message = "cluster_name output"
  }

  assert {
    condition     = output.cluster_arn == "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
    error_message = "cluster_arn output"
  }

  assert {
    condition     = output.endpoint == "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
    error_message = "endpoint output"
  }

  assert {
    condition     = output.certificate_authority_data == "Y2VydGlmaWNhdGU="
    error_message = "certificate_authority_data output"
  }

  assert {
    condition     = output.oidc_issuer_url == "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABCDEF0123456789"
    error_message = "oidc_issuer_url output"
  }

  assert {
    condition     = output.node_group_names == ["system"]
    error_message = "node_group_names output"
  }

  assert {
    condition     = output.karpenter_interruption_queue_name == null
    error_message = "karpenter_interruption_queue_name must be null without karpenter"
  }
}
