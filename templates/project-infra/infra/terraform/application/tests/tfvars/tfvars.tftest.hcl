# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/app_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/data_access"]
  values = { insecure_value = "{\"db\":[\"api\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_ecs_execution_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = { insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"app_endpoint\":\"alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com\",\"app_reader_endpoint\":\"alpha-dev-db-ro.endpoint.proxy-abc.ap-northeast-1.rds.amazonaws.com\",\"writer_endpoint\":\"alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com\",\"reader_endpoint\":\"alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com\",\"proxy_endpoint\":\"alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com\",\"has_reader\":true}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/alb_arn_suffix"]
  values = { insecure_value = "app/alpha-dev-alb/0123456789abcdef" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/listener_arn"]
  values = { insecure_value = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev-alb/0123456789abcdef/fedcba9876543210" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-app/tracing"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-app/agent_access"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_api_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-api" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["network/sg_api_id"]
  values = { insecure_value = "sg-0123456789abcdef0" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["iam-app/role_api_task_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-api-task" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["iam-app/ecs_exec_api"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_worker_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-worker" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["network/sg_worker_id"]
  values = { insecure_value = "sg-0123456789abcdef1" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["iam-app/role_worker_task_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-worker-task" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["iam-app/ecs_exec_worker"]
  values = { insecure_value = "{\"enabled\":false}" }
}

run "tfvars_deploy_every_service" {
  command = plan

  assert {
    condition     = length(var.services) > 0 && length(module.service) == length(var.services) && length(module.service_alarms) == length(var.services)
    error_message = "Every service in tfvars must get an ECS service and alarms"
  }

  assert {
    condition     = alltrue([for s in values(var.services) : s.image_tag != "latest"])
    error_message = "Image tags must be unique, never latest"
  }
}

run "tfvars_scale_in_production" {
  command = plan

  assert {
    condition     = var.env != "prod" || alltrue([for s in values(var.services) : s.max_capacity != null && s.desired_count >= 2])
    error_message = "Production services must autoscale and run at least two tasks"
  }
}

run "tfvars_collector_setting_is_valid_when_given" {
  command = plan

  assert {
    condition     = var.adot_collector == null || (var.adot_collector.tag != "latest" && contains(["public", "mirror"], var.adot_collector.source))
    error_message = "A tfvars file that sets adot_collector must use an explicit tag and a known source"
  }
}
