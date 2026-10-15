# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 用三個 map 建 CloudWatch Logs 的 vended log：`sources`（delivery source）、`destinations`（delivery destination）、`deliveries`（把兩者接起來），名稱是 `<name_prefix>-<key>`，最多 60 字。
- `log_type` 只收 `APPLICATION_LOGS`、`TRACES`、`USAGE_LOGS`。
- 目的地 `type` 只收 `CWL`、`XRAY`、`S3`：`XRAY` 只設 `delivery_destination_type`，不給 `resource_arn`；`CWL` 必須是 log group ARN、`S3` 必須是 bucket ARN，只送 `destination_resource_arn`。
- 每個 delivery 的 `source`、`destination` 必須是存在的 key，同一組 source 與 destination 不能接兩次。
- source 的 `resource_arn` 變了（例如 Runtime 重建），delivery 會跟著替換，避免刪 source 時撞 `ConflictException`；只改 tag 不會連帶替換。
- 輸出 `source_names`、`destination_arns`、`delivery_ids`。
- 不建 log group、不建 IAM、不做跨帳號的 destination policy、不開放 `record_fields`、`field_delimiter`、`s3_delivery_configuration`。
- aws provider 需要 `>= 6.69, < 7.0`。
