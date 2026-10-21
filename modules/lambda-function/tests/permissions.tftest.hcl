mock_provider "aws" {}

variables {
  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"
}

run "no_permissions_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_permission.this) == 0
    error_message = "Without permissions no aws_lambda_permission may exist"
  }
}

run "permissions_create_one_statement_each" {
  command = plan

  variables {
    permissions = {
      s3_upload = {
        principal      = "s3.amazonaws.com"
        source_arn     = "arn:aws:s3:::alpha-dev-uploads"
        source_account = "111111111111"
      }
      schedule = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 2
    error_message = "Each permissions entry must create one aws_lambda_permission"
  }

  assert {
    condition = (
      aws_lambda_permission.this["s3_upload"].statement_id == "s3_upload" &&
      aws_lambda_permission.this["s3_upload"].principal == "s3.amazonaws.com" &&
      aws_lambda_permission.this["s3_upload"].source_arn == "arn:aws:s3:::alpha-dev-uploads" &&
      aws_lambda_permission.this["s3_upload"].source_account == "111111111111" &&
      aws_lambda_permission.this["s3_upload"].action == "lambda:InvokeFunction" &&
      aws_lambda_permission.this["s3_upload"].function_name == "alpha-dev-worker"
    )
    error_message = "The S3 permission must carry principal, source_arn, source_account and the default action"
  }

  # Negative: a permission without source_account must not invent one.
  assert {
    condition     = aws_lambda_permission.this["schedule"].source_account == null
    error_message = "source_account must stay unset when not given"
  }

  # Negative: every permission is scoped by a source ARN; none is open to the whole principal.
  assert {
    condition     = alltrue([for p in aws_lambda_permission.this : p.source_arn != null && p.source_arn != ""])
    error_message = "Every permission must be limited by source_arn"
  }
}

run "permission_action_follows_input" {
  command = plan

  variables {
    permissions = {
      url = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        action     = "lambda:InvokeFunctionUrl"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["url"].action == "lambda:InvokeFunctionUrl"
    error_message = "action must follow the input"
  }
}

run "rejects_principal_wildcard" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "*"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_principal_that_is_not_an_aws_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "example.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_principal_account_id" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "111111111111"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_principal_with_amazonaws_com_only_as_a_suffix_of_another_domain" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com.example.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_principal_wildcard_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "*.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "accepts_principal_events_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["p"].principal == "events.amazonaws.com"
    error_message = "An AWS service principal must be accepted"
  }
}

run "accepts_principal_regional_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "logs.ap-northeast-1.amazonaws.com"
        source_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/alpha/dev/app:*"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["p"].principal == "logs.ap-northeast-1.amazonaws.com"
    error_message = "A regional service principal must be accepted"
  }
}

run "rejects_s3_principal_without_source_account" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "s3.amazonaws.com"
        source_arn = "arn:aws:s3:::alpha-dev-uploads"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_s3_principal_with_null_source_account" {
  command = plan

  variables {
    permissions = {
      p = {
        principal      = "s3.amazonaws.com"
        source_arn     = "arn:aws:s3:::alpha-dev-uploads"
        source_account = null
      }
    }
  }

  expect_failures = [var.permissions]
}

run "accepts_s3_principal_with_source_account" {
  command = plan

  variables {
    permissions = {
      p = {
        principal      = "s3.amazonaws.com"
        source_arn     = "arn:aws:s3:::alpha-dev-uploads"
        source_account = "111111111111"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["p"].source_account == "111111111111"
    error_message = "S3 with a source_account must be accepted"
  }
}

run "rejects_source_account_that_is_not_12_digits" {
  command = plan

  variables {
    permissions = {
      p = {
        principal      = "events.amazonaws.com"
        source_arn     = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        source_account = "1111"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_source_account_with_letters" {
  command = plan

  variables {
    permissions = {
      p = {
        principal      = "events.amazonaws.com"
        source_arn     = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        source_account = "11111111111a"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "accepts_source_account_12_digits_on_another_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal      = "events.amazonaws.com"
        source_arn     = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        source_account = "111111111111"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["p"].source_account == "111111111111"
    error_message = "A 12-digit source_account must be accepted"
  }
}

# Omitting source_arn altogether fails the variable type (the attribute is required), which expect_failures cannot catch; null and empty are covered below.
run "rejects_null_source_arn" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = null
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_empty_source_arn" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = ""
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_source_arn_wildcard" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "*"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_source_arn_that_is_not_an_arn" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "alpha-dev-uploads"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_statement_id_with_a_space" {
  command = plan

  variables {
    permissions = {
      "bad id" = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "accepts_statement_id_with_hyphen_and_digits" {
  command = plan

  variables {
    permissions = {
      "s3-upload-1" = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["s3-upload-1"].statement_id == "s3-upload-1"
    error_message = "A statement id with hyphen and digits must be accepted"
  }
}

run "rejects_action_wildcard" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        action     = "*"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_action_lambda_wildcard" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        action     = "lambda:*"
      }
    }
  }

  expect_failures = [var.permissions]
}

run "rejects_action_of_another_service" {
  command = plan

  variables {
    permissions = {
      p = {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-nightly"
        action     = "s3:GetObject"
      }
    }
  }

  expect_failures = [var.permissions]
}

# CloudWatch alarm actions invoke Lambda through this dedicated principal (lb-traffic-breaker).
run "accepts_principal_cloudwatch_alarms" {
  command = plan

  variables {
    permissions = {
      breaker = {
        principal      = "lambda.alarms.cloudwatch.amazonaws.com"
        source_arn     = "arn:aws:cloudwatch:ap-northeast-1:111111111111:alarm:example-breaker"
        source_account = "111111111111"
      }
    }
  }

  assert {
    condition = (
      aws_lambda_permission.this["breaker"].principal == "lambda.alarms.cloudwatch.amazonaws.com" &&
      aws_lambda_permission.this["breaker"].source_arn == "arn:aws:cloudwatch:ap-northeast-1:111111111111:alarm:example-breaker" &&
      aws_lambda_permission.this["breaker"].source_account == "111111111111"
    )
    error_message = "The CloudWatch alarms principal must be accepted with its alarm ARN and source_account"
  }
}
