mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
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
  target = module.in.data.aws_ssm_parameter.this["data/table_arn"]
  values = { insecure_value = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-app" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn              = "foundation/kms_key_arn"
      api_secret_arn           = "foundation/api_secret_arn"
      origin_verify_secret_arn = "foundation/origin_verify_secret_arn"
      table_arn                = "data/table_arn"
    } && local.ssm_input_lists == {}
    error_message = "iam may read only the foundation and data keys it needs (design 8.2)"
  }
}

# The api stack names the function exactly like this; its tests pin the same string.
run "naming_rule_of_the_api_function" {
  command = plan

  assert {
    condition     = local.api_function_name == "example-dev-api"
    error_message = "The API Lambda must be named <name_prefix>-api"
  }

  assert {
    condition     = local.api_log_group_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/example-dev-api"
    error_message = "The log group ARN must be built from the function naming rule"
  }
}

run "role_trusts_lambda_in_this_account_only" {
  command = plan

  assert {
    condition = (
      local.api_role.name == "example-dev-api-lambda" &&
      local.api_role.trust.service_principals == ["lambda.amazonaws.com"] &&
      local.api_role.trust.source_account == "111111111111"
    )
    error_message = "The role must be <name_prefix>-api-lambda and trust lambda.amazonaws.com with aws:SourceAccount"
  }

  assert {
    condition     = module.api_role.name == "example-dev-api-lambda"
    error_message = "iam-role must create the role with that name"
  }
}

run "policy_is_attached_to_the_role" {
  command = plan

  assert {
    condition = (
      length(regexall("(?m)^\\s*role_arn\\s*=\\s*module\\.api_role\\.arn\\s*$", file("${path.module}/policies.tf"))) == 1 &&
      length(regexall("(?m)^\\s*policies\\s*=\\s*local\\.api_policies\\s*$", file("${path.module}/policies.tf"))) == 1
    )
    error_message = "The iam-role-policy module must attach local.api_policies to the API role"
  }

  assert {
    condition     = keys(local.api_policies) == ["permissions"]
    error_message = "There must be exactly one inline policy named permissions"
  }
}

run "table_access_is_this_table_and_its_indexes" {
  command = plan

  assert {
    condition = toset(local.api_statements["ReadWriteTable"].Resource) == toset([
      "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-app",
      "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-app/index/*",
    ])
    error_message = "DynamoDB access is limited to the table data publishes and its indexes"
  }

  assert {
    condition = toset(local.api_statements["ReadWriteTable"].Action) == toset([
      "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:PutItem", "dynamodb:UpdateItem",
      "dynamodb:DeleteItem", "dynamodb:BatchWriteItem", "dynamodb:ConditionCheckItem", "dynamodb:DescribeTable",
    ])
    error_message = "The table actions are item reads and writes plus DescribeTable; no table management"
  }
}

run "secrets_are_read_by_full_arn" {
  command = plan

  assert {
    condition = (
      local.api_statements["ReadSecrets"].Action == ["secretsmanager:GetSecretValue"] &&
      toset(local.api_statements["ReadSecrets"].Resource) == toset([
        "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf",
        "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl",
      ])
    )
    error_message = "The role may only read the values of the two secrets foundation publishes"
  }
}

run "kms_and_logs_are_scoped" {
  command = plan

  assert {
    condition = (
      local.api_statements["DecryptWithSharedKey"].Action == ["kms:Decrypt"] &&
      local.api_statements["DecryptWithSharedKey"].Resource == ["arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
    )
    error_message = "KMS use is kms:Decrypt on the shared key only"
  }

  assert {
    condition = (
      toset(local.api_statements["WriteOwnLogs"].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      local.api_statements["WriteOwnLogs"].Resource == ["arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/lambda/example-dev-api:*"]
    )
    error_message = "Log writes are limited to the streams of the API Lambda's own log group"
  }
}

run "has_exactly_these_statements" {
  command = plan

  assert {
    condition     = toset(keys(local.api_statements)) == toset(["ReadWriteTable", "ReadSecrets", "DecryptWithSharedKey", "WriteOwnLogs"])
    error_message = "A new statement must come with a test"
  }
}

# No statement may use Resource "*": everything the API Lambda touches has an ARN.
run "no_policy_uses_a_wildcard_resource" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for p in values(local.api_policies) : [
        for s in jsondecode(p).Statement : [
          for res in s.Resource : res != "*" && !startswith(res, "*") && !can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:\\*$", res))
        ]
      ]
    ]))
    error_message = "No Resource may be * or an account-wide wildcard"
  }

  assert {
    condition = alltrue(flatten([
      for p in values(local.api_policies) : [
        for s in jsondecode(p).Statement : s.Effect == "Allow" && !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")])
      ]
    ]))
    error_message = "Statements must be Allow and may not use * or service:* actions"
  }
}

run "publishes_exactly_the_role_arn" {
  command = plan

  override_module {
    target = module.api_role
    outputs = {
      arn  = "arn:aws:iam::111111111111:role/example-dev-api-lambda"
      name = "example-dev-api-lambda"
    }
  }

  assert {
    condition     = local.published_strings == { api_role_arn = "arn:aws:iam::111111111111:role/example-dev-api-lambda" }
    error_message = "iam must publish exactly api_role_arn (design 8.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { api_role_arn = "/example/dev/iam/api_role_arn" }
    error_message = "ssm-publish must write the key under the iam path"
  }
}

run "sit_follows_env_and_account" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition = (
      local.api_role.name == "example-sit-api-lambda" &&
      local.api_role.trust.source_account == "222222222222" &&
      local.api_statements["WriteOwnLogs"].Resource == ["arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/lambda/example-sit-api:*"]
    )
    error_message = "Names and ARNs must follow the env and account"
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
