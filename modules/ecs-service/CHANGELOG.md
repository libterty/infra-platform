# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 log group、task definition（單一 container `app`，預設 ARM64、512/1024）、service。
- service 固定行為：Fargate、awsvpc、無公有 IP、部署 100／200、circuit breaker 加 rollback、`propagate_tags = "SERVICE"`、AZ rebalancing、`ignore_changes = [desired_count]`。
- `aws_appautoscaling_target` 一律建立；`autoscaling = null` 時 min = max = `desired_count`。
- 兩種 policy：`target_tracking`（CPU，可加請求數）與 `step`（CPU、記憶體各一組，+1／+2／+3 與 −1，加 4 個 CloudWatch alarm）。
- load balancer 三種接法：不接、傳 `target_group_arn`、傳 `listener_arn` 由 module 建 target group 與 listener rule。
- 可選 Service Connect、container health check、ECS Exec。
- 新增 `sidecars`（預設 `[]`，task definition 與單一 container 完全一致）：在 task 裡加額外 container，log 共用同一個 log group、只換 stream prefix，可用 `app_depends_on` 讓 `app` 等 sidecar；介面通用，不寫死 ADOT。範例見 `examples/adot-sidecar/`。
- 不建 IAM 與 security group；不支援排程擴縮、自訂指標 step scaling、`readonlyRootFilesystem`。
