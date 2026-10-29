# s3-bucket

建一個 log 或內容用的 S3 bucket：封鎖公開存取、加密、lifecycle、只允許 TLS，並依輸入加上 log delivery 的寫入權限，或讓 CloudFront 透過 OAC 讀取。`foundation` 用它建 flow log bucket 與 access log bucket；像 Knowledge Base 語料這類不能過期的內容，就用 `never_expire = true`。

## 用法

```hcl
module "access_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.3.0"

  name            = "alpha-dev-access-logs"
  log_delivery    = ["vended_logs"]
  expiration_days = 14
}

module "flow_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.1.0"

  name         = "alpha-dev-flow-logs"
  log_delivery = ["vpc_flow_logs"]
  kms_key_arn  = module.key.key_arn
}

module "kb_corpus" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.1.1"

  name         = "alpha-dev-kb-corpus"
  never_expire = true
}

module "raw" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.4.0"

  name            = "alpha-dev-raw"
  kms_key_arn     = module.key.key_arn
  expiration_days = 365
  eventbridge     = true

  transitions = [
    { days = 30, storage_class = "STANDARD_IA" },
    { days = 90, storage_class = "GLACIER_IR" },
  ]
}

module "web" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.5.0"

  name                         = "alpha-dev-web"
  never_expire                 = true
  cloudfront_distribution_arns = [module.cdn.arn]
}

module "audit_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.6.0"

  name            = "alpha-dev-audit-logs"
  log_delivery    = ["cloudtrail", "config"]
  expiration_days = 365
  versioning      = {}
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 封鎖公開存取 | 四項全開 |
| object ownership | `BucketOwnerEnforced`（停用 ACL） |
| 只允許 TLS | bucket policy 第一段固定是 `Deny`，條件 `aws:SecureTransport = false` |
| lifecycle | 過期天數由 `expiration_days` 決定（沒給是 90），rule id `expire-objects`；`never_expire = true` 時不過期，rule id 改成 `abort-incomplete-uploads`。兩種都會在 7 天後清除未完成的 multipart upload |
| versioning | 預設關閉；`versioning` 有給（0.2.0 起）才開，並多一條 rule id `cleanup-noncurrent-versions`（整個 bucket：舊版本過期、清掉過期的 delete marker） |
| lifecycle 分層 | 預設沒有；`transitions`（0.4.0 起）寫進過期那條 rule（目前版本），跟過期共用 `expiration_prefix`；清舊版本那條 rule 不分層 |
| EventBridge | 預設關閉；`eventbridge = true`（0.4.0 起）才開，跟 `lambda_notifications` 共用同一個 `aws_s3_bucket_notification` |
| bucket policy | `depends_on` public access block，避免 policy 先套用而被判定為公開 |

## log delivery

| `log_delivery` 值 | principal | 動作與資源 | 條件 |
|---|---|---|---|
| `vended_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl`、`s3:ListBucket` on bucket | `aws:SourceAccount`、`aws:SourceArn` 符合 `arn:<partition>:logs:*:<account>:delivery-source:*`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |
| `vpc_flow_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl` on bucket | `aws:SourceAccount`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |
| `cloudtrail`（0.6.0 起） | `cloudtrail.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl` on bucket | `aws:SourceAccount`、`aws:SourceArn` 符合 `arn:<partition>:cloudtrail:*:<account>:trail/*`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |
| `config`（0.6.0 起） | `config.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/Config/*`；`s3:GetBucketAcl`、`s3:ListBucket` on bucket | `aws:SourceAccount`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |

`organization_id`（0.6.0 起）有給時，每種稽核來源再多兩段，條件改成 `aws:SourceOrgID = <organization ID>`：

| 來源 | 動作與資源 |
|---|---|
| `cloudtrail` | `s3:PutObject` on `<bucket>/AWSLogs/<organization ID>/*`（organization trail 的成員帳號路徑）；`s3:GetBucketAcl` on bucket |
| `config` | `s3:PutObject` on `<bucket>/AWSLogs/*/Config/*`（各成員帳號的路徑）；`s3:GetBucketAcl`、`s3:ListBucket` on bucket |

新的 statement 排在 `vpc_flow_logs` 之後、CloudFront 之前。沒有 `cloudtrail`、`config` 時，policy 跟 0.5.0 完全一樣。

## CloudFront 讀取

`cloudfront_distribution_arns`（0.5.0 起）非空時，bucket policy 最後多一條 statement：

| Sid | principal | 動作與資源 | 條件 |
|---|---|---|---|
| `AllowCloudFrontRead` | `cloudfront.amazonaws.com` | `s3:GetObject` on `<bucket>/*` | `StringEquals` `AWS:SourceArn` 是列出的 distribution ARN |

- 這是 CloudFront OAC 的標準寫法。principal 是固定的服務、條件是固定的 ARN，S3 不會把它當成公開 policy，所以封鎖公開存取維持四項全開也能用。
- 空的時候 policy 跟 0.4.0 完全一樣，原本的 statement 位置不變。
- distribution 必須在目前帳號，ARN 格式是 `arn:aws:cloudfront::<帳號>:distribution/<id>`；其他帳號的 distribution 會被 precondition 擋下。
- 只給 `s3:GetObject`，沒有 `s3:ListBucket`：不存在的物件 CloudFront 收到 403 而不是 404，SPA 的 fallback 要處理 403。
- **用 SSE-KMS 時，CloudFront 還要能用這把 key 解密**：key policy 要允許 `cloudfront.amazonaws.com` 做 `kms:Decrypt`，條件同樣是 `AWS:SourceArn`（用 `kms-key` 的 `service_principals` 給）。這個 module 不管 key policy；放公開靜態檔的 bucket 可以直接用 SSE-S3（`kms_key_arn = null`）避開。
- distribution 跟 bucket 在同一個 stack 時，distribution 讀 bucket 的 `bucket_regional_domain_name`，bucket policy 讀 distribution 的 ARN，兩個方向用的是不同的值，不會形成循環。

## 注意

- **`vended_logs` 給 `log-delivery` 的 `S3` 目的地用**（ALB、NLB、S3 server access log、CloudFront 等）。CloudWatch Logs 建 delivery 時會自己把這兩段加進 bucket policy，但這個 module 管整份 policy，下一次 apply 就會蓋掉，所以要在這裡宣告。只開放本帳號的 delivery source，source 可以在任何 region。
- 寫入範圍是 `AWSLogs/<account>/*`，對應 `log-delivery` 預設的路徑。`log-delivery` 不開放 destination prefix 與 Hive 相容路徑；之後要開的話，這裡的 resource 也要跟著改。
- **用 SSE-KMS 時必須是客戶管理的 key**，key policy 要允許 `delivery.logs.amazonaws.com` 使用（AWS 文件〈Logs sent to Amazon S3〉）；用 AWS 管理的 key，log 會變成讀不了的格式。key policy 不在這個 module 管。
- 0.3.0 移除了 `alb_access_logs`：`alb` 不再支援傳統的 `access_logs`，ALB access log 改用 `log-delivery` 送，bucket 改給 `vended_logs`。
- **`cloudtrail` 不鎖單一 trail**：AWS 文件建議 `aws:SourceArn` 寫死 trail ARN，但 bucket 通常比 trail 先建，所以這裡放寬成本帳號的任何 trail，另加 `aws:SourceAccount`。trail 設了 S3 key prefix 就寫不進來，寫入路徑固定是 `AWSLogs/`。
- **organization trail 的管理帳號路徑**：organization trail 的管理帳號自己的 log 寫在 `AWSLogs/<管理帳號>/`。bucket 跟 trail 在同一個帳號時，`cloudtrail` 的本帳號 statement 已經涵蓋；bucket 放在 log 封存帳號時，這條路徑沒有開，這個 module 只開 `AWSLogs/<organization ID>/`。
- **`config` 用 IAM role 投遞時**，跨帳號的 bucket 還要給那個 role `s3:ListBucket`，這個 module 不開；同帳號、或 Config 改用服務 principal 投遞時不需要。
- **稽核 bucket 用 SSE-KMS 時**，key policy 要允許 `cloudtrail.amazonaws.com`、`config.amazonaws.com` 使用這把 key（用 `kms-key` 的 `service_principals`）。
- 投遞失敗不會讓 `apply` 失敗，驗收條件是「S3 上真的有物件」。
- bucket 名稱不可含 `.`（會破壞 TLS virtual-host 定址）。
- `force_destroy` 預設 `false`，只放可重建的觀測資料時才在呼叫端打開。
- **不過期一律要明寫 `never_expire = true`。** `expiration_days = null` 代表預設的 90 天，不是不過期：呼叫端常用 `optional(number)` 轉傳，沒給值時就是 null，如果 null 代表不過期，log bucket 會在沒人注意時變成永久保存。
- `never_expire = true` 時不能再給 `expiration_days`，也不能有 `log_delivery`（log bucket 一定要過期），兩種都會被 validation 擋下。
- 預設沒有 versioning，物件被刪掉就救不回來；要保留舊版本就給 `versioning`（0.2.0 起）。`versioning` 不能跟 `vended_logs`、`vpc_flow_logs` 一起用；`cloudtrail`、`config` 的 bucket 放的是稽核證據，0.6.0 起可以開 versioning。清舊版本的 rule 套用整個 bucket，不受 `expiration_prefix` 限制。
- `expiration_prefix` 只限制「目前版本過期」那條 rule；沒給時範圍是整個 bucket，跟 0.1.1 相同。
- `lambda_notifications` 只建 bucket 這一側的 notification。呼叫端要自己讓 `s3.amazonaws.com` 有權限 invoke 那支 Lambda（permission 要帶 `source_account` 與 `source_arn`），而且要在 notification 之前建好，否則 S3 會拒絕建立 notification。
- 一個 bucket 只能有一個 `aws_s3_bucket_notification`，所以 `lambda_notifications` 設了之後，不要在 module 外面再對同一個 bucket 建 notification。
- `transitions` 的 `days` 要嚴格遞增、至少 1，而且都要小於過期天數（沒給 `expiration_days` 時是 90；`never_expire = true` 時不比較）。AWS 現行文件沒有寫死「`STANDARD_IA` 至少 30 天」這類下限，API 的 `Days` 是 0 或正整數；但 `STANDARD_IA`、`ONEZONE_IA` 最少存放 30 天、`GLACIER_IR`、`GLACIER` 最少 90 天，提早轉出去仍照最少天數計費，而且 AWS 說同一條 rule 不能在最少存放天數之前就轉到下一層。這個 module 不檢查相鄰兩層的間隔，排 `transitions` 時自己留夠。
- 小於 128 KB 的物件預設不會分層（2024 年 9 月起的 S3 預設行為），這個 module 沒有提供物件大小的 filter。
- `transitions` 只管目前版本；舊版本（`versioning`）一律只過期，不分層。
- `eventbridge = true` 只是讓 bucket 把事件送到 default event bus，沒有任何 rule 比對就不會觸發任何東西。rule、target 與 role 由呼叫端建，建議 rule 的 pattern 限定 `detail.bucket.name` 與 `detail.object.key` 的前綴。這個設定會送出這個 bucket 全部的事件，不能只送某個前綴。
- `lambda_notifications` 與 `eventbridge` 共用同一個 `aws_s3_bucket_notification`，兩個都沒給就不建，跟 0.3.1 相同。
- 沒有開 `versioning` 時，物件刪掉就救不回來；如果放的是 Knowledge Base 語料，物件一刪，下一次同步就會清掉對應的向量。

## 刻意不做

replication、object lock、bucket 本身的 access logging（要開就用 `log-delivery`，source 給這個 bucket 的 ARN、`log_type = "S3_SERVER_ACCESS_LOGS"`）、Lambda 與 EventBridge 以外的 event notification（SQS、SNS）、多個 prefix 各自的 lifecycle rule、依物件大小或 tag 過濾的分層、CORS、跨帳號寫入與讀取（包括其他帳號的 CloudFront distribution）、給 CloudFront 的 `s3:ListBucket`，以及允許其他 principal 寫入的 bucket policy。上傳後自動觸發 ingestion 由應用程式處理；上傳的人或 CI 用自己的 IAM 權限寫入。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | bucket 名稱，3–63 字元，小寫英數字與連字號，不可含 `.` 或 `--`。 |
| `kms_key_arn` | `string` | `null` | 否 | `null` 用 SSE-S3（`AES256`）；有給就用 SSE-KMS。`log_delivery` 含 `vended_logs` 或 `vpc_flow_logs` 時必須是客戶管理的 key，而且 key policy 要允許 `delivery.logs.amazonaws.com` 使用。 |
| `expiration_days` | `number` | `null` | 否 | 物件過期天數，1–3650；`null` 當成 90。`never_expire = true` 時必須是 `null`。 |
| `never_expire` | `bool` | `false` | 否 | 不設過期，物件保留到被明確刪除，lifecycle rule 沒有 expiration。給內容 bucket（例如 Knowledge Base 語料），不要用在 log bucket；與非空的 `log_delivery` 互斥。 |
| `log_delivery` | `set(string)` | `[]` | 否 | 允許寫入的 log 來源：`vended_logs`（本帳號 CloudWatch Logs 的 vended delivery，例如用 `log-delivery` 設定的 ALB、NLB、S3 access log）、`vpc_flow_logs`、`cloudtrail`（本帳號 trail 寫到 `AWSLogs/<帳號>/`）、`config`（本帳號 Config delivery channel 寫到 `AWSLogs/<帳號>/Config/`）。 |
| `organization_id` | `string` | `null` | 否 | AWS Organizations 的 organization ID（`o-` 開頭）。有給時，`log_delivery` 的 `cloudtrail` 多開 organization trail 的寫入路徑 `AWSLogs/<organization ID>/`，`config` 多開成員帳號的 `AWSLogs/<帳號>/Config/`，兩者都以 `aws:SourceOrgID` 限制；`log_delivery` 至少要有 `cloudtrail` 或 `config` 其中一種。`null` 只開本帳號的路徑。 |
| `cloudfront_distribution_arns` | `set(string)` | `[]` | 否 | 可以透過 OAC 讀取物件（`s3:GetObject`）的 CloudFront distribution ARN（`arn:aws:cloudfront::<帳號>:distribution/<id>`），必須是目前帳號。非空時 bucket policy 多一條 principal 為 `cloudfront.amazonaws.com`、條件為 `AWS:SourceArn` 的 statement；空的就不加。 |
| `versioning` | `object` | `null` | 否 | `null` 不開 versioning。給物件就開 versioning：舊版本在 `noncurrent_expiration_days`（1–3650，預設 30）天後過期，並清掉過期的 delete marker。與 `log_delivery` 的 `vended_logs`、`vpc_flow_logs` 互斥；`cloudtrail`、`config` 是稽核證據，可以開。 |
| `expiration_prefix` | `string` | `null` | 否 | 目前版本的過期規則只套用在這個 prefix 底下（1–1024 字元）；`null` 套用整個 bucket。 |
| `transitions` | `list(object)` | `[]` | 否 | 目前版本的 lifecycle 分層，依序列出 `days`（物件建立後第幾天，至少 1，必須嚴格遞增）與 `storage_class`（`STANDARD_IA`、`ONEZONE_IA`、`INTELLIGENT_TIERING`、`GLACIER_IR`、`GLACIER`、`DEEP_ARCHIVE`）。每個 `days` 都要小於過期天數（沒給 `expiration_days` 時是 90）；`never_expire = true` 時不比較。跟過期規則共用 `expiration_prefix`。空的就不分層。 |
| `eventbridge` | `bool` | `false` | 否 | 是否把這個 bucket 的所有 S3 事件送到本帳號 default event bus（`aws.s3`，例如 `Object Created`）。為 `true` 時建立 notification，可以跟 `lambda_notifications` 並存；呼叫端另外建 EventBridge rule 與 target。 |
| `lambda_notifications` | `map(object)` | `{}` | 否 | notification id 對應 bucket 事件要呼叫的 Lambda。欄位：`function_arn`（必須是 Lambda function ARN）、`events`（至少一個，預設 `s3:ObjectCreated:*`）、`filter_prefix`、`filter_suffix`。呼叫端要先給 `s3.amazonaws.com` 呼叫每個 function 的權限（帶 `source_account` 與 `source_arn`）再 apply。空的就不建 notification。 |
| `force_destroy` | `bool` | `false` | 否 | 是否允許刪除非空的 bucket。 |
| `tags` | `map(string)` | `{}` | 否 | bucket 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `bucket_name` | bucket 名稱。 |
| `arn` | bucket 的 ARN。 |
| `bucket_regional_domain_name` | bucket 的 regional domain name。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/s3-bucket
```
