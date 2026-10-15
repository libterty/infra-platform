mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"

  services = {
    api = {
      image_tag      = "abc1234"
      container_port = 8080
      desired_count  = 2
      max_capacity   = 6
      alb = {
        priority            = 100
        path_patterns       = ["/api/*"]
        requests_per_target = 300
      }
    }
    worker = {
      image_tag      = "abc1234"
      container_port = 9000
    }
  }
}

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

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == {
        alarm_topic_arn        = "foundation/alarm_topic_arn"
        app_secret_arn         = "foundation/app_secret_arn"
        vpc_id                 = "network/vpc_id"
        data_access            = "network/data_access"
        role_ecs_execution_arn = "iam-base/role_ecs_execution_arn"
        database               = "data/database"
        alb_arn_suffix         = "loadbalancer/alb_arn_suffix"
        listener_arn           = "loadbalancer/listener_arn"
      } &&
      local.ssm_input_lists == {
        services       = "containerimage/services"
        subnet_ids_app = "network/subnet_ids_app"
      }
    )
    error_message = "application must read exactly the keys it uses from the earlier stacks"
  }

  assert {
    condition = local.ssm_service_strings == {
      ecr_api_url          = "containerimage/ecr_api_url"
      ecr_worker_url       = "containerimage/ecr_worker_url"
      sg_api_id            = "network/sg_api_id"
      sg_worker_id         = "network/sg_worker_id"
      role_api_task_arn    = "iam-app/role_api_task_arn"
      role_worker_task_arn = "iam-app/role_worker_task_arn"
      ecs_exec_api         = "iam-app/ecs_exec_api"
      ecs_exec_worker      = "iam-app/ecs_exec_worker"
    }
    error_message = "application must read the image URL, security group, task role and ECS Exec flag of every service"
  }
}

# application is the last stack: nothing downstream reads from it.
run "publishes_nothing" {
  command = plan

  assert {
    condition     = !contains(fileset(path.module, "*.tf"), "ssm-outputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-publish")])
    error_message = "application must not publish to SSM"
  }
}

run "services_must_match_containerimage_extra_rejected" {
  command = plan

  variables {
    services = {
      api    = { image_tag = "abc1234", container_port = 8080 }
      worker = { image_tag = "abc1234", container_port = 9000 }
      batch  = { image_tag = "abc1234", container_port = 9100 }
    }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_batch_url"]
    values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-batch" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["network/sg_batch_id"]
    values = { insecure_value = "sg-0123456789abcdef2" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["iam-app/role_batch_task_arn"]
    values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-batch-task" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["iam-app/ecs_exec_batch"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  expect_failures = [terraform_data.services_match_containerimage]
}

run "services_must_match_containerimage_missing_rejected" {
  command = plan

  variables {
    services = {
      api = { image_tag = "abc1234", container_port = 8080 }
    }
  }

  expect_failures = [terraform_data.services_match_containerimage]
}

run "services_matching_containerimage_passes" {
  command = plan

  assert {
    condition     = toset(keys(var.services)) == toset(module.in.lists["services"]) && length(module.service) == 2
    error_message = "Services equal to the containerimage list must pass and each get an ECS service"
  }
}

run "roles_from_iam_stacks" {
  command = plan

  assert {
    condition     = alltrue([for s in values(local.service_inputs) : s.execution_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"])
    error_message = "Every service must use the shared execution role from iam-base"
  }

  assert {
    condition     = local.service_inputs["api"].task_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-api-task" && local.service_inputs["worker"].task_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-worker-task"
    error_message = "Every service must use its own task role from iam-app"
  }
}

run "image_from_containerimage" {
  command = plan

  assert {
    condition     = local.service_inputs["api"].image == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-api:abc1234"
    error_message = "The image must be the repository URL published by containerimage plus the tag from tfvars"
  }

  assert {
    condition     = local.service_inputs["worker"].image == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-worker:abc1234"
    error_message = "Every service must get its own repository"
  }
}

run "network_from_network_stack" {
  command = plan

  assert {
    condition     = alltrue([for s in values(local.service_inputs) : tolist(s.network.subnet_ids) == tolist(["subnet-0app1", "subnet-0app2"])])
    error_message = "Services must run in the app tier subnets"
  }

  assert {
    condition     = local.service_inputs["api"].network.security_group_ids == ["sg-0123456789abcdef0"] && local.service_inputs["worker"].network.security_group_ids == ["sg-0123456789abcdef1"]
    error_message = "Every service must use its own security group from network"
  }
}

run "listener_from_loadbalancer" {
  command = plan

  assert {
    condition = (
      local.service_inputs["api"].load_balancer.listener_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev-alb/0123456789abcdef/fedcba9876543210" &&
      local.service_inputs["api"].load_balancer.vpc_id == "vpc-0123456789abcdef0" &&
      local.service_inputs["api"].load_balancer.priority == 100
    )
    error_message = "The listener rule must use the listener of loadbalancer and the VPC of network"
  }

  assert {
    condition     = local.service_inputs["api"].load_balancer.alb_arn_suffix == "app/alpha-dev-alb/0123456789abcdef" && local.alarm_inputs.alb_arn_suffix == "app/alpha-dev-alb/0123456789abcdef"
    error_message = "ecs-service and ecs-service-alarms must both get the ALB ARN suffix of loadbalancer"
  }

  assert {
    condition     = local.service_inputs["worker"].load_balancer == null
    error_message = "A service without alb settings must not be attached to the ALB"
  }
}

run "database_env" {
  command = plan

  assert {
    condition = local.service_inputs["api"].environment == tomap({
      DB_HOST        = "alpha-dev-db.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      DB_READER_HOST = "alpha-dev-db-ro.endpoint.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      DB_PORT        = "5432"
      DB_NAME        = "app"
      DB_SECRET_ARN  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"
    })
    error_message = "A service on the data_access list must get exactly the five DB variables"
  }

  assert {
    condition     = length(local.service_inputs["worker"].environment) == 0
    error_message = "A service that is not on the data_access list must get no DB variables"
  }

  assert {
    condition     = !strcontains(jsonencode([for s in values(local.service_inputs) : s.secrets]), "rds!")
    error_message = "The database secret must not be injected through secrets; the task role reads it from DB_SECRET_ARN"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !strcontains(file("${path.module}/${f}"), "database.proxy_endpoint") && !strcontains(file("${path.module}/${f}"), "database.deployment") &&
      !strcontains(file("${path.module}/${f}"), "database.writer_endpoint") && !strcontains(file("${path.module}/${f}"), "database.reader_endpoint")
    ])
    error_message = "The application must not depend on proxy_endpoint, deployment, writer_endpoint or reader_endpoint"
  }
}

run "app_secret_via_value_from" {
  command = plan

  assert {
    condition     = alltrue([for s in values(local.service_inputs) : s.secrets == { APP_SECRET = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf" }])
    error_message = "The application secret of foundation must be injected as a secret (valueFrom)"
  }
}

run "no_db_env_when_disabled" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition     = alltrue([for s in values(local.service_inputs) : length(s.environment) == 0]) && length(local.db_environment) == 0
    error_message = "Without a database no service may get DB variables"
  }
}

run "exec_flag_from_iam_app_enabled" {
  command = plan

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["iam-app/ecs_exec_api"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  assert {
    condition     = local.service_inputs["api"].enable_execute_command == true && local.service_inputs["worker"].enable_execute_command == false
    error_message = "enable_execute_command must follow the flag published by iam-app, service by service"
  }
}

run "exec_flag_from_iam_app_disabled" {
  command = plan

  assert {
    condition     = alltrue([for s in values(local.service_inputs) : s.enable_execute_command == false])
    error_message = "With every flag false no service may enable ECS Exec"
  }

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ecs_exec_services")])
    error_message = "application has no ECS Exec variable of its own; the switch lives in iam-app"
  }
}

run "alarms_wired_to_foundation_topic" {
  command = plan

  assert {
    condition     = local.alarm_inputs.sns_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    error_message = "Service alarms must notify the topic of foundation"
  }

  assert {
    condition     = length(module.service_alarms) == 2 && toset(keys(module.service_alarms)) == toset(["api", "worker"])
    error_message = "ecs-service-alarms must be called once per service"
  }
}

run "names_match_the_execution_role_scope" {
  command = plan

  assert {
    condition     = alltrue([for s in values(module.service) : startswith(s.log_group_name, "/ecs/alpha-dev-")])
    error_message = "Log groups must be /ecs/<name_prefix>-<service>, the pattern the execution role of iam-base is limited to"
  }

  assert {
    condition     = local.service_inputs["api"].name == "alpha-dev-api" && module.cluster.cluster_name == "alpha-dev-app"
    error_message = "Service and cluster names must follow <name_prefix>-<name>"
  }
}

run "service_settings_reach_the_module" {
  command = plan

  assert {
    condition = (
      local.service_inputs["api"].autoscaling.min_capacity == 2 && local.service_inputs["api"].autoscaling.max_capacity == 6 &&
      local.service_inputs["api"].autoscaling.target_tracking.requests_per_target == 300
    )
    error_message = "max_capacity must turn autoscaling on with the desired count as the minimum"
  }

  assert {
    condition     = local.service_inputs["worker"].autoscaling == null && local.service_inputs["worker"].desired_count == 2
    error_message = "Without max_capacity the task count must stay fixed"
  }

  assert {
    condition     = local.service_inputs["api"].cpu_architecture == "ARM64" && local.service_inputs["api"].cpu == 512 && local.service_inputs["api"].memory == 1024
    error_message = "Defaults must be ARM64, 512 CPU units and 1024 MiB"
  }
}

run "alb_service_needs_a_container_port" {
  command = plan

  variables {
    services = {
      api    = { image_tag = "abc1234", alb = { priority = 100, path_patterns = ["/api/*"] } }
      worker = { image_tag = "abc1234", container_port = 9000 }
    }
  }

  expect_failures = [var.services]
}

run "hyphenated_service_name" {
  command = plan

  variables {
    services = {
      order-api = { image_tag = "abc1234", container_port = 8080 }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
    values = { insecure_value = "order-api" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_order_api_url"]
    values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-order-api" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["network/sg_order_api_id"]
    values = { insecure_value = "sg-0123456789abcdef2" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["iam-app/role_order_api_task_arn"]
    values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-order-api-task" }
  }

  override_data {
    target = module.in_services.data.aws_ssm_parameter.this["iam-app/ecs_exec_order_api"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition = toset(keys(local.ssm_service_strings)) == toset([
      "ecr_order_api_url", "sg_order_api_id", "role_order_api_task_arn", "ecs_exec_order_api",
    ])
    error_message = "A hyphen in the service name must become an underscore in the SSM keys"
  }

  assert {
    condition     = local.service_inputs["order-api"].name == "alpha-dev-order-api"
    error_message = "The service name keeps the hyphen"
  }
}

run "no_cross_stack_id_in_variables" {
  command = plan

  assert {
    condition     = length(regexall("(?m)^variable \"[a-z_]*(_arn|_id|_ids|_url|_arns)\"", file("${path.module}/variables.tf"))) == 0
    error_message = "variables.tf must not take ARNs, IDs or URLs of other stacks; read them from SSM"
  }
}

run "observability_off_by_default" {
  command = plan

  assert {
    condition     = length(var.log_alarms) == 0 && length(var.xray_sampling_rules) == 0 && length(var.xray_groups) == 0
    error_message = "log_alarms, xray_sampling_rules and xray_groups must default to empty"
  }

  assert {
    condition     = length(module.log_alarms) == 0 && length(module.xray.sampling_rule_arns) == 0 && length(module.xray.group_arns) == 0
    error_message = "Empty inputs must create no log alarm, sampling rule or group"
  }
}

run "log_alarms_wired" {
  command = plan

  variables {
    log_alarms = {
      api = {
        audit_write_failed = {
          pattern     = "\"audit_write_failed\""
          metric_name = "AuditWriteFailed"
          description = "The api could not write an audit record."
        }
      }
    }
  }

  assert {
    condition     = local.log_alarm_inputs["api"].log_group_name == "/ecs/alpha-dev-api" && local.log_alarm_inputs["api"].log_group_name == module.service["api"].log_group_name
    error_message = "The metric filter must read the log group of the api service"
  }

  assert {
    condition     = local.log_alarm_inputs["api"].sns_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    error_message = "Log alarms must notify the topic of foundation"
  }

  assert {
    condition     = toset(keys(module.log_alarms["api"].alarm_names)) == toset(["audit_write_failed"]) && local.log_alarm_inputs["api"].namespace == "alpha/dev"
    error_message = "One alarm per key, in the project/env namespace"
  }
}

run "log_alarms_services_known" {
  command = plan

  variables {
    log_alarms = {
      ghost = {
        audit_write_failed = {
          pattern     = "\"audit_write_failed\""
          metric_name = "AuditWriteFailed"
          description = "The ghost service could not write an audit record."
        }
      }
    }
  }

  expect_failures = [terraform_data.log_alarm_services_are_known]
}

run "xray_rules_and_groups_wired" {
  command = plan

  variables {
    xray_sampling_rules = {
      all = { priority = 100, fixed_rate = 1 }
    }
    xray_groups = {
      errors = { filter_expression = "fault = true OR error = true" }
    }
  }

  assert {
    condition     = toset(keys(module.xray.sampling_rule_arns)) == toset(["all"]) && toset(keys(module.xray.group_arns)) == toset(["errors"])
    error_message = "Every rule and group must reach the xray module"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
