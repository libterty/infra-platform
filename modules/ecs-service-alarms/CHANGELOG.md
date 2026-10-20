# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 一個服務一組告警：`cpu_high`、`memory_high`、`cpu_missing`、`memory_missing`、`tasks_below_desired`、`cpu_throttling`、`memory_pressure` 一律建立。
- `max_capacity` 非 null 才建 `at_max_capacity`；`load_balancer` 非 null 才建 `target_5xx_ratio`、`target_4xx_ratio`、`latency_p95`、`unhealthy_hosts`、`target_connection_errors`。
- 每個告警的 `alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`，空清單與非 SNS ARN 被擋。
- `alarm_config` 為巢狀 `optional()`，只改一個門檻不影響其他預設。
- `dashboard_name` 非 null 才建 dashboard。
- 輸出 `alarm_arns`、`alarm_names`、`dashboard_arn`。
- 不含 `HTTPCode_ELB_5XX_Count`（在 `alb` module）、不含資料庫告警，不支援 `insufficient_data_actions` 與嚴重度分級。
