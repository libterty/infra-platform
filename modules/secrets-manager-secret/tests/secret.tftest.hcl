mock_provider "aws" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_secretsmanager_secret.this
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
    id  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
  }
}

variables {
  name = "alpha-dev/app"
}

# ---- name only ------------------------------------------------------------------------------------------------

run "name_only_uses_the_aws_managed_key_and_a_7_day_window" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.name == "alpha-dev/app"
    error_message = "The secret keeps the given name"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == null
    error_message = "Without kms_key_arn the secret must use the AWS managed key aws/secretsmanager"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 7
    error_message = "A deleted secret must stay recoverable for 7 days by default"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags == tomap({ Name = "alpha-dev/app" })
    error_message = "The secret gets a Name tag"
  }
}

run "name_only_creates_no_policy_and_no_rotation" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 0
    error_message = "No resource policy may be created when policy_statements is empty"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "No rotation may be created when rotation is null"
  }
}

run "outputs_come_from_the_secret" {
  command = apply

  override_resource {
    target = aws_secretsmanager_secret.this
    values = {
      arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
      id   = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
      name = "alpha-dev/app"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
    error_message = "arn must be the secret ARN"
  }

  assert {
    condition     = output.id == output.arn
    error_message = "id must be the secret id (its ARN)"
  }

  assert {
    condition     = output.name == "alpha-dev/app"
    error_message = "name must be the secret name"
  }
}

# ---- CMK, policy and rotation ---------------------------------------------------------------------------------

run "cmk_policy_and_rotation" {
  command = plan

  variables {
    description             = "Database user of alpha-dev."
    kms_key_arn             = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    recovery_window_in_days = 30
    tags                    = { Project = "alpha" }

    policy_statements = [
      {
        sid        = "AllowAppRead"
        effect     = "Allow"
        principals = { type = "AWS", identifiers = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
        actions    = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      },
      {
        sid        = "DenyOutsideOrg"
        effect     = "Deny"
        principals = { type = "AWS", identifiers = ["*"] }
        actions    = ["secretsmanager:*"]
        conditions = [
          { test = "StringNotEquals", variable = "aws:PrincipalAccount", values = ["111111111111"] },
          { test = "Bool", variable = "aws:PrincipalIsAWSService", values = ["false"] },
        ]
      },
    ]

    rotation = {
      lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      automatically_after_days = 30
      duration                 = "3h"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The secret must use the given CMK"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.description == "Database user of alpha-dev." && aws_secretsmanager_secret.this.recovery_window_in_days == 30
    error_message = "description and recovery_window_in_days must be passed through"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags == tomap({ Project = "alpha", Name = "alpha-dev/app" })
    error_message = "Tags are merged with Name"
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
    error_message = "The policy belongs to this secret"
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy == true
    error_message = "block_public_policy must always be on"
  }

  assert {
    condition = jsondecode(aws_secretsmanager_secret_policy.this[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowAppRead"
          Effect    = "Allow"
          Principal = { AWS = ["arn:aws:iam::111111111111:role/alpha-dev-app"] }
          Action    = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource  = "*"
        },
        {
          Sid       = "DenyOutsideOrg"
          Effect    = "Deny"
          Principal = { AWS = ["*"] }
          Action    = ["secretsmanager:*"]
          Resource  = "*"
          Condition = {
            StringNotEquals = { "aws:PrincipalAccount" = ["111111111111"] }
            Bool            = { "aws:PrincipalIsAWSService" = ["false"] }
          }
        },
      ]
    }
    error_message = "The policy must render the statements as given, scoped to this secret"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].secret_id == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf"
    error_message = "Rotation belongs to this secret"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_lambda_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
    error_message = "Rotation uses the given Lambda"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == 30 && aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].schedule_expression == null && aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].duration == "3h"
    error_message = "Rotation rules must be passed through"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotate_immediately == false
    error_message = "Rotation must not run immediately by default"
  }
}

run "rotation_by_schedule_expression" {
  command = plan

  variables {
    rotation = {
      lambda_arn          = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-rotate"
      schedule_expression = "rate(10 days)"
      rotate_immediately  = true
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].schedule_expression == "rate(10 days)" && aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == null
    error_message = "schedule_expression must be passed through"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotate_immediately == true
    error_message = "rotate_immediately must be passed through"
  }
}

run "deny_with_wildcard_principal_needs_no_condition" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "DenyDelete"
      effect     = "Deny"
      principals = { type = "AWS", identifiers = ["*"] }
      actions    = ["secretsmanager:DeleteSecret"]
    }]
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 1
    error_message = "A Deny with Principal * and no condition is allowed"
  }
}

run "allow_with_wildcard_principal_and_condition_is_accepted" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowOwnAccount"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = ["*"] }
      actions    = ["secretsmanager:GetSecretValue"]
      conditions = [{ test = "StringEquals", variable = "aws:PrincipalAccount", values = ["111111111111"] }]
    }]
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 1
    error_message = "An Allow with Principal * is accepted when it has a condition"
  }
}
