mock_provider "aws" {}

variables {
  name = "alpha-dev-ecs-execution"
  trust = {
    service_principals = ["ecs-tasks.amazonaws.com"]
  }
}

run "trust_principals_only" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Service = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"] }
    error_message = "Trust principal must be exactly the given service principals"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "Trust policy must have a single statement"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRole" && jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Effect == "Allow"
    error_message = "Trust action must be sts:AssumeRole only"
  }
}

run "source_account_condition" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com"]
      source_account     = "111111111111"
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == { StringEquals = { "aws:SourceAccount" = "111111111111" } }
    error_message = "source_account must add an aws:SourceAccount condition"
  }
}

run "source_arn_condition" {
  command = plan

  variables {
    trust = {
      service_principals = ["bedrock.amazonaws.com"]
      source_arn         = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*"
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*" } }
    error_message = "source_arn must add an ArnLike aws:SourceArn condition"
  }
}

run "source_account_and_source_arn_in_one_statement" {
  command = plan

  variables {
    trust = {
      service_principals = ["bedrock.amazonaws.com"]
      source_account     = "111111111111"
      source_arn         = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*"
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == {
      StringEquals = { "aws:SourceAccount" = "111111111111" }
      ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*" }
    }
    error_message = "source_account and source_arn must both be conditions of the single trust statement"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "Trust policy must keep a single statement"
  }
}

# Existing callers must get a byte-identical trust policy.
run "source_account_only_policy_unchanged" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com"]
      source_account     = "111111111111"
    }
  }

  assert {
    condition     = aws_iam_role.this.assume_role_policy == "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Condition\":{\"StringEquals\":{\"aws:SourceAccount\":\"111111111111\"}},\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"ecs-tasks.amazonaws.com\"]}}],\"Version\":\"2012-10-17\"}"
    error_message = "Trust policy JSON must not change for callers that only set source_account"
  }
}

run "no_condition_without_source_account" {
  command = plan

  assert {
    condition     = !contains(keys(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0]), "Condition")
    error_message = "Trust policy must have no Condition when source_account is not set"
  }
}

run "inline_policy_per_entry" {
  command = plan

  variables {
    inline_policies = {
      logs = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/x:*" }]
      })
      ecr = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" }]
      })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 2
    error_message = "Each inline policy must create one aws_iam_role_policy"
  }

  assert {
    condition     = aws_iam_role_policy.this["ecr"].name == "ecr" && jsondecode(aws_iam_role_policy.this["ecr"].policy).Statement[0].Action == "ecr:GetAuthorizationToken"
    error_message = "Inline policy name and content must match the input"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this["logs"].policy).Statement[0].Action == ["logs:CreateLogStream", "logs:PutLogEvents"]
    error_message = "Inline policy content must match the input"
  }

  assert {
    condition     = aws_iam_role_policy.this["logs"].role == "alpha-dev-ecs-execution"
    error_message = "Inline policies must attach to the created role"
  }
}

run "no_inline_policies" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.this) == 0
    error_message = "inline_policies = {} must create no aws_iam_role_policy"
  }
}

run "role_attributes_defaults" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "alpha-dev-ecs-execution" && aws_iam_role.this.permissions_boundary == null && aws_iam_role.this.description == null
    error_message = "Role must use the given name and have no boundary or description by default"
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Name = "alpha-dev-ecs-execution" })
    error_message = "Tags must contain only Name by default"
  }
}

run "permissions_boundary_and_tags" {
  command = plan

  variables {
    description          = "execution role"
    permissions_boundary = "arn:aws:iam::111111111111:policy/boundary"
    tags                 = { Project = "alpha" }
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::111111111111:policy/boundary" && aws_iam_role.this.description == "execution role"
    error_message = "permissions_boundary and description must pass through"
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-ecs-execution" })
    error_message = "Tags must be merged with Name"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_iam_role.this
    override_during = plan
    values = {
      arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
      id  = "alpha-dev-ecs-execution"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
    error_message = "arn output must expose the role ARN"
  }

  assert {
    condition     = output.name == "alpha-dev-ecs-execution" && output.id == "alpha-dev-ecs-execution"
    error_message = "name and id outputs must expose the role"
  }
}

run "name_length_65_rejected" {
  command = plan

  variables {
    name = replace(format("%65s", "x"), " ", "a")
  }

  expect_failures = [var.name]
}

run "name_length_64_passes" {
  command = plan

  variables {
    name = replace(format("%64s", "x"), " ", "a")
  }

  assert {
    condition     = length(aws_iam_role.this.name) == 64
    error_message = "A 64-char name must be accepted"
  }
}

run "trust_empty_rejected" {
  command = plan

  variables {
    trust = { service_principals = [] }
  }

  expect_failures = [var.trust]
}

run "trust_wildcard_rejected" {
  command = plan

  variables {
    trust = { service_principals = ["*"] }
  }

  expect_failures = [var.trust]
}

run "trust_non_service_rejected" {
  command = plan

  variables {
    trust = { service_principals = ["example.com"] }
  }

  expect_failures = [var.trust]
}

run "trust_arn_principal_rejected" {
  command = plan

  variables {
    trust = { service_principals = ["arn:aws:iam::111111111111:root"] }
  }

  expect_failures = [var.trust]
}

run "source_account_format_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["ecs-tasks.amazonaws.com"]
      source_account     = "1234"
    }
  }

  expect_failures = [var.trust]
}

run "source_arn_without_arn_prefix_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["bedrock.amazonaws.com"]
      source_arn         = "bedrock:ap-northeast-1:111111111111:knowledge-base/*"
    }
  }

  expect_failures = [var.trust]
}

run "source_arn_bare_prefix_rejected" {
  command = plan

  variables {
    trust = {
      service_principals = ["bedrock.amazonaws.com"]
      source_arn         = "arn:"
    }
  }

  expect_failures = [var.trust]
}

run "policy_not_json_rejected" {
  command = plan

  variables {
    inline_policies = { bad = "not json" }
  }

  expect_failures = [var.inline_policies]
}

run "policy_without_statement_rejected" {
  command = plan

  variables {
    inline_policies = { bad = jsonencode({ Version = "2012-10-17" }) }
  }

  expect_failures = [var.inline_policies]
}

run "allow_wildcard_string_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_wildcard_list_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_service_wildcard_string_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "s3:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_service_wildcard_in_list_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_without_effect_wildcard_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Action = "s3:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_prefix_wildcard_passes" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["s3:Get*", "s3:List*"], Resource = "*" }] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Partial wildcards such as s3:Get* are not service-wide and must be accepted"
  }
}

run "deny_wildcard_is_allowed" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [
        { Effect = "Deny", Action = "*", Resource = "*" },
        { Effect = "Deny", Action = ["s3:*"], Resource = "*" },
      ] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Deny statements may use wildcard actions"
  }
}

run "statement_object_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = { Effect = "Allow", Action = "*", Resource = "*" } })
    }
  }

  expect_failures = [var.inline_policies]
}

run "empty_statement_list_rejected" {
  command = plan

  variables {
    inline_policies = { p = jsonencode({ Statement = [] }) }
  }

  expect_failures = [var.inline_policies]
}

run "allow_notaction_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", NotAction = "iam:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_notaction_list_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", NotAction = ["iam:*", "organizations:*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_notaction_without_effect_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ NotAction = "iam:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "deny_notaction_is_allowed" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Deny", NotAction = ["s3:GetObject"], Resource = "*" }, { Effect = "Deny", NotAction = "s3:GetObject", Resource = "*" }] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Deny statements may use NotAction"
  }
}

run "allow_notresource_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "s3:GetObject", NotResource = "arn:aws:s3:::secret/*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_notresource_list_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "s3:GetObject", NotResource = ["arn:aws:s3:::a/*", "arn:aws:s3:::b/*"] }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "allow_notresource_without_effect_rejected" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Action = "s3:GetObject", NotResource = "arn:aws:s3:::secret/*" }] })
    }
  }

  expect_failures = [var.inline_policies]
}

run "deny_notresource_is_allowed" {
  command = plan

  variables {
    inline_policies = {
      p = jsonencode({ Statement = [{ Effect = "Deny", Action = "s3:GetObject", NotResource = "arn:aws:s3:::ok/*" }, { Effect = "Deny", Action = "s3:GetObject", NotResource = ["arn:aws:s3:::ok/*"] }] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Deny statements may use NotResource"
  }
}
