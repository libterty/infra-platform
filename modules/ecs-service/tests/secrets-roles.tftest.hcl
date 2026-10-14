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

run "secrets_use_value_from" {
  command = plan

  variables {
    environment = { LOG_LEVEL = "info" }
    secrets = {
      API_KEY = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha/api-AbCdEf:key::"
      DB_URL  = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/db-url"
    }
  }

  assert {
    condition = toset(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets) == toset([
      { name = "API_KEY", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha/api-AbCdEf:key::" },
      { name = "DB_URL", valueFrom = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/db-url" },
    ])
    error_message = "Each secret must be {name, valueFrom}"
  }

  assert {
    condition     = [for e in jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment : e.name] == ["LOG_LEVEL"]
    error_message = "Secrets must not appear in environment"
  }
}

run "secret_arn_rejects_plain_name" {
  command = plan
  variables { secrets = { X = "my-secret" } }
  expect_failures = [var.secrets]
}

run "secret_arn_accepts_secretsmanager" {
  command = plan
  variables { secrets = { X = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:x-AbCdEf" } }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets) == 1
    error_message = "Secrets Manager ARN must be accepted"
  }
}

run "secret_arn_accepts_ssm" {
  command = plan
  variables { secrets = { X = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/x" } }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets) == 1
    error_message = "SSM parameter ARN must be accepted"
  }
}

run "role_arns_passed_through" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.execution_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
    error_message = "execution_role_arn must pass through"
  }

  assert {
    condition     = aws_ecs_task_definition.this.task_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-alpha-api-task"
    error_message = "task_role_arn must pass through"
  }
}

run "execution_role_rejects_plain_name" {
  command = plan
  variables { execution_role_arn = "my-role" }
  expect_failures = [var.execution_role_arn]
}

run "execution_role_rejects_user_arn" {
  command = plan
  variables { execution_role_arn = "arn:aws:iam::123456789012:user/x" }
  expect_failures = [var.execution_role_arn]
}

run "task_role_rejects_plain_name" {
  command = plan
  variables { task_role_arn = "my-role" }
  expect_failures = [var.task_role_arn]
}

run "task_role_rejects_user_arn" {
  command = plan
  variables { task_role_arn = "arn:aws:iam::123456789012:user/x" }
  expect_failures = [var.task_role_arn]
}
