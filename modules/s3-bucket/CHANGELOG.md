# Changelog

## [0.4.0](https://github.com/libterty/infra-platform/compare/s3-bucket-v0.3.1...s3-bucket-v0.4.0) (2026-10-24)


### Features

* **s3-bucket:** add lifecycle transitions and EventBridge notifications ([b6cdce4](https://github.com/libterty/infra-platform/commit/b6cdce47d8f01f14820400eeb2862053546acb9b))

## [0.3.1](https://github.com/libterty/infra-platform/compare/s3-bucket-v0.3.0...s3-bucket-v0.3.1) (2026-10-23)


### Bug Fixes

* **s3-bucket:** rewrite the input and output descriptions in Chinese ([9dcb8aa](https://github.com/libterty/infra-platform/commit/9dcb8aa41f04e569b237d76adb9d7665e80e1fde))

## [0.3.0](https://github.com/libterty/infra-platform/compare/s3-bucket-v0.2.0...s3-bucket-v0.3.0) (2026-10-21)


### ⚠ BREAKING CHANGES

* **s3-bucket:** alb_access_logs is removed together with the ELB service account statements, and the SSE-KMS restriction that came with it. ALB access logs now go through log-delivery; give the bucket vended_logs.

### Features

* **s3-bucket:** replace alb_access_logs with vended_logs ([e153241](https://github.com/libterty/infra-platform/commit/e153241d51b1746d52d7c9d70eaaaa54ea8aec5c))

## 0.2.0（2026-10-20）

新增功能，升 MINOR。tag 在驗收後由人手動打。

- 新變數 `versioning`（預設 `null`）：有給時建 `aws_s3_bucket_versioning`，並多一條 lifecycle rule `cleanup-noncurrent-versions`（整個 bucket：舊版本 `noncurrent_expiration_days` 天後過期，預設 30，範圍 1–3650；清掉過期的 delete marker）。不能跟非空的 `log_delivery` 一起用。
- 新變數 `expiration_prefix`（預設 `null`）：有給時，過期那條 rule 只套用在這個 prefix；`null` 時 filter 維持空的。
- 新變數 `lambda_notifications`（預設 `{}`）：非空才建 `aws_s3_bucket_notification`，每個 entry 一個 Lambda 目標，`events` 預設 `s3:ObjectCreated:*`，可加 prefix／suffix filter。`function_arn` 必須是 Lambda function ARN。Lambda 端的 invoke permission 由呼叫端負責。
- 三個變數都沒給的既有呼叫端，resource 與既有 rule 都沒有變化，換版應該零差異：`filter { prefix = null }` 與原本的空 `filter {}` 在設定上相同。**這是測試與讀程式推論的，沒有用 plan 驗證；mock provider 下 `filter.prefix` 是 unknown，測試只能確認 filter 區塊還在，無法直接斷言它是空的。**

## 0.1.1（2026-10-16）

新增功能，照 semver 表本該升 MINOR；這一版照使用者決定（design 決策 54）跟 7 個新 module 一起用 `0.1.1`，在增補驗收後手動打 tag（manifest 屆時才改成 `0.1.1`），release-please 不會產生這一段。之後的版本照 semver 表。

- 新變數 `never_expire`（預設 `false`，`nullable = false`）：`true` 時 lifecycle rule 沒有 `expiration`，只留未完成 multipart upload 的 7 天清除，rule id 改成 `abort-incomplete-uploads`。給 Knowledge Base 語料這類不能過期的內容 bucket。
- `expiration_days` 的預設從 `90` 改成 `null`，module 內當成 90；`never_expire = true` 又給了 `expiration_days` 會被 validation 擋下。
- 既有消費端換版、不改程式碼時 plan 應零差異：`never_expire = false` 時 rule id 仍是 `expire-objects`，`expiration.days` 與 multipart upload 清除都跟 0.1.0 相同。**這是讀程式推論的，沒有用 plan 驗證。**
- `never_expire = true` 搭配非空的 `log_delivery` 會被 validation 擋下：log bucket 一定要過期。`never_expire` 是這一版才有的，0.1.0 的呼叫端不會撞到。
- 放寬：`expiration_days` 明寫 `null` 以前會被 validation 擋下，現在當成 90。

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 log 用 S3 bucket：封鎖公開存取（四項全開）、`BucketOwnerEnforced`、lifecycle（預設 90 天過期，未完成的 multipart upload 7 天清除）。
- bucket policy 一律有 `aws:SecureTransport = false` 的 Deny。
- 加密二選一：`kms_key_arn = null` 用 SSE-S3，有給用 SSE-KMS。
- `log_delivery` 支援 `alb_access_logs`（ELB 服務帳號加服務主體）與 `vpc_flow_logs`，statement 都限縮到 `AWSLogs/<account>/` 並帶 `aws:SourceAccount`。
- `alb_access_logs` 搭配 `kms_key_arn` 會被 validation 擋下。
- 輸出 `bucket_name`、`arn`、`bucket_regional_domain_name`。
- 不做 versioning、replication、object lock、access logging、event notification、CORS、跨帳號寫入。
