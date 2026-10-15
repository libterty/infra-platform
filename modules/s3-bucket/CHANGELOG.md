# Changelog

## 0.2.0（未發布）

MINOR。跟 7 個新 module 一起在增補驗收後手動打 tag（manifest 屆時才改成 `0.2.0`），release-please 不會產生這一段。

- 新變數 `never_expire`（預設 `false`，`nullable = false`）：`true` 時 lifecycle rule 沒有 `expiration`，只留未完成 multipart upload 的 7 天清除，rule id 改成 `abort-incomplete-uploads`。給 Knowledge Base 語料這類不能過期的內容 bucket。
- `expiration_days` 的預設從 `90` 改成 `null`，module 內當成 90；`never_expire = true` 又給了 `expiration_days` 會被 validation 擋下。
- 既有消費端換版、不改程式碼時 plan 應零差異：`never_expire = false` 時 rule id 仍是 `expire-objects`，`expiration.days` 與 multipart upload 清除都跟 0.1.0 相同。**這是讀程式推論的，沒有用 plan 驗證。**
- 放寬：`expiration_days` 明寫 `null` 以前會被 validation 擋下，現在當成 90。

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 log 用 S3 bucket：封鎖公開存取（四項全開）、`BucketOwnerEnforced`、lifecycle（預設 90 天過期，未完成的 multipart upload 7 天清除）。
- bucket policy 一律有 `aws:SecureTransport = false` 的 Deny。
- 加密二選一：`kms_key_arn = null` 用 SSE-S3，有給用 SSE-KMS。
- `log_delivery` 支援 `alb_access_logs`（ELB 服務帳號加服務主體）與 `vpc_flow_logs`，statement 都限縮到 `AWSLogs/<account>/` 並帶 `aws:SourceAccount`。
- `alb_access_logs` 搭配 `kms_key_arn` 會被 validation 擋下。
- 輸出 `bucket_name`、`arn`、`bucket_regional_domain_name`。
- 不做 versioning、replication、object lock、access logging、event notification、CORS、跨帳號寫入。
