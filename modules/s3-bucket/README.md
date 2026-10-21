# s3-bucket

建一個 log 或內容用的 S3 bucket：封鎖公開存取、加密、lifecycle、只允許 TLS，並依輸入加上 log delivery 的寫入權限。`foundation` 用它建 flow log bucket 與 access log bucket；像 Knowledge Base 語料這類不能過期的內容，就用 `never_expire = true`。

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
| bucket policy | `depends_on` public access block，避免 policy 先套用而被判定為公開 |

## log delivery

| `log_delivery` 值 | principal | 動作與資源 | 條件 |
|---|---|---|---|
| `vended_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl`、`s3:ListBucket` on bucket | `aws:SourceAccount`、`aws:SourceArn` 符合 `arn:<partition>:logs:*:<account>:delivery-source:*`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |
| `vpc_flow_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl` on bucket | `aws:SourceAccount`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |

## 注意

- **`vended_logs` 給 `log-delivery` 的 `S3` 目的地用**（ALB、NLB、S3 server access log、CloudFront 等）。CloudWatch Logs 建 delivery 時會自己把這兩段加進 bucket policy，但這個 module 管整份 policy，下一次 apply 就會蓋掉，所以要在這裡宣告。只開放本帳號的 delivery source，source 可以在任何 region。
- 寫入範圍是 `AWSLogs/<account>/*`，對應 `log-delivery` 預設的路徑。`log-delivery` 不開放 destination prefix 與 Hive 相容路徑；之後要開的話，這裡的 resource 也要跟著改。
- **用 SSE-KMS 時必須是客戶管理的 key**，key policy 要允許 `delivery.logs.amazonaws.com` 使用（AWS 文件〈Logs sent to Amazon S3〉）；用 AWS 管理的 key，log 會變成讀不了的格式。key policy 不在這個 module 管。
- 0.3.0 移除了 `alb_access_logs`：`alb` 不再支援傳統的 `access_logs`，ALB access log 改用 `log-delivery` 送，bucket 改給 `vended_logs`。
- 投遞失敗不會讓 `apply` 失敗，驗收條件是「S3 上真的有物件」。
- bucket 名稱不可含 `.`（會破壞 TLS virtual-host 定址）。
- `force_destroy` 預設 `false`，只放可重建的觀測資料時才在呼叫端打開。
- **不過期一律要明寫 `never_expire = true`。** `expiration_days = null` 代表預設的 90 天，不是不過期：呼叫端常用 `optional(number)` 轉傳，沒給值時就是 null，如果 null 代表不過期，log bucket 會在沒人注意時變成永久保存。
- `never_expire = true` 時不能再給 `expiration_days`，也不能有 `log_delivery`（log bucket 一定要過期），兩種都會被 validation 擋下。
- 預設沒有 versioning，物件被刪掉就救不回來；要保留舊版本就給 `versioning`（0.2.0 起）。`versioning` 不能跟 `log_delivery` 一起用。清舊版本的 rule 套用整個 bucket，不受 `expiration_prefix` 限制。
- `expiration_prefix` 只限制「目前版本過期」那條 rule；沒給時範圍是整個 bucket，跟 0.1.1 相同。
- `lambda_notifications` 只建 bucket 這一側的 notification。呼叫端要自己讓 `s3.amazonaws.com` 有權限 invoke 那支 Lambda（permission 要帶 `source_account` 與 `source_arn`），而且要在 notification 之前建好，否則 S3 會拒絕建立 notification。
- 一個 bucket 只能有一個 `aws_s3_bucket_notification`，所以 `lambda_notifications` 設了之後，不要在 module 外面再對同一個 bucket 建 notification。
- 沒有開 `versioning` 時，物件刪掉就救不回來；如果放的是 Knowledge Base 語料，物件一刪，下一次同步就會清掉對應的向量。

## 刻意不做

replication、object lock、bucket 本身的 access logging（要開就用 `log-delivery`，source 給這個 bucket 的 ARN、`log_type = "S3_SERVER_ACCESS_LOGS"`）、Lambda 以外的 event notification（SQS、SNS、EventBridge）、CORS、跨帳號寫入，以及允許其他 principal 寫入的 bucket policy。上傳後自動觸發 ingestion 由應用程式處理；上傳的人或 CI 用自己的 IAM 權限寫入。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | bucket 名稱，3–63 字元，小寫英數與連字號，不可含 `.` 或 `--` |
| `kms_key_arn` | `string` | `null` | 否 | `null` 用 SSE-S3；有給用 SSE-KMS。收 log 時必須是客戶管理的 key，key policy 要允許 `delivery.logs.amazonaws.com` |
| `expiration_days` | `number` | `null` | 否 | 物件過期天數，1–3650；null 當成 90。`never_expire = true` 時必須是 null |
| `never_expire` | `bool` | `false` | 否 | 不設過期，物件保留到被明確刪除；給內容 bucket（例如 Knowledge Base 語料），不要用在 log bucket；與非空的 `log_delivery` 互斥。null 當成 `false` |
| `log_delivery` | `set(string)` | `[]` | 否 | 允許寫入的 log 來源：`vended_logs`（`log-delivery` 送來的 vended log）、`vpc_flow_logs` |
| `versioning` | `object({ noncurrent_expiration_days = optional(number, 30) })` | `null` | 否 | 有給就開 versioning，舊版本在 `noncurrent_expiration_days`（1–3650）天後過期並清掉過期的 delete marker；與非空的 `log_delivery` 互斥 |
| `expiration_prefix` | `string` | `null` | 否 | 目前版本過期只套用在這個 prefix（1–1024 字元）；`null` 套用整個 bucket |
| `lambda_notifications` | `map(object({ function_arn, events = optional(list(string), ["s3:ObjectCreated:*"]), filter_prefix = optional(string), filter_suffix = optional(string) }))` | `{}` | 否 | notification id 對要呼叫的 Lambda；`function_arn` 必須是 Lambda function ARN，`events` 至少一個；空的就不建 notification |
| `force_destroy` | `bool` | `false` | 否 | 是否允許刪除非空 bucket |
| `tags` | `map(string)` | `{}` | 否 | bucket 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `bucket_name` | `string` | bucket 名稱 |
| `arn` | `string` | bucket ARN |
| `bucket_regional_domain_name` | `string` | bucket 的 regional domain name |

## 測試

```bash
scripts/validate.sh modules/s3-bucket
```
