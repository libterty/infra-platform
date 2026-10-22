mock_provider "aws" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"
}

run "output_is_valid_json_with_statements" {
  command = plan

  assert {
    condition     = jsondecode(output.load_balancer_controller_policy_json).Version == "2012-10-17" && length(jsondecode(output.load_balancer_controller_policy_json).Statement) > 0
    error_message = "LB Controller policy must be a policy document with statements"
  }
}

run "equals_vendored_official_file" {
  command = plan

  assert {
    condition     = jsondecode(output.load_balancer_controller_policy_json) == jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.1.json"))
    error_message = "Output must decode to exactly the vendored official iam_policy.json"
  }
}

run "output_is_minified" {
  command = plan

  assert {
    condition     = output.load_balancer_controller_policy_json == jsonencode(jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.1.json")))
    error_message = "Output must be the compact jsonencode form of the vendored file"
  }
}

run "partition_does_not_change_lb_controller_policy" {
  command = plan

  variables {
    partition = "aws-cn"
  }

  assert {
    condition     = jsondecode(output.load_balancer_controller_policy_json) == jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.1.json"))
    error_message = "The official policy is used verbatim whatever the partition"
  }
}

run "default_version_is_3_6_1" {
  command = plan

  assert {
    condition     = output.load_balancer_controller_policy_json == jsonencode(jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.1.json")))
    error_message = "The default LB Controller policy must be the vendored v3.6.1 file"
  }
}

run "explicit_supported_versions_accepted" {
  command = plan

  variables {
    load_balancer_controller_version = "3.6.0"
  }

  assert {
    condition     = jsondecode(output.load_balancer_controller_policy_json) == jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.0.json"))
    error_message = "3.6.0 must still be accepted and return the vendored v3.6.0 file"
  }
}

run "explicit_3_6_1_accepted" {
  command = plan

  variables {
    load_balancer_controller_version = "3.6.1"
  }

  assert {
    condition     = jsondecode(output.load_balancer_controller_policy_json) == jsondecode(file("${path.module}/policies/aws-load-balancer-controller/v3.6.1.json"))
    error_message = "3.6.1 must be accepted"
  }
}

run "unsupported_version_rejected" {
  command = plan

  variables {
    load_balancer_controller_version = "3.5.0"
  }

  expect_failures = [var.load_balancer_controller_version]
}

run "version_with_v_prefix_rejected" {
  command = plan

  variables {
    load_balancer_controller_version = "v3.6.0"
  }

  expect_failures = [var.load_balancer_controller_version]
}

run "path_traversal_version_rejected" {
  command = plan

  variables {
    load_balancer_controller_version = "../../x"
  }

  expect_failures = [var.load_balancer_controller_version]
}
