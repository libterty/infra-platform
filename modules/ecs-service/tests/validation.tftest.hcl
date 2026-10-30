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

run "cpu_memory_rejects_256_4096" {
  command = plan
  variables {
    cpu    = 256
    memory = 4096
  }
  expect_failures = [var.memory]
}

run "cpu_memory_accepts_1024_2048" {
  command = plan
  variables {
    cpu    = 1024
    memory = 2048
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "1024" && aws_ecs_task_definition.this.memory == "2048"
    error_message = "1024/2048 must be accepted"
  }
}

run "network_rejects_one_subnet" {
  command = plan
  variables {
    network = { subnet_ids = ["subnet-aaa"], security_group_ids = ["sg-111"] }
  }
  expect_failures = [var.network]
}

run "network_rejects_duplicate_subnets" {
  command = plan
  variables {
    network = { subnet_ids = ["subnet-aaa", "subnet-aaa"], security_group_ids = ["sg-111"] }
  }
  expect_failures = [var.network]
}

run "network_rejects_no_security_group" {
  command = plan
  variables {
    network = { subnet_ids = ["subnet-aaa", "subnet-bbb"], security_group_ids = [] }
  }
  expect_failures = [var.network]
}

run "image_rejects_latest" {
  command = plan
  variables { image = "repo:latest" }
  expect_failures = [var.image]
}

run "image_rejects_no_tag" {
  command = plan
  variables { image = "repo" }
  expect_failures = [var.image]
}

run "image_accepts_tag" {
  command = plan
  variables { image = "repo:1.2.3" }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == "repo:1.2.3"
    error_message = "Tagged image must be accepted"
  }
}

run "image_accepts_digest" {
  command = plan
  variables { image = "repo@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }

  assert {
    condition     = endswith(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image, "0123456789abcdef")
    error_message = "Digest image must be accepted"
  }
}

run "name_rejects_27_chars" {
  command = plan
  variables { name = replace(format("%27s", ""), " ", "a") }
  expect_failures = [var.name]
}

run "name_accepts_26_chars" {
  command = plan
  variables { name = replace(format("%26s", ""), " ", "a") }

  assert {
    condition     = length(aws_ecs_service.this[0].name) == 26
    error_message = "26-char name must be accepted"
  }
}

run "cluster_arn_rejects_plain_name" {
  command = plan
  variables { cluster_arn = "my-cluster" }
  expect_failures = [var.cluster_arn]
}

run "retention_rejects_10" {
  command = plan
  variables { log_retention_days = 10 }
  expect_failures = [var.log_retention_days]
}

run "container_port_rejects_out_of_range" {
  command = plan
  variables { container_port = 70000 }
  expect_failures = [var.container_port]
}

run "container_port_rejects_zero" {
  command = plan
  variables { container_port = 0 }
  expect_failures = [var.container_port]
}

run "container_port_accepts_65535" {
  command = plan
  variables { container_port = 65535 }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings[0].containerPort == 65535
    error_message = "65535 must be accepted"
  }
}
