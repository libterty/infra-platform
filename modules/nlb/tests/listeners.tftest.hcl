mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/net/alpha-dev/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/alpha-dev/0123456789abcdef/fedcba9876543210"
    }
  }
}

# The provider validates ARNs, and mock values for the target groups would be random strings that are not ARNs.
override_resource {
  target = aws_lb_target_group.this["web"]
  values = {
    arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"
  }
}

override_resource {
  target = aws_lb_target_group.this["old"]
  values = {
    arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-old/0123456789abcdef"
  }
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  vpc_id             = "vpc-0123456789abcdef0"
  target_groups = {
    web = { port = 8080 }
    old = { port = 8080, dns_failover = "off" }
  }
}

run "single_target_uses_forward_block" {
  command = apply

  variables {
    listeners = {
      app = {
        port    = 80
        targets = { new = { target_group = "web", weight = 1 } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["app"].port == 80 && aws_lb_listener.this["app"].protocol == "TCP"
    error_message = "protocol defaults to TCP"
  }

  assert {
    condition     = aws_lb_listener.this["app"].default_action[0].type == "forward" && aws_lb_listener.this["app"].default_action[0].target_group_arn == null
    error_message = "Single target still uses a forward block, not target_group_arn"
  }

  assert {
    condition     = length(aws_lb_listener.this["app"].default_action[0].forward[0].target_group) == 1
    error_message = "One target_group block per target"
  }

  assert {
    condition     = [for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.arn][0] == aws_lb_target_group.this["web"].arn
    error_message = "A local target uses the module's target group ARN"
  }

  assert {
    condition     = length(aws_lb_listener.this["app"].default_action[0].forward[0].stickiness) == 0
    error_message = "No forward stickiness block (NLB has no group level stickiness)"
  }

  assert {
    condition     = aws_lb_listener.this["app"].load_balancer_arn == aws_lb.this.arn
    error_message = "Listener belongs to the NLB"
  }
}

run "tcp_listener_ignores_tls_settings" {
  command = plan

  variables {
    listeners = {
      app = {
        port    = 80
        targets = { new = { target_group = "web", weight = 1 } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["app"].certificate_arn == null && aws_lb_listener.this["app"].alpn_policy == null
    error_message = "TCP listener must not set a certificate or ALPN policy"
  }
}

run "weighted_local_and_external" {
  command = apply

  variables {
    listeners = {
      app = {
        port = 80
        targets = {
          new = { target_group = "web", weight = 10 }
          old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 90 }
        }
      }
    }
    target_groups = {
      web = { port = 8080, dns_failover = "off" }
    }
  }

  assert {
    condition     = length(aws_lb_listener.this["app"].default_action[0].forward[0].target_group) == 2
    error_message = "Two target_group blocks"
  }

  assert {
    condition     = contains([for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.weight], 90) && contains([for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.weight], 10)
    error_message = "Weights are passed through"
  }

  assert {
    condition     = contains([for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.arn], "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef") && contains([for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.arn], aws_lb_target_group.this["web"].arn)
    error_message = "External ARN used as is, local key resolved to the module target group"
  }
}

run "weight_defaults_to_one" {
  command = apply

  variables {
    listeners = {
      app = {
        port    = 80
        targets = { new = { target_group = "web" } }
      }
    }
  }

  assert {
    condition     = [for t in aws_lb_listener.this["app"].default_action[0].forward[0].target_group : t.weight][0] == 1
    error_message = "weight defaults to 1"
  }
}

run "tls_listener" {
  command = plan

  variables {
    listeners = {
      app = {
        port            = 443
        protocol        = "TLS"
        certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
        alpn_policy     = "HTTP2Preferred"
        targets         = { new = { target_group = "web", weight = 1 } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["app"].protocol == "TLS" && aws_lb_listener.this["app"].certificate_arn == "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
    error_message = "TLS listener carries the certificate"
  }

  assert {
    condition     = aws_lb_listener.this["app"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "ssl_policy defaults to the TLS 1.3 policy"
  }

  assert {
    condition     = aws_lb_listener.this["app"].alpn_policy == "HTTP2Preferred"
    error_message = "alpn_policy is passed through"
  }
}

run "tls_listener_custom_ssl_policy" {
  command = plan

  variables {
    listeners = {
      app = {
        port            = 443
        protocol        = "TLS"
        certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
        ssl_policy      = "ELBSecurityPolicy-TLS13-1-3-2021-06"
        targets         = { new = { target_group = "web", weight = 1 } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["app"].ssl_policy == "ELBSecurityPolicy-TLS13-1-3-2021-06"
    error_message = "ssl_policy override must be used"
  }
}

run "udp_and_tcp_udp_listeners" {
  command = plan

  variables {
    target_groups = {
      dns = { port = 53, protocol = "UDP" }
      mix = { port = 5353, protocol = "TCP_UDP" }
    }
    listeners = {
      dns = {
        port     = 53
        protocol = "UDP"
        targets  = { a = { target_group = "dns", weight = 1 } }
      }
      mix = {
        port     = 5353
        protocol = "TCP_UDP"
        targets  = { a = { target_group = "mix", weight = 1 } }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["dns"].protocol == "UDP" && aws_lb_listener.this["mix"].protocol == "TCP_UDP"
    error_message = "UDP and TCP_UDP listeners are allowed"
  }
}

run "listener_arns_output" {
  command = apply

  variables {
    listeners = {
      app = {
        port    = 80
        targets = { new = { target_group = "web", weight = 1 } }
      }
    }
  }

  assert {
    condition     = output.listener_arns == { app = aws_lb_listener.this["app"].arn }
    error_message = "listener_arns is keyed by the listeners key"
  }
}
