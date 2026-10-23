# eks-workload-alarms

替一個 EKS 工作負載（Deployment）建一組標準的 CloudWatch 告警，全部通知同一組 SNS topic。一個 Deployment 呼叫一次。指標來自 Container Insights，cluster 要先開啟。

## 用法

```hcl
module "alarms" {
  source = "git::https://github.com/<org>/<repo>.git//modules/eks-workload-alarms?ref=eks-workload-alarms-v0.1.0"

  name           = "alpha-api"
  cluster_name   = module.eks.cluster_name
  namespace      = "alpha"
  workload_name  = "alpha-api"
  container_name = "api"
  sns_topic_arns = [module.alarm_topic.topic_arn]

  load_balancer = {
    alb_arn_suffix          = module.alb.alb_arn_suffix
    target_group_arn_suffix = module.alb.target_group_arn_suffixes["api"]
  }
}
```

範例：[`examples/basic/`](./examples/basic/main.tf)、[`examples/with-alb/`](./examples/with-alb/main.tf)。

## 告警清單

告警名稱是 `<name>-<key>`。所有告警的 `alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`。Container Insights 的 namespace 是 `ContainerInsights`。

| key | 條件 | 週期 | 缺資料 | 建立條件 |
|---|---|---|---|---|
| `replicas_below_desired` | `replicas_desired` − `replicas_ready` > 0（metric math，兩個都取 Average） | 60 秒，10 中 10 | breaching | 一律 |
| `crash_loop` | `pod_container_status_waiting_reason_crash_loop_back_off` 最大值 > 0 | 60 秒，5 中 3 | notBreaching | 一律 |
| `restarts` | `pod_number_of_container_restarts` 總和 > `restart_threshold`（預設 0） | 300 秒 × 1 | notBreaching | 一律 |
| `pending` | `pod_status_pending` 最大值 ≥ 1 | 60 秒，10 中 10 | notBreaching | 一律 |
| `oom_killed` | `pod_container_status_terminated_reason_oom_killed` 總和 > 0 | 300 秒 × 1 | notBreaching | 一律 |
| `target_5xx_ratio` | Target 5xx / RequestCount > 0.01 | 300 秒 × 1 | notBreaching | `load_balancer != null` |
| `latency_p95` | TargetResponseTime p95 > 800 ms | 300 秒 × 3 | notBreaching | `load_balancer != null` |
| `unhealthy_hosts` | HealthyHostCount 最小值 < 1 | 60 秒，3 中 2 | notBreaching | `load_balancer != null` |

維度：前四個 Container Insights 告警用 `ClusterName`、`Namespace`、`PodName`；`oom_killed` 多一個 `ContainerName`；ALB 告警用 `TargetGroup`、`LoadBalancer`。

## 注意

- **`PodName` 維度放的是 `workload_name`（Deployment 名稱）**。這是依設計文件的假設，C1 要在真實叢集確認 Container Insights 在 Deployment 層級回報的實際值；沒對上時告警會一直沒資料。
- **`pod_number_of_container_restarts` 當作每個收集週期的增量**，所以用 `Sum` 加上 `restart_threshold` 比較。如果實測是累計值，要改成 metric math `DIFF`。
- `replicas_below_desired` 的缺資料設 breaching：採集停止也該知道。其他告警缺資料都視為正常。
- `target_group_arn_suffix` 要帶 `targetgroup/` 前綴（`alb_arn_suffix` 要帶 `app/`），給完整 ARN 會被 validation 擋下。
- `sns_topic_arns` 必填且不能是空清單。

## 刻意不做

- 不含 worker 的 backlog 與 consumer 告警，沿用 `postdeploy` 的 stream 告警。
- 不用固定的 Running pod 下限，因為擴縮後副本數會變。
- 不含 HPA／KEDA 的告警，也不建 dashboard 與 IAM。
- 不分嚴重度與 topic 路由。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 告警名稱前綴，通常用工作負載名稱；告警命名為 `<name>-<key>`。小寫字母開頭，限小寫英數字與連字號，2–201 字元。 |
| `cluster_name` | `string` | 無 | 是 | EKS cluster 名稱，當作 Container Insights 的 `ClusterName` 維度。不可為空。 |
| `namespace` | `string` | 無 | 是 | 工作負載所在的 Kubernetes namespace（`Namespace` 維度）。須符合 DNS label：小寫英數字與連字號，最多 63 字元。 |
| `workload_name` | `string` | 無 | 是 | Deployment 名稱；Container Insights 把它放在 `PodName` 維度。不可為空。 |
| `container_name` | `string` | 無 | 是 | pod 裡的容器名稱，當作 OOM 告警的 `ContainerName` 維度。不可為空。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 接收告警與恢復通知（`alarm_actions`、`ok_actions`）的 SNS topic ARN，至少一個：沒人收的告警等於沒有告警。 |
| `load_balancer` | `object` | `null` | 否 | ALB 的 CloudWatch 維度；給了才建 ALB target 告警，`null` 時不建。欄位：`alb_arn_suffix`（`app/<name>/<id>`）、`target_group_arn_suffix`（`targetgroup/<name>/<id>`），都要用 ARN 後綴，不是完整 ARN。 |
| `restart_threshold` | `number` | `0` | 否 | 5 分鐘內容器重啟次數超過這個值，`restarts` 告警就觸發。不可為負。 |
| `alarm_config` | `object` | `{}` | 否 | ALB 告警門檻覆寫，每個欄位都有預設。`alb` 欄位：`target_5xx_ratio_threshold`（預設 `0.01`，不可為負）、`latency_p95_threshold_ms`（預設 `800`，須大於 0）、`healthy_host_min`（預設 `1`，不可為負）。 |
| `tags` | `map(string)` | `{}` | 否 | 每個告警的 tag。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alarm_arns` | 告警 ARN 的 map，key 同〈告警清單〉的 key。 |
| `alarm_names` | 告警名稱的 map，key 同〈告警清單〉的 key。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/eks-workload-alarms
```
