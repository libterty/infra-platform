locals {
  has_certificate = var.certificate_arn != null

  # Rules go on the HTTPS listener; without a certificate the HTTP listener is the only one.
  rule_listener_arn = local.has_certificate ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = var.security_group_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]
    content {
      enabled = true
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_lb_listener" "https" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = var.additional_certificate_arns

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = local.has_certificate ? "redirect" : "fixed-response"

    dynamic "redirect" {
      for_each = local.has_certificate ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = local.has_certificate ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  # web_acl is an object so that "is it set" stays known at plan time even when its arn is not.
  count = var.web_acl != null || var.web_acl_arn != null ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl != null ? var.web_acl.arn : var.web_acl_arn
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name                 = "${var.name}-${each.key}"
  port                 = each.value.port
  protocol             = "HTTP"
  protocol_version     = each.value.protocol_version
  target_type          = each.value.target_type
  vpc_id               = var.vpc_id
  deregistration_delay = tostring(each.value.deregistration_delay)

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness == null ? [] : [each.value.stickiness]
    content {
      type            = "lb_cookie"
      enabled         = true
      cookie_duration = stickiness.value.duration
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_lb_listener_rule" "this" {
  for_each = var.listener_rules

  listener_arn = local.rule_listener_arn
  priority     = each.value.priority

  action {
    type = "forward"
    # Without forward the rule keeps the single target group action of 0.3.0.
    target_group_arn = each.value.forward == null ? aws_lb_target_group.this[each.value.target_group].arn : null

    dynamic "forward" {
      for_each = each.value.forward == null ? [] : [each.value.forward]
      content {
        dynamic "target_group" {
          for_each = forward.value.targets
          content {
            arn    = target_group.value.target_group != null ? aws_lb_target_group.this[target_group.value.target_group].arn : target_group.value.target_group_arn
            weight = target_group.value.weight
          }
        }

        # The provider requires duration inside stickiness, so no duration means no block (stickiness stays off).
        dynamic "stickiness" {
          for_each = forward.value.stickiness_duration == null ? [] : [forward.value.stickiness_duration]
          content {
            enabled  = true
            duration = stickiness.value
          }
        }
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.host_headers) > 0 ? [each.value.host_headers] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_patterns) > 0 ? [each.value.path_patterns] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.require_origin_verify ? [1] : []
    content {
      http_header {
        http_header_name = var.origin_verify_header_name
        values           = [var.origin_verify_header_value]
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
