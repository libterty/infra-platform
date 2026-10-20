# ecs-service

部署一個 Fargate 服務：log group、task definition、service、autoscaling target，可選 target group 與 listener rule。單一 container，名稱固定 `app`。

## 用法

不接 LB 的 worker：

```hcl
module "worker" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"

  name        = "alpha-worker"
  cluster_arn = module.cluster.cluster_arn
  image       = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-worker:1.0.0"

  execution_role_arn = local.execution_role_arn
  task_role_arn      = local.task_role_arn

  network = {
    subnet_ids         = local.subnet_ids
    security_group_ids = [local.sg_worker]
  }
}
```

範例：[`examples/basic/`](./examples/basic/main.tf)（不接 LB）、[`examples/with-alb/`](./examples/with-alb/main.tf)（`listener_arn` 模式加 target tracking）。

## 兩種 LB 接法

`load_balancer` 的 `target_group_arn` 與 `listener_arn` 擇一，都不給整個變數就傳 `null`。

| 模式 | 輸入 | module 建什麼 |
|---|---|---|
| 不接 LB | `load_balancer = null` | 都不建；service 的 `health_check_grace_period_seconds` 傳 null |
| 外部 target group | `target_group_arn` | 不建 target group 與 rule，service 直接掛傳入的 ARN |
| module 建 | `listener_arn`、`vpc_id`、`priority`，加 `host_headers` 或 `path_patterns` 至少一項 | 一個 target group（名稱 `<name>-<container_port>`、`ip`、HTTP）與一條 listener rule |

接了 LB 或 Service Connect 時 `container_port` 必填。需要 `requests_per_target` 或告警時，另外給 `load_balancer.alb_arn_suffix`。

## Autoscaling

- `autoscaling = null`：仍然建 scalable target，`min = max = desired_count`。service 忽略 `desired_count` 的變動，改這個值是靠 target 生效。
- `policy = "target_tracking"`（預設）：CPU 60%；`requests_per_target` 有值時多一條 ALB 請求數。冷卻 scale-in 300 秒、scale-out 60 秒。
- `policy = "step"`：CPU 與記憶體各一組 scale-out（門檻 70，三階 +1／+2／+3，每階 10%，冷卻 180 秒、評估 1 分鐘）與 scale-in（CPU 40、記憶體 50，−1，冷卻 300 秒、評估 5 分鐘）。共 4 個 policy 與 4 個 CloudWatch alarm。
- `autoscaling != null` 時 `desired_count` 必須落在 `min_capacity` 與 `max_capacity` 之間。
- `policy = "custom"`（0.2.0 起）：不建內建的 CPU、請求數與 step policy，只建下面兩種。scheduled action 與自訂 step policy 也可以跟其他三種 policy 一起用。
- `scheduled_actions`（0.2.0 起）：key（snake_case）對應 `schedule`（`cron()`、`rate()` 或 `at()`）、`timezone`（`UTC`）、`min_capacity`、`max_capacity`，每項建一個 scheduled action，名稱 `<name>-<key>`。`min_capacity` 不可大於 `max_capacity`，`max_capacity` 不可超過 `autoscaling.max_capacity`。
- `step_policies`（0.2.0 起）：key（snake_case）對應 `comparison_operator`、`threshold`、`evaluation_periods`，`metric`（單一指標）與 `queries`（metric math）二選一，以及 `adjustments`（`lower`、`upper`、`change` 的 list）；可選 `cooldown`（300）、`datapoints_to_alarm`、`treat_missing_data`（`notBreaching`）。每項建一個 StepScaling policy 與觸發它的 CloudWatch alarm（`alarm_actions` 指向該 policy），名稱 `<name>-step-<key>`。`lower`、`upper` 是相對於 alarm 門檻的區間。
- `queries` 裡的項目照 CloudWatch metric math 的規則寫：`expression` 或 `metric` 擇一，最後算出結果的那一項 `return_data = true`；module 不替你檢查，錯誤由 CloudWatch API 回報。
- 用輸出的 `autoscaling_resource_id` 仍然可以在 module 外加自己的 policy。

## system_controls

`system_controls`（0.2.0 起）預設 `{}`，此時 container definition 不會出現 `systemControls`，task definition 與 0.1.0 完全一致。有給時只加在 `app`，不加在 sidecar，依 namespace 排序。**設了之後會產生新的 task definition revision，觸發一次部署。**

## Sidecars

`sidecars` 預設是空 list，此時 task definition 與沒有這個變數之前完全一致（只有一個 container `app`，沒有 `dependsOn`），不會產生新的 revision。

- `container_definitions` 是 `app` 加上所有 sidecar，`app` 永遠排第一個且是 essential。
- sidecar 的 log 寫進同一個 log group、同一組 awslogs 設定，只有 `awslogs-stream-prefix` 換成 `log_stream_prefix`（預設為 sidecar 名稱）。
- sidecar 固定 `initProcessEnabled = true`、`stopTimeout = 120`；`essential` 預設 `false`。
- 只有當某個 sidecar 設了 `app_depends_on`，`app` 才會加 `dependsOn`。可用值：`START`、`HEALTHY`、`COMPLETE`、`SUCCESS`；`HEALTHY` 時該 sidecar 必須有 `health_check`。
- 名稱要符合 `^[a-z][a-z0-9-]{0,62}$`、不可重複、不可是 `app`；映像要帶明確 tag（不可 `latest`）或 digest；`secrets` 的值要是 ARN；`container_port` 不可跟 `app` 或其他 sidecar 重複（awsvpc 共用一張網卡）。
- sidecar 的 CPU 與記憶體是從 task 的 `cpu`、`memory` 裡分，module 不檢查總和，超過時 Fargate 在 API 端才會拒絕。
- 拉 sidecar 映像與讀它的 `secrets` 都用 execution role，權限要由呼叫端補上。

範例見 `examples/adot-sidecar/`。

## 呼叫端要準備的

module 不建 IAM 與 security group，兩者都由呼叫端傳入。

| execution role 需要的權限 | 用途 |
|---|---|
| `ecr:GetAuthorizationToken`，以及該 repo 的 `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`、`ecr:BatchCheckLayerAvailability` | 拉映像 |
| 該 log group 的 `logs:CreateLogStream`、`logs:PutLogEvents` | 寫 log；log group 由 module 建好 |
| 用到的 secret 的 `secretsmanager:GetSecretValue` 或 `ssm:GetParameters` | `secrets` 走 `valueFrom`，由 execution role 在啟動時讀 |
| secret 用自管 KMS key 時的 `kms:Decrypt` | 解密 |

- `secrets` 只給一般 secret。DB secret 由應用程式在執行期間用 task role 讀取，不放進 `secrets`。
- `enable_execute_command = true` 時，task role 要有 `ssmmessages:*Channel` 權限。

## 刻意不做

- 不建 security group、不建 IAM。
- 不寫死任何 sidecar 產品（ADOT、log router 等）；`sidecars` 只負責把額外 container 放進 task，映像、設定與權限由呼叫端決定。
- 不做 `readonlyRootFilesystem`。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | service 名稱，2–26 字元；也是 task family 與 target group 名稱前綴 |
| `cluster_arn` | `string` | 無 | 是 | cluster ARN |
| `image` | `string` | 無 | 是 | 映像，要帶明確 tag（不可 `latest`）或 sha256 digest |
| `cpu` | `number` | `512` | 否 | 與 `memory` 要是 Fargate 支援的組合 |
| `memory` | `number` | `1024` | 否 | MiB |
| `cpu_architecture` | `string` | `"ARM64"` | 否 | `ARM64` 或 `X86_64` |
| `container_port` | `number` | `null` | 否 | 接 LB 或 Service Connect 時必填 |
| `environment` | `map(string)` | `{}` | 否 | 一般環境變數 |
| `secrets` | `map(string)` | `{}` | 否 | 變數名稱 → Secrets Manager 或 SSM 參數 ARN |
| `execution_role_arn` | `string` | 無 | 是 | 呼叫端建好的 execution role |
| `task_role_arn` | `string` | 無 | 是 | 呼叫端建好的 task role |
| `network` | `object` | 無 | 是 | `subnet_ids`（至少 2 個不同）與 `security_group_ids`（至少 1 個） |
| `capacity_provider_strategy` | `list(object)` | `[{ capacity_provider = "FARGATE" }]` | 否 | service 的策略 |
| `desired_count` | `number` | `2` | 否 | 初始 task 數 |
| `autoscaling` | `object` | `null` | 否 | 見上方 Autoscaling；`policy` 可為 `target_tracking`、`step`、`custom`，另有 `scheduled_actions`、`step_policies`（皆預設 `{}`） |
| `load_balancer` | `object` | `null` | 否 | 見上方兩種 LB 接法 |
| `health_check_grace_period_seconds` | `number` | `180` | 否 | 只在有 LB 時套用 |
| `container_health_check` | `object` | `null` | 否 | `command` 必填，其餘有預設 |
| `service_connect` | `object` | `null` | 否 | `namespace_arn` 必填，`dns_name` 預設為 `name` |
| `sidecars` | `list(object)` | `[]` | 否 | 主 container `app` 以外的 container，見下方 Sidecars |
| `system_controls` | `map(string)` | `{}` | 否 | `app` container 的核心參數（namespace → 值）；空的時候 container definition 不含 `systemControls`。見上方 system_controls |
| `enable_execute_command` | `bool` | `false` | 否 | ECS Exec |
| `log_group_name` | `string` | `null` | 否 | `null` 時為 `/ecs/<name>` |
| `log_retention_days` | `number` | `30` | 否 | log 保留天數 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的 KMS key |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `service_name` | `string` | service 名稱 |
| `service_arn` | `string` | service ARN |
| `cluster_name` | `string` | 從 `cluster_arn` 拆出的 cluster 名稱 |
| `task_definition_arn` | `string` | task definition ARN（含 revision） |
| `task_definition_family` | `string` | task family |
| `container_name` | `string` | 固定 `app` |
| `log_group_name` | `string` | log group 名稱 |
| `log_group_arn` | `string` | log group ARN |
| `target_group_arn` | `string` | 外部傳入或 module 建的 target group；不接 LB 時 `null` |
| `target_group_arn_suffix` | `string` | `targetgroup/<name>/<id>`，給告警用；不接 LB 時 `null` |
| `autoscaling_resource_id` | `string` | `service/<cluster>/<service>` |

## 測試

```bash
scripts/validate.sh modules/ecs-service
```
