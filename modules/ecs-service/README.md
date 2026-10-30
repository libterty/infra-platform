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

`load_balancer` 的 `target_group_arn` 與 `listener_arn` 擇一，兩個都不給時，整個變數傳 `null`。

| 模式 | 輸入 | module 建什麼 |
|---|---|---|
| 不接 LB | `load_balancer = null` | 都不建；service 的 `health_check_grace_period_seconds` 傳 null |
| 外部 target group | `target_group_arn` | 不建 target group 與 rule，service 直接掛傳入的 ARN |
| module 建 | `listener_arn`、`vpc_id`、`priority`，加 `host_headers` 或 `path_patterns` 至少一項 | 一個 target group（名稱 `<name>-<container_port>`、`ip`、HTTP）與一條 listener rule |

接了 LB 或 Service Connect 時 `container_port` 必填。需要 `requests_per_target` 或告警時，另外給 `load_balancer.alb_arn_suffix`。

## Autoscaling

- `autoscaling = null`：仍然建 scalable target，`min = max = desired_count`。service 忽略 `desired_count` 的變動，改這個值要靠 scalable target 生效。
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
- sidecar 的 CPU 與記憶體從 task 的 `cpu`、`memory` 裡分。module 不檢查總和，超過時要到 Fargate API 才會拒絕。
- 拉 sidecar 映像與讀它的 `secrets` 都用 execution role，權限要由呼叫端補上。

範例見 `examples/adot-sidecar/`。

## 交給 pipeline 部署

`pipeline_managed`（0.3.0 起）預設 `false`，行為跟 0.2.1 一樣。設成 `true` 時：

- service 忽略 `task_definition` 的變動。Terraform 改環境變數、secret、CPU 這類設定時還是會註冊新的 task definition 版本，但 service 不會改用，要等下一次 pipeline 部署才會上線。
- `image` 只用在第一次建立，之後的映像檔由 pipeline 換。
- pipeline 的部署步驟建議是：取得 task definition family 的最新版本（Terraform 最後註冊的那一版）、換上新映像檔、註冊成新版本，再 `UpdateService`。CodePipeline 的 ECS 標準 action 會複製 service 目前用的版本，Terraform 改的設定永遠帶不上去，所以不要用（v11 設計文件 §5.4）。
- state 裡的 task definition 跟 service 實際用的不同，這是預期的，`terraform plan` 不會顯示差異。

## 原生 blue/green

`deployment`（0.3.0 起）預設 `{ strategy = "ROLLING" }`。設成 `BLUE_GREEN` 時用 ECS 原生的 blue/green，不需要 CodeDeploy：

```hcl
  pipeline_managed = true
  deployment = {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = 5
    role_arn             = module.ecs_infrastructure_role.role_arn
  }
```

- 必須搭配 `pipeline_managed = true`，而且只支援 `load_balancer.listener_arn` 接法：module 多建一個 alternate target group（`<name>-<container_port>-alt`，所以這兩段加起來最多 32 字元），listener rule 改成同時轉到兩個 target group（權重 100／0）。部署時 ECS 會改這兩個權重，所以 Terraform 忽略 rule 的 `action`。
- `role_arn` 是讓 ECS 改 ALB 的 role，trust `ecs.amazonaws.com`，掛 AWS managed policy `AmazonECSInfrastructureRolePolicyForLoadBalancers`（`iam-role` 0.6.0 起在白名單內）。
- `bake_time_in_minutes`（0–1440）是流量切到新版本後，新舊兩組 task 一起跑的時間；不給時用 ECS 的預設值。
- 部署完 service 的 `load_balancer.target_group_arn` 會不會跟 alternate 互換，還沒在真實環境確認。如果會換，下一次 `terraform plan` 會想把它改回來，採用前要先驗證。
- `target_group_arn`、`target_group_arn_suffix` 輸出的是主要的 target group。部署後流量可能在 alternate 上，用這兩個輸出建的告警要一併確認。

## 0.3.0 的位址變動

service 從 `aws_ecs_service.this` 變成 `aws_ecs_service.this[0]`，module 內有 `moved` 區塊，升版不會重建；listener rule 本來就有 `count`，位址不變。`pipeline_managed` 或 `strategy` 改值會換成另一個 resource 區塊，service 會被刪掉重建，要先用 `terraform state mv` 搬位址。

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
- 不做 canary、linear 部署策略，也不建 blue/green 的 test listener rule；外部 target group 接法不支援 blue/green。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | service 名稱，2–26 字元，限小寫英數字與連字號，字母開頭；同時是 task family、log group 名稱後綴與 target group 名稱前綴（target group 名稱 `<name>-<container_port>` 上限 32 字元）。 |
| `cluster_arn` | `string` | 無 | 是 | ECS cluster 的完整 ARN，來自 `ecs-cluster` module。 |
| `image` | `string` | 無 | 是 | 主 container 的映像，要帶明確 tag（不可 `latest`）或 sha256 digest。 |
| `cpu` | `number` | `512` | 否 | task 的 CPU 單位，與 `memory` 要是 Fargate 支援的 Linux 組合（`256`–`4096`）。 |
| `memory` | `number` | `1024` | 否 | task 的記憶體（MiB），要與 `cpu` 搭配：`256` 配 `512`／`1024`／`2048`；`512` 配 `1024`–`4096`；`1024` 配 `2048`–`8192`；`2048` 配 `4096`–`16384`；`4096` 配 `8192`–`30720`（範圍皆以 `1024` 為間隔）。 |
| `cpu_architecture` | `string` | `"ARM64"` | 否 | CPU 架構，`ARM64` 或 `X86_64`，要與映像一致。 |
| `container_port` | `number` | `null` | 否 | 主 container 的 port，1–65535 的整數。設了 `load_balancer` 或 `service_connect` 時必填；沒有 port 的 worker 傳 `null`。 |
| `environment` | `map(string)` | `{}` | 否 | 一般環境變數。 |
| `secrets` | `map(string)` | `{}` | 否 | 環境變數名稱對應 Secrets Manager 或 SSM SecureString 參數 ARN（Secrets Manager 可加 `:json-key::` 後綴），由 execution role 在啟動時讀取。 |
| `execution_role_arn` | `string` | 無 | 是 | task execution role ARN，由呼叫端建立（`iam-base` stack）。 |
| `task_role_arn` | `string` | 無 | 是 | task role ARN，由呼叫端建立（`iam-app` stack）。 |
| `network` | `object` | 無 | 是 | service 的網路設定，都由呼叫端建立（network stack）。欄位：`subnet_ids`（至少 2 個不同的 subnet，分屬不同 AZ）、`security_group_ids`（至少 1 個）。 |
| `capacity_provider_strategy` | `list(object)` | `[ { "capacity_provider": "FARGATE" } ]` | 否 | service 的 capacity provider 策略。欄位：`capacity_provider`、`weight`（預設 `1`）、`base`（預設 `0`）。 |
| `desired_count` | `number` | `2` | 否 | 初始 task 數。之後的變動 service 會忽略，容量由 autoscaling target 管理。 |
| `autoscaling` | `object` | `null` | 否 | autoscaling 設定；`null` 時仍建 scalable target，`min = max = desired_count`。`policy` 可為 `target_tracking`（預設）、`step`、`custom`，`custom` 不建內建 policy；`scheduled_actions`、`step_policies`（皆預設 `{}`）可搭配任何 policy。行為見〈Autoscaling〉，欄位見〈`autoscaling` 欄位〉。 |
| `system_controls` | `map(string)` | `{}` | 否 | `app` container 的 namespaced 核心參數，例如 `net.ipv4.tcp_keepalive_time` 對應 `"240"`。空的時候 container definition 不含 `systemControls`；非空會產生新的 task definition 並觸發一次部署。見〈system\_controls〉。 |
| `load_balancer` | `object` | `null` | 否 | LB 設定；`null` 時不接 LB。`target_group_arn`（外部 target group）與 `listener_arn`（module 建 target group 與 listener rule）擇一。接法見〈兩種 LB 接法〉，欄位見〈`load_balancer` 欄位〉。 |
| `pipeline_managed` | `bool` | `false` | 否 | `true` 時部署交給 pipeline：service 忽略 `task_definition` 的變動。Terraform 改設定時還是會註冊新的 task definition 版本，但 service 不會改用，要等下一次 pipeline 部署；`image` 只用在第一次建立。見〈交給 pipeline 部署〉。 |
| `deployment` | `object` | `{ "strategy": "ROLLING" }` | 否 | 部署策略。欄位：`strategy`（`ROLLING` 或 `BLUE_GREEN`，預設 `ROLLING`）、`bake_time_in_minutes`（0–1440，只用在 `BLUE_GREEN`）、`role_arn`（讓 ECS 改 ALB listener rule 的 IAM role，`BLUE_GREEN` 必填）。`BLUE_GREEN` 必須搭配 `pipeline_managed = true` 與 `load_balancer.listener_arn` 接法。見〈原生 blue/green〉。 |
| `health_check_grace_period_seconds` | `number` | `180` | 否 | health check 寬限秒數，只在設了 `load_balancer` 時套用，否則 service 拿到 `null`。 |
| `container_health_check` | `object` | `null` | 否 | 主 container 的 health check；`null` 時不設。欄位：`command`（必填）、`interval`（預設 `10`）、`timeout`（預設 `5`）、`retries`（預設 `3`）、`start_period`（預設 `60`）。 |
| `service_connect` | `object` | `null` | 否 | Service Connect 註冊；`null` 時停用。欄位：`namespace_arn`（必填）、`dns_name`（`null` 時用 `name`）。 |
| `sidecars` | `list(object)` | `[]` | 否 | 主 container `app` 以外的 container；空 list 時 task definition 與單一 container 時完全一致。行為見〈Sidecars〉，欄位見〈`sidecars` 欄位〉。 |
| `enable_execute_command` | `bool` | `false` | 否 | 啟用 ECS Exec。task role 需要 `ssmmessages` 權限。 |
| `log_group_name` | `string` | `null` | 否 | service 的 log group 名稱；`null` 時用 `/ecs/<name>`。 |
| `log_retention_days` | `number` | `30` | 否 | service log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`）。 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的 KMS key ARN；`null` 時用預設加密。 |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `service_name` | ECS service 名稱。 |
| `service_arn` | ECS service ARN。 |
| `cluster_name` | 從 `cluster_arn` 拆出的 cluster 名稱。 |
| `task_definition_arn` | task definition ARN，含 revision。 |
| `task_definition_family` | task definition family。 |
| `container_name` | 主 container 名稱，固定 `app`。 |
| `log_group_name` | service log group 名稱。 |
| `log_group_arn` | service log group ARN。 |
| `target_group_arn` | target group ARN：`target_group_arn` 模式是傳入的值，`listener_arn` 模式是 module 建的；不接 LB 時 `null`。 |
| `target_group_arn_suffix` | `targetgroup/<name>/<id>`，給告警的 dimension 用；不接 LB 時 `null`。 |
| `autoscaling_resource_id` | `service/<cluster>/<service>`，給在 module 外另加的 scaling policy 用。 |
<!-- END_TF_DOCS -->

## `autoscaling` 欄位

| 欄位 | 預設 | 說明 |
|---|---|---|
| `min_capacity` | 必填 | 最少 task 數，至少 `1` |
| `max_capacity` | 必填 | 最多 task 數，不可小於 `min_capacity`；`desired_count` 要落在兩者之間 |
| `policy` | `"target_tracking"` | `target_tracking`、`step` 或 `custom` |
| `target_tracking.cpu_percent` | `60` | CPU 目標百分比 |
| `target_tracking.requests_per_target` | `null` | 每個 target 的 ALB 請求數目標（`ALBRequestCountPerTarget`）；有值時需要 `load_balancer.alb_arn_suffix` |
| `target_tracking.scale_in_cooldown` | `300` | scale-in 冷卻秒數 |
| `target_tracking.scale_out_cooldown` | `60` | scale-out 冷卻秒數 |
| `step.cpu_scale_out_threshold` | `70` | CPU scale-out 門檻（%） |
| `step.cpu_scale_in_threshold` | `40` | CPU scale-in 門檻（%） |
| `step.memory_scale_out_threshold` | `70` | 記憶體 scale-out 門檻（%） |
| `step.memory_scale_in_threshold` | `50` | 記憶體 scale-in 門檻（%） |
| `step.scale_out_step_size` | `10` | scale-out 每一階的寬度（超過門檻的百分點） |
| `step.scale_out_cooldown` | `180` | scale-out 冷卻秒數 |
| `step.scale_in_cooldown` | `300` | scale-in 冷卻秒數 |
| `scheduled_actions` | `{}` | key（snake_case）對應 `schedule`（必填，`cron()`、`rate()` 或 `at()`）、`timezone`（預設 `UTC`）、`min_capacity`、`max_capacity`（皆必填）。`min_capacity` 不可大於 `max_capacity`，`max_capacity` 不可超過 `autoscaling.max_capacity` |
| `step_policies` | `{}` | key（snake_case）對應一個 StepScaling policy 與觸發它的 alarm，欄位見下表 |

`step_policies` 每一項：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `comparison_operator` | 必填 | alarm 的比較運算子 |
| `threshold` | 必填 | alarm 門檻 |
| `evaluation_periods` | 必填 | 評估期數 |
| `datapoints_to_alarm` | `null` | 觸發所需的資料點數 |
| `treat_missing_data` | `"notBreaching"` | 缺資料時的處理方式 |
| `cooldown` | `300` | policy 冷卻秒數 |
| `metric` | `null` | 單一指標：`namespace`、`metric_name`（必填）、`dimensions`（預設 `{}`）、`period`（預設 `60`）、`statistic`（預設 `"Average"`）。與 `queries` 二選一 |
| `queries` | `null` | metric math：每項 `id`（必填）、`expression`、`label`、`return_data`、`metric`（`namespace`、`metric_name`、`dimensions` 預設 `{}`、`period` 預設 `60`、`stat` 預設 `"Average"`）。與 `metric` 二選一 |
| `adjustments` | 必填 | `lower`、`upper`（相對於 alarm 門檻的區間）與 `change`（必填）的 list |

## `load_balancer` 欄位

| 欄位 | 預設 | 說明 |
|---|---|---|
| `target_group_arn` | `null` | 外部 target group 模式：直接掛這個 ARN。與 `listener_arn` 擇一 |
| `listener_arn` | `null` | module 建 target group 與 listener rule 的模式。與 `target_group_arn` 擇一 |
| `vpc_id` | `null` | `listener_arn` 模式必填 |
| `priority` | `null` | listener rule 優先順序，`listener_arn` 模式必填 |
| `host_headers` | `[]` | `listener_arn` 模式下，與 `path_patterns` 至少要有一項 |
| `path_patterns` | `[]` | 同上 |
| `health_check` | `{}` | target group health check：`path`（`"/health"`）、`matcher`（`"200"`）、`interval`（`10`）、`timeout`（`5`）、`healthy_threshold`（`3`）、`unhealthy_threshold`（`3`） |
| `alb_arn_suffix` | `null` | 兩種模式都可給；`requests_per_target` 與告警需要 |

## `sidecars` 欄位

| 欄位 | 預設 | 說明 |
|---|---|---|
| `name` | 必填 | 符合 `^[a-z][a-z0-9-]{0,62}$`，不可重複，不可是 `app` |
| `image` | 必填 | 要帶明確 tag（不可 `latest`）或 sha256 digest |
| `essential` | `false` | 是否為 essential container |
| `command` | `null` | container command |
| `cpu` | `null` | 從 task `cpu` 裡保留的 CPU 單位 |
| `memory_reservation` | `null` | 從 task `memory` 裡保留的軟性上限（MiB） |
| `environment` | `{}` | 一般環境變數 |
| `secrets` | `{}` | 環境變數名稱對應 Secrets Manager 或 SSM 參數 ARN |
| `port_mappings` | `[]` | `container_port`（必填）、`protocol`（預設 `"tcp"`）的 list；port 不可跟 `app` 或其他 sidecar 重複 |
| `health_check` | `null` | `command`（必填）、`interval`（`10`）、`timeout`（`5`）、`retries`（`3`）、`start_period`（`10`） |
| `app_depends_on` | `null` | `START`、`HEALTHY`、`COMPLETE` 或 `SUCCESS`；`null` 時 `app` 不等這個 sidecar。`HEALTHY` 時必須有 `health_check` |
| `log_stream_prefix` | `null` | awslogs stream prefix；`null` 時用 sidecar 名稱 |

## 測試

```bash
scripts/validate.sh modules/ecs-service
```
