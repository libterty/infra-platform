# s3-bucket

建一個 log 或內容用的 S3 bucket：封鎖公開存取、加密、lifecycle、只允許 TLS，並依輸入加上 log delivery 的寫入權限。`foundation` 用它建 flow log bucket 與 ALB access log bucket；Knowledge Base 的語料這類不能過期的內容，用 `never_expire = true`。

## 用法

```hcl
module "alb_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.1.0"

  name            = "alpha-dev-alb-logs"
  log_delivery    = ["alb_access_logs"]
  expiration_days = 14
}

module "flow_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.1.0"

  name         = "alpha-dev-flow-logs"
  log_delivery = ["vpc_flow_logs"]
  kms_key_arn  = module.key.key_arn
}

module "kb_corpus" {
  source = "git::https://github.com/<org>/<repo>.git//modules/s3-bucket?ref=s3-bucket-v0.2.0"

  name         = "alpha-dev-kb-corpus"
  kms_key_arn  = module.key.key_arn
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
| bucket policy | `depends_on` public access block，避免 policy 先套用被判為公開 |

## log delivery

| `log_delivery` 值 | principal | 動作與資源 | 條件 |
|---|---|---|---|
| `alb_access_logs` | 該 region 的 ELB 服務帳號；`logdelivery.elasticloadbalancing.amazonaws.com` | `s3:PutObject` on `<bucket>/*AWSLogs/<account>/*` | 服務主體那段帶 `aws:SourceAccount` |
| `vpc_flow_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl` on bucket | `aws:SourceAccount`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |

## 注意

- **ALB access log bucket 只能用 SSE-S3。** ALB 不支援 SSE-KMS，設了 log 會靜默消失、不報錯。所以 `log_delivery` 含 `alb_access_logs` 時，`kms_key_arn` 必須是 `null`，否則 validation 直接擋下。
- ALB 投遞失敗不會有任何錯誤，驗收條件是「S3 上真的有物件」，不是 `apply` 成功。
- ap-northeast-1 這類較舊的 region 由 region 專屬的 ELB 服務帳號寫入，只給服務主體會 Access Denied，所以兩種 principal 都給。
- bucket 名稱不可含 `.`（會破壞 TLS virtual-host 定址）。
- `force_destroy` 預設 `false`，只放可重建的觀測資料時才在呼叫端打開。
- **不過期一律要明寫 `never_expire = true`。** `expiration_days = null` 代表預設的 90 天，不是不過期：呼叫端常用 `optional(number)` 轉傳，沒給值時就是 null，如果 null 代表不過期，log bucket 會在沒人注意時變成永久保存。
- `never_expire = true` 時不能再給 `expiration_days`，validation 會擋下。
- 內容 bucket 的物件被刪掉之後救不回來（沒有 versioning）；放 Knowledge Base 語料時，物件被刪，下一次同步就會清掉對應的向量。

## 刻意不做

versioning、replication、object lock、bucket 本身的 access logging、event notification、CORS、跨帳號寫入，以及允許其他 principal 寫入的 bucket policy。內容 bucket 的 versioning 等有專案需要再做（下一個 MINOR）；上傳後自動觸發 ingestion 是應用程式的事；上傳的人或 CI 用自己的 IAM 權限寫入。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | bucket 名稱，3–63 字元，小寫英數與連字號，不可含 `.` 或 `--` |
| `kms_key_arn` | `string` | `null` | 否 | `null` 用 SSE-S3；有給用 SSE-KMS。與 `alb_access_logs` 互斥 |
| `expiration_days` | `number` | `null` | 否 | 物件過期天數，1–3650；null 當成 90。`never_expire = true` 時必須是 null |
| `never_expire` | `bool` | `false` | 否 | 不設過期，物件保留到被明確刪除；給內容 bucket（例如 Knowledge Base 語料），不要用在 log bucket。null 當成 `false` |
| `log_delivery` | `set(string)` | `[]` | 否 | 允許寫入的 log 來源：`alb_access_logs`、`vpc_flow_logs` |
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
