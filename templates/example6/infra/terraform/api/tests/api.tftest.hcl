mock_provider "aws" {}

variables {
  project                   = "example"
  env                       = "dev"
  expected_account_id       = "111111111111"
  api_image_tag             = "0.1.0"
  api_reserved_concurrency  = 10
  api_throttling            = { rate_limit = 50, burst_limit = 100 }
  origin_verify_header_name = "X-Origin-Verify"
  log_retention_days        = 30
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/api_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/origin_verify_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["auth/issuer_url"]
  values = { insecure_value = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["auth/spa_client_id"]
  values = { insecure_value = "1example23456789abcdefghij" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/table_name"]
  values = { insecure_value = "example-dev-app" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-api-lambda" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      api_repository_url       = "containerimage/api_repository_url"
      kms_key_arn              = "foundation/kms_key_arn"
      alarm_topic_arn          = "foundation/alarm_topic_arn"
      api_secret_arn           = "foundation/api_secret_arn"
      origin_verify_secret_arn = "foundation/origin_verify_secret_arn"
      issuer_url               = "auth/issuer_url"
      spa_client_id            = "auth/spa_client_id"
      table_name               = "data/table_name"
      api_role_arn             = "iam/api_role_arn"
    } && local.ssm_input_lists == {}
    error_message = "api may read only the keys it needs from earlier stacks (design 8.2)"
  }
}

# Design K12 and section 4.3: only the explicit health check is public; every other route needs a Cognito JWT.
run "every_route_has_an_authorizer_except_health" {
  command = plan

  assert {
    condition = alltrue([
      for k, r in local.api_routes : k == "GET /api/health" ? (r.public && r.authorizer == null) : (!r.public && r.authorizer == "cognito" && length(r.scopes) > 0)
    ])
    error_message = "Every route except GET /api/health must use the cognito authorizer with a scope; only the health route is public"
  }

  assert {
    condition     = length([for r in values(local.api_routes) : r if r.public]) == 1
    error_message = "Exactly one route may be public"
  }

  assert {
    condition     = alltrue([for k in keys(local.api_routes) : can(regex("^[A-Z]+ /api/", k))])
    error_message = "Every route must sit under /api/, the path CloudFront sends to the API (design K16)"
  }

  assert {
    condition = (
      local.api_routes["GET /api/items"].scopes == ["api/read"] &&
      local.api_routes["POST /api/items"].scopes == ["api/write"]
    )
    error_message = "Reads need api/read and writes need api/write"
  }
}

run "authorizer_checks_the_issuer_and_the_spa_client" {
  command = plan

  assert {
    condition = local.api.jwt_authorizers == {
      cognito = {
        issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
        audience = ["1example23456789abcdefghij"]
      }
    }
    error_message = "The JWT authorizer must use the auth issuer and the SPA client id as audience"
  }
}

# Design K16 and 8.3: CloudFront needs the execute-api URL, and the stage throttling caps direct calls.
run "api_settings" {
  command = plan

  assert {
    condition = (
      local.api.name == "example-dev-api" &&
      local.api.disable_execute_api_endpoint == false &&
      local.api.throttling == { rate_limit = 50, burst_limit = 100 }
    )
    error_message = "The API keeps the execute-api URL for CloudFront and uses the tfvars throttling"
  }

  assert {
    condition     = !strcontains(file("${path.module}/api.tf"), "custom_domain") && !strcontains(file("${path.module}/api.tf"), "cors")
    error_message = "The API has no custom domain and no CORS: the SPA and the API share app.<zone> (design K16)"
  }
}

run "access_log_group_uses_the_cmk" {
  command = plan

  assert {
    condition = local.access_log_group == {
      name           = "/aws/apigateway/example-dev-api-access"
      retention_days = 30
      kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
    error_message = "The access log group must be encrypted with the shared key and keep the tfvars retention"
  }
}

# Design K17: the Lambda compares the origin verify header with the secret, so it needs both the name and the ARN.
run "lambda_gets_the_origin_verify_header_name_and_secret" {
  command = plan

  assert {
    condition = local.api_function.environment == {
      TABLE_NAME                = "example-dev-app"
      API_SECRET_ARN            = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf"
      ORIGIN_VERIFY_HEADER_NAME = "X-Origin-Verify"
      ORIGIN_VERIFY_SECRET_ARN  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl"
    }
    error_message = "The Lambda must get the table name, both secret ARNs and the origin verify header name"
  }
}

# Design 8.3 and iam/naming.tf.
run "lambda_settings" {
  command = plan

  assert {
    condition = (
      local.api_function.name == "example-dev-api" &&
      local.api_function.image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-dev-api:0.1.0" &&
      local.api_function.role_arn == "arn:aws:iam::111111111111:role/example-dev-api-lambda" &&
      local.api_function.architectures == ["arm64"] &&
      local.api_function.memory_size == 512 &&
      local.api_function.timeout == 10 &&
      local.api_function.reserved_concurrent_executions == 10
    )
    error_message = "The Lambda must be <name_prefix>-api from the repository image, arm64, 512 MB, 10 s, with the tfvars concurrency"
  }

  assert {
    condition     = module.function.function_name == "example-dev-api"
    error_message = "lambda-function must create the function with the name iam built its log permissions for"
  }
}

run "only_this_api_may_invoke_the_lambda" {
  command = plan

  override_module {
    target = module.api
    outputs = {
      api_id           = "a1b2c3d4e5"
      api_endpoint     = "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com"
      execution_arn    = "arn:aws:execute-api:ap-northeast-1:111111111111:a1b2c3d4e5"
      stage_invoke_url = "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com/"
      domain_target    = null
    }
  }

  assert {
    condition = local.api_function.permissions == {
      apigateway = {
        principal  = "apigateway.amazonaws.com"
        source_arn = "arn:aws:execute-api:ap-northeast-1:111111111111:a1b2c3d4e5/*/*"
      }
    }
    error_message = "Only API Gateway, for this API's execution ARN, may invoke the Lambda"
  }

  assert {
    condition     = local.alarms["api_5xx"].metric.dimensions == { ApiId = "a1b2c3d4e5" }
    error_message = "The 5xx alarm must watch this API"
  }

  assert {
    condition     = local.published_strings == { api_endpoint = "a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com" }
    error_message = "api must publish exactly api_endpoint, as a host name for the CloudFront origin (design 8.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { api_endpoint = "/example/dev/api/api_endpoint" }
    error_message = "ssm-publish must write the key under the api path"
  }
}

run "alarms_watch_lambda_errors_and_api_5xx" {
  command = plan

  assert {
    condition = (
      toset(keys(local.alarms)) == toset(["lambda_errors", "api_5xx"]) &&
      local.alarms["lambda_errors"].metric.namespace == "AWS/Lambda" &&
      local.alarms["lambda_errors"].metric.metric_name == "Errors" &&
      local.alarms["lambda_errors"].metric.dimensions == { FunctionName = "example-dev-api" } &&
      local.alarms["api_5xx"].metric.namespace == "AWS/ApiGateway" &&
      local.alarms["api_5xx"].metric.metric_name == "5xx"
    )
    error_message = "There must be a Lambda Errors alarm and an API 5xx alarm"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*sns_topic_arns\\s*=\\s*\\[module\\.in\\.strings\\[\"alarm_topic_arn\"\\]\\]\\s*$", file("${path.module}/alarms.tf"))) == 1
    error_message = "The alarms must notify the foundation alarm topic"
  }
}

run "sit_follows_env_and_account" {
  command = plan

  variables {
    env                      = "sit"
    expected_account_id      = "222222222222"
    api_reserved_concurrency = 50
    api_throttling           = { rate_limit = 200, burst_limit = 400 }
    log_retention_days       = 90
  }

  assert {
    condition = (
      local.api_function.name == "example-sit-api" &&
      local.api.name == "example-sit-api" &&
      local.access_log_group.name == "/aws/apigateway/example-sit-api-access"
    )
    error_message = "Names must follow the env"
  }
}

run "origin_verify_header_name_rejected" {
  command = plan

  variables {
    origin_verify_header_name = "X Origin Verify"
  }

  expect_failures = [var.origin_verify_header_name]
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
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
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
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
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
