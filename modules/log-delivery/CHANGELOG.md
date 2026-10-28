# Changelog

## [0.3.0](https://github.com/libterty/infra-platform/compare/log-delivery-v0.2.1...log-delivery-v0.3.0) (2026-10-28)


### Features

* **log-delivery:** add region input for sources, destinations and deliveries ([77f3624](https://github.com/libterty/infra-platform/commit/77f3624c21b2d9b482c7a776ee6c7ac1980556ad))

## [0.2.1](https://github.com/libterty/infra-platform/compare/log-delivery-v0.2.0...log-delivery-v0.2.1) (2026-10-23)


### Bug Fixes

* **log-delivery:** rewrite the input and output descriptions in Chinese ([930658b](https://github.com/libterty/infra-platform/commit/930658b654a0698702e48e61be1f89d2e68a5791))

## [0.2.0](https://github.com/libterty/infra-platform/compare/log-delivery-v0.1.1...log-delivery-v0.2.0) (2026-10-21)


### Features

* **log-delivery:** accept any vended log source and Firehose destinations ([bfb9396](https://github.com/libterty/infra-platform/commit/bfb9396b3c5cb9aaa20e86a0ecd6078737599456))


### Bug Fixes

* **log-delivery:** skip the source account check only for S3 bucket ARNs ([0ee4d3e](https://github.com/libterty/infra-platform/commit/0ee4d3e9b30ec4e77eb7c1d7e94e50673187c1f6))

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 用三個 map 建 CloudWatch Logs 的 vended log：`sources`（delivery source）、`destinations`（delivery destination）、`deliveries`（把兩者接起來），名稱是 `<name_prefix>-<key>`，最多 60 字。
- `log_type` 只收 `APPLICATION_LOGS`、`TRACES`、`USAGE_LOGS`。
- 目的地 `type` 只收 `CWL`、`XRAY`、`S3`：`XRAY` 只設 `delivery_destination_type`，不給 `resource_arn`；`CWL` 必須是 log group ARN、`S3` 必須是 bucket ARN，只送 `destination_resource_arn`。
- 每個 delivery 的 `source`、`destination` 必須是存在的 key，同一組 source 與 destination 不能接兩次。
- source 的 `resource_arn` 變了（例如 Runtime 重建），delivery 會跟著替換，避免刪 source 時撞 `ConflictException`；只改 tag 不會連帶替換。
- source 的 `resource_arn` 必須是帶 12 位數帳號的 ARN。
- 新增 `allowed_account_ids`（預設 `[]`）：source 與 `CWL` 目的地的帳號必須是目前帳號或在這份清單裡，否則 plan 被 precondition 擋下。目前帳號的呼叫端不用改設定。`S3` 的 bucket ARN 不帶帳號，不檢查。
- 輸出 `source_names`、`destination_arns`、`delivery_ids`。
- 不建 log group、不建 IAM、不做跨帳號的 destination policy、不開放 `record_fields`、`field_delimiter`、`s3_delivery_configuration`。
- aws provider 需要 `>= 6.69, < 7.0`。
