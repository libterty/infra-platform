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

run "no_sidecars_keeps_single_container" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)) == 1
    error_message = "Default sidecars must leave exactly one container"
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "dependsOn")
    error_message = "Main container must not have dependsOn without sidecars"
  }

  assert {
    condition = jsonencode(sort(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]))) == jsonencode([
      "environment", "essential", "image", "linuxParameters", "logConfiguration", "name", "secrets", "stopTimeout"
    ])
    error_message = "Main container must keep exactly its pre-sidecar key set"
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == var.image
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].essential == true
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout == 120
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.initProcessEnabled == true
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-stream-prefix"] == "app"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/ecs/alpha-api"
    )
    error_message = "Main container key fields must be unchanged"
  }
}

run "one_sidecar_order" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0" }]
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)) == 2
    error_message = "One sidecar must yield two containers"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app" && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].name == "collector"
    error_message = "app must come first, then the sidecar"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].image == "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
    error_message = "Sidecar image must be passed through"
  }
}

run "sidecar_logs_share_group" {
  command = plan
  variables {
    sidecars = [
      { name = "collector", image = "example.com/collector:1.0" },
      { name = "router", image = "example.com/router:1.0", log_stream_prefix = "fluent" },
    ]
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.logDriver == "awslogs"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["awslogs-group"] == "/ecs/alpha-api"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["mode"] == "non-blocking"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["max-buffer-size"] == "25m"
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["awslogs-region"] == "ap-northeast-1"
    )
    error_message = "Sidecar must log to the same group with the same awslogs settings"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["awslogs-stream-prefix"] == "collector"
    error_message = "Stream prefix must default to the sidecar name"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[2].logConfiguration.options["awslogs-stream-prefix"] == "fluent"
    error_message = "log_stream_prefix must override the default"
  }
}

run "sidecar_defaults" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/collector:1.0" }]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].linuxParameters.initProcessEnabled == true && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].stopTimeout == 120
    error_message = "Sidecar must set initProcessEnabled and stopTimeout 120"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].essential == false
    error_message = "Sidecar essential must default to false"
  }

  assert {
    condition = length(setintersection(
      toset(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[1])),
      toset(["command", "cpu", "memoryReservation", "healthCheck", "portMappings"])
    )) == 0
    error_message = "Unset optional sidecar fields must be omitted"
  }
}

run "app_waits_only_when_asked" {
  command = plan
  variables {
    sidecars = [
      { name = "collector", image = "example.com/collector:1.0", app_depends_on = "START" },
      { name = "router", image = "example.com/router:1.0" },
    ]
  }

  assert {
    condition     = jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].dependsOn) == jsonencode([{ containerName = "collector", condition = "START" }])
    error_message = "app must depend only on the sidecar that asked for it"
  }
}

run "no_depends_on_when_not_asked" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/collector:1.0" }]
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "dependsOn")
    error_message = "app must not get dependsOn when no sidecar sets app_depends_on"
  }
}

run "sidecar_secrets_value_from" {
  command = plan
  variables {
    sidecars = [{
      name  = "collector"
      image = "example.com/collector:1.0"
      secrets = {
        B_KEY = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/b"
        A_KEY = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:a-AbCdEf"
      }
    }]
  }

  assert {
    condition = jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[1].secrets) == jsonencode([
      { name = "A_KEY", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:a-AbCdEf" },
      { name = "B_KEY", valueFrom = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/b" },
    ])
    error_message = "Secrets must become sorted name/valueFrom pairs"
  }
}

run "sidecar_port_mappings_and_health_check" {
  command = plan
  variables {
    sidecars = [{
      name               = "collector"
      image              = "example.com/collector:1.0"
      command            = ["--config", "env:CFG"]
      cpu                = 128
      memory_reservation = 256
      environment        = { B = "2", A = "1" }
      port_mappings      = [{ container_port = 4317 }, { container_port = 4318, protocol = "udp" }]
      health_check       = { command = ["CMD", "/healthcheck"] }
    }]
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[1].cpu == 128
      && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].memoryReservation == 256
      && jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[1].command) == jsonencode(["--config", "env:CFG"])
    )
    error_message = "cpu, memoryReservation and command must be written through"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[1].environment) == jsonencode([{ name = "A", value = "1" }, { name = "B", value = "2" }])
    error_message = "environment must become sorted name/value pairs"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[1].portMappings) == jsonencode([{ containerPort = 4317, protocol = "tcp" }, { containerPort = 4318, protocol = "udp" }])
    error_message = "portMappings must carry container port and protocol"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)[1].healthCheck) == jsonencode({ command = ["CMD", "/healthcheck"], interval = 10, timeout = 5, retries = 3, startPeriod = 10 })
    error_message = "healthCheck must apply the sidecar defaults"
  }
}

run "main_container_keeps_its_own_port" {
  command = plan
  variables {
    container_port = 8080
    sidecars       = [{ name = "collector", image = "example.com/collector:1.0", port_mappings = [{ container_port = 4317 }] }]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings[0].containerPort == 8080
    error_message = "Main container port must be untouched by sidecar ports"
  }
}

run "sidecar_name_accepts_valid" {
  command = plan
  variables {
    sidecars = [{ name = "log-router-2", image = "example.com/router:1.0" }]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].name == "log-router-2"
    error_message = "A valid sidecar name must be accepted"
  }
}

run "sidecar_name_rejects_app" {
  command = plan
  variables {
    sidecars = [{ name = "app", image = "example.com/x:1.0" }]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_name_rejects_duplicates" {
  command = plan
  variables {
    sidecars = [
      { name = "collector", image = "example.com/x:1.0" },
      { name = "collector", image = "example.com/y:1.0" },
    ]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_name_rejects_uppercase" {
  command = plan
  variables {
    sidecars = [{ name = "App", image = "example.com/x:1.0" }]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_image_rejects_latest" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x:latest" }]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_image_rejects_no_tag" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x" }]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_image_accepts_digest" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }]
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)) == 2
    error_message = "A sha256 digest image must be accepted"
  }
}

run "app_depends_on_rejects_unknown_value" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x:1.0", app_depends_on = "READY" }]
  }
  expect_failures = [var.sidecars]
}

run "app_depends_on_healthy_needs_health_check" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x:1.0", app_depends_on = "HEALTHY" }]
  }
  expect_failures = [var.sidecars]
}

run "app_depends_on_healthy_with_health_check" {
  command = plan
  variables {
    sidecars = [{
      name           = "collector"
      image          = "example.com/x:1.0"
      app_depends_on = "HEALTHY"
      health_check   = { command = ["CMD", "/healthcheck"] }
    }]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].dependsOn[0].condition == "HEALTHY"
    error_message = "HEALTHY with a health check must be accepted"
  }
}

run "sidecar_port_conflicts_with_main" {
  command = plan
  variables {
    container_port = 8080
    sidecars       = [{ name = "collector", image = "example.com/x:1.0", port_mappings = [{ container_port = 8080 }] }]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_port_conflicts_between_sidecars" {
  command = plan
  variables {
    sidecars = [
      { name = "a", image = "example.com/x:1.0", port_mappings = [{ container_port = 4317 }] },
      { name = "b", image = "example.com/y:1.0", port_mappings = [{ container_port = 4317 }] },
    ]
  }
  expect_failures = [var.sidecars]
}

run "sidecar_port_without_main_port_is_accepted" {
  command = plan
  variables {
    sidecars = [{ name = "a", image = "example.com/x:1.0", port_mappings = [{ container_port = 4317 }] }]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].portMappings[0].containerPort == 4317
    error_message = "A sidecar port must be accepted when the main container has none"
  }
}

run "sidecar_secret_rejects_non_arn" {
  command = plan
  variables {
    sidecars = [{ name = "collector", image = "example.com/x:1.0", secrets = { K = "plain-value" } }]
  }
  expect_failures = [var.sidecars]
}
