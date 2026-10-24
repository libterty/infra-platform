# dynamodb-table

建一張 DynamoDB table：on-demand 或 provisioned、可選 GSI、TTL、Streams、Contributor Insights。加密（客戶管理 KMS key）、point-in-time recovery 與刪除保護是固定的安全設定，不能關。

## 用法

```hcl
module "orders" {
  source = "git::https://github.com/<org>/<repo>.git//modules/dynamodb-table?ref=dynamodb-table-v0.1.0"

  name        = "alpha-dev-orders"
  kms_key_arn = module.key.key_arn

  hash_key  = "customer_id"
  range_key = "order_id"

  attributes = {
    customer_id = "S"
    order_id    = "S"
    status      = "S"
    created_at  = "N"
  }

  global_secondary_indexes = {
    by-status = { hash_key = "status", range_key = "created_at" }
  }

  ttl_attribute    = "expires_at"
  stream_view_type = "NEW_AND_OLD_IMAGES"
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | `server_side_encryption` 開啟，key 是必填輸入 `kms_key_arn`（客戶管理 key），沒有 AWS 擁有的 key 或 AWS 管理 key 的選項 |
| point-in-time recovery | 一律開啟，`point_in_time_recovery_days` 預設 35，範圍 1–35 |
| 刪除保護 | `deletion_protection` 預設 `true` |
| 計費模式 | `billing_mode` 預設 `PAY_PER_REQUEST` |
| GSI 的 key | 一律寫成 `key_schema`（provider 6.x 已把 GSI 的 `hash_key`、`range_key` 標為 deprecated） |

## 注意

- **`attributes` 只能放用在 key 的屬性，不缺也不多。** 缺一個（例如 GSI 的 `hash_key` 沒宣告），或多放一個沒用在 key 的屬性，都會被 validation 擋下，不必等到 apply 才被 DynamoDB 拒絕。TTL 屬性與其他資料欄位不是 key，不要放進來。
- `hash_key`、`range_key` 建立後不能改，改了會重建 table。
- `PROVISIONED` 要給 `read_capacity`、`write_capacity`，每個 GSI 也要各自給；`PAY_PER_REQUEST` 全部都要是 `null`。module 不做 autoscaling。
- `point_in_time_recovery_days` 與刪除保護不能整個關掉。要 destroy 之前，先把 `deletion_protection` 設成 `false` 並 apply；PITR 隨 table 一起刪除。
- `kms_key_arn` 只收客戶管理 key 的 ARN（含 multi-Region key），不收 alias；key policy 要讓存取這張 table 的 role 能使用這把 key。
- `stream_view_type` 有給才開 Streams，`stream_arn` 輸出在沒開時是 `null`。
- `contributor_insights` 只對 table 本身開，不含 GSI；另外計費。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

global table 與 replica、local secondary index（只能在建立 table 時定義）、GSI 的多屬性 key、resource policy、從備份或 S3 匯入、autoscaling、Kinesis streaming destination、`on_demand_throughput` 與 `warm_throughput`、資料項目。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | table 名稱，3–255 字元，限英數字、`_`、`-`、`.`。 |
| `kms_key_arn` | `string` | 無 | 是 | table 加密（SSE）用的客戶管理 KMS key ARN，必填；不提供使用 AWS 擁有的 key 或 AWS 管理 key 的選項。key policy 要讓存取這張 table 的 role 能用這把 key。 |
| `hash_key` | `string` | 無 | 是 | partition key 的屬性名稱，必須同時出現在 `attributes`。建立後不能改。 |
| `range_key` | `string` | `null` | 否 | sort key 的屬性名稱；`null` 表示沒有 sort key。給了就必須同時出現在 `attributes`。建立後不能改。 |
| `attributes` | `map(string)` | 無 | 是 | 屬性名稱對應型別（`S`、`N`、`B`）。只能宣告用在 key 的屬性：`hash_key`、`range_key` 與 `global_secondary_indexes` 的 key，不缺也不多；TTL 屬性與其他資料欄位不要放進來。 |
| `billing_mode` | `string` | `"PAY_PER_REQUEST"` | 否 | `PAY_PER_REQUEST`（預設，按請求計費）或 `PROVISIONED`（要給 `read_capacity`、`write_capacity`，GSI 也要各自給容量）。 |
| `read_capacity` | `number` | `null` | 否 | table 的讀取容量單位，至少 1。`billing_mode = "PROVISIONED"` 時必填，`PAY_PER_REQUEST` 時必須是 `null`。 |
| `write_capacity` | `number` | `null` | 否 | table 的寫入容量單位，至少 1。`billing_mode = "PROVISIONED"` 時必填，`PAY_PER_REQUEST` 時必須是 `null`。 |
| `global_secondary_indexes` | `map(object)` | `{}` | 否 | GSI，key 是 index 名稱（3–255 字元）。欄位：`hash_key`、`range_key`（都必須出現在 `attributes`，用 `key_schema` 寫入）、`projection_type`（`ALL`、`KEYS_ONLY`、`INCLUDE`，預設 `ALL`）、`non_key_attributes`（只有 `INCLUDE` 要給，而且必給）、`read_capacity`、`write_capacity`（`PROVISIONED` 時必填，`PAY_PER_REQUEST` 時必須是 `null`）。 |
| `ttl_attribute` | `string` | `null` | 否 | 存放 TTL 過期時間（epoch 秒）的屬性名稱；`null` 不開 TTL。這個屬性不是 key，不要放進 `attributes`。 |
| `stream_view_type` | `string` | `null` | 否 | `null` 不開 DynamoDB Streams；給值就開，並決定寫進 stream 的內容：`KEYS_ONLY`、`NEW_IMAGE`、`OLD_IMAGE`、`NEW_AND_OLD_IMAGES`。 |
| `point_in_time_recovery_days` | `number` | `35` | 否 | point-in-time recovery 的保留天數，1–35（預設 35）。PITR 固定開啟，沒有關閉的選項。 |
| `deletion_protection` | `bool` | `true` | 否 | 刪除保護，預設開啟。要 destroy 之前，先把它設成 `false` 並 apply。 |
| `table_class` | `string` | `"STANDARD"` | 否 | `STANDARD`（預設）或 `STANDARD_INFREQUENT_ACCESS`。 |
| `contributor_insights` | `bool` | `false` | 否 | 是否對 table 開 CloudWatch Contributor Insights（另外計費）。只開 table 本身，不含 GSI。 |
| `tags` | `map(string)` | `{}` | 否 | table 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `table_name` | table 名稱。 |
| `arn` | table 的 ARN。 |
| `stream_arn` | DynamoDB Streams 的 ARN；沒開 stream（`stream_view_type = null`）時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/dynamodb-table
```
