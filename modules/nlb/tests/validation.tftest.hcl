mock_provider "aws" {}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "name_internal_prefix" {
  command = plan

  variables {
    name = "internal-alpha"
  }

  expect_failures = [var.name]
}

run "name_too_long" {
  command = plan

  variables {
    name = format("%33s", "x")
  }

  expect_failures = [var.name]
}

run "name_leading_hyphen" {
  command = plan

  variables {
    name = "-alpha"
  }

  expect_failures = [var.name]
}

run "name_32_chars_passes" {
  command = plan

  variables {
    name = replace(format("%32s", ""), " ", "a")
  }

  assert {
    condition     = length(aws_lb.this.name) == 32
    error_message = "Valid input must pass"
  }
}

run "subnet_ids_single" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "subnet_ids_duplicate" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaa", "subnet-aaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "subnet_ids_two_pass" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaa", "subnet-bbb"]
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "security_group_ids_empty" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "security_group_ids_one_pass" {
  command = plan

  variables {
    security_group_ids = ["sg-aaa", "sg-bbb"]
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "sns_topic_arns_empty" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "sns_topic_arns_malformed" {
  command = plan

  variables {
    sns_topic_arns = ["not-an-arn"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "vpc_id_required_with_target_groups" {
  command = plan

  variables {
    vpc_id        = null
    target_groups = { web = { port = 8080 } }
  }

  expect_failures = [var.vpc_id]
}

run "vpc_id_given_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080 } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_name_too_long" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { aaaaaaaaaaaaaaaaaaaaaaa = { port = 8080 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_name_32_chars_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { aaaaaaaaaaaaaaaaaaaaaa = { port = 8080 } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_key_trailing_hyphen" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { "web-" = { port = 8080 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_protocol_http_rejected" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, protocol = "HTTP" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_protocol_tcp_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, protocol = "TCP" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_protocol_tls_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, protocol = "TLS" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_protocol_udp_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, protocol = "UDP" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_protocol_tcp_udp_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, protocol = "TCP_UDP" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_target_type_lambda_rejected" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, target_type = "lambda" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_target_type_ip_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, target_type = "ip" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_target_type_instance_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, target_type = "instance" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_target_type_alb_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 80, target_type = "alb", health_check = { protocol = "HTTP" } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_alb_with_udp_rejected" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 80, protocol = "UDP", target_type = "alb" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_alb_with_tcp_health_check_rejected" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 80, target_type = "alb" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_port_zero" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 0 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_port_65536" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 65536 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_port_65535_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 65535 } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_deregistration_delay_3601" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, deregistration_delay = 3601 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_deregistration_delay_negative" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, deregistration_delay = -1 } }
  }

  expect_failures = [var.target_groups]
}

run "tg_deregistration_delay_3600_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, deregistration_delay = 3600 } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_deregistration_delay_zero_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, deregistration_delay = 0 } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_health_check_protocol_udp_rejected" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { protocol = "UDP" } } }
  }

  expect_failures = [var.target_groups]
}

run "tg_health_check_https_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { protocol = "HTTPS" } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_health_check_interval_4" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { interval = 4 } } }
  }

  expect_failures = [var.target_groups]
}

run "tg_health_check_interval_301" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { interval = 301 } } }
  }

  expect_failures = [var.target_groups]
}

run "tg_health_check_interval_5_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { interval = 5 } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_health_check_threshold_1" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { healthy_threshold = 1 } } }
  }

  expect_failures = [var.target_groups]
}

run "tg_health_check_unhealthy_threshold_11" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { unhealthy_threshold = 11 } } }
  }

  expect_failures = [var.target_groups]
}

run "tg_health_check_thresholds_2_and_10_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, health_check = { healthy_threshold = 2, unhealthy_threshold = 10 } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_dns_failover_invalid_zero" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "0" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_word" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "abc" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_empty" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_leading_zero" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "01" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_above_max" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "3001" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_negative" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "-1" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_upper_off" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "OFF" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_invalid_decimal" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "1.5" } }
  }

  expect_failures = [var.target_groups]
}

run "tg_dns_failover_off_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "off" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_dns_failover_one_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "1" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tg_dns_failover_max_pass" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { port = 8080, dns_failover = "3000" } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "listener_protocol_http_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, protocol = "HTTP", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_port_zero" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 0, targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_port_65536" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 65536, targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_port_65535_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 65535, targets = { a = { target_group = "web", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "listener_tls_without_certificate" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_tls_with_certificate_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "listener_tcp_with_certificate_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_certificate_not_acm_arn" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:iam::111111111111:server-certificate/x", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_alpn_invalid" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", alpn_policy = "HTTP3", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_alpn_on_tcp_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, alpn_policy = "HTTP2Preferred", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "listener_alpn_none_on_tls_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", alpn_policy = "None", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "targets_empty" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = {} } }
  }

  expect_failures = [var.listeners]
}

run "targets_six" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, c = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, d = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, e = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, f = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "targets_five_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, c = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, d = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 }, e = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "targets_one_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "weight_1000" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1000 } } } }
  }

  expect_failures = [var.listeners]
}

run "weight_negative" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = -1 } } } }
  }

  expect_failures = [var.listeners]
}

run "weight_999_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 999 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "weights_all_zero" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 0 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 0 } } } }
  }

  expect_failures = [var.listeners]
}

run "weights_one_zero_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 0 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "target_both_group_and_arn" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "web", target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "target_neither_group_nor_arn" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "target_group_key_missing" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "nope", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "target_group_arn_malformed" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:s3:::bucket", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "target_group_arn_alb_listener_arn_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/x/0123456789abcdef/fedcba9876543210", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "d14_two_targets_default_dns_failover_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "web", weight = 1 }, b = { target_group = "old", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "d14_two_targets_all_off_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "off2", weight = 1 }, b = { target_group = "old", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "d14_two_targets_local_off_and_external_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "old", weight = 1 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "d14_two_targets_local_default_and_external_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "web", weight = 1 }, b = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "d14_zero_weight_target_still_counts" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "web", weight = 0 }, b = { target_group = "old", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "d14_single_target_default_dns_failover_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "web", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "d14_other_listener_with_one_target_not_affected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { one = { port = 80, targets = { a = { target_group = "web", weight = 1 } } }, two = { port = 81, targets = { a = { target_group = "old", weight = 1 }, b = { target_group = "off2", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "protocol_mismatch_in_listener" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      tcp = { port = 8080, dns_failover = "off" }
      udp = { port = 53, protocol = "UDP", dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "tcp", weight = 1 }, b = { target_group = "udp", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "protocol_same_in_listener_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      one = { port = 53, protocol = "UDP", dns_failover = "off" }
      two = { port = 54, protocol = "UDP", dns_failover = "off" }
    }
    listeners = { app = { port = 53, protocol = "UDP", targets = { a = { target_group = "one", weight = 1 }, b = { target_group = "two", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "protocol_differs_across_listeners_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      tcp = { port = 8080 }
      udp = { port = 53, protocol = "UDP" }
    }
    listeners = {
      a = { port = 80, targets = { a = { target_group = "tcp", weight = 1 } } }
      b = { port = 53, protocol = "UDP", targets = { a = { target_group = "udp", weight = 1 } } }
    }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tls_listener_with_sticky_target_group_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", targets = { a = { target_group = "sticky", weight = 1 } } } }
  }

  expect_failures = [var.listeners]
}

run "tls_listener_without_sticky_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 443, protocol = "TLS", certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555", targets = { a = { target_group = "web", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}

run "tcp_listener_with_sticky_target_group_pass" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web    = { port = 8080 }
      old    = { port = 8080, dns_failover = "off" }
      sticky = { port = 8080, stickiness = true }
      udp    = { port = 53, protocol = "UDP" }
      off2   = { port = 8081, dns_failover = "off" }
    }
    listeners = { app = { port = 80, targets = { a = { target_group = "sticky", weight = 1 } } } }
  }

  assert {
    condition     = aws_lb.this.name != ""
    error_message = "Valid input must pass"
  }
}
