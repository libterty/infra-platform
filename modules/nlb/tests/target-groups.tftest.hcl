mock_provider "aws" {}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  vpc_id             = "vpc-0123456789abcdef0"
}

run "defaults" {
  command = plan

  variables {
    target_groups = {
      web = { port = 8080 }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["web"].name == "alpha-dev-web" && aws_lb_target_group.this["web"].port == 8080 && aws_lb_target_group.this["web"].vpc_id == "vpc-0123456789abcdef0"
    error_message = "Target group is named <name>-<key> in the given VPC"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].protocol == "TCP" && aws_lb_target_group.this["web"].target_type == "ip"
    error_message = "protocol defaults to TCP and target_type to ip"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].deregistration_delay == "300"
    error_message = "deregistration_delay defaults to 300"
  }

  assert {
    condition     = length(aws_lb_target_group.this["web"].stickiness) == 0
    error_message = "No stickiness block by default"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].health_check[0].enabled == true && aws_lb_target_group.this["web"].health_check[0].protocol == "TCP" && aws_lb_target_group.this["web"].health_check[0].interval == 30
    error_message = "Default health check is TCP every 30 seconds"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].health_check[0].healthy_threshold == 3 && aws_lb_target_group.this["web"].health_check[0].unhealthy_threshold == 3
    error_message = "Default thresholds are 3"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].target_group_health[0].dns_failover[0].minimum_healthy_targets_count == "1"
    error_message = "dns_failover defaults to 1"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].tags["Name"] == "alpha-dev-web"
    error_message = "Name tag is <name>-<key>"
  }
}

run "overrides" {
  command = plan

  variables {
    target_groups = {
      db = {
        port                 = 5432
        protocol             = "TLS"
        target_type          = "instance"
        deregistration_delay = 30
        preserve_client_ip   = false
        stickiness           = true
        dns_failover         = "off"
        health_check = {
          protocol            = "HTTP"
          port                = "8081"
          path                = "/ping"
          matcher             = "200-299"
          interval            = 10
          healthy_threshold   = 2
          unhealthy_threshold = 2
        }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["db"].protocol == "TLS" && aws_lb_target_group.this["db"].target_type == "instance" && aws_lb_target_group.this["db"].deregistration_delay == "30"
    error_message = "protocol, target_type and deregistration_delay must be passed through"
  }

  assert {
    condition     = aws_lb_target_group.this["db"].preserve_client_ip == "false"
    error_message = "preserve_client_ip bool must be sent as a string"
  }

  assert {
    condition     = aws_lb_target_group.this["db"].stickiness[0].type == "source_ip" && aws_lb_target_group.this["db"].stickiness[0].enabled == true
    error_message = "stickiness = true must enable source_ip stickiness"
  }

  assert {
    condition     = aws_lb_target_group.this["db"].target_group_health[0].dns_failover[0].minimum_healthy_targets_count == "off"
    error_message = "dns_failover off must be sent as off"
  }

  assert {
    condition = (
      aws_lb_target_group.this["db"].health_check[0].protocol == "HTTP" &&
      aws_lb_target_group.this["db"].health_check[0].port == "8081" &&
      aws_lb_target_group.this["db"].health_check[0].path == "/ping" &&
      aws_lb_target_group.this["db"].health_check[0].matcher == "200-299" &&
      aws_lb_target_group.this["db"].health_check[0].interval == 10 &&
      aws_lb_target_group.this["db"].health_check[0].healthy_threshold == 2 &&
      aws_lb_target_group.this["db"].health_check[0].unhealthy_threshold == 2
    )
    error_message = "health_check overrides must be passed through"
  }
}

run "preserve_client_ip_true" {
  command = plan

  variables {
    target_groups = {
      web = { port = 8080, preserve_client_ip = true }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["web"].preserve_client_ip == "true"
    error_message = "preserve_client_ip = true must be sent as true"
  }
}

run "alb_target_type" {
  command = plan

  variables {
    target_groups = {
      front = {
        port        = 80
        target_type = "alb"
        health_check = {
          protocol = "HTTP"
          path     = "/health"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["front"].target_type == "alb" && aws_lb_target_group.this["front"].protocol == "TCP"
    error_message = "An alb target group is TCP"
  }
}

run "no_target_groups" {
  command = plan

  assert {
    condition     = length(aws_lb_target_group.this) == 0
    error_message = "No target group unless given"
  }
}
