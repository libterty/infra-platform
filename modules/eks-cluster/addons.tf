locals {
  # DaemonSet add-ons that do not need a node to become ACTIVE. Everything else (coredns, aws-ebs-csi-driver,
  # metrics-server, ...) schedules pods that need a node, and without one the add-on stays DEGRADED.
  node_independent_addons = ["vpc-cni", "kube-proxy", "eks-pod-identity-agent"]
}

resource "aws_eks_addon" "before_compute" {
  for_each = { for k, v in var.addons : k => v if contains(local.node_independent_addons, k) }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_role_arn == null ? [] : [each.value]
    content {
      role_arn        = pod_identity_association.value.pod_identity_role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  tags = local.tags
}

resource "aws_eks_addon" "after_compute" {
  for_each = { for k, v in var.addons : k => v if !contains(local.node_independent_addons, k) }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_role_arn == null ? [] : [each.value]
    content {
      role_arn        = pod_identity_association.value.pod_identity_role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  tags = local.tags

  # With Auto Mode alone there is nothing to wait for: pending pods make Auto Mode launch nodes.
  depends_on = [
    aws_eks_addon.before_compute,
    aws_eks_node_group.this,
    aws_eks_fargate_profile.this,
  ]
}
