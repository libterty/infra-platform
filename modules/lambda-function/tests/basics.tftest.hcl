mock_provider "aws" {}

variables {
  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-worker"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "alpha-dev-worker"
    error_message = "function_name must equal the name input"
  }

  assert {
    condition     = aws_lambda_function.this.package_type == "Image"
    error_message = "The function must be a container image function"
  }

  assert {
    condition     = aws_lambda_function.this.image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
    error_message = "image_uri must follow the input"
  }

  assert {
    condition     = aws_lambda_function.this.role == "arn:aws:iam::111111111111:role/alpha-dev-worker"
    error_message = "role must follow role_arn"
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"])
    error_message = "Default architecture must be arm64"
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 512 && aws_lambda_function.this.timeout == 30
    error_message = "Default memory_size must be 512 and timeout 30"
  }

  assert {
    condition     = aws_lambda_function.this.tags == tomap({ Name = "alpha-dev-worker" })
    error_message = "Without tags input the only tag is Name"
  }
}

# A container image function has no zip settings; the module must never set them.
run "sets_no_zip_package_settings" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.this.handler == null &&
      aws_lambda_function.this.runtime == null &&
      aws_lambda_function.this.filename == null &&
      aws_lambda_function.this.s3_bucket == null
    )
    error_message = "handler, runtime, filename and s3_bucket must stay unset for an Image function"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_lambda_function.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-worker" })
    error_message = "Input tags must be kept and Name added"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Project = "alpha", Name = "/aws/lambda/alpha-dev-worker" })
    error_message = "The log group must carry the input tags and its own name"
  }
}

run "reserved_concurrency_follows_input" {
  command = plan

  variables {
    reserved_concurrent_executions = 5
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 5
    error_message = "reserved_concurrent_executions must follow the input"
  }
}

run "module_owns_the_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/alpha-dev-worker"
    error_message = "Log group name must be /aws/lambda/<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Default retention must be 30 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Without log_kms_key_arn the log group must not set a key"
  }
}

run "logging_config_points_at_the_module_log_group" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_group == "/aws/lambda/alpha-dev-worker"
    error_message = "logging_config.log_group must be the module's log group"
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_format == "Text"
    error_message = "Default log_format must be Text"
  }
}

run "log_settings_follow_input" {
  command = plan

  variables {
    log_retention_days = 365
    log_kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
    log_format         = "JSON"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "log_retention_days must follow the input"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"
    error_message = "log_kms_key_arn must be set on the log group"
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_format == "JSON"
    error_message = "log_format must follow the input"
  }
}

run "no_vpc_config_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 0
    error_message = "Without vpc the function must not have a vpc_config"
  }
}

run "vpc_config_when_vpc_is_given" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 1
    error_message = "vpc must create one vpc_config"
  }

  assert {
    condition     = aws_lambda_function.this.vpc_config[0].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "vpc_config subnet_ids must follow the input"
  }

  assert {
    condition     = aws_lambda_function.this.vpc_config[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "vpc_config security_group_ids must follow the input"
  }
}

run "outputs" {
  command = apply

  variables {
    permissions = {
      s3_upload = {
        principal      = "s3.amazonaws.com"
        source_arn     = "arn:aws:s3:::alpha-dev-uploads"
        source_account = "111111111111"
      }
    }
  }

  assert {
    condition     = output.function_name == "alpha-dev-worker"
    error_message = "function_name must be the function name"
  }

  assert {
    condition     = output.function_arn == aws_lambda_function.this.arn
    error_message = "function_arn must be the function ARN"
  }

  assert {
    condition     = output.invoke_arn == aws_lambda_function.this.invoke_arn
    error_message = "invoke_arn must be the function invoke ARN"
  }

  assert {
    condition     = output.log_group_name == "/aws/lambda/alpha-dev-worker"
    error_message = "log_group_name must be the module log group"
  }
}

run "rejects_name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-worker"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "alpha_dev_worker"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_64" {
  command = plan

  variables {
    name = "a${join("", [for i in range(64) : "b"])}"
  }

  expect_failures = [var.name]
}

run "accepts_lowercase_name" {
  command = plan

  variables {
    name = "alpha-sit-worker"
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "alpha-sit-worker"
    error_message = "A lowercase name must be accepted"
  }
}

run "rejects_role_arn_that_is_not_a_role" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/alpha"
  }

  expect_failures = [var.role_arn]
}

run "rejects_role_arn_malformed" {
  command = plan

  variables {
    role_arn = "alpha-dev-worker"
  }

  expect_failures = [var.role_arn]
}

run "accepts_role_arn_with_path" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service/alpha-dev-worker"
  }

  assert {
    condition     = aws_lambda_function.this.role == "arn:aws:iam::111111111111:role/service/alpha-dev-worker"
    error_message = "A role ARN with a path must be accepted"
  }
}

run "rejects_empty_architectures" {
  command = plan

  variables {
    architectures = []
  }

  expect_failures = [var.architectures]
}

run "rejects_two_architectures" {
  command = plan

  variables {
    architectures = ["arm64", "x86_64"]
  }

  expect_failures = [var.architectures]
}

run "rejects_unknown_architecture" {
  command = plan

  variables {
    architectures = ["arm"]
  }

  expect_failures = [var.architectures]
}

run "accepts_x86_64_architecture" {
  command = plan

  variables {
    architectures = ["x86_64"]
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["x86_64"])
    error_message = "x86_64 must be accepted"
  }
}

run "rejects_memory_size_127" {
  command = plan

  variables {
    memory_size = 127
  }

  expect_failures = [var.memory_size]
}

run "rejects_memory_size_10241" {
  command = plan

  variables {
    memory_size = 10241
  }

  expect_failures = [var.memory_size]
}

run "rejects_fractional_memory_size" {
  command = plan

  variables {
    memory_size = 256.5
  }

  expect_failures = [var.memory_size]
}

run "accepts_memory_size_128" {
  command = plan

  variables {
    memory_size = 128
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 128
    error_message = "128 MB must be accepted"
  }
}

run "accepts_memory_size_10240" {
  command = plan

  variables {
    memory_size = 10240
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 10240
    error_message = "10240 MB must be accepted"
  }
}

run "rejects_timeout_0" {
  command = plan

  variables {
    timeout = 0
  }

  expect_failures = [var.timeout]
}

run "rejects_timeout_901" {
  command = plan

  variables {
    timeout = 901
  }

  expect_failures = [var.timeout]
}

run "accepts_timeout_1" {
  command = plan

  variables {
    timeout = 1
  }

  assert {
    condition     = aws_lambda_function.this.timeout == 1
    error_message = "1 second must be accepted"
  }
}

run "accepts_timeout_900" {
  command = plan

  variables {
    timeout = 900
  }

  assert {
    condition     = aws_lambda_function.this.timeout == 900
    error_message = "900 seconds must be accepted"
  }
}

run "rejects_negative_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = -1
  }

  expect_failures = [var.reserved_concurrent_executions]
}

run "accepts_zero_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = 0
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 0
    error_message = "0 (throttle everything) must be accepted"
  }
}

run "rejects_zero_log_retention" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_unsupported_log_retention" {
  command = plan

  variables {
    log_retention_days = 2
  }

  expect_failures = [var.log_retention_days]
}

run "accepts_log_retention_90" {
  command = plan

  variables {
    log_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90
    error_message = "90 days must be accepted"
  }
}

run "rejects_malformed_log_kms_key_arn" {
  command = plan

  variables {
    log_kms_key_arn = "alias/alpha"
  }

  expect_failures = [var.log_kms_key_arn]
}

run "rejects_log_kms_key_arn_of_another_service" {
  command = plan

  variables {
    log_kms_key_arn = "arn:aws:s3:::alpha-dev-uploads"
  }

  expect_failures = [var.log_kms_key_arn]
}

run "rejects_unknown_log_format" {
  command = plan

  variables {
    log_format = "XML"
  }

  expect_failures = [var.log_format]
}

run "rejects_lowercase_log_format" {
  command = plan

  variables {
    log_format = "json"
  }

  expect_failures = [var.log_format]
}

run "accepts_json_log_format" {
  command = plan

  variables {
    log_format = "JSON"
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_format == "JSON"
    error_message = "JSON must be accepted"
  }
}

run "rejects_vpc_without_subnets" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = []
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc]
}

run "rejects_vpc_without_security_groups" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = []
    }
  }

  expect_failures = [var.vpc]
}

run "rejects_vpc_with_malformed_subnet_id" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = ["vpc-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc]
}

run "rejects_vpc_with_malformed_security_group_id" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["subnet-0123456789abcdef0"]
    }
  }

  expect_failures = [var.vpc]
}

run "accepts_vpc_with_one_subnet_and_one_security_group" {
  command = plan

  variables {
    vpc = {
      subnet_ids         = ["subnet-0a1b2c3d"]
      security_group_ids = ["sg-0a1b2c3d"]
    }
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 1
    error_message = "One subnet and one security group must be accepted"
  }
}
