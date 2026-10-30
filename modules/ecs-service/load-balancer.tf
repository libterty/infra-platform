locals {
  create_target_group = local.has_lb && try(var.load_balancer.listener_arn, null) != null

  target_group_arn = !local.has_lb ? null : (
    local.create_target_group ? aws_lb_target_group.this[0].arn : var.load_balancer.target_group_arn
  )

  # The alarm TargetGroup dimension needs the targetgroup/<name>/<id> part of the ARN.
  target_group_arn_suffix = local.has_lb ? split(":", local.target_group_arn)[5] : null
}

resource "aws_lb_target_group" "this" {
  count = local.create_target_group ? 1 : 0

  name        = "${var.name}-${var.container_port}"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.load_balancer.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.load_balancer.health_check.path
    matcher             = var.load_balancer.health_check.matcher
    interval            = var.load_balancer.health_check.interval
    timeout             = var.load_balancer.health_check.timeout
    healthy_threshold   = var.load_balancer.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer.health_check.unhealthy_threshold
  }

  tags = local.tags

  # The port in the name lets a port change create the new group before destroying the old one.
  lifecycle {
    create_before_destroy = true
  }
}

# ECS registers the new revision here during a blue/green deployment.
resource "aws_lb_target_group" "alternate" {
  count = local.blue_green ? 1 : 0

  name        = "${var.name}-${var.container_port}-alt"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.load_balancer.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.load_balancer.health_check.path
    matcher             = var.load_balancer.health_check.matcher
    interval            = var.load_balancer.health_check.interval
    timeout             = var.load_balancer.health_check.timeout
    healthy_threshold   = var.load_balancer.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer.health_check.unhealthy_threshold
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.create_target_group && !local.blue_green ? 1 : 0

  listener_arn = var.load_balancer.listener_arn
  priority     = var.load_balancer.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.load_balancer.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.path_patterns) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.load_balancer.path_patterns
      }
    }
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "blue_green" {
  count = local.blue_green ? 1 : 0

  listener_arn = var.load_balancer.listener_arn
  priority     = var.load_balancer.priority

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.this[0].arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.alternate[0].arn
        weight = 0
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.load_balancer.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.path_patterns) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.load_balancer.path_patterns
      }
    }
  }

  tags = local.tags

  # ECS shifts the weights between the two target groups during every deployment.
  lifecycle {
    ignore_changes = [action]
  }
}
