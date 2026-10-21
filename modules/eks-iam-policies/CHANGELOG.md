# Changelog

## 0.1.0（2026-10-21）

初版。tag 在驗收後由人手動打。

- 不建任何資源，只把輸入轉成 policy JSON 輸出：`load_balancer_controller_policy_json`、`karpenter_controller_policy_json`（`karpenter` 為 `null` 時是 `null`）、`argo_rollouts_cloudwatch_policy_json`、`policy_sizes`。
- 附的版本：AWS Load Balancer Controller `3.6.0`（官方 `iam_policy.json` 原樣收錄，16 段 statement）、Karpenter `1.15.0`（官方 CloudFormation 的 controller policy，18 段 statement 全收）。其他版本被 validation 擋下。
- Karpenter 的 `iam:PassRole` 只限 `karpenter.node_role_arn`，SQS 動作只限 `interruption_queue_name` 組出的 queue ARN。
- `versions.tf` 仍宣告 `aws` provider，原因見 README「限制」。
