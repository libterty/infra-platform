locals {
  tags = merge(var.tags, { Name = var.name })

  # The primary type goes in the launch template; the mixed policy overrides it with the full list.
  primary_instance_type = var.instance_types[0]
  ami_id                = var.ami_id == null ? data.aws_ami.al2023[0].id : var.ami_id
}

# Latest Amazon Linux 2023 for the chosen architecture. A data source rather than the SSM public parameter,
# because only ssm-read may read SSM parameters in this repo.
data "aws_ami" "al2023" {
  count = var.ami_id == null ? 1 : 0

  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-${var.architecture}"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_launch_template" "this" {
  name          = var.name
  image_id      = local.ami_id
  instance_type = local.primary_instance_type
  user_data     = var.user_data == null ? null : base64encode(var.user_data)

  # Every new version becomes the default, so the default never lags behind what the group launches.
  update_default_version = true

  iam_instance_profile {
    name = var.instance_profile_name
  }

  # IMDSv2 only, and one hop so containers on the host cannot reach the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Explicit false so a subnet that maps public IPs on launch cannot give the instances one.
  # Security groups live here: a launch template cannot mix vpc_security_group_ids with network_interfaces.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = var.security_group_ids
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume.size
      encrypted             = true
      kms_key_id            = var.root_volume.kms_key_arn
      delete_on_termination = true
    }
  }

  tags = local.tags
}

resource "aws_autoscaling_group" "this" {
  name                      = var.name
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = length(var.target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = var.health_check_grace_period
  target_group_arns         = var.target_group_arns

  # Plain launch template when there is no spot, so the group has no mixed_instances_policy at all.
  dynamic "launch_template" {
    for_each = var.spot == null ? [1] : []
    content {
      id = aws_launch_template.this.id
      # The version number, not "$Latest": a new version changes this value and so starts the instance refresh.
      version = aws_launch_template.this.latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = var.spot == null ? [] : [var.spot]
    content {
      instances_distribution {
        on_demand_base_capacity                  = mixed_instances_policy.value.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = mixed_instances_policy.value.on_demand_percentage_above_base
        spot_allocation_strategy                 = mixed_instances_policy.value.allocation_strategy
      }

      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this.id
          version            = aws_launch_template.this.latest_version
        }

        dynamic "override" {
          for_each = var.instance_types
          content {
            instance_type = override.value
          }
        }
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.instance_refresh.min_healthy_percentage
    }
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    # Scaling policies own the instance count after creation; a plan must not reset it to the input.
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu" {
  count = var.cpu_target == null ? 0 : 1

  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target
  }
}
