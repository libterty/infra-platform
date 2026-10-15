# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- `alarms` 每個項目建一個 `aws_cloudwatch_log_metric_filter` 與一個 `aws_cloudwatch_metric_alarm`，名稱為 `<name_prefix>-<key 的 _ 換成 ->`；alarm 依賴 filter。
- filter 預設 `value = "1"`、`default_value = 0`；alarm 預設 `Sum`、60 秒、1 期、`>= 1`、`notBreaching`。
- `sns_topic_arns` 必填，每個 alarm 的 `alarm_actions` 與 `ok_actions` 都接。
- `alarms = {}` 時什麼都不建。
- 輸出 `alarm_arns`、`alarm_names`、`metric_filter_names`。
- 不支援 metric filter 的 `dimensions`、多個 log group、composite alarm、anomaly detection。
