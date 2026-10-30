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

run "task_definition_defaults" {
  command = plan

  assert {
    condition     = contains(aws_ecs_task_definition.this.requires_compatibilities, "FARGATE") && aws_ecs_task_definition.this.network_mode == "awsvpc"
    error_message = "Task definition must be FARGATE and awsvpc"
  }

  assert {
    condition     = one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64" && one(aws_ecs_task_definition.this.runtime_platform).operating_system_family == "LINUX"
    error_message = "Runtime platform must default to LINUX ARM64"
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "512" && aws_ecs_task_definition.this.memory == "1024"
    error_message = "cpu/memory must default to 512/1024"
  }

  assert {
    condition     = aws_ecs_task_definition.this.family == "alpha-api"
    error_message = "family must equal name"
  }
}

run "container_defaults" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app"
    error_message = "Container name must be app"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.initProcessEnabled == true
    error_message = "initProcessEnabled must be true"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout == 120
    error_message = "stopTimeout must be 120"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.logDriver == "awslogs"
    error_message = "Log driver must be awslogs"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["mode"] == "non-blocking"
    error_message = "Log mode must be non-blocking"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/ecs/alpha-api"
    error_message = "Log group must be the module-created one"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-region"] == "ap-northeast-1"
    error_message = "Region must come from cluster_arn"
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "portMappings") && !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "healthCheck")
    error_message = "No port mapping or health check without container_port and container_health_check"
  }
}

run "container_port_and_health_check_when_set" {
  command = plan

  variables {
    container_port = 8000
    container_health_check = {
      command = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
    }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings[0].containerPort == 8000
    error_message = "containerPort must be passed through"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.startPeriod == 60 && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.retries == 3
    error_message = "Health check defaults must apply"
  }
}

run "service_defaults" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.this[0].network_configuration).assign_public_ip == false
    error_message = "assign_public_ip must be false"
  }

  assert {
    condition     = aws_ecs_service.this[0].deployment_minimum_healthy_percent == 100 && aws_ecs_service.this[0].deployment_maximum_percent == 200
    error_message = "Deployment must be 100/200"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].deployment_circuit_breaker).enable == true && one(aws_ecs_service.this[0].deployment_circuit_breaker).rollback == true
    error_message = "Circuit breaker with rollback must be on"
  }

  assert {
    condition     = aws_ecs_service.this[0].propagate_tags == "SERVICE" && aws_ecs_service.this[0].availability_zone_rebalancing == "ENABLED"
    error_message = "propagate_tags and AZ rebalancing must be set"
  }

  assert {
    condition     = aws_ecs_service.this[0].wait_for_steady_state == false && aws_ecs_service.this[0].enable_execute_command == false
    error_message = "wait_for_steady_state and ECS Exec must default to false"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "FARGATE"
    error_message = "Default strategy must be FARGATE"
  }

  assert {
    condition     = aws_ecs_service.this[0].cluster == "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev" && aws_ecs_service.this[0].desired_count == 2
    error_message = "cluster and desired_count must pass through"
  }
}

run "log_group_per_service" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/ecs/alpha-api" && aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Log group must default to /ecs/<name> with 30 days"
  }
}

run "log_group_name_override" {
  command = plan

  variables {
    log_group_name = "/custom/alpha"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/custom/alpha"
    error_message = "log_group_name must be used"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/custom/alpha"
    error_message = "Container must log to the overridden group"
  }
}

run "network_passed_through" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.this[0].network_configuration).subnets == toset(["subnet-aaa", "subnet-bbb"])
    error_message = "subnets must equal the input"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].network_configuration).security_groups == toset(["sg-111"])
    error_message = "security_groups must equal the input"
  }
}

run "x86_override" {
  command = plan

  variables {
    cpu_architecture = "X86_64"
  }

  assert {
    condition     = one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "X86_64"
    error_message = "cpu_architecture must follow the input"
  }
}

run "execute_command_when_enabled" {
  command = plan

  variables {
    enable_execute_command = true
  }

  assert {
    condition     = aws_ecs_service.this[0].enable_execute_command == true
    error_message = "enable_execute_command must follow the input"
  }
}

run "tags_are_applied" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_ecs_service.this[0].tags == tomap({ Project = "alpha", Name = "alpha-api" })
    error_message = "Service must carry tags plus Name"
  }

  assert {
    condition     = aws_ecs_task_definition.this.tags == tomap({ Project = "alpha", Name = "alpha-api" })
    error_message = "Task definition must carry tags plus Name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Project = "alpha", Name = "/ecs/alpha-api" })
    error_message = "Log group must carry tags plus its own Name"
  }
}

run "outputs_without_lb" {
  command = plan

  assert {
    condition     = output.container_name == "app" && output.cluster_name == "alpha-dev" && output.task_definition_family == "alpha-api"
    error_message = "Static outputs must be filled"
  }

  assert {
    condition     = output.target_group_arn == null && output.target_group_arn_suffix == null
    error_message = "Target group outputs must be null without a load balancer"
  }

  assert {
    condition     = output.autoscaling_resource_id == "service/alpha-dev/alpha-api"
    error_message = "autoscaling_resource_id must be service/<cluster>/<service>"
  }
}
