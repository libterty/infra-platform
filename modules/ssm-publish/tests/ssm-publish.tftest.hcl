mock_provider "aws" {}

variables {
  ssm_prefix = "/alpha/dev"
  stack      = "network"
  strings    = { vpc_id = "vpc-0123456789abcdef0" }
  lists      = { subnet_ids_db = ["subnet-aaa", "subnet-bbb"] }
}

run "paths_and_types" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.string["vpc_id"].name == "/alpha/dev/network/vpc_id"
    error_message = "String parameter name must be <ssm_prefix>/<stack>/<key>"
  }

  assert {
    condition     = aws_ssm_parameter.string["vpc_id"].type == "String"
    error_message = "Scalars must be published as String"
  }

  assert {
    condition     = aws_ssm_parameter.string["vpc_id"].tier == "Standard"
    error_message = "Parameters must use the Standard tier"
  }

  assert {
    condition     = aws_ssm_parameter.string["vpc_id"].insecure_value == "vpc-0123456789abcdef0"
    error_message = "Scalars must be written through insecure_value, never value"
  }

  assert {
    condition     = aws_ssm_parameter.list["subnet_ids_db"].name == "/alpha/dev/network/subnet_ids_db"
    error_message = "StringList parameter name must be <ssm_prefix>/<stack>/<key>"
  }

  assert {
    condition     = aws_ssm_parameter.list["subnet_ids_db"].type == "StringList"
    error_message = "Lists must be published as StringList"
  }

  assert {
    condition     = aws_ssm_parameter.list["subnet_ids_db"].tier == "Standard"
    error_message = "Parameters must use the Standard tier"
  }

  assert {
    condition     = aws_ssm_parameter.list["subnet_ids_db"].insecure_value == "subnet-aaa,subnet-bbb"
    error_message = "StringList must be comma-joined so consumers can split(\",\", ...)"
  }
}

run "outputs_cover_both_maps" {
  command = plan

  assert {
    condition     = output.names == { vpc_id = "/alpha/dev/network/vpc_id", subnet_ids_db = "/alpha/dev/network/subnet_ids_db" }
    error_message = "names must map every string and list key to its parameter path"
  }

  # arns are unknown at plan, so only the key set is asserted.
  assert {
    condition     = toset(keys(output.arns)) == toset(["vpc_id", "subnet_ids_db"])
    error_message = "arns keys must be the union of strings and lists keys"
  }
}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
run "arns_expose_parameter_arns" {
  command = plan

  override_resource {
    target          = aws_ssm_parameter.string["vpc_id"]
    override_during = plan
    values          = { arn = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/dev/network/vpc_id" }
  }

  override_resource {
    target          = aws_ssm_parameter.list["subnet_ids_db"]
    override_during = plan
    values          = { arn = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/dev/network/subnet_ids_db" }
  }

  assert {
    condition     = output.arns["vpc_id"] == "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/dev/network/vpc_id"
    error_message = "arns must expose the string parameter ARN"
  }

  assert {
    condition     = output.arns["subnet_ids_db"] == "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha/dev/network/subnet_ids_db"
    error_message = "arns must expose the list parameter ARN"
  }
}

run "empty_maps_publish_nothing" {
  command = plan

  variables {
    strings = {}
    lists   = {}
  }

  assert {
    condition     = length(aws_ssm_parameter.string) == 0
    error_message = "No String parameter may be created when strings is empty"
  }

  assert {
    condition     = length(aws_ssm_parameter.list) == 0
    error_message = "No StringList parameter may be created when lists is empty"
  }

  assert {
    condition     = length(output.names) == 0 && length(output.arns) == 0
    error_message = "Outputs must be empty maps when nothing is published"
  }
}

run "prefix_accepts_project_env" {
  command = plan

  variables {
    ssm_prefix = "/alpha/dev"
  }

  assert {
    condition     = length(aws_ssm_parameter.string) == 1
    error_message = "A valid prefix must plan normally"
  }
}

run "prefix_rejects_missing_leading_slash" {
  command = plan

  variables {
    ssm_prefix = "alpha/dev"
  }

  expect_failures = [var.ssm_prefix]
}

run "prefix_rejects_extra_segment" {
  command = plan

  variables {
    ssm_prefix = "/alpha/dev/network"
  }

  expect_failures = [var.ssm_prefix]
}

run "prefix_rejects_trailing_slash" {
  command = plan

  variables {
    ssm_prefix = "/alpha/dev/"
  }

  expect_failures = [var.ssm_prefix]
}

run "stack_name_accepts_hyphen" {
  command = plan

  variables {
    stack = "iam-base"
  }

  assert {
    condition     = aws_ssm_parameter.string["vpc_id"].name == "/alpha/dev/iam-base/vpc_id"
    error_message = "A hyphenated stack name must be used as the path segment"
  }
}

run "stack_name_rejects_space_and_uppercase" {
  command = plan

  variables {
    stack = "Net Work"
  }

  expect_failures = [var.stack]
}

run "key_accepts_snake_case" {
  command = plan

  variables {
    strings = { vpc_id = "vpc-1" }
    lists   = {}
  }

  assert {
    condition     = length(aws_ssm_parameter.string) == 1
    error_message = "A snake_case key must plan normally"
  }
}

run "key_rejects_hyphen_in_strings" {
  command = plan

  variables {
    strings = { "vpc-id" = "vpc-1" }
    lists   = {}
  }

  expect_failures = [var.strings]
}

run "key_rejects_hyphen_in_lists" {
  command = plan

  variables {
    strings = {}
    lists   = { "subnet-ids" = ["subnet-a"] }
  }

  expect_failures = [var.lists]
}

run "rejects_empty_string_value" {
  command = plan

  variables {
    strings = { a = "" }
    lists   = {}
  }

  expect_failures = [var.strings]
}

run "value_length_accepts_4096" {
  command = plan

  variables {
    strings = { a = format("%4096s", "x") }
    lists   = {}
  }

  assert {
    condition     = length(aws_ssm_parameter.string["a"].insecure_value) == 4096
    error_message = "A 4096-char value is the allowed upper bound"
  }
}

run "value_length_rejects_4097" {
  command = plan

  variables {
    strings = { a = format("%4097s", "x") }
    lists   = {}
  }

  expect_failures = [var.strings]
}

run "list_accepts_single_element" {
  command = plan

  variables {
    strings = {}
    lists   = { a = ["x"] }
  }

  assert {
    condition     = aws_ssm_parameter.list["a"].insecure_value == "x"
    error_message = "A one-element list must publish the element unchanged"
  }
}

run "rejects_empty_list" {
  command = plan

  variables {
    strings = {}
    lists   = { a = [] }
  }

  expect_failures = [var.lists]
}

run "rejects_empty_list_element" {
  command = plan

  variables {
    strings = {}
    lists   = { a = ["x", ""] }
  }

  expect_failures = [var.lists]
}

run "rejects_list_element_with_comma" {
  command = plan

  variables {
    strings = {}
    lists   = { a = ["x,y"] }
  }

  expect_failures = [var.lists]
}

run "rejects_key_in_both_maps" {
  command = plan

  variables {
    strings = { a = "x" }
    lists   = { a = ["y"] }
  }

  expect_failures = [var.lists]
}

run "distinct_keys_in_both_maps_pass" {
  command = plan

  variables {
    strings = { a = "x" }
    lists   = { b = ["y"] }
  }

  assert {
    condition     = length(aws_ssm_parameter.string) == 1 && length(aws_ssm_parameter.list) == 1
    error_message = "Different keys in strings and lists must both be published"
  }
}
