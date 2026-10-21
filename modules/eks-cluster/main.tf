locals {
  tags = merge(var.tags, { Name = var.name })

  auto_mode = var.auto_mode != null
}

# Created before the cluster so the retention and KMS key apply from the first log line. When EKS creates the group itself,
# it never expires.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = local.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  # The three fixed settings below are ForceNew and have no input. Add-ons come from var.addons, and cluster admin
  # comes from var.access_entries, so nothing depends on what the creator of the cluster happens to be.
  bootstrap_self_managed_addons = false
  deletion_protection           = var.deletion_protection
  enabled_cluster_log_types     = var.enabled_log_types

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = var.kms_key_arn
    }
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.security_group_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  upgrade_policy {
    support_type = var.support_type
  }

  zonal_shift_config {
    enabled = var.zonal_shift
  }

  # Auto Mode needs these three enabled or disabled together (the provider rejects a mix). They are always sent, so
  # setting auto_mode back to null turns Auto Mode off instead of leaving it on.
  compute_config {
    enabled       = local.auto_mode
    node_pools    = local.auto_mode ? var.auto_mode.node_pools : null
    node_role_arn = local.auto_mode ? var.auto_mode.node_role_arn : null
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = local.auto_mode
    }
  }

  storage_config {
    block_storage {
      enabled = local.auto_mode
    }
  }

  tags = local.tags

  # The log group must exist first, otherwise EKS creates one with no expiry.
  depends_on = [aws_cloudwatch_log_group.cluster]

  lifecycle {
    # A precondition rather than a variable validation: the rule spans four variables, and variable validations that
    # refer to each other form a cycle.
    precondition {
      condition     = length(var.managed_node_groups) > 0 || length(var.fargate_profiles) > 0 || local.auto_mode || var.karpenter != null
      error_message = "Pick at least one node mode: managed_node_groups, fargate_profiles, auto_mode or karpenter."
    }
  }
}
