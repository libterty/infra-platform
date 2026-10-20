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

run "default_task_definition_has_no_system_controls" {
  command = plan

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "systemControls")
    error_message = "Without system_controls the container definition must not contain a systemControls key"
  }
}

run "empty_system_controls_keeps_task_definition_identical" {
  command = plan

  variables {
    system_controls = {}
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "systemControls")
    error_message = "An empty system_controls must not add the key"
  }
}

run "system_controls_added_sorted_by_namespace" {
  command = plan

  variables {
    system_controls = {
      "net.ipv4.tcp_keepalive_time"  = "240"
      "net.ipv4.ip_local_port_range" = "20000 65000"
    }
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].systemControls == [
      { namespace = "net.ipv4.ip_local_port_range", value = "20000 65000" },
      { namespace = "net.ipv4.tcp_keepalive_time", value = "240" },
    ]
    error_message = "systemControls must list namespace/value pairs sorted by namespace"
  }
}

run "system_controls_apply_to_app_container_only" {
  command = plan

  variables {
    system_controls = { "net.ipv4.tcp_keepalive_time" = "240" }
    sidecars = [{
      name  = "collector"
      image = "public.ecr.aws/example/collector:1.0.0"
    }]
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[1]), "systemControls")
    error_message = "Sidecars must not receive systemControls"
  }
}
