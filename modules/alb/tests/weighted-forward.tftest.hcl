mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev/0123456789abcdef"
      arn_suffix = "app/alpha-dev/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/fedcba9876543210"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"
      arn_suffix = "targetgroup/alpha-dev-web/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener_rule" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/alpha-dev/0123456789abcdef/fedcba9876543210/0011223344556677"
    }
  }
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  vpc_id             = "vpc-0123456789abcdef0"
  certificate_arn    = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  target_groups = {
    web = { port = 8080 }
  }
}

run "forward_weighted_local_and_external" {
  command = apply

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            new = { target_group = "web", weight = 10 }
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 90 }
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["canary"].action[0].forward[0].target_group) == 2
    error_message = "A forward rule must have one target_group block per target"
  }

  assert {
    condition = (
      aws_lb_listener_rule.this["canary"].action[0].type == "forward" &&
      aws_lb_listener_rule.this["canary"].action[0].target_group_arn == null
    )
    error_message = "A forward rule must not set the single target_group_arn"
  }

  assert {
    condition     = contains([for t in aws_lb_listener_rule.this["canary"].action[0].forward[0].target_group : t.weight], 90) && contains([for t in aws_lb_listener_rule.this["canary"].action[0].forward[0].target_group : t.arn], "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef")
    error_message = "The external ARN must be used as is, with its weight"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["canary"].action[0].forward[0].stickiness) == 0
    error_message = "Without stickiness_duration no stickiness block may be sent (provider requires duration)"
  }
}

run "forward_external_only_plan" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 100 }
          }
        }
      }
    }
  }

  assert {
    condition     = [for t in aws_lb_listener_rule.this["canary"].action[0].forward[0].target_group : t.arn] == ["arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef"]
    error_message = "An external target group needs no vpc or target_groups entry"
  }
}

run "forward_external_without_local_target_groups" {
  command = plan

  variables {
    target_groups = {}
    vpc_id        = null
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }
}

run "forward_zero_weight_allowed_next_to_positive" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            new = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 0 }
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-api/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }
}

run "forward_boundary_weights_and_five_targets" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            t0 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg0/0123456789abcdef", weight = 999 }
            t1 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg1/0123456789abcdef", weight = 0 }
            t2 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg2/0123456789abcdef", weight = 0 }
            t3 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg3/0123456789abcdef", weight = 0 }
            t4 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg4/0123456789abcdef", weight = 0 }
          }
        }
      }
    }
  }
}

run "forward_with_stickiness_duration" {
  command = apply

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 3600 } } }
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            new = { target_group = "web", weight = 1 }
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
          stickiness_duration = 600
        }
      }
    }
  }

  assert {
    condition = (
      aws_lb_listener_rule.this["canary"].action[0].forward[0].stickiness[0].enabled == true &&
      aws_lb_listener_rule.this["canary"].action[0].forward[0].stickiness[0].duration == 600
    )
    error_message = "stickiness_duration must enable rule-level stickiness with that duration"
  }
}

run "forward_stickiness_duration_without_tg_stickiness_is_allowed" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
          stickiness_duration = 1
        }
      }
    }
  }
}

run "forward_zero_targets_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_six_targets_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            t0 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg0/0123456789abcdef", weight = 1 }
            t1 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg1/0123456789abcdef", weight = 1 }
            t2 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg2/0123456789abcdef", weight = 1 }
            t3 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg3/0123456789abcdef", weight = 1 }
            t4 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg4/0123456789abcdef", weight = 1 }
            t5 = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/tg5/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_all_weights_zero_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 0 }
            b = { target_group = "web", weight = 0 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_negative_weight_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = -1 }
            b = { target_group = "web", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_weight_1000_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1000 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_unknown_target_group_key_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group = "missing", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_target_with_both_key_and_arn_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group = "web", target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_target_with_neither_key_nor_arn_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_external_arn_not_a_target_group_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/x/0123", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_external_arn_garbage_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "not-an-arn", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_stickiness_duration_zero_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
          stickiness_duration = 0
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_stickiness_duration_too_long_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
          stickiness_duration = 604801
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_stickiness_duration_max_allowed" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
          stickiness_duration = 604800
        }
      }
    }
  }
}

run "forward_stickiness_duration_required_when_local_tg_sticky" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 3600 } } }
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            new = { target_group = "web", weight = 1 }
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_stickiness_duration_not_required_when_only_external_tg_used" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 3600 } } }
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        forward = {
          targets = {
            old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }
          }
        }
      }
    }
  }
}

run "rule_target_group_and_forward_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
        target_group  = "web"
        forward       = { targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rule_without_target_group_or_forward_rejected" {
  command = plan

  variables {
    listener_rules = {
      canary = {
        priority      = 10
        path_patterns = ["/*"]
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rule_target_group_only_still_works" {
  command = apply

  variables {
    listener_rules = {
      plain = {
        priority      = 10
        path_patterns = ["/*"]
        target_group  = "web"
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["plain"].action[0].forward) == 0 && aws_lb_listener_rule.this["plain"].action[0].target_group_arn != null
    error_message = "Without forward the rule keeps the single target_group_arn action"
  }
}

run "forward_rules_priority_must_be_unique" {
  command = plan

  variables {
    listener_rules = {
      a = {
        priority      = 10
        path_patterns = ["/*"]
        forward       = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
      b = {
        priority              = 10
        path_patterns         = ["/b"]
        host_headers          = []
        require_origin_verify = false
        forward               = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_rule_needs_condition" {
  command = plan

  variables {
    listener_rules = {
      a = {
        priority      = 10
        path_patterns = ["/*"]
        forward       = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
      b = {
        priority              = 20
        path_patterns         = []
        host_headers          = []
        require_origin_verify = false
        forward               = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_rule_condition_values_capped_at_five" {
  command = plan

  variables {
    listener_rules = {
      a = {
        priority      = 10
        path_patterns = ["/*"]
        forward       = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
      b = {
        priority              = 20
        path_patterns         = ["/1", "/2", "/3", "/4", "/5", "/6"]
        host_headers          = []
        require_origin_verify = false
        forward               = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_rule_origin_verify_needs_header" {
  command = plan

  variables {
    listener_rules = {
      a = {
        priority      = 10
        path_patterns = ["/*"]
        forward       = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
      b = {
        priority              = 20
        path_patterns         = ["/b"]
        host_headers          = []
        require_origin_verify = true
        forward               = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "forward_rules_distinct_priority_ok" {
  command = plan

  variables {
    listener_rules = {
      a = {
        priority      = 10
        path_patterns = ["/*"]
        forward       = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
      b = {
        priority              = 20
        path_patterns         = ["/b"]
        host_headers          = ["a.example.com"]
        require_origin_verify = false
        forward               = { targets = { x = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }
}

run "target_type_defaults_to_ip" {
  command = plan

  variables {
  }

  assert {
    condition     = aws_lb_target_group.this["web"].target_type == "ip" && aws_lb_target_group.this["web"].protocol == "HTTP"
    error_message = "target_type must default to ip with HTTP protocol"
  }

  assert {
    condition     = length(aws_lb_target_group.this["web"].stickiness) == 0
    error_message = "stickiness must be off by default"
  }
}

run "target_type_instance" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, target_type = "instance" } }
  }

  assert {
    condition     = aws_lb_target_group.this["web"].target_type == "instance" && aws_lb_target_group.this["web"].protocol == "HTTP"
    error_message = "target_type = instance must be passed through, protocol stays HTTP"
  }
}

run "target_type_lambda_rejected" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, target_type = "lambda" } }
  }

  expect_failures = [var.target_groups]
}

run "target_type_empty_rejected" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, target_type = "" } }
  }

  expect_failures = [var.target_groups]
}

run "target_group_stickiness_lb_cookie" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 86400 } } }
  }

  assert {
    condition = (
      aws_lb_target_group.this["web"].stickiness[0].type == "lb_cookie" &&
      aws_lb_target_group.this["web"].stickiness[0].enabled == true &&
      aws_lb_target_group.this["web"].stickiness[0].cookie_duration == 86400
    )
    error_message = "stickiness must create an lb_cookie stickiness block with the given duration"
  }
}

run "target_group_stickiness_bounds_ok" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 1 } }, api = { port = 9090, stickiness = { duration = 604800 } } }
  }
}

run "target_group_stickiness_zero_rejected" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 0 } } }
  }

  expect_failures = [var.target_groups]
}

run "target_group_stickiness_too_long_rejected" {
  command = plan

  variables {
    target_groups = { web = { port = 8080, stickiness = { duration = 604801 } } }
  }

  expect_failures = [var.target_groups]
}

run "listener_rule_arns_output" {
  command = apply

  variables {
    listener_rules = {
      plain = {
        priority      = 10
        path_patterns = ["/*"]
        target_group  = "web"
      }
      canary = {
        priority     = 20
        host_headers = ["a.example.com"]
        forward      = { targets = { old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } }
      }
    }
  }

  assert {
    condition     = toset(keys(output.listener_rule_arns)) == toset(["canary", "plain"])
    error_message = "listener_rule_arns must be keyed like listener_rules"
  }

  assert {
    condition     = alltrue([for a in values(output.listener_rule_arns) : startswith(a, "arn:aws:elasticloadbalancing:")])
    error_message = "listener_rule_arns values must be rule ARNs"
  }
}

run "listener_rule_arns_empty_by_default" {
  command = apply

  variables {
    target_groups = {}
    vpc_id        = null
  }

  assert {
    condition     = output.listener_rule_arns == {}
    error_message = "listener_rule_arns must be an empty map without rules"
  }
}

run "listener_arns_with_certificate" {
  command = apply

  variables {
  }

  assert {
    condition     = output.listener_arns.http != null && output.listener_arns.https != null
    error_message = "Both listener ARNs must be set when a certificate is given"
  }

  assert {
    condition     = output.listener_arns.https == output.listener_arn
    error_message = "https must be the listener_arn when a certificate is given"
  }
}

run "listener_arns_without_certificate" {
  command = apply

  variables {
    certificate_arn = null
  }

  assert {
    condition     = output.listener_arns.http != null && output.listener_arns.https == null
    error_message = "https must be null without a certificate"
  }

  assert {
    condition     = output.listener_arns.http == output.listener_arn
    error_message = "http must be the listener_arn without a certificate"
  }
}
