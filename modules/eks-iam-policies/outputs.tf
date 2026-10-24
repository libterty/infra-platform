output "load_balancer_controller_policy_json" {
  description = "所選版本的 AWS Load Balancer Controller 官方 IAM policy，去空白的 JSON 字串。"
  value       = local.load_balancer_controller_policy_json
}

output "karpenter_controller_policy_json" {
  description = "所選版本的 Karpenter controller IAM policy（官方各份 controller policy 併成一份），去空白的 JSON 字串。`karpenter` 為 `null` 時是 `null`。"
  value       = local.karpenter_controller_policy_json
}

output "argo_rollouts_cloudwatch_policy_json" {
  description = "Argo Rollouts 做 CloudWatch 指標分析用的 policy（`cloudwatch:GetMetricData`），去空白的 JSON 字串。"
  value       = local.argo_rollouts_cloudwatch_policy_json
}

output "keda_cloudwatch_policy_json" {
  description = "KEDA `aws-cloudwatch` scaler 用的 policy（`cloudwatch:GetMetricData`），去空白的 JSON 字串。"
  value       = local.keda_cloudwatch_policy_json
}

output "policy_sizes" {
  description = "各 policy JSON 去空白後的字元數（`map(number)`），IAM 就是這樣計入 role inline policy 的 10,240 字元上限。key：`load_balancer_controller`、`argo_rollouts_cloudwatch`、`keda_cloudwatch`，`karpenter` 有給時加 `karpenter_controller`。放在同一個 role 的 policy 要把大小加總。"
  value       = local.policy_sizes
}
