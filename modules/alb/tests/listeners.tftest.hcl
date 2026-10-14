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
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "https_with_certificate" {
  command = apply

  variables {
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/primary"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "A certificate must create the HTTPS listener"
  }

  assert {
    condition     = aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS"
    error_message = "HTTPS listener must be 443/HTTPS"
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener must use the TLS 1.3 policy"
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].type == "fixed-response" && aws_lb_listener.https[0].default_action[0].fixed_response[0].status_code == "404" && aws_lb_listener.https[0].default_action[0].fixed_response[0].content_type == "text/plain"
    error_message = "HTTPS default action must be a text/plain 404"
  }

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP"
    error_message = "HTTP listener must always exist on 80"
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301" && aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" && aws_lb_listener.http.default_action[0].redirect[0].port == "443"
    error_message = "With a certificate HTTP must 301 to HTTPS 443"
  }

  assert {
    condition     = output.listener_protocol == "HTTPS" && output.listener_arn == aws_lb_listener.https[0].arn
    error_message = "listener_arn must be the HTTPS listener"
  }
}

run "http_only_without_certificate" {
  command = plan

  variables {
    certificate_arn = null
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "Without a certificate no 443 listener may exist"
  }

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.default_action[0].type == "fixed-response" && aws_lb_listener.http.default_action[0].fixed_response[0].status_code == "404"
    error_message = "Without a certificate HTTP must answer 404, not redirect"
  }

  assert {
    condition     = length(aws_lb_listener.http.default_action[0].redirect) == 0
    error_message = "Without a certificate there must be no redirect"
  }

  assert {
    condition     = output.listener_protocol == "HTTP"
    error_message = "listener_protocol must be HTTP"
  }
}

run "http_only_listener_arn_is_http_listener" {
  command = apply

  assert {
    condition     = output.listener_arn == aws_lb_listener.http.arn
    error_message = "listener_arn must be the HTTP listener without a certificate"
  }
}

run "additional_certificates" {
  command = plan

  variables {
    certificate_arn             = "arn:aws:acm:ap-northeast-1:111111111111:certificate/primary"
    additional_certificate_arns = ["arn:aws:acm:ap-northeast-1:111111111111:certificate/a", "arn:aws:acm:ap-northeast-1:111111111111:certificate/b"]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 2
    error_message = "One listener certificate per additional ARN"
  }
}

run "no_additional_certificates" {
  command = plan

  variables {
    certificate_arn             = "arn:aws:acm:ap-northeast-1:111111111111:certificate/primary"
    additional_certificate_arns = []
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 0
    error_message = "An empty set must create none"
  }
}

run "additional_certificates_need_primary" {
  command = plan

  variables {
    certificate_arn             = null
    additional_certificate_arns = ["arn:aws:acm:ap-northeast-1:111111111111:certificate/a"]
  }

  expect_failures = [var.additional_certificate_arns]
}
