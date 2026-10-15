# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 log 用 S3 bucket：封鎖公開存取（四項全開）、`BucketOwnerEnforced`、lifecycle（預設 90 天過期，未完成的 multipart upload 7 天清除）。
- bucket policy 一律有 `aws:SecureTransport = false` 的 Deny。
- 加密二選一：`kms_key_arn = null` 用 SSE-S3，有給用 SSE-KMS。
- `log_delivery` 支援 `alb_access_logs`（ELB 服務帳號加服務主體）與 `vpc_flow_logs`，statement 都限縮到 `AWSLogs/<account>/` 並帶 `aws:SourceAccount`。
- `alb_access_logs` 搭配 `kms_key_arn` 會被 validation 擋下。
- 輸出 `bucket_name`、`arn`、`bucket_regional_domain_name`。
- 不做 versioning、replication、object lock、access logging、event notification、CORS、跨帳號寫入。
