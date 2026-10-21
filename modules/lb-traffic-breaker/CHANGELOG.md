# Changelog

## 0.1.0（未發布）

初版。

- 每個 `breakers` 項目建立 CloudWatch alarm，名稱為 `<name>-<key>-<signal>`：
  - ALB：`error-rate`（5xx 錯誤率，metric math，請求數低於 `min_requests` 不算，缺資料視為 `notBreaching`）、`healthy-hosts`（`HealthyHostCount` 低於 `min_healthy_hosts`，缺資料視為 `breaching`）。
  - NLB：只有 `healthy-hosts`；設定 `error_rate_percent` 或 `min_requests` 會被拒。
  - 兩者都可以加 `custom` alarm（`custom_metric`）。
- alarm 的 `alarm_actions` 是 Lambda 加 SNS，`ok_actions` 只有 SNS。
- 輸出 `alarm_arns`、`alarm_names`、`lambda_config_json`、`lambda_permissions`（可直接傳給 `lambda-function` 的 `permissions`）。
- `lambda/` 附上 Lambda 程式碼（`breaker.py`、`handler.py`）、單元測試與 Dockerfile。映像由使用者自己 build 並推到 ECR。
