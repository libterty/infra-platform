mock_provider "aws" {}

variables {
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-db-proxy"
  policies = {
    secret = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
      }]
    })
  }
}

run "policy_per_entry" {
  command = plan

  variables {
    policies = {
      secret = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:x" }]
      })
      kms = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["kms:Decrypt"], Resource = "arn:aws:kms:ap-northeast-1:111111111111:key/x" }]
      })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 2
    error_message = "Each policy must create one aws_iam_role_policy"
  }

  assert {
    condition     = aws_iam_role_policy.this["secret"].name == "secret" && jsondecode(aws_iam_role_policy.this["secret"].policy).Statement[0].Action == "secretsmanager:GetSecretValue"
    error_message = "Policy name and content must match the input"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this["kms"].policy).Statement[0].Action == ["kms:Decrypt"]
    error_message = "Policy content must match the input"
  }
}

run "role_name_from_arn" {
  command = plan

  assert {
    condition     = alltrue([for p in aws_iam_role_policy.this : p.role == "alpha-dev-db-proxy"])
    error_message = "role must be the last segment of role_arn"
  }

  assert {
    condition     = output.role_name == "alpha-dev-db-proxy"
    error_message = "role_name output must be the last segment of role_arn"
  }
}

run "outputs" {
  command = plan

  variables {
    policies = {
      b = jsonencode({ Statement = [{ Effect = "Allow", Action = "kms:Decrypt", Resource = "*" }] })
      a = jsonencode({ Statement = [{ Effect = "Allow", Action = "kms:Encrypt", Resource = "*" }] })
    }
  }

  assert {
    condition     = tolist(output.policy_names) == tolist(keys(var.policies))
    error_message = "policy_names must equal keys(policies)"
  }
}

run "role_arn_without_path_passes" {
  command = plan

  variables {
    role_arn = "arn:aws-cn:iam::111111111111:role/x"
  }

  assert {
    condition     = output.role_name == "x"
    error_message = "A role ARN without a path must be accepted"
  }
}

run "role_arn_with_path_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service/x"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_user_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/x"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_garbage_rejected" {
  command = plan

  variables {
    role_arn = "alpha-dev-db-proxy"
  }

  expect_failures = [var.role_arn]
}

run "policies_required" {
  command = plan

  variables {
    policies = {}
  }

  expect_failures = [var.policies]
}

run "policy_not_json_rejected" {
  command = plan

  variables {
    policies = { bad = "not json" }
  }

  expect_failures = [var.policies]
}

run "policy_without_statement_rejected" {
  command = plan

  variables {
    policies = { bad = jsonencode({ Version = "2012-10-17" }) }
  }

  expect_failures = [var.policies]
}

run "statement_object_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = { Effect = "Allow", Action = "*", Resource = "*" } })
    }
  }

  expect_failures = [var.policies]
}

run "empty_statement_list_rejected" {
  command = plan

  variables {
    policies = { p = jsonencode({ Statement = [] }) }
  }

  expect_failures = [var.policies]
}

run "allow_wildcard_string_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_wildcard_list_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_service_wildcard_string_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "secretsmanager:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_service_wildcard_in_list_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_without_effect_wildcard_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Action = "secretsmanager:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_prefix_wildcard_passes" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = ["secretsmanager:Get*"], Resource = "*" }] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Partial wildcards such as secretsmanager:Get* are not service-wide and must be accepted"
  }
}

run "deny_wildcard_is_allowed" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [
        { Effect = "Deny", Action = "*", Resource = "*" },
        { Effect = "Deny", Action = ["secretsmanager:*"], Resource = "*" },
      ] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Deny statements may use wildcard actions"
  }
}

run "allow_notaction_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", NotAction = "iam:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_notaction_list_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", NotAction = ["iam:*", "organizations:*"], Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_notaction_without_effect_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ NotAction = "iam:*", Resource = "*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "deny_notaction_is_allowed" {
  command = plan

  variables {
    policies = {
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
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "s3:GetObject", NotResource = "arn:aws:s3:::secret/*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_notresource_list_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Allow", Action = "s3:GetObject", NotResource = ["arn:aws:s3:::a/*", "arn:aws:s3:::b/*"] }] })
    }
  }

  expect_failures = [var.policies]
}

run "allow_notresource_without_effect_rejected" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Action = "s3:GetObject", NotResource = "arn:aws:s3:::secret/*" }] })
    }
  }

  expect_failures = [var.policies]
}

run "deny_notresource_is_allowed" {
  command = plan

  variables {
    policies = {
      p = jsonencode({ Statement = [{ Effect = "Deny", Action = "s3:GetObject", NotResource = "arn:aws:s3:::ok/*" }, { Effect = "Deny", Action = "s3:GetObject", NotResource = ["arn:aws:s3:::ok/*"] }] })
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Deny statements may use NotResource"
  }
}
