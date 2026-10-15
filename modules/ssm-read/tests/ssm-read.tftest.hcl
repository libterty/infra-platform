mock_provider "aws" {}

variables {
  ssm_prefix = "/alpha/dev"
}

run "strings_output" {
  command = plan

  variables {
    strings = { vpc_id = "network/vpc_id" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["network/vpc_id"]
    values = { insecure_value = "vpc-0abc" }
  }

  assert {
    condition     = output.strings["vpc_id"] == "vpc-0abc"
    error_message = "strings must expose insecure_value under the local name"
  }

  assert {
    condition     = data.aws_ssm_parameter.this["network/vpc_id"].name == "/alpha/dev/network/vpc_id"
    error_message = "Parameter name must be <ssm_prefix>/<stack>/<key>"
  }

  assert {
    condition     = output.lists == {}
    error_message = "lists must be empty when no list is requested"
  }
}

run "lists_split_by_comma" {
  command = plan

  variables {
    lists = { subnet_ids_app = "network/subnet_ids_app" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["network/subnet_ids_app"]
    values = { insecure_value = "subnet-a,subnet-b" }
  }

  assert {
    condition     = output.lists["subnet_ids_app"] == tolist(["subnet-a", "subnet-b"])
    error_message = "lists must split the stored value on commas"
  }

  assert {
    condition     = output.strings == {}
    error_message = "strings must be empty when no string is requested"
  }
}

run "list_with_single_element" {
  command = plan

  variables {
    lists = { azs = "network/azs" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["network/azs"]
    values = { insecure_value = "ap-northeast-1a" }
  }

  assert {
    condition     = output.lists["azs"] == tolist(["ap-northeast-1a"])
    error_message = "A value without commas must become a one element list"
  }
}

run "same_path_read_once" {
  command = plan

  variables {
    strings = { vpc_id = "network/vpc_id", main_vpc = "network/vpc_id" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["network/vpc_id"]
    values = { insecure_value = "vpc-0abc" }
  }

  assert {
    condition     = length(data.aws_ssm_parameter.this) == 1
    error_message = "Two local names for one path must read it once"
  }

  assert {
    condition     = output.strings == { vpc_id = "vpc-0abc", main_vpc = "vpc-0abc" }
    error_message = "Both local names must expose the value"
  }
}

run "string_and_list_same_path_read_once" {
  command = plan

  variables {
    strings = { raw = "network/subnets" }
    lists   = { parsed = "network/subnets" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["network/subnets"]
    values = { insecure_value = "a,b" }
  }

  assert {
    condition     = length(data.aws_ssm_parameter.this) == 1
    error_message = "A path used by both maps must be read once"
  }

  assert {
    condition     = output.strings["raw"] == "a,b" && output.lists["parsed"] == tolist(["a", "b"])
    error_message = "strings keep the raw value and lists split it"
  }
}

run "empty_inputs_no_data_source" {
  command = plan

  assert {
    condition     = length(data.aws_ssm_parameter.this) == 0
    error_message = "No data source must be read when both maps are empty"
  }

  assert {
    condition     = output.strings == {} && output.lists == {}
    error_message = "Both outputs must be empty maps"
  }
}

run "json_values_untouched" {
  command = plan

  variables {
    strings = { database = "data/database" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"host\":\"a,b\",\"port\":5432}" }
  }

  assert {
    condition     = output.strings["database"] == "{\"host\":\"a,b\",\"port\":5432}"
    error_message = "JSON values must be returned untouched"
  }

  assert {
    condition     = jsondecode(output.strings["database"]).port == 5432
    error_message = "The caller must be able to jsondecode the value"
  }
}

run "prefix_accepts_project_env" {
  command = plan

  variables {
    ssm_prefix = "/alpha-x/dev1"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.this) == 0
    error_message = "A valid prefix must be accepted"
  }
}

run "prefix_rejects_missing_leading_slash" {
  command = plan

  variables {
    ssm_prefix = "alpha/dev"
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

run "prefix_rejects_hyphen_in_env" {
  command = plan

  variables {
    ssm_prefix = "/alpha/dev-1"
  }

  expect_failures = [var.ssm_prefix]
}

run "string_value_accepts_hyphenated_stack" {
  command = plan

  variables {
    strings = { role = "iam-base/role_rds_proxy_arn" }
  }

  override_data {
    target = data.aws_ssm_parameter.this["iam-base/role_rds_proxy_arn"]
    values = { insecure_value = "arn:aws:iam::111111111111:role/x" }
  }

  assert {
    condition     = output.strings["role"] == "arn:aws:iam::111111111111:role/x"
    error_message = "A kebab-case stack with a snake_case key must be accepted"
  }
}

run "string_rejects_uppercase_key" {
  command = plan

  variables {
    strings = { vpc_id = "network/VPC_ID" }
  }

  expect_failures = [var.strings]
}

run "string_rejects_leading_slash" {
  command = plan

  variables {
    strings = { vpc_id = "/network/vpc_id" }
  }

  expect_failures = [var.strings]
}

run "string_rejects_missing_key" {
  command = plan

  variables {
    strings = { vpc_id = "network" }
  }

  expect_failures = [var.strings]
}

run "string_rejects_hyphen_in_key" {
  command = plan

  variables {
    strings = { vpc_id = "network/vpc-id" }
  }

  expect_failures = [var.strings]
}

run "list_rejects_uppercase_key" {
  command = plan

  variables {
    lists = { subnets = "network/VPC_ID" }
  }

  expect_failures = [var.lists]
}

run "list_rejects_leading_slash" {
  command = plan

  variables {
    lists = { subnets = "/network/subnet_ids" }
  }

  expect_failures = [var.lists]
}

run "list_rejects_missing_key" {
  command = plan

  variables {
    lists = { subnets = "network" }
  }

  expect_failures = [var.lists]
}
