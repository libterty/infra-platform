# Changelog

## [0.2.1](https://github.com/libterty/infra-platform/compare/ecs-service-v0.2.0...ecs-service-v0.2.1) (2026-10-24)


### Bug Fixes

* **ecs-service:** rewrite the input and output descriptions in Chinese ([8e07d59](https://github.com/libterty/infra-platform/commit/8e07d59e3723e60592cc1d645545c5c960edbbb8))

## 0.2.0（2026-10-20）

新增功能，升 MINOR。tag 在驗收後由人手動打。

- 新變數 `system_controls`（`map(string)`，預設 `{}`）：給 `app` container 設核心參數（例如 `net.ipv4.tcp_keepalive_time`）。空的時候 container definition 不出現 `systemControls`，task definition 跟 0.1.0 一致。**設了之後會產生新的 task definition revision，觸發一次部署。**
- `autoscaling.policy` 新增 `"custom"`：不建內建的 CPU、請求數與 step policy，scalable target 仍由 module 擁有。
- 新增 `autoscaling.scheduled_actions`（預設 `{}`）：每項建一個 `aws_appautoscaling_scheduled_action`；`min_capacity` 不可大於 `max_capacity`，`max_capacity` 不可超過 `autoscaling.max_capacity`。
- 新增 `autoscaling.step_policies`（預設 `{}`）：每項建一個 `aws_appautoscaling_policy`（StepScaling）與觸發它的 `aws_cloudwatch_metric_alarm`，alarm 的 `alarm_actions` 指向該 policy；`metric` 與 `queries`（metric math）二選一，不符合會被 validation 擋下。資源名稱帶 `step-` 前綴，避免跟內建 policy 重名。
- 三個新欄位都沒給的既有呼叫端，resource 與 task definition 都沒有變化，換版應該零差異。**這是測試與讀程式推論的，沒有用 plan 驗證。** `queries` 內部的組合（`expression` 與 `metric` 擇一、`return_data`）交給 CloudWatch API 檢查，mock 測試驗不到。
- 原本寫在「刻意不做」的排程擴縮與自訂指標 step scaling，從這一版起支援。

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 log group、task definition（單一 container `app`，預設 ARM64、512/1024）、service。
- service 固定行為：Fargate、awsvpc、無公有 IP、部署 100／200、circuit breaker 加 rollback、`propagate_tags = "SERVICE"`、AZ rebalancing、`ignore_changes = [desired_count]`。
- `aws_appautoscaling_target` 一律建立；`autoscaling = null` 時 min = max = `desired_count`。
- 兩種 policy：`target_tracking`（CPU，可加請求數）與 `step`（CPU、記憶體各一組，+1／+2／+3 與 −1，加 4 個 CloudWatch alarm）。
- load balancer 三種接法：不接、傳 `target_group_arn`、傳 `listener_arn` 由 module 建 target group 與 listener rule。
- 可選 Service Connect、container health check、ECS Exec。
- 新增 `sidecars`（預設 `[]`，task definition 與單一 container 完全一致）：在 task 裡加額外 container，log 共用同一個 log group、只換 stream prefix，可用 `app_depends_on` 讓 `app` 等 sidecar；介面通用，不寫死 ADOT。範例見 `examples/adot-sidecar/`。
- 不建 IAM 與 security group；不支援排程擴縮、自訂指標 step scaling、`readonlyRootFilesystem`。
