mock_provider "aws" {}

variables {
  name               = "alpha-api"
  cluster_arn        = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
  image              = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-api:1.0.0"
  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
  task_role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-alpha-api-task"
  network = {
    subnet_ids         = ["subnet-aaa", "subnet-bbb"]
    security_group_ids = ["sg-111"]
  }
}

run "no_load_balancer" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.this.load_balancer) == 0
    error_message = "No load_balancer block without a load balancer"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0
    error_message = "No target group or listener rule without a load balancer"
  }

  assert {
    condition     = aws_ecs_service.this.health_check_grace_period_seconds == null
    error_message = "Grace period must be null without a load balancer"
  }
}

run "grace_period_with_lb" {
  command = plan

  variables {
    container_port = 8000
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    }
  }

  assert {
    condition     = aws_ecs_service.this.health_check_grace_period_seconds == 180
    error_message = "Grace period must be 180 with a load balancer"
  }
}

run "grace_period_is_configurable" {
  command = plan

  variables {
    container_port                    = 8000
    health_check_grace_period_seconds = 300
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    }
  }

  assert {
    condition     = aws_ecs_service.this.health_check_grace_period_seconds == 300
    error_message = "Grace period must follow the input"
  }
}

run "external_target_group" {
  command = plan

  variables {
    container_port = 8000
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    }
  }

  assert {
    condition     = one(aws_ecs_service.this.load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "Service must use the given target group"
  }

  assert {
    condition     = one(aws_ecs_service.this.load_balancer).container_name == "app" && one(aws_ecs_service.this.load_balancer).container_port == 8000
    error_message = "Service must register container app on the container port"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0
    error_message = "Module must not create a target group or listener rule"
  }

  assert {
    condition     = output.target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" && output.target_group_arn_suffix == "targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "Outputs must expose the given ARN and its suffix"
  }
}

run "module_creates_target_group" {
  command = plan

  variables {
    container_port = 8000
    load_balancer = {
      listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-alb/fedcba9876543210/0123456789abcdef"
      vpc_id        = "vpc-0123456789abcdef0"
      priority      = 100
      path_patterns = ["/api/*"]
    }
  }

  override_resource {
    target          = aws_lb_target_group.this[0]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1 && aws_lb_target_group.this[0].name == "alpha-api-8000"
    error_message = "Target group must be named <name>-<container_port>"
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "ip" && aws_lb_target_group.this[0].protocol == "HTTP" && aws_lb_target_group.this[0].port == 8000
    error_message = "Target group must be ip/HTTP on the container port"
  }

  assert {
    condition     = aws_lb_target_group.this[0].vpc_id == "vpc-0123456789abcdef0"
    error_message = "Target group must use vpc_id"
  }

  assert {
    condition     = one(aws_lb_target_group.this[0].health_check).path == "/health" && one(aws_lb_target_group.this[0].health_check).matcher == "200" && one(aws_lb_target_group.this[0].health_check).interval == 10
    error_message = "Health check defaults must apply"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1 && aws_lb_listener_rule.this[0].priority == 100
    error_message = "One listener rule with the given priority must exist"
  }

  assert {
    condition     = one(aws_lb_listener_rule.this[0].action).type == "forward"
    error_message = "Rule must forward"
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this[0].condition : c if length(c.path_pattern) == 1]) == 1 && length([for c in aws_lb_listener_rule.this[0].condition : c if length(c.host_header) == 1]) == 0
    error_message = "Only a path_pattern condition must exist"
  }

  assert {
    condition     = one(aws_ecs_service.this.load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "Service must use the created target group"
  }

  assert {
    condition     = output.target_group_arn_suffix == "targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "Suffix must be split from the created target group ARN"
  }
}

run "listener_rule_host_and_path" {
  command = plan

  variables {
    container_port = 8000
    load_balancer = {
      listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-alb/fedcba9876543210/0123456789abcdef"
      vpc_id        = "vpc-0123456789abcdef0"
      priority      = 100
      host_headers  = ["api.example.com"]
      path_patterns = ["/v1/*"]
      health_check  = { path = "/healthz", matcher = "200-299" }
    }
  }

  override_resource {
    target          = aws_lb_target_group.this[0]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this[0].condition) == 2
    error_message = "Host and path conditions must both exist"
  }

  assert {
    condition     = one(aws_lb_target_group.this[0].health_check).path == "/healthz" && one(aws_lb_target_group.this[0].health_check).matcher == "200-299"
    error_message = "health_check overrides must apply"
  }
}

run "lb_mode_rejects_both" {
  command = plan
  variables {
    container_port = 8000
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/x/0123456789abcdef"
      listener_arn     = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/x/1/2"
      vpc_id           = "vpc-1"
      priority         = 1
      path_patterns    = ["/*"]
    }
  }
  expect_failures = [var.load_balancer]
}

run "lb_mode_rejects_neither" {
  command = plan
  variables {
    container_port = 8000
    load_balancer  = {}
  }
  expect_failures = [var.load_balancer]
}

run "listener_mode_rejects_missing_vpc_id" {
  command = plan
  variables {
    container_port = 8000
    load_balancer = {
      listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/x/1/2"
      priority      = 1
      path_patterns = ["/*"]
    }
  }
  expect_failures = [var.load_balancer]
}

run "listener_mode_rejects_missing_priority" {
  command = plan
  variables {
    container_port = 8000
    load_balancer = {
      listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/x/1/2"
      vpc_id        = "vpc-1"
      path_patterns = ["/*"]
    }
  }
  expect_failures = [var.load_balancer]
}

run "listener_mode_rejects_no_conditions" {
  command = plan
  variables {
    container_port = 8000
    load_balancer = {
      listener_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/x/1/2"
      vpc_id       = "vpc-1"
      priority     = 1
    }
  }
  expect_failures = [var.load_balancer]
}

run "container_port_required_with_lb" {
  command = plan
  variables {
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/x/0123456789abcdef"
    }
  }
  expect_failures = [var.container_port]
}

run "service_connect_configured" {
  command = plan

  variables {
    container_port  = 8000
    service_connect = { namespace_arn = "arn:aws:servicediscovery:ap-northeast-1:111111111111:namespace/ns-abc" }
  }

  assert {
    condition     = one(aws_ecs_service.this.service_connect_configuration).enabled == true && one(aws_ecs_service.this.service_connect_configuration).namespace == "arn:aws:servicediscovery:ap-northeast-1:111111111111:namespace/ns-abc"
    error_message = "service_connect_configuration must be enabled in the namespace"
  }

  assert {
    condition     = one(one(one(aws_ecs_service.this.service_connect_configuration).service).client_alias).dns_name == "alpha-api"
    error_message = "dns_name must default to name"
  }

  assert {
    condition     = one(one(one(aws_ecs_service.this.service_connect_configuration).service).client_alias).port == 8000 && one(one(aws_ecs_service.this.service_connect_configuration).service).port_name == "app"
    error_message = "client alias must use container_port and port name app"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings[0].name == "app"
    error_message = "Port mapping must be named app for Service Connect"
  }
}

run "service_connect_dns_name_override" {
  command = plan

  variables {
    container_port  = 8000
    service_connect = { namespace_arn = "arn:aws:servicediscovery:ap-northeast-1:111111111111:namespace/ns-abc", dns_name = "api" }
  }

  assert {
    condition     = one(one(one(aws_ecs_service.this.service_connect_configuration).service).client_alias).dns_name == "api"
    error_message = "dns_name override must apply"
  }
}

run "no_service_connect_by_default" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.this.service_connect_configuration) == 0
    error_message = "No service connect by default"
  }
}

run "container_port_required_with_service_connect" {
  command = plan
  variables {
    service_connect = { namespace_arn = "arn:aws:servicediscovery:ap-northeast-1:111111111111:namespace/ns-abc" }
  }
  expect_failures = [var.container_port]
}
