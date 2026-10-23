# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/metric-alarm-v0.1.0...metric-alarm-v0.1.1) (2026-10-23)


### Bug Fixes

* **metric-alarm:** rewrite the input and output descriptions in Chinese ([5de9067](https://github.com/libterty/infra-platform/commit/5de906764999ac2bdbe5c9b4a40d98752083f033))

## 0.1.0（2026-10-20）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- `alarms` 每個項目建一個 `aws_cloudwatch_metric_alarm`，名稱為 `<name_prefix>-<key 的 _ 換成 ->`。
- 每個項目二選一：`metric`（單一指標）或 `queries`（metric math）。兩個都給或都不給會被 validation 擋下。
- `queries` 每個項目要有 `expression` 或 `metric` 其中一個，id 不可重複，而且只能有一個 `return_data = true`。
- 預設值：`Average`、300 秒、1 期、`>=`、`notBreaching`。
- `sns_topic_arns` 必填且至少一個，每個 alarm 的 `alarm_actions` 與 `ok_actions` 都接。
- 輸出 `alarm_arns`、`alarm_names`。
- 不支援 percentile（`extended_statistic`）、anomaly detection、composite alarm、`insufficient_data_actions`、`unit`。
- 不建 metric filter；要從 log 產生指標請用 `log-metric-alarm`。
