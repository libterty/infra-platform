# eventbridge-rule

建一條 EventBridge rule 與 1–5 個 target：rule 用 event pattern 比對事件，或用排程運算式定時觸發，兩者擇一。target 可以設 input transformer、DLQ 與 retry policy。

## 用法

```hcl
module "model_approved" {
  source = "git::https://github.com/<org>/<repo>.git//modules/eventbridge-rule?ref=eventbridge-rule-v0.1.0"

  name = "alpha-dev-model-approved"

  event_pattern = {
    source        = ["aws.sagemaker"]
    "detail-type" = ["SageMaker Model Package State Change"]
    detail = {
      ModelPackageGroupName = ["alpha-dev-models"]
      ModelApprovalStatus   = ["Approved"]
    }
  }

  targets = {
    queue = { arn = module.model_approved_queue.queue_arn }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 觸發方式 | `event_pattern`（物件，module 用 `jsonencode`）與 `schedule_expression` 恰好給一個 |
| target 數量 | 1–5 個，target id 是 map 的 key |
| target 授權 | SQS、SNS、Lambda 以外的 target 一定要有 `role_arn` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- SQS、SNS、Lambda target 是靠 target 自己的 resource policy 授權，不用 role：SQS 用 `sqs-queue` 的 `allowed_source_arns`（填這個 module 的 `rule_arn`）；SNS 要 topic policy 允許 `events.amazonaws.com`；Lambda 要 `aws_lambda_permission`。這些都不在這個 module 裡。queue 或 topic 用 CMK 加密時，key policy 也要允許 `events.amazonaws.com`。
- 其他 target（Step Functions、Kinesis、SageMaker pipeline 等）的 `role_arn` 由呼叫端建，部署者要有對它的 `iam:PassRole`。
- FIFO queue target 一定要給 `sqs_message_group_id`，標準 queue 不能給，validation 會擋。
- `dead_letter_arn` 只收 SQS queue；那個 queue 的 queue policy 也要允許這條 rule 送訊息（同樣可以用 `sqs-queue` 的 `allowed_source_arns`）。
- 排程 rule 只能掛 `default` bus。新的排程建議用 `scheduler-schedule`（EventBridge Scheduler 支援時區與 flexible window）。
- `event_bus_name` 只收名稱，不收 ARN；module 不建 event bus。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

自訂 event bus、archive 與 replay、API destination、跨帳號 target、ECS、Batch、Redshift 等 target 專用參數、`input` 與 `input_path`（用 `input_transformer`）、IAM role 與 resource policy。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | rule 名稱，1–64 字元，限英數字、`_`、`-`、`.`。 |
| `event_bus_name` | `string` | `"default"` | 否 | rule 掛的 event bus 名稱（預設 `default`）。module 不建 event bus；排程 rule 只能掛 `default`。 |
| `event_pattern` | `any` | `null` | 否 | event pattern 物件（module 用 `jsonencode` 轉成 JSON），例如 `{ source = ["aws.sagemaker"], "detail-type" = [...] }`。與 `schedule_expression` 二擇一。 |
| `schedule_expression` | `string` | `null` | 否 | 排程運算式，`rate(...)` 或 `cron(...)`，只能用在 `default` bus。與 `event_pattern` 二擇一。新的排程建議用 `scheduler-schedule`（EventBridge Scheduler）。 |
| `state` | `string` | `"ENABLED"` | 否 | rule 的狀態：`ENABLED`（預設）、`DISABLED`，或 `ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS`（連 read-only 的 CloudTrail 管理事件也比對）。 |
| `targets` | `map(object)` | 無 | 是 | rule 的 target，1–5 個，key 是 target id（1–64 字元，限英數字、`_`、`-`、`.`）。`arn` 是 target 的 ARN；`role_arn` 是 EventBridge 呼叫 target 用的 role，SQS、SNS、Lambda 以外的 target 必填（這三種靠 resource policy 授權）；`input_transformer` 改寫送給 target 的內容；`dead_letter_arn` 是送不出去時放事件的 SQS queue ARN；`retry` 的 `maximum_event_age_seconds` 60–86400、`maximum_retry_attempts` 0–185；`sqs_message_group_id` 只給 FIFO queue target，而且 FIFO queue target 必填。 |
| `tags` | `map(string)` | `{}` | 否 | rule 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `rule_arn` | rule 的 ARN；給 `sqs-queue` 的 `allowed_source_arns`。 |
| `rule_name` | rule 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/eventbridge-rule
```
