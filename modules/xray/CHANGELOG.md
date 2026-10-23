# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/xray-v0.1.0...xray-v0.1.1) (2026-10-23)


### Bug Fixes

* **xray:** rewrite the input and output descriptions in Chinese ([5124751](https://github.com/libterty/infra-platform/commit/51247511c4c21715569a8a2178d9b5447931ccc8))

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 每個 `sampling_rules` 建立一個 `aws_xray_sampling_rule`，名稱 `<name_prefix>-<key>`；沒給的比對欄位都是 `*`，`reservoir_size` 預設 1。
- 每個 `groups` 建立一個 `aws_xray_group`，`insights_configuration` 照輸入（預設都是 false）。
- 兩個 map 都預設 `{}`，沒給就什麼都不建。
- 擋下：名稱超過 32 字、`priority` 不在 1–9999 或重複、`fixed_rate` 不在 0–1、`reservoir_size` 為負、`filter_expression` 為空、`notifications_enabled = true` 但 `insights_enabled = false`。
- 輸出 `sampling_rule_arns`、`group_arns`。
- 不管帳號層級的 `Default` sampling rule、X-Ray 加密設定、Resource Policy，不建 IAM。
