resource "aws_launch_template" "node_group" {
  for_each = var.managed_node_groups

  name = "${var.name}-${each.key}"

  # Every new version becomes the default, so the default never lags behind what the node group launches.
  update_default_version = true

  # IMDSv2 only, and one hop so pods cannot reach the node role through the metadata service (Pod Identity covers them).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # AL2023 root device. The image and user data stay with EKS, which merges them into this template.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = each.value.disk_size
      encrypted             = true
      kms_key_id            = each.value.disk_kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-${each.key}" })
  }

  tags = local.tags
}

resource "aws_eks_node_group" "this" {
  for_each = var.managed_node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = each.value.node_role_arn
  subnet_ids      = each.value.subnet_ids == null ? var.subnet_ids : each.value.subnet_ids

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  labels         = each.value.labels

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable_percentage = each.value.max_unavailable_percentage
  }

  launch_template {
    id = aws_launch_template.node_group[each.key].id
    # The version number, not "$Latest": a new version changes this value and so rolls the node group.
    version = aws_launch_template.node_group[each.key].latest_version
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = local.tags

  lifecycle {
    # The autoscaler (Karpenter does not touch managed groups, Cluster Autoscaler does) owns the node count after creation.
    ignore_changes = [scaling_config[0].desired_size]
  }

  # Nodes only become Ready once the CNI is installed.
  depends_on = [aws_eks_addon.before_compute]
}

resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = each.value.pod_execution_role_arn
  subnet_ids             = each.value.subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = local.tags
}
