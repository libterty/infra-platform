mock_provider "aws" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"
}

run "sizes_without_karpenter" {
  command = plan

  assert {
    condition     = output.policy_sizes["load_balancer_controller"] == length(replace(file("${path.module}/policies/aws-load-balancer-controller/v3.6.0.json"), "/\\s/", ""))
    error_message = "load_balancer_controller size must count the official file with whitespace removed"
  }

  assert {
    condition     = output.policy_sizes["argo_rollouts_cloudwatch"] == length(replace(output.argo_rollouts_cloudwatch_policy_json, "/\\s/", ""))
    error_message = "argo_rollouts_cloudwatch size must match the output JSON"
  }

  assert {
    condition     = length(output.policy_sizes) == 2 && !contains(keys(output.policy_sizes), "karpenter_controller")
    error_message = "policy_sizes must omit karpenter_controller when karpenter is null"
  }
}

run "sizes_with_karpenter" {
  command = plan

  variables {
    karpenter = {
      node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      interruption_queue_name = "alpha-dev-karpenter"
    }
  }

  assert {
    condition     = output.policy_sizes["karpenter_controller"] == length(replace(output.karpenter_controller_policy_json, "/\\s/", ""))
    error_message = "karpenter_controller size must match the output JSON"
  }

  assert {
    condition     = length(output.policy_sizes) == 3
    error_message = "policy_sizes must have three keys when karpenter is set"
  }
}
