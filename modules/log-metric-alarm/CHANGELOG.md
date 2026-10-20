# Changelog

## 0.2.0（未發布）

新增功能，升 MINOR。tag 在驗收後由人手動打。

- 新變數 `metrics`（預設 `{}`）：只建 `aws_cloudwatch_log_metric_filter`，不建 alarm，給 dashboard 或在別處管理的告警用。每項有 `pattern`、`metric_name`、可選的 `metric_value`（`"1"`）與 `default_value`（`0`）。
- `sns_topic_arns` 改成預設 `[]`，只有 `alarms` 非空時必填；`alarms` 非空卻沒給 SNS 仍會被 validation 擋下。`alarms` 也改成預設 `{}`。
- 同一個 key 不能同時出現在 `alarms` 與 `metrics`。
- 新輸出 `metric_names`（key 對應指標名稱，含 `alarms` 與 `metrics`）；`metric_filter_names` 現在也包含 `metrics` 的項目。
- `alarms`、`metrics`、`sns_topic_arns` 都沒給會被擋下。為了讓既有的 `alarms = {}` 搭配 `sns_topic_arns` 仍然什麼都不建（0.1.0 的行為），這個檢查只在 `sns_topic_arns` 也是空的時候才成立。
- 只用 `alarms` 的既有呼叫端，filter 與 alarm 的 resource 位址不變（`for_each` 的 key 沒變），換版應該零差異。**這是測試與讀程式推論的，沒有用 plan 驗證。**

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- `alarms` 每個項目建一個 `aws_cloudwatch_log_metric_filter` 與一個 `aws_cloudwatch_metric_alarm`，名稱為 `<name_prefix>-<key 的 _ 換成 ->`；alarm 依賴 filter。
- filter 預設 `value = "1"`、`default_value = 0`；alarm 預設 `Sum`、60 秒、1 期、`>= 1`、`notBreaching`。
- `sns_topic_arns` 必填，每個 alarm 的 `alarm_actions` 與 `ok_actions` 都接。
- `alarms = {}` 時什麼都不建。
- 輸出 `alarm_arns`、`alarm_names`、`metric_filter_names`。
- 不支援 metric filter 的 `dimensions`、多個 log group、composite alarm、anomaly detection。
