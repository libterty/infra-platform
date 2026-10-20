mock_provider "aws" {}

variables {
  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"
}

run "no_environment_block_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.this.environment) == 0
    error_message = "Without environment the function must not have an environment block"
  }
}

run "environment_follows_input" {
  command = plan

  variables {
    environment = {
      LOG_LEVEL = "info"
      STAGE     = "dev"
    }
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables == tomap({ LOG_LEVEL = "info", STAGE = "dev" })
    error_message = "environment variables must follow the input"
  }
}

run "rejects_environment_password_name" {
  command = plan

  variables {
    environment = {
      DB_PASSWORD = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_passwd_name" {
  command = plan

  variables {
    environment = {
      DB_PASSWD = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_secret_name" {
  command = plan

  variables {
    environment = {
      CLIENT_SECRET = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_token_name" {
  command = plan

  variables {
    environment = {
      GITHUB_TOKEN = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_api_key_name" {
  command = plan

  variables {
    environment = {
      API_KEY = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_apikey_name" {
  command = plan

  variables {
    environment = {
      STRIPE_APIKEY = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_private_key_name" {
  command = plan

  variables {
    environment = {
      PRIVATE_KEY = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_privatekey_name" {
  command = plan

  variables {
    environment = {
      SIGNING_PRIVATEKEY = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_credential_name" {
  command = plan

  variables {
    environment = {
      AWS_CREDENTIALS = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_lowercase_secret_name" {
  command = plan

  variables {
    environment = {
      db_password = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_secret_name_ending_in_arn_inside_the_name" {
  command = plan

  variables {
    environment = {
      SECRET_ARN_PATH = "value"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_secret_arn_name_with_a_non_arn_value" {
  command = plan

  variables {
    environment = {
      DB_PASSWORD_ARN = "hunter2"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_secret_name_next_to_a_plain_one" {
  command = plan

  variables {
    environment = {
      LOG_LEVEL   = "info"
      DB_PASSWORD = "hunter2"
    }
  }

  expect_failures = [var.environment]
}

run "accepts_plain_environment_name" {
  command = plan

  variables {
    environment = {
      LOG_LEVEL = "info"
    }
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables == tomap({ LOG_LEVEL = "info" })
    error_message = "A plain name must be accepted"
  }
}

run "accepts_secret_arn_name_with_an_arn_value" {
  command = plan

  variables {
    environment = {
      DB_PASSWORD_ARN = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-db-AbCdEf"
    }
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DB_PASSWORD_ARN"] == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-db-AbCdEf"
    error_message = "A secret name ending in _ARN with an ARN value must be accepted"
  }
}

run "rejects_environment_name_starting_with_a_digit" {
  command = plan

  variables {
    environment = {
      "1LEVEL" = "info"
    }
  }

  expect_failures = [var.environment]
}

run "rejects_environment_name_with_a_hyphen" {
  command = plan

  variables {
    environment = {
      "LOG-LEVEL" = "info"
    }
  }

  expect_failures = [var.environment]
}
