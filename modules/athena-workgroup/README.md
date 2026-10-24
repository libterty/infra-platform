# athena-workgroup

建一個 Athena SQL workgroup：查詢設定由 workgroup 強制（使用者不能改結果位置或加密方式），結果一律用客戶管理的 KMS key 以 `SSE_KMS` 加密，每個查詢有掃描量上限，CloudWatch 指標開啟。可以順便建 named query。

## 用法

```hcl
module "athena" {
  source = "git::https://github.com/<org>/<repo>.git//modules/athena-workgroup?ref=athena-workgroup-v0.1.0"

  name                = "alpha-dev"
  results_bucket_name = module.results_bucket.name
  kms_key_arn         = module.key.key_arn

  named_queries = {
    latest-events = {
      database = "alpha_dev_curated"
      query    = "SELECT * FROM events ORDER BY event_time DESC LIMIT 10"
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 強制設定 | `enforce_workgroup_configuration = true`，workgroup 的設定蓋過 client 端 |
| 結果加密 | `encryption_option = "SSE_KMS"`，key 是必填輸入 `kms_key_arn`，沒有不加密或 `SSE_S3` 的選項 |
| 結果位置 | `s3://<results_bucket_name>/<results_prefix>`，預設前綴 `athena-results/` |
| 掃描上限 | `bytes_scanned_cutoff_per_query` 預設 10 GiB（`10737418240`），最小 `10485760`，`null` 會退回預設，不能關閉 |
| 指標 | `publish_cloudwatch_metrics_enabled = true` |
| 引擎 | `engine_version` 預設 `AUTO` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- **`enable_minimum_encryption_configuration` 沒有設**：AWS 文件寫明 `EnforceWorkGroupConfiguration` 為 `true` 時這個旗標會被忽略，改用 workgroup 自己的加密設定。這個 module 固定強制 workgroup 設定，所以不需要、也不開放這個旗標。
- **掃描上限的下限**：provider 在 plan 時就檢查至少 `10485760`（10 MiB），AWS API 文件寫的下限是 `10000000`；module 取較嚴的 provider 值，避免到 apply 才失敗。
- `kms_key_arn` 只收客戶管理 key 的 ARN，不收 alias 與裸 key id；查詢者的 role 要有這把 key 的 `kms:GenerateDataKey` 與 `kms:Decrypt`，也要有結果 bucket 的讀寫權限。module 不建 bucket、IAM 與 key policy。
- `results_bucket_name` 只收 bucket 名稱，不收 `s3://` 或 ARN；`results_prefix` 空字串或以 `/` 結尾。
- `force_destroy = false` 時，workgroup 裡還有 named query 或查詢歷史就刪不掉；開發環境要拆掉再改成 `true`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

代管查詢結果（managed query results）、Spark workgroup、capacity reservation、data catalog、Identity Center、S3 Access Grants、requester pays、告警（用 `metric-alarm`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | workgroup 名稱，1–128 字元，限英數字、`_`、`-`、`.`。 |
| `results_bucket_name` | `string` | 無 | 是 | 存放查詢結果的 S3 bucket 名稱（只有名稱，不含 `s3://`）。bucket 由呼叫端建立，查詢者的 role 要有它的讀寫權限。 |
| `results_prefix` | `string` | `"athena-results/"` | 否 | 查詢結果在 bucket 裡的前綴；空字串代表 bucket 根目錄，否則要以 `/` 結尾且不以 `/` 開頭（預設 `athena-results/`）。 |
| `kms_key_arn` | `string` | 無 | 是 | 查詢結果加密用的客戶管理 KMS key ARN（symmetric），必填。結果一律用 `SSE_KMS`；查詢者的 role 要有這把 key 的 `kms:GenerateDataKey` 與 `kms:Decrypt`。 |
| `bytes_scanned_cutoff_per_query` | `number` | `10737418240` | 否 | 單一查詢最多可掃描的位元組數，超過就取消查詢；至少 `10485760`（10 MiB，provider 的下限；AWS API 文件寫 `10000000`），預設 10 GiB（`10737418240`）。不提供「不設上限」的選項。 |
| `engine_version` | `string` | `"AUTO"` | 否 | Athena SQL 引擎版本：`AUTO`（預設，由 AWS 選）或指定的 `Athena engine version N`（例如 `Athena engine version 3`）。 |
| `named_queries` | `map(object)` | `{}` | 否 | 要建在 workgroup 裡的 named query，key 是名稱；`database` 是 Glue database 名稱，`query` 是 SQL（不可為空）。 |
| `force_destroy` | `bool` | `false` | 否 | 刪除 workgroup 時是否連同其中的 named query 與查詢歷史一起刪除（預設 `false`）。 |
| `tags` | `map(string)` | `{}` | 否 | workgroup 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | workgroup 名稱。 |
| `arn` | workgroup 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/athena-workgroup
```
