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
- 排程擴縮與自訂指標的 policy 不在 module 內；用輸出的 `autoscaling_resource_id` 在 module 外自己加。

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
- 不支援多 container 或 sidecar。
- 不做排程擴縮、自訂指標 step scaling、`readonlyRootFilesystem`。

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
| `autoscaling` | `object` | `null` | 否 | 見上方 Autoscaling |
| `load_balancer` | `object` | `null` | 否 | 見上方兩種 LB 接法 |
| `health_check_grace_period_seconds` | `number` | `180` | 否 | 只在有 LB 時套用 |
| `container_health_check` | `object` | `null` | 否 | `command` 必填，其餘有預設 |
| `service_connect` | `object` | `null` | 否 | `namespace_arn` 必填，`dns_name` 預設為 `name` |
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
