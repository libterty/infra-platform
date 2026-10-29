# cloudtrail

建一條 CloudTrail trail：預設 multi-region、只記 management event，log 用客戶管理的 KMS key 加密並開 log file validation。可以同時送到 CloudWatch Logs 做告警，也可以在管理帳號建 organization trail。

## 用法

```hcl
module "trail" {
  source = "git::https://github.com/<org>/<repo>.git//modules/cloudtrail?ref=cloudtrail-v0.1.0"

  name           = "alpha-dev-trail"
  s3_bucket_name = module.audit_logs.bucket_name
  s3_key_prefix  = "cloudtrail"
  kms_key_arn    = module.audit_key.key_arn

  cloudwatch_logs = {
    log_group_arn = "${module.trail_logs.arn}:*"
    role_arn      = module.trail_logs_role.role_arn
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | log 與 digest 檔都用 `kms_key_arn`（必填），不提供 SSE-S3 |
| log file validation | 一律開，被改過或刪掉的 log 可以用 digest 檔驗出來 |
| global service event | 一律記錄（IAM、STS 等） |
| logging | 一律開；要暫停請在 console 操作，不從 module 關 |
| 事件 | `advanced_event_selectors = null` 時只記 management event（讀寫都記） |
| tag | 給定的 `tags` 加上 `Name`（trail 名稱） |

## 注意

- bucket 與 KMS key 由其他 module 建：
  - bucket policy 要允許 `cloudtrail.amazonaws.com` 的 `s3:GetBucketAcl` 與 `s3:PutObject`，條件 `aws:SourceArn`；`s3-bucket` 0.6.0 的 `log_delivery` 有 `cloudtrail`，organization trail 也要用它的 organization 寫入路徑。
  - key policy 要允許 `cloudtrail.amazonaws.com` 的 `kms:GenerateDataKey*`，條件 `kms:EncryptionContext:aws:cloudtrail:arn`；bucket 與 key 要在同一個 region。
- `cloudwatch_logs.log_group_arn` 要在 log group ARN 後面加 `:*`（CloudTrail 要求 log stream 的萬用字元，module 會擋沒加的值）。log group 要在同一個帳號；role 要有寫入 `<帳號>_CloudTrail_<region>*` log stream 的 `logs:CreateLogStream` 與 `logs:PutLogEvents`，organization trail 另外要 `<organization ID>_*`。role 在範本的 `iam` stack 建。
- organization trail 只能在管理帳號（或 CloudTrail 的委派管理帳號）apply，Organizations 要先開 CloudTrail 的 trusted access（`organization-delegated-admin`）。
- management event 的第一份 trail 免費；第二條以上的 trail、data event、Insights 都另外計費。帳號已經有 trail 時，再建一條會重複計費。
- 給 `advanced_event_selectors` 就整個取代預設：要繼續記 management event，記得放一個 `eventCategory = Management` 的 selector。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

CloudTrail Lake（event data store）、SNS 通知、建 bucket（用 `s3-bucket`）、建 log group 或 role、舊式 `event_selector`（一律用 advanced event selector）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | trail 名稱，3–128 字元，限英數字、`.`、`_`、`-`，開頭與結尾是英數字，不能有相鄰的 `.`、`_`、`-`。 |
| `s3_bucket_name` | `string` | 無 | 是 | 存放 log 的 S3 bucket 名稱。bucket policy 要允許 `cloudtrail.amazonaws.com` 寫入（`s3-bucket` 0.6.0 的 `log_delivery` 含 `cloudtrail`）；module 不建 bucket。 |
| `s3_key_prefix` | `string` | `null` | 否 | log 在 bucket 裡的 key prefix，最多 200 字元；`null`（預設）寫在 bucket 根目錄的 `AWSLogs/`。 |
| `kms_key_arn` | `string` | 無 | 是 | 加密 log 與 digest 檔的客戶管理 KMS key ARN（`key/<id>`，不收 alias），必填。key policy 要允許 `cloudtrail.amazonaws.com`，條件 `kms:EncryptionContext:aws:cloudtrail:arn`。 |
| `is_multi_region_trail` | `bool` | `true` | 否 | 是否記錄所有 region 的事件（預設 `true`）。organization trail 一定要 `true`。 |
| `is_organization_trail` | `bool` | `false` | 否 | 是否為 organization trail（預設 `false`）。`true` 時只能在管理帳號或 CloudTrail 的委派管理帳號 apply，且 `is_multi_region_trail` 必須是 `true`。 |
| `cloudwatch_logs` | `object` | `null` | 否 | 同時把事件送到 CloudWatch Logs（選填）。`log_group_arn` 要以 `:*` 結尾（CloudTrail 要求 log stream 的萬用字元）；`role_arn` 是讓 `cloudtrail.amazonaws.com` 寫入 log group 的 role。`null`（預設）不送。 |
| `advanced_event_selectors` | `list(object)` | `null` | 否 | advanced event selector（選填）。`null`（預設）只記 management event（第一份免費）。要記 data event 時給 selector，記得保留一個 `eventCategory = Management` 的 selector，否則 management event 會停掉；data event 依量計費。每個 selector 都要有 `eventCategory` 的 field selector。 |
| `insight_types` | `list(string)` | `[]` | 否 | 要開的 CloudTrail Insights：`ApiCallRateInsight`、`ApiErrorRateInsight`（另外計費）。空的（預設）不開。 |
| `region` | `string` | `null` | 否 | trail 的 home region；`null`（預設）用 provider 的 region。multi-region trail 在一個 region 建就涵蓋所有 region。 |
| `tags` | `map(string)` | `{}` | 否 | trail 的 tag；`Name` 由 module 加上（值是 `name`）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | trail 的 ARN，KMS key policy 的 `kms:EncryptionContext:aws:cloudtrail:arn` 條件與 bucket policy 的 `aws:SourceArn` 用。 |
| `name` | trail 名稱。 |
| `home_region` | trail 建立所在的 region。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/cloudtrail
```
