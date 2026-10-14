locals {
  create_target_group = local.has_lb && try(var.load_balancer.listener_arn, null) != null

  target_group_arn = !local.has_lb ? null : (
    local.create_target_group ? aws_lb_target_group.this[0].arn : var.load_balancer.target_group_arn
  )

  # arn:aws:elasticloadbalancing:<region>:<account>:targetgroup/<name>/<id>；告警的 TargetGroup 維度要帶 targetgroup/ 前綴
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

  # 名稱帶 port，改 port 時新舊名稱不同，才能先建後刪。
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.create_target_group ? 1 : 0

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
