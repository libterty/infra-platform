resource "aws_lb" "this" {
  name                             = var.name
  load_balancer_type               = "network"
  internal                         = var.internal
  subnets                          = var.subnet_ids
  security_groups                  = var.security_group_ids
  enable_cross_zone_load_balancing = var.cross_zone
  enable_deletion_protection       = var.deletion_protection


  tags = merge(var.tags, { Name = var.name })
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name                 = "${var.name}-${each.key}"
  port                 = each.value.port
  protocol             = each.value.protocol
  target_type          = each.value.target_type
  vpc_id               = var.vpc_id
  deregistration_delay = tostring(each.value.deregistration_delay)
  # The provider takes the attribute as a string; null leaves the AWS default (client IP preserved for ip/instance types as AWS decides).
  preserve_client_ip = each.value.preserve_client_ip == null ? null : tostring(each.value.preserve_client_ip)

  health_check {
    enabled             = true
    protocol            = each.value.health_check.protocol
    port                = each.value.health_check.port
    interval            = each.value.health_check.interval
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    # path and matcher only exist for HTTP and HTTPS health checks.
    path    = contains(["HTTP", "HTTPS"], each.value.health_check.protocol) ? each.value.health_check.path : null
    matcher = contains(["HTTP", "HTTPS"], each.value.health_check.protocol) ? each.value.health_check.matcher : null
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness ? [1] : []
    content {
      type    = "source_ip"
      enabled = true
    }
  }

  target_group_health {
    dns_failover {
      minimum_healthy_targets_count = each.value.dns_failover
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol
  # TLS settings only apply to TLS listeners; validation rejects them on the other protocols.
  ssl_policy      = each.value.protocol == "TLS" ? each.value.ssl_policy : null
  certificate_arn = each.value.certificate_arn
  alpn_policy     = each.value.alpn_policy

  # A forward block is used for one target as well, so adding a second target later does not change the action type.
  default_action {
    type = "forward"

    forward {
      dynamic "target_group" {
        for_each = each.value.targets
        content {
          arn    = target_group.value.target_group != null ? aws_lb_target_group.this[target_group.value.target_group].arn : target_group.value.target_group_arn
          weight = target_group.value.weight
        }
      }
    }
  }

  tags = var.tags
}
