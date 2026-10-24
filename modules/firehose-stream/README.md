# firehose-stream

建一個 Firehose delivery stream：來源是 Kinesis Data Stream 或 Direct PUT，目的地二選一（S3，或 VPC 內的 OpenSearch，失敗的文件備份到 S3）。S3 物件、Direct PUT 的 at-rest 加密與 module 建的 log group 一律用客戶管理的 KMS key，delivery 的 CloudWatch logging 一律開啟。資料管線的中段：Kinesis 讀進來，GZIP JSON 寫到 raw bucket，或寫進 OpenSearch。

## 用法

```hcl
module "raw" {
  source = "git::https://github.com/<org>/<repo>.git//modules/firehose-stream?ref=firehose-stream-v0.1.0"

  name              = "alpha-dev-raw"
  role_arn          = module.role_firehose.arn
  kms_key_arn       = module.key.key_arn
  source_stream_arn = module.events.arn

  s3 = {
    bucket_arn          = module.raw_bucket.arn
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
  }
}
```

寫進 VPC 內的 OpenSearch：多給 `opensearch`，`s3` 就變成失敗文件的備份位置。

```hcl
module "search" {
  source = "git::https://github.com/<org>/<repo>.git//modules/firehose-stream?ref=firehose-stream-v0.1.0"

  name              = "alpha-dev-search"
  role_arn          = module.role_firehose.arn
  kms_key_arn       = module.key.key_arn
  source_stream_arn = module.events.arn

  s3 = {
    bucket_arn = module.raw_bucket.arn
    prefix     = "errors/"
  }

  opensearch = {
    domain_arn         = module.domain.arn
    index_name         = "alpha-dev-events"
    subnet_ids         = module.vpc.data_subnet_ids
    security_group_ids = [module.sg_firehose.id]
  }
}
```

完整範例見 [`examples/kinesis-to-s3/`](./examples/kinesis-to-s3/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 目的地 | 沒給 `opensearch` 是 `extended_s3`，給了是 `opensearch` |
| SSE | `source_stream_arn = null`（Direct PUT）時開 SSE，`CUSTOMER_MANAGED_CMK` 加 `kms_key_arn`；給了來源 stream 就不開（SSE 只支援 Direct PUT，at-rest 加密在來源 stream） |
| S3 加密 | 寫進 S3 的物件（含 OpenSearch 的失敗文件備份）用 `kms_key_arn` |
| 壓縮 | `GZIP`（可改，預設不變） |
| buffer | S3 預設 `buffering_interval = 900` 秒、`buffering_size = 64` MiB（事件觸發 ETL 靠 900 秒壓低觸發次數） |
| OpenSearch 備份 | `s3_backup_mode = "FailedDocumentsOnly"` 寫死，只存失敗的文件 |
| logging | delivery 與 S3 備份的 CloudWatch logging 都開，log group `/aws/kinesisfirehose/<name>` 由 module 建，用 `kms_key_arn` 加密，保留 `log_retention_days`（預設 30） |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- **Direct PUT 與 Kinesis 來源的加密不一樣**：Direct PUT 的 stream 由這個 module 開 SSE；Kinesis 來源的 stream 不開 SSE（AWS 只給 Direct PUT 開），資料在來源 Kinesis stream 加密，所以來源 stream 要用 KMS（`kinesis-stream` 已寫死）。
- **prefix 規則**：`s3.prefix` 用了 `!{timestamp:...}` 這類表達式時，`s3.error_output_prefix` 必填，而且要含 `!{firehose:error-output-type}`；`prefix` 不能含這個表達式；`error_output_prefix` 本身用了表達式也要含它。`prefix` 沒有表達式時可以不給 `error_output_prefix`，AWS 會自己補。這些規則在 module 就會擋下，不必等到 apply。
- **buffer 範圍**：`buffering_interval` 0–900 秒、`buffering_size` 1–128 MiB（S3，OpenSearch 備份的 S3 也一樣）。OpenSearch 目的地本身的 buffer 用 AWS 預設值（300 秒、5 MiB），module 不開放。
- **role**：`role_arn` 由呼叫端建立，trust 是 `firehose.amazonaws.com`，同一個 role 也可以給 OpenSearch 的 `vpc_config`（AWS 文件允許沿用 delivery role）。權限要涵蓋：讀來源 stream（`kinesis:*` 讀取動作）、對 raw bucket 的 `s3:PutObject` 等、`kms:GenerateDataKey`／`kms:Decrypt`、`logs:PutLogEvents`；OpenSearch 目的地還要 `es:DescribeDomain` 系列與 `es:ESHttpPost`／`ESHttpPut`／`ESHttpGet`，以及 8 個 `ec2:*NetworkInterface*`／`Describe*` 動作（建好後不能收回）。這個 module 不建 IAM。
- **OpenSearch 端**：Firehose 的 role 要先對應到 domain 的 FGAC role（見 `opensearch-config`），domain access policy 要放行這個 role。目的地的 subnet 要有足夠的空 IP，每個 subnet 最多會建 3 個 ENI。
- **index 輪替**：`index_rotation_period` 為 `NoRotation`、`OneHour`、`OneDay`（預設）、`OneWeek`、`OneMonth`，Firehose 會在 `index_name` 後面加時間戳。
- **KMS**：`kms_key_arn` 只收客戶管理 key 的 ARN，不收 alias 與裸 key id；key 要是 symmetric，key policy 要讓 `role_arn` 能用，Firehose 開 SSE 時會建立 grant（呼叫端要有 `kms:CreateGrant`），log group 加密還要讓 `logs.<region>.amazonaws.com` 能用這把 key。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

Redshift 目的地（AWS 要求 Redshift 公開才能收，跟「Redshift 不公開」衝突）、Parquet 轉換、dynamic partitioning、Lambda 處理、HTTP endpoint、Splunk、Snowflake、Iceberg、OpenSearch Serverless、MSK 來源、`AllDocuments` 備份、不加密的 stream、告警（用 `metric-alarm`）、IAM role 與 security group。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | delivery stream 名稱，1–64 字元，限英數字、`_`、`-`、`.`。 |
| `role_arn` | `string` | 無 | 是 | Firehose 假設的 IAM role ARN，由呼叫端建立。同一個 role 用於讀來源 stream、寫 S3、寫 OpenSearch、建 VPC 內的 ENI 與寫 CloudWatch Logs；trust 要是 `firehose.amazonaws.com`。 |
| `kms_key_arn` | `string` | 無 | 是 | 客戶管理的 KMS key ARN（symmetric），必填。Direct PUT 的 SSE、S3 物件加密與 module 建的 log group 都用這把 key；key policy 要讓 `role_arn` 與 CloudWatch Logs 能用它。 |
| `source_stream_arn` | `string` | `null` | 否 | 來源 Kinesis Data Stream 的 ARN。`null` 是 Direct PUT，這時 module 會用 `kms_key_arn` 開 SSE；給了來源就不開 SSE（SSE 只支援 Direct PUT，at-rest 加密由來源 stream 負責）。 |
| `s3` | `object` | 無 | 是 | S3 設定，必填。沒給 `opensearch` 時是主要目的地（`extended_s3`）；給了 `opensearch` 時是失敗文件的備份（只備份失敗的）。`bucket_arn` 是 bucket 的 ARN（不含物件路徑）；`prefix` 可用 `!{timestamp:...}`，用了表達式就必須給 `error_output_prefix`，而且它要含 `!{firehose:error-output-type}`；`buffering_size` 單位 MiB（1–128，預設 64）；`buffering_interval` 單位秒（0–900，預設 900，事件觸發 ETL 靠它壓低觸發次數）；`compression` 預設 `GZIP`。 |
| `opensearch` | `object` | `null` | 否 | OpenSearch 目的地；`null` 就是 S3 目的地。domain 一定在 VPC 內，所以 `subnet_ids`（1–16 個）與 `security_group_ids`（1–5 個）必填；Firehose 會在這些 subnet 建 ENI，role 要有建 ENI 的 `ec2:*` 權限，建好後不能收回。`index_rotation_period` 為 `NoRotation`、`OneHour`、`OneDay`、`OneWeek`、`OneMonth`；`retry_seconds` 0–7200。 |
| `log_retention_days` | `number` | `30` | 否 | module 自己建的 log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 30）。 |
| `tags` | `map(string)` | `{}` | 否 | 資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | delivery stream 名稱。 |
| `arn` | delivery stream 的 ARN。 |
| `log_group_name` | module 建的 CloudWatch log group 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/firehose-stream
```
