# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_rds_proxy_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/data_access"]
  values = { insecure_value = "{\"db\":[\"api\",\"worker\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = {
    insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"has_reader\":false}"
  }
}

run "tfvars_create_a_task_role_per_service" {
  command = plan

  assert {
    condition     = length(module.task_role) == 2 && length(module.proxy_secret_access) == 1
    error_message = "Every service needs a task role and the Proxy role needs its secret policy"
  }

  assert {
    condition     = alltrue([for s in var.ecs_exec_services : contains(["api", "worker"], s)])
    error_message = "ecs_exec_services in tfvars must name known services"
  }
}
