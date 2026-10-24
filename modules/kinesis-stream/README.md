# kinesis-stream

建一個 Kinesis Data Stream：容量模式二選一（`ON_DEMAND`、`PROVISIONED`），一律用客戶管理的 KMS key 做 at-rest 加密。資料管線的入口，producer 寫進來，Firehose 或其他 consumer 讀出去。

## 用法

```hcl
module "events" {
  source = "git::https://github.com/<org>/<repo>.git//modules/kinesis-stream?ref=kinesis-stream-v0.1.0"

  name        = "alpha-dev-events"
  kms_key_arn = module.key.key_arn

  mode        = "PROVISIONED"
  shard_count = 1
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | `encryption_type = "KMS"`，key 是必填輸入 `kms_key_arn`，沒有不加密或用 AWS 管理 key 的選項 |
| 容量模式 | `mode` 預設 `ON_DEMAND`；`PROVISIONED` 才有 `shard_count` |
| 保留 | `retention_hours` 預設 24，範圍 24–8760 |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- `kms_key_arn` 只收客戶管理 key 的 ARN（含 multi-Region key），不收 alias 與裸 key id。key 要是 symmetric，key policy 或呼叫端的 role 要讓 producer 有 `kms:GenerateDataKey`、consumer 有 `kms:Decrypt`；這個 module 不管 key policy 與 IAM。
- `mode = "PROVISIONED"` 一定要給 `shard_count`（至少 1）；`ON_DEMAND` 給了會被 validation 擋下，因為 provider 對 on-demand 的 `shard_count` 沒有意義。
- 保留超過 24 小時與開啟 shard 層級指標都另外計費。`shard_level_metrics` 不收 `ALL`（provider 文件建議明列），預設一個都不開。
- stream 的存取權限（producer 的 `kinesis:PutRecord(s)`、consumer 的讀取）由呼叫端給各自的 role，這個 module 不建 IAM。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

enhanced fan-out consumer、resource policy、不加密的 stream、自訂 `max_record_size_in_kib`、`enforce_consumer_deletion`、告警（用 `metric-alarm`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | stream 名稱，1–128 字元，限英數字、`_`、`-`、`.`。 |
| `kms_key_arn` | `string` | 無 | 是 | stream 加密用的客戶管理 KMS key ARN（symmetric），必填。`encryption_type` 固定是 `KMS`；key policy 要讓 producer 與 consumer 的 role 能用這把 key。 |
| `mode` | `string` | `"ON_DEMAND"` | 否 | 容量模式：`ON_DEMAND`（自動擴縮，不能給 `shard_count`）或 `PROVISIONED`（必須給 `shard_count`）。 |
| `shard_count` | `number` | `null` | 否 | shard 數量，至少 1。`mode = "PROVISIONED"` 時必填，`ON_DEMAND` 時必須是 `null`。 |
| `retention_hours` | `number` | `24` | 否 | 資料保留時數，24–8760（預設 24）。超過 24 小時的保留期會另外計費。 |
| `shard_level_metrics` | `set(string)` | `[]` | 否 | 要開的 shard 層級 CloudWatch 指標（`IncomingBytes`、`IncomingRecords`、`OutgoingBytes`、`OutgoingRecords`、`WriteProvisionedThroughputExceeded`、`ReadProvisionedThroughputExceeded`、`IteratorAgeMilliseconds`）。不收 `ALL`，要開就明列；空的就不開（額外計費）。 |
| `tags` | `map(string)` | `{}` | 否 | stream 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | stream 名稱。 |
| `arn` | stream 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/kinesis-stream
```
