output "load_balancer_controller_policy_json" {
  description = "Official AWS Load Balancer Controller IAM policy for the selected version, as compact JSON."
  value       = local.load_balancer_controller_policy_json
}

output "karpenter_controller_policy_json" {
  description = "Karpenter controller IAM policy for the selected version (all official controller policies in one document), as compact JSON. Null when karpenter is null."
  value       = local.karpenter_controller_policy_json
}

output "argo_rollouts_cloudwatch_policy_json" {
  description = "Policy for Argo Rollouts CloudWatch metric analysis: cloudwatch:GetMetricData, as compact JSON."
  value       = local.argo_rollouts_cloudwatch_policy_json
}

output "keda_cloudwatch_policy_json" {
  description = "Policy for the KEDA aws-cloudwatch scaler: cloudwatch:GetMetricData, as compact JSON."
  value       = local.keda_cloudwatch_policy_json
}

output "policy_sizes" {
  description = "Characters of each policy JSON with whitespace removed, which is how IAM counts against the 10,240-character inline policy limit of a role. Keys: load_balancer_controller, argo_rollouts_cloudwatch, keda_cloudwatch, and karpenter_controller when karpenter is set. Add the sizes of the policies put on the same role."
  value       = local.policy_sizes
}
