# ecs-service-alarms

替一個 ECS 服務建一組標準的 CloudWatch 告警，全部通知同一組 SNS topic；可選建 dashboard。一個服務呼叫一次。

## 用法

```hcl
module "alarms" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service-alarms?ref=ecs-service-alarms-v0.1.0"

  name           = module.service.service_name
  cluster_name   = module.cluster.cluster_name
  service_name   = module.service.service_name
  sns_topic_arns = [module.alarm_topic.topic_arn]

  load_balancer = {
    alb_arn_suffix          = module.alb.alb_arn_suffix
    target_group_arn_suffix = module.service.target_group_arn_suffix
  }
  max_capacity = 6
}
```

範例：[`examples/basic/`](./examples/basic/main.tf)、[`examples/with-alb/`](./examples/with-alb/main.tf)。

## 告警清單

告警名稱是 `<name>-<key>`。所有告警的 `alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`。

| key | 條件 | 週期 | 缺資料 | 建立條件 |
|---|---|---|---|---|
| `cpu_high` | `AWS/ECS` CPUUtilization 平均 ≥ 80 | 300 秒 × 1 | missing | 一律 |
| `memory_high` | `AWS/ECS` MemoryUtilization 平均 ≥ 80 | 300 秒 × 1 | missing | 一律 |
| `cpu_missing` | CPUUtilization < 0（只靠缺資料觸發） | 60 秒 × 2 | breaching | 一律 |
| `memory_missing` | MemoryUtilization < 0 | 60 秒 × 2 | breaching | 一律 |
| `tasks_below_desired` | Container Insights Desired − Running > 0 | 60 秒，5 中 3 | notBreaching | 一律 |
| `cpu_throttling` | CpuUtilized / CpuReserved > 0.9 | 300 秒，3 中 2 | notBreaching | 一律 |
| `memory_pressure` | MemoryUtilized / MemoryReserved > 0.85 | 300 秒，3 中 2 | notBreaching | 一律 |
| `at_max_capacity` | RunningTaskCount 最大值 ≥ `max_capacity` | 60 秒 × 5 | notBreaching | `max_capacity != null` |
| `target_5xx_ratio` | Target 5xx / RequestCount > 0.01 | 300 秒 × 1 | notBreaching | `load_balancer != null` |
| `target_4xx_ratio` | Target 4xx / RequestCount > 0.05 | 300 秒，3 中 2 | notBreaching | `load_balancer != null` |
| `latency_p95` | TargetResponseTime p95 > 800 ms | 300 秒 × 3 | notBreaching | `load_balancer != null` |
| `unhealthy_hosts` | HealthyHostCount 最小值 < 1 | 60 秒，3 中 2 | notBreaching | `load_balancer != null` |
| `target_connection_errors` | TargetConnectionErrorCount 總和 > 0 | 300 秒 × 1 | notBreaching | `load_balancer != null` |

## 注意

- **`target_group_arn_suffix` 要帶 `targetgroup/` 前綴**（`alb_arn_suffix` 要帶 `app/`）。CloudWatch 維度要用這個格式，給完整 ARN 會被 validation 擋下。
- `*_missing` 用「門檻 < 0 加缺資料視為 breaching」偵測服務停止回報：數值本身不會觸發，只靠缺資料觸發。
- Container Insights 的告警與 dashboard widget 要 cluster 開啟 Container Insights 才有資料；service 層級的 `CpuUtilized`／`CpuReserved` 維度在 `enhanced` 與 `enabled` 兩種模式是否都有，要等有 AWS 環境時確認。
- `sns_topic_arns` 必填且不能是空清單，不然告警響了也沒人收到。
- 所有告警都帶 `ClusterName`／`ServiceName` 或 `TargetGroup`／`LoadBalancer` 維度，一個服務一組。

## 刻意不做

- 不含 ALB 整體的 `HTTPCode_ELB_5XX_Count`：它只有 `LoadBalancer` 維度，多個服務共用 ALB 時會重複，放在 `alb` module。
- 不含資料庫、Bedrock、ElastiCache 告警。
- 不用 `insufficient_data_actions`（缺資料已用 `*_missing` 處理）。
- 不分嚴重度與 topic 路由：所有告警送同一組 `sns_topic_arns`。
- 不建 IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 告警名稱前綴，通常就是 service 名稱；告警名稱為 `<name>-<key>`。限小寫英數字與連字號，字母開頭，2–201 字元。 |
| `cluster_name` | `string` | 無 | 是 | ECS cluster 名稱（CloudWatch `ClusterName` 維度）。 |
| `service_name` | `string` | 無 | 是 | ECS service 名稱（CloudWatch `ServiceName` 維度）。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 接收告警（`alarm_actions`）與恢復通知（`ok_actions`）的 SNS topic ARN，至少一個：沒人收的告警不算告警。 |
| `load_balancer` | `object` | `null` | 否 | ALB 的 CloudWatch 維度；`null` 時不建 ALB target 告警。欄位：`alb_arn_suffix`（`app/<name>/<id>`）、`target_group_arn_suffix`（`targetgroup/<name>/<id>`），都要用 suffix，不是完整 ARN。 |
| `max_capacity` | `number` | `null` | 否 | autoscaling 的最大 task 數；給了數字才建 `at_max_capacity` 告警。 |
| `alarm_config` | `object` | `{}` | 否 | 告警門檻。欄位：`ecs`（`cpu_threshold`、`memory_threshold`，預設皆 `80`）、`container`（`cpu_throttling_threshold` 預設 `0.9`、`memory_pressure_threshold` 預設 `0.85`）、`alb`（`target_5xx_ratio_threshold` 預設 `0.01`、`target_4xx_ratio_threshold` 預設 `0.05`、`latency_p95_threshold_ms` 預設 `800`、`healthy_host_min` 預設 `1`）。各告警見〈告警清單〉。 |
| `dashboard_name` | `string` | `null` | 否 | dashboard 名稱；`null` 時不建 dashboard。 |
| `tags` | `map(string)` | `{}` | 否 | 告警的 tag。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alarm_arns` | 告警 ARN 的 map，key 同〈告警清單〉的 key。 |
| `alarm_names` | 告警名稱的 map，key 同〈告警清單〉的 key。 |
| `dashboard_arn` | dashboard ARN；`dashboard_name` 為 `null` 時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/ecs-service-alarms
```
