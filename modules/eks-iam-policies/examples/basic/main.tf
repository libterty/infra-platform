terraform {
  required_version = ">= 1.10"
}

module "policies" {
  source = "../.."

  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  account_id   = "111111111111"

  karpenter = {
    node_role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
    interruption_queue_name = "alpha-dev-karpenter"
  }
}

# Pass these to the iam-role module as inline_policies, one role per controller.
output "load_balancer_controller_policy_json" {
  value = module.policies.load_balancer_controller_policy_json
}

output "karpenter_controller_policy_json" {
  value = module.policies.karpenter_controller_policy_json
}

output "argo_rollouts_cloudwatch_policy_json" {
  value = module.policies.argo_rollouts_cloudwatch_policy_json
}

output "keda_cloudwatch_policy_json" {
  value = module.policies.keda_cloudwatch_policy_json
}

output "policy_sizes" {
  value = module.policies.policy_sizes
}
