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
  container_port = 8000
  load_balancer = {
    listener_arn  = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-alb/fedcba9876543210/0123456789abcdef"
    vpc_id        = "vpc-0123456789abcdef0"
    priority      = 100
    path_patterns = ["/api/*"]
  }
}

run "default_creates_only_the_default_variant" {
  command = plan

  override_resource {
    target          = aws_lb_target_group.this[0]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  assert {
    condition     = length(aws_ecs_service.this) == 1 && length(aws_ecs_service.pipeline_managed) == 0 && length(aws_ecs_service.blue_green) == 0
    error_message = "Default inputs must create exactly the default service"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1 && length(aws_lb_listener_rule.blue_green) == 0 && length(aws_lb_target_group.alternate) == 0
    error_message = "Default inputs must keep the single listener rule and target group"
  }

  assert {
    condition     = output.service_name == "alpha-api"
    error_message = "service_name must come from the default variant"
  }
}

run "pipeline_managed_rolling" {
  command = apply

  variables {
    pipeline_managed = true
  }

  override_resource {
    target = aws_lb_target_group.this[0]
    values = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.pipeline_managed) == 1 && length(aws_ecs_service.blue_green) == 0
    error_message = "pipeline_managed with ROLLING must create exactly the pipeline-managed service"
  }

  assert {
    condition     = aws_ecs_service.pipeline_managed[0].task_definition == aws_ecs_task_definition.this.arn
    error_message = "The first deployment must use the module task definition"
  }

  assert {
    condition     = one(aws_ecs_service.pipeline_managed[0].deployment_circuit_breaker).enable == true && one(aws_ecs_service.pipeline_managed[0].deployment_circuit_breaker).rollback == true
    error_message = "The circuit breaker with rollback must stay on"
  }

  assert {
    condition     = aws_ecs_service.pipeline_managed[0].deployment_minimum_healthy_percent == 100 && aws_ecs_service.pipeline_managed[0].deployment_maximum_percent == 200
    error_message = "Rolling percentages must match the default variant"
  }

  assert {
    condition     = one(aws_ecs_service.pipeline_managed[0].load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "The pipeline-managed service must use the module target group"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1 && length(aws_lb_listener_rule.blue_green) == 0 && length(aws_lb_target_group.alternate) == 0
    error_message = "ROLLING must not create the blue/green resources"
  }

  assert {
    condition     = output.service_name == "alpha-api" && output.service_arn == aws_ecs_service.pipeline_managed[0].id
    error_message = "Outputs must follow the pipeline-managed service"
  }

  assert {
    condition     = aws_appautoscaling_target.this.resource_id == "service/alpha-dev/alpha-api"
    error_message = "The scalable target must point at the service"
  }
}

run "blue_green" {
  command = apply

  variables {
    pipeline_managed = true
    deployment = {
      strategy             = "BLUE_GREEN"
      bake_time_in_minutes = 5
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  override_resource {
    target = aws_lb_target_group.this[0]
    values = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  override_resource {
    target = aws_lb_target_group.alternate[0]
    values = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000-alt/fedcba9876543210" }
  }

  override_resource {
    target = aws_lb_listener_rule.blue_green[0]
    values = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/alpha-alb/fedcba9876543210/0123456789abcdef/1111111111111111" }
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.pipeline_managed) == 0 && length(aws_ecs_service.blue_green) == 1
    error_message = "BLUE_GREEN must create exactly the blue/green service"
  }

  assert {
    condition     = one(aws_ecs_service.blue_green[0].deployment_configuration).strategy == "BLUE_GREEN" && one(aws_ecs_service.blue_green[0].deployment_configuration).bake_time_in_minutes == "5"
    error_message = "The service must use the BLUE_GREEN strategy with the bake time"
  }

  assert {
    condition     = one(aws_ecs_service.blue_green[0].deployment_circuit_breaker).enable == true && one(aws_ecs_service.blue_green[0].deployment_circuit_breaker).rollback == true
    error_message = "The circuit breaker with rollback must stay on"
  }

  assert {
    condition     = length(aws_lb_target_group.alternate) == 1 && aws_lb_target_group.alternate[0].name == "alpha-api-8000-alt"
    error_message = "An alternate target group named <name>-<port>-alt must exist"
  }

  assert {
    condition     = aws_lb_target_group.alternate[0].target_type == "ip" && aws_lb_target_group.alternate[0].port == 8000 && one(aws_lb_target_group.alternate[0].health_check).path == "/health"
    error_message = "The alternate target group must match the primary one"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 0 && length(aws_lb_listener_rule.blue_green) == 1 && aws_lb_listener_rule.blue_green[0].priority == 100
    error_message = "BLUE_GREEN must swap in the blue/green listener rule"
  }

  assert {
    condition = { for tg in one(one(aws_lb_listener_rule.blue_green[0].action).forward).target_group : tg.arn => tg.weight } == {
      "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"     = 100
      "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000-alt/fedcba9876543210" = 0
    }
    error_message = "The rule must forward 100/0 to the primary and alternate target groups"
  }

  assert {
    condition     = one(aws_ecs_service.blue_green[0].load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    error_message = "The service must start on the primary target group"
  }

  assert {
    condition = (
      one(one(aws_ecs_service.blue_green[0].load_balancer).advanced_configuration).alternate_target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000-alt/fedcba9876543210" &&
      one(one(aws_ecs_service.blue_green[0].load_balancer).advanced_configuration).production_listener_rule == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/alpha-alb/fedcba9876543210/0123456789abcdef/1111111111111111" &&
      one(one(aws_ecs_service.blue_green[0].load_balancer).advanced_configuration).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure" &&
      one(one(aws_ecs_service.blue_green[0].load_balancer).advanced_configuration).test_listener_rule == null
    )
    error_message = "advanced_configuration must point at the module resources and the given role"
  }

  assert {
    condition     = output.service_arn == aws_ecs_service.blue_green[0].id
    error_message = "Outputs must follow the blue/green service"
  }
}

run "blue_green_without_bake_time" {
  command = plan

  variables {
    pipeline_managed = true
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  override_resource {
    target          = aws_lb_target_group.this[0]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef" }
  }

  assert {
    condition     = one(aws_ecs_service.blue_green[0].deployment_configuration).strategy == "BLUE_GREEN"
    error_message = "BLUE_GREEN must be set even without a bake time"
  }
}

run "worker_without_lb_can_be_pipeline_managed" {
  command = plan

  variables {
    container_port   = null
    load_balancer    = null
    pipeline_managed = true
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.pipeline_managed) == 1 && length(aws_ecs_service.blue_green) == 0
    error_message = "A worker can be pipeline-managed"
  }

  assert {
    condition     = length(aws_ecs_service.pipeline_managed[0].load_balancer) == 0
    error_message = "No load_balancer block without a load balancer"
  }
}

run "rejects_blue_green_without_role" {
  command = plan

  variables {
    pipeline_managed = true
    deployment = {
      strategy = "BLUE_GREEN"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_blue_green_with_invalid_role" {
  command = plan

  variables {
    pipeline_managed = true
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_blue_green_without_pipeline_managed" {
  command = plan

  variables {
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_blue_green_with_external_target_group" {
  command = plan

  variables {
    pipeline_managed = true
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api-8000/0123456789abcdef"
    }
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_blue_green_without_load_balancer" {
  command = plan

  variables {
    container_port   = null
    load_balancer    = null
    pipeline_managed = true
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_unknown_strategy" {
  command = plan

  variables {
    deployment = {
      strategy = "CANARY"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_bake_time_with_rolling" {
  command = plan

  variables {
    deployment = {
      bake_time_in_minutes = 5
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_role_with_rolling" {
  command = plan

  variables {
    deployment = {
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_bake_time_out_of_range" {
  command = plan

  variables {
    pipeline_managed = true
    deployment = {
      strategy             = "BLUE_GREEN"
      bake_time_in_minutes = 1441
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_name_too_long_for_the_alternate_target_group" {
  command = plan

  variables {
    name             = "alpha-api-abcdefghijklmnop"
    container_port   = 18000
    pipeline_managed = true
    deployment = {
      strategy = "BLUE_GREEN"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-infrastructure"
    }
  }

  expect_failures = [var.deployment]
}
