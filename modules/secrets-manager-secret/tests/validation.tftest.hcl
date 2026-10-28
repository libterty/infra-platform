mock_provider "aws" {}

variables {
  name = "alpha-dev/app"
}

# ---- name -----------------------------------------------------------------------------------------------------

run "name_of_512_chars_is_accepted" {
  command = plan

  variables {
    name = join("", [for i in range(512) : "a"])
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this.name) == 512
    error_message = "512 chars is the Secrets Manager limit and must be accepted"
  }
}

run "name_of_513_chars_is_rejected" {
  command = plan

  variables {
    name = join("", [for i in range(513) : "a"])
  }

  expect_failures = [var.name]
}

run "name_with_invalid_chars_is_rejected" {
  command = plan

  variables {
    name = "alpha dev/app"
  }

  expect_failures = [var.name]
}

run "name_ending_like_the_arn_suffix_is_accepted" {
  command = plan

  variables {
    name = "alpha-dev/opensearch-master"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.name == "alpha-dev/opensearch-master"
    error_message = "A name ending in a hyphen and six chars is valid; existing template secrets use one"
  }
}

# ---- kms_key_arn ----------------------------------------------------------------------------------------------

run "kms_alias_arn_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

# ---- recovery_window_in_days ----------------------------------------------------------------------------------

run "recovery_window_of_0_is_rejected" {
  command = plan

  variables {
    recovery_window_in_days = 0
  }

  expect_failures = [var.recovery_window_in_days]
}

run "recovery_window_of_31_is_rejected" {
  command = plan

  variables {
    recovery_window_in_days = 31
  }

  expect_failures = [var.recovery_window_in_days]
}

# ---- policy_statements ----------------------------------------------------------------------------------------

run "allow_wildcard_principal_without_condition_is_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowEveryone"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = ["*"] }
      actions    = ["secretsmanager:GetSecretValue"]
    }]
  }

  expect_failures = [var.policy_statements]
}

run "allow_secretsmanager_wildcard_is_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowAll"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
      actions    = ["secretsmanager:*"]
    }]
  }

  expect_failures = [var.policy_statements]
}

run "action_outside_secretsmanager_is_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowAny"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
      actions    = ["*"]
    }]
  }

  expect_failures = [var.policy_statements]
}

run "unknown_effect_is_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "Maybe"
      effect     = "allow"
      principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
      actions    = ["secretsmanager:GetSecretValue"]
    }]
  }

  expect_failures = [var.policy_statements]
}

run "unknown_principal_type_is_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowFederated"
      effect     = "Allow"
      principals = { type = "Federated", identifiers = ["cognito-identity.amazonaws.com"] }
      actions    = ["secretsmanager:GetSecretValue"]
    }]
  }

  expect_failures = [var.policy_statements]
}

run "sid_with_invalid_chars_is_rejected" {
  command = plan

  variables {
    policy_statements = [
      {
        sid        = "Allow-App"
        effect     = "Allow"
        principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
        actions    = ["secretsmanager:GetSecretValue"]
      },
    ]
  }

  expect_failures = [var.policy_statements]
}

run "duplicate_sid_is_rejected" {
  command = plan

  variables {
    policy_statements = [
      {
        sid        = "AllowApp"
        effect     = "Allow"
        principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
        actions    = ["secretsmanager:GetSecretValue"]
      },
      {
        sid        = "AllowApp"
        effect     = "Deny"
        principals = { type = "AWS", identifiers = ["*"] }
        actions    = ["secretsmanager:DeleteSecret"]
      },
    ]
  }

  expect_failures = [var.policy_statements]
}

run "empty_actions_or_identifiers_are_rejected" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowNobody"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = [] }
      actions    = []
    }]
  }

  expect_failures = [var.policy_statements]
}

# ---- rotation -------------------------------------------------------------------------------------------------

run "both_rotation_schedules_are_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      automatically_after_days = 30
      schedule_expression      = "rate(10 days)"
    }
  }

  expect_failures = [var.rotation]
}

run "no_rotation_schedule_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
    }
  }

  expect_failures = [var.rotation]
}

run "rotation_after_1001_days_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      automatically_after_days = 1001
    }
  }

  expect_failures = [var.rotation]
}

run "rotation_after_0_days_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      automatically_after_days = 0
    }
  }

  expect_failures = [var.rotation]
}

run "rotation_lambda_that_is_not_a_function_arn_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn               = "alpha-dev-rotate"
      automatically_after_days = 30
    }
  }

  expect_failures = [var.rotation]
}

run "invalid_schedule_expression_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn          = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      schedule_expression = "every 10 days"
    }
  }

  expect_failures = [var.rotation]
}

run "invalid_duration_is_rejected" {
  command = plan

  variables {
    rotation = {
      lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      automatically_after_days = 30
      duration                 = "25h"
    }
  }

  expect_failures = [var.rotation]
}
