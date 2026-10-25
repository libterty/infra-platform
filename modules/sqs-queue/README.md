# sqs-queue

建一個 SQS queue 與它的 DLQ：收超過 `max_receive_count` 次的訊息移到 DLQ，DLQ 只接受這個 queue 轉來的訊息。兩個 queue 一律用客戶管理的 KMS key 加密。要讓 EventBridge rule 送進來，給 `allowed_source_arns` 就會產生只允許那些 rule 的 queue policy。

## 用法

```hcl
module "model_approved" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sqs-queue?ref=sqs-queue-v0.1.0"

  name        = "alpha-dev-model-approved"
  kms_key_arn = module.key.key_arn

  visibility_timeout_seconds = 300
  allowed_source_arns        = [module.model_approved_rule.rule_arn]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | 主 queue 與 DLQ 都用 `kms_key_arn`（必填），不提供 SQS 管理的 SSE |
| DLQ | 一定建立，名稱 `<name>-dlq`；redrive policy 寫在主 queue，redrive allow policy 是 `byQueue`，只允許主 queue |
| FIFO | `fifo = true` 時兩個 queue 都是 FIFO、名稱加 `.fifo`、開 content-based deduplication |
| queue policy | 只在 `allowed_source_arns` 有值時建立：principal 只有 `events.amazonaws.com`、動作只有 `sqs:SendMessage`、resource 是主 queue、條件 `aws:SourceArn` |
| tag | 給定的 `tags` 加上 `Name`（各自的 queue 名稱） |

## 注意

- EventBridge 的 SQS target 只能靠 queue policy 授權，所以 rule 要列進 `allowed_source_arns`。IoT rule 的 SQS action 是用 rule 的 role 寫入，不需要 queue policy；role 要有這個 queue 的 `sqs:SendMessage` 與 key 的 `kms:GenerateDataKey`、`kms:Decrypt`。
- 用 CMK 加密時，EventBridge 要能用這把 key：key policy 要允許 `events.amazonaws.com` 的 `kms:GenerateDataKey` 與 `kms:Decrypt`。這個 module 不管 key policy。
- 標準 queue 的訊息保留期是從進主 queue 時起算，移到 DLQ 後不會重算，所以 `dlq_retention_seconds` 要比 `message_retention_seconds` 長，否則訊息可能在 DLQ 裡很快就過期。預設主 queue 4 天、DLQ 14 天。
- `name` 不含 `.fifo`，最多 71 字元（加上 `-dlq.fifo` 後不超過 SQS 的 80 字元）。
- FIFO 開了 content-based deduplication，傳送端自己給 deduplication id 時以傳送端的為準。EventBridge 送 FIFO queue 要在 target 給 message group id（`eventbridge-rule` 的 `sqs_message_group_id`）。
- consumer 的 `visibility_timeout_seconds` 要比處理一則訊息的時間長，否則同一則訊息會被重複處理，且很快就累積到 `max_receive_count`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

SNS 訂閱、跨帳號 queue policy、SQS 管理的 SSE（一律 CMK）、DLQ 以外的 redrive 目的地、`delay_seconds` 與 `receive_wait_time_seconds` 等調校參數、FIFO 的 high throughput 模式、告警（用 `metric-alarm`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 主 queue 的名稱，1–71 字元，限英數字、`_`、`-`，不含 `.fifo`。DLQ 的名稱是 `<name>-dlq`；`fifo = true` 時兩個名稱都由 module 加上 `.fifo`。 |
| `kms_key_arn` | `string` | 無 | 是 | 主 queue 與 DLQ 加密用的客戶管理 KMS key ARN（symmetric），必填，不提供 SQS 管理的 SSE。key policy 要讓傳送端有 `kms:GenerateDataKey`、consumer 有 `kms:Decrypt`；EventBridge 寫入時 key policy 要允許 `events.amazonaws.com`。 |
| `fifo` | `bool` | `false` | 否 | 是否建 FIFO queue（預設 `false`）。`true` 時主 queue 與 DLQ 都是 FIFO、開 content-based deduplication，名稱加上 `.fifo`。 |
| `visibility_timeout_seconds` | `number` | `30` | 否 | 主 queue 的 visibility timeout 秒數，0–43200（預設 30）。要比 consumer 處理一則訊息的時間長。 |
| `message_retention_seconds` | `number` | `345600` | 否 | 主 queue 的訊息保留秒數，60–1209600（預設 345600，4 天）。 |
| `max_receive_count` | `number` | `5` | 否 | 訊息被收幾次還沒刪除就移到 DLQ，1–1000（預設 5）。 |
| `dlq_retention_seconds` | `number` | `1209600` | 否 | DLQ 的訊息保留秒數，60–1209600（預設 1209600，14 天）。標準 queue 的保留期從訊息進主 queue 時起算，DLQ 的保留期要比主 queue 長。 |
| `allowed_source_arns` | `list(string)` | `[]` | 否 | 可以送訊息到主 queue 的 EventBridge rule ARN（`arn:aws:events:...:rule/...`）。有值就建 queue policy，只允許 `events.amazonaws.com` 在 `aws:SourceArn` 符合時 `sqs:SendMessage`；空的就不建 queue policy（IoT rule 等用 role 寫入的來源不需要）。 |
| `tags` | `map(string)` | `{}` | 否 | 主 queue 與 DLQ 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `queue_arn` | 主 queue 的 ARN。 |
| `queue_url` | 主 queue 的 URL。 |
| `queue_name` | 主 queue 的名稱（FIFO 含 `.fifo`）。 |
| `dlq_arn` | DLQ 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/sqs-queue
```
