# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_cloudwatch_log_group`，保留天數預設 30，只接受 CloudWatch Logs 允許的值，拒絕 0（永不過期）。
- 可選 `kms_key_arn`。
- 可選 `subscription`，建立一個 subscription filter；Kinesis、Firehose 目的地必須給 `role_arn`。
- 輸出 `name`、`arn`。
- 不建 IAM、不建訂閱目的地、不建 Lambda permission、不支援 `INFREQUENT_ACCESS` log class、一個 log group 只有一個 subscription filter。
