mock_provider "aws" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"
}

run "account_id_12_digits_accepted" {
  command = plan

  assert {
    condition     = length(output.load_balancer_controller_policy_json) > 0
    error_message = "A 12-digit account_id must be accepted"
  }
}

run "account_id_11_digits_rejected" {
  command = plan

  variables {
    account_id = "11111111111"
  }

  expect_failures = [var.account_id]
}

run "account_id_13_digits_rejected" {
  command = plan

  variables {
    account_id = "1111111111111"
  }

  expect_failures = [var.account_id]
}

run "account_id_letters_rejected" {
  command = plan

  variables {
    account_id = "11111111111a"
  }

  expect_failures = [var.account_id]
}

run "account_id_wildcard_rejected" {
  command = plan

  variables {
    account_id = "*"
  }

  expect_failures = [var.account_id]
}

run "account_id_trailing_newline_rejected" {
  command = plan

  variables {
    account_id = "111111111111\n"
  }

  expect_failures = [var.account_id]
}

run "partition_cn_accepted" {
  command = plan

  variables {
    partition = "aws-cn"
  }

  assert {
    condition     = length(output.load_balancer_controller_policy_json) > 0
    error_message = "aws-cn must be accepted"
  }
}

run "partition_unknown_rejected" {
  command = plan

  variables {
    partition = "aws*"
  }

  expect_failures = [var.partition]
}

run "region_wildcard_rejected" {
  command = plan

  variables {
    region = "*"
  }

  expect_failures = [var.region]
}

run "region_uppercase_rejected" {
  command = plan

  variables {
    region = "AP-NORTHEAST-1"
  }

  expect_failures = [var.region]
}

run "cluster_name_with_quote_rejected" {
  command = plan

  variables {
    cluster_name = "alpha\"dev"
  }

  expect_failures = [var.cluster_name]
}

run "cluster_name_with_wildcard_rejected" {
  command = plan

  variables {
    cluster_name = "alpha-*"
  }

  expect_failures = [var.cluster_name]
}

run "cluster_name_empty_rejected" {
  command = plan

  variables {
    cluster_name = ""
  }

  expect_failures = [var.cluster_name]
}

run "cluster_name_100_chars_accepted" {
  command = plan

  variables {
    cluster_name = join("", [for i in range(100) : "a"])
  }

  assert {
    condition     = length(output.load_balancer_controller_policy_json) > 0
    error_message = "A 100-char cluster name is the EKS maximum and must be accepted"
  }
}

run "cluster_name_101_chars_rejected" {
  command = plan

  variables {
    cluster_name = join("", [for i in range(101) : "a"])
  }

  expect_failures = [var.cluster_name]
}
