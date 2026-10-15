# 觀測性：ADOT sidecar、X-Ray 與 log 告警

結論：範本預設不開追蹤。要追蹤的服務，在 `iam-app` 加進 `tracing_services`，task role 就拿到 X-Ray 的四個動作，同時發布 `tracing_<service>`；`application` 讀這個 key，開的服務才掛 ADOT collector sidecar 並設 `OTEL_EXPORTER_OTLP_ENDPOINT`。抽樣用 `application` 的 `xray_sampling_rules` 控制成本，log 裡的事件用 `log_alarms` 接告警。

範本沒有把追蹤做進去，原因是它牽涉 `iam-app`、`application`、`network` 三個 stack，放進範本會讓每個專案都背一個預設關閉的 sidecar（設計文件 §4.20）。這份 guide 不會被 CI 驗證，HCL 片段裡 sidecar 的部分逐行照 `modules/ecs-service/examples/adot-sidecar/main.tf`，那份 example 會被 CI 跑 `init -backend=false` 與 `validate`。

以下都沒有在真實帳號驗證過，對應設計文件 §7.3 第 13 項。

## 整體分工

| 要做的事 | 在哪個 stack | 單一決定點 |
|---|---|---|
| 決定哪些服務要追蹤、給 task role X-Ray 權限 | `iam-app` | `iam-app/tracing_<service>`，`application` 只讀不設 |
| 掛 ADOT collector sidecar、設 OTLP endpoint | `application` | — |
| collector 映像能被拉到 | `containerimage` 的 `mirrored_images` 加 `iam-base`（拉私有 ECR 時），或 `network`（拉 ECR Public 時要有 NAT） | — |
| X-Ray 的 interface endpoint（沒有 NAT 或想走私網時） | `network` 的 `interface_endpoints.services` 加 `xray` | — |
| 抽樣規則與 group | `application` 的 `xray_sampling_rules`、`xray_groups` | — |
| log 事件告警 | `application` 的 `log_alarms` | — |

跟 ECS Exec 的做法相同：權限與開關由同一個 stack 決定、同一個 key 發布，不會出現「掛了 collector 但 task role 沒有權限」或反過來。

## 1. `iam-app`：權限與開關

`variables.tf` 加一個變數：

```hcl
variable "tracing_services" {
  description = "Services that send traces to X-Ray through an ADOT collector sidecar. Each gets the X-Ray permissions on its task role, and application adds the sidecar from the flag published here."
  type        = list(string)
  default     = []
}
```

`task-roles.tf` 加 X-Ray 的 statement，並併進每個服務的 `task_policies`：

```hcl
locals {
  tracing_enabled = toset(var.tracing_services)

  tracing_statements = [
    {
      # These X-Ray actions do not support resource-level permissions; "*" is the only valid Resource.
      Sid      = "XRayTracesAndSampling"
      Effect   = "Allow"
      Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
      Resource = "*"
    },
  ]
}
```

```hcl
  # task_policies 的 merge() 裡多一項
  contains(local.tracing_enabled, s) ? {
    tracing = jsonencode({ Version = "2012-10-17", Statement = local.tracing_statements })
  } : {},
```

`ssm-outputs.tf` 的 `published_strings` 多發布一組：

```hcl
    { for s, k in local.service_key : "tracing_${k}" => jsonencode({ enabled = contains(local.tracing_enabled, s) }) },
```

`guards.tf` 照 `ecs_exec_services_are_known` 的寫法加一條 precondition：`tracing_services` 只能是 `containerimage/services` 裡的名稱。

這四個 X-Ray 動作已經在 `iam-base`、`iam-app` 測試的 `wildcard_resource_allowlist` 允許清單裡，加上去不會被自己的測試擋下。要改的測試是：

- `publishes_under_stack_path`：`module.ssm_publish.names` 多了每個服務的 `tracing_<service>`。
- 加一個 run：`tracing_services = ["api"]` 時 api 的 task role 有 `tracing` policy、發布 `{"enabled":true}`；worker 兩者都沒有。

collector 如果也送 metric（例如 `awsemf` exporter 寫 CloudWatch Logs），task role 還要 `logs:CreateLogStream`、`logs:PutLogEvents`、`logs:DescribeLogStreams`，Resource 限定那個 log group，不要給 `*`。下面的 collector 設定只送 trace，不需要這組權限。

## 2. collector 映像從哪裡拉

| 來源 | 需要什麼 |
|---|---|
| ECR Public（`public.ecr.aws/aws-observability/aws-otel-collector`，example 用的） | ECR Public 拉映像不需要 execution role 的 ECR 權限，但 task 所在的 subnet 要能經 NAT 出去；`nat_mode = "none"` 或客戶 VPC 沒有對外路由時拉不到。**未驗證** |
| 複製到專案自己的 ECR | 映像推進一個專案的 repository；`iam-base` 的 `PullImagesFromProjectRepositories` statement 的 Resource 要加上那個 repository 的 ARN（經 SSM 讀，不寫死在 tfvars），私網環境再加 `ecr.api`、`ecr.dkr` interface endpoint |

沒有 NAT 的環境建議走第二種。範本的 `containerimage` 有 `mirrored_images` 輸入，專門放外部映像的副本；`iam-base` 會把這些 repository 的 ARN 加進 execution role 的拉取權限，不需要自己改 policy。

### 沒有 NAT 時：把 collector 映像放進 mirror repository

下面四步都在已經跑過 `foundation` 的環境做；mirror 是 `containerimage` 的一個輸入，不需要新增 stack。

**1. `containerimage` 的 tfvars 加 mirror**

```hcl
# infra/terraform/containerimage/envs/<env>.tfvars
mirrored_images = ["adot-collector"]
```

名稱用 kebab-case，不能跟任何服務同名。Repository 名稱是 `<project>-<env>-mirror-adot-collector`（例如 `alpha-dev-mirror-adot-collector`），設定跟服務的 repository 相同：tag 不可覆蓋（`IMMUTABLE`）、推上去就掃描、KMS 加密、同一組 lifecycle。

**2. 先 apply `containerimage`，再 apply `iam-base`**

順序不能反：`iam-base` 讀的是 `containerimage/mirrored_images` 與 `containerimage/ecr_mirror_adot_collector_arn`，`containerimage` 還沒發布時 `iam-base` 的 plan 會讀不到。`containerimage` 的 `terraform output mirror_repository_urls` 會印出 repository URL。`iam-base` 的 plan 應該只有 execution role 的 inline policy 一個變更：`PullImagesFromProjectRepositories` 的 Resource 多出 mirror 的 ARN。

**3. 把映像複製進 mirror repository**

由有網路的人或 CI 做，用上游版本號當 tag（repository 是 `IMMUTABLE`，同一個 tag 推第二次會被拒絕，所以不要用 `latest`）。版本號跟 `application` 的 `adot_sidecar` 用的一致（下例 `v0.43.1`）：

```bash
VERSION="v0.43.1"
ACCOUNT_ID="<account-id>"
REGION="ap-northeast-1"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="${REGISTRY}/alpha-dev-mirror-adot-collector"

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# Fargate 跑 ARM64 時改 linux/arm64，跟 ecs-service 的 cpu_architecture 一致
docker pull --platform linux/amd64 "public.ecr.aws/aws-observability/aws-otel-collector:${VERSION}"
docker tag  "public.ecr.aws/aws-observability/aws-otel-collector:${VERSION}" "${REPO}:${VERSION}"
docker push "${REPO}:${VERSION}"
```

不想裝 docker 的話，用 [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) 直接在 registry 之間複製，會保留上游所有平台的 manifest：

```bash
aws ecr get-login-password --region "$REGION" | crane auth login --username AWS --password-stdin "$REGISTRY"
crane copy "public.ecr.aws/aws-observability/aws-otel-collector:${VERSION}" "${REPO}:${VERSION}"
```

這兩組指令都**未驗證**，沒有在真實帳號跑過。

**4. sidecar 的 image 改指 mirror**

`application` 的 `adot_sidecar.image` 改成上一步的 `${REPO}:${VERSION}`。repository URL 不要寫死帳號 ID：從 `containerimage/ecr_mirror_adot_collector_url` 讀，再接上版本號，讀法跟 `ssm_service_strings` 讀 `ecr_<service>_url` 相同。

task 所在的 subnet 沒有 NAT 時，Fargate 拉私有 ECR 的映像還需要 `ecr.api`、`ecr.dkr` 兩個 interface endpoint（在 `network` 的 `interface_endpoints.services` 加上去）與 S3 的 gateway endpoint（映像的 layer 存在 S3）。目前範本的 `network` 沒有 S3 gateway endpoint 的輸入，這一項要另外處理。**未驗證**。

### 替代方案：ECR pull-through cache

ECR 的 pull-through cache 規則讓帳號自己的 ECR 在第一次被拉取時，自動從 ECR Public 抓一份進來，不需要人或 CI 複製映像，也不用管 tag。但目前這個 repo 沒有管 `aws_ecr_pull_through_cache_rule` 的 module，要用就得新增一個（還要處理 execution role 多出的 `ecr:CreateRepository`、`ecr:BatchImportUpstreamImage` 權限，以及第一次拉取時要連得到上游），第一版不做。需要時先用上面的 mirror 做法。

## 3. `application`：掛 sidecar

`ssm-inputs.tf` 的 `ssm_service_strings` 多讀一組：

```hcl
    { for s, k in local.service_key : "tracing_${k}" => "iam-app/tracing_${k}" },
```

`ecs.tf` 加 collector 的設定與 sidecar，並把結果接進 `service_inputs` 與 `module "service"`：

```hcl
locals {
  tracing = { for s, k in local.service_key : s => jsondecode(module.in_services.strings["tracing_${k}"]).enabled }

  # OTLP in, X-Ray out. Passed through environment, not a secret.
  collector_config = <<-YAML
    extensions:
      health_check: {}
      awsproxy: {}
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    processors:
      memory_limiter:
        check_interval: 1s
        limit_mib: 200
        spike_limit_mib: 50
      filter/health:
        error_mode: ignore
        traces:
          span:
            - 'attributes["url.path"] == "/health"'
            - 'attributes["http.target"] == "/health"'
      batch: {}
    exporters:
      awsxray: {}
    service:
      extensions: [health_check, awsproxy]
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, filter/health, batch]
          exporters: [awsxray]
  YAML

  adot_sidecar = {
    name               = "adot-collector"
    image              = "public.ecr.aws/aws-observability/aws-otel-collector:v0.43.1"
    essential          = false
    cpu                = 128
    memory_reservation = 256
    environment        = { AOT_CONFIG_CONTENT = local.collector_config }
    port_mappings      = [{ container_port = 4317 }]
    health_check       = { command = ["CMD", "/healthcheck"] }
    app_depends_on     = "START"
  }
}
```

```hcl
  # service_inputs 的每個服務
      environment = merge(
        contains(local.db_readers, s) ? local.db_environment : {},
        # Containers share the task network interface, so localhost reaches the collector.
        local.tracing[s] ? { OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317" } : {},
      )
      sidecars = local.tracing[s] ? [local.adot_sidecar] : []
```

```hcl
module "service" {
  # 其他參數不變
  sidecars = each.value.sidecars
}
```

`tracing_<service>` 是新的 SSM key，`application` 的測試檔開頭要為每個服務加 `override_data`（值給 `{"enabled":false}`），不然 mock 會回隨機字串，`jsondecode` 直接失敗；`reads_only_listed_keys` 對 `local.ssm_service_strings` 的斷言也要加上這組 key。

### 跟 example 逐行對照

`local.adot_sidecar` 的每一行跟 `modules/ecs-service/examples/adot-sidecar/main.tf` 的 `sidecars = [{ ... }]` 完全相同：

| 行 | example | 這份 guide |
|---|---|---|
| 名稱 | `name               = "adot-collector"` | 相同 |
| 映像 | `image              = "public.ecr.aws/aws-observability/aws-otel-collector:v0.43.1"` | 相同 |
| essential | `essential          = false` | 相同 |
| CPU | `cpu                = 128` | 相同 |
| 記憶體 | `memory_reservation = 256` | 相同 |
| 設定 | `environment        = { AOT_CONFIG_CONTENT = local.collector_config }` | 相同 |
| port | `port_mappings      = [{ container_port = 4317 }]` | 相同 |
| health check | `health_check       = { command = ["CMD", "/healthcheck"] }` | 相同 |
| 等待條件 | `app_depends_on     = "START"` | 相同 |
| 主 container | `environment = { OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317" }` | 相同的值，併進既有的 `environment` |

不一樣的只有 `local.collector_config` 的內容：example 只放 OTLP、batch、awsxray 三段讓它最小；這裡多了 `memory_limiter`、濾掉 health check 的 `filter/health`、`health_check` 與 `awsproxy` 兩個 extension。

### 為什麼 `essential = false`

collector 只負責送 trace，不在請求路徑上。`essential = true` 時 collector 一掛掉，ECS 會停掉整個 task 重開，等於追蹤元件的故障變成服務中斷。設成 `false`，collector 掛了只是少一段時間的 trace，主 container 照常服務。參考來源 project-c 的寫法是 `true`（`project-c-app/modules/app-service/ecs-standard.tf`），這裡刻意不同。

`app_depends_on = "START"` 讓主 container 等 collector 啟動後才啟動，減少開機時第一批 trace 送不出去的機會；用 `START` 而不是 `HEALTHY`，是不讓 collector 的健康狀態卡住服務啟動。

### collector 設定的幾個注意

- `/healthcheck` 是 ADOT 映像內建的檢查程式，它查的是 `health_check` extension。example 的最小設定沒有開這個 extension，health check 可能一直不健康；因為是 `essential = false` 加 `START`，不影響服務，但 console 會顯示 unhealthy。上面的設定已經開了。**未驗證**。
- `filter/health` 用的 attribute 名稱取決於 SDK 的 semantic convention 版本：新版是 `url.path`，舊版是 `http.target`，兩個都寫。health check 路徑照服務實際的寫。
- `memory_limiter` 的上限要小於 `memory_reservation`（256 MiB）。sidecar 的 CPU 與記憶體從 task 的 `cpu`／`memory` 裡分，task 預設 512／1024，掛了 collector 之後主 container 能用的就少了這一塊。
- 設定用 `environment` 帶，不學 project-c 存成 SSM parameter 再用 `secrets` 讀：設定不是機密，而且範本規定 `aws_ssm_parameter` 只能由 `ssm-publish` 建。設定太大放不進環境變數時，改成把設定烤進自己的 collector 映像。

## 4. `network`：X-Ray 的 interface endpoint

沒有 NAT，或希望 trace 不經網際網路時，在 `network` 的 tfvars 加上 `xray`：

```hcl
interface_endpoints = {
  services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms", "xray"]
}
```

範本的大流量範例（`network/envs/examples/high.tfvars`）已經包含 `xray`。endpoint 的 SG 只開 443 給 VPC CIDR，服務 SG 的 egress 443 本來就開著，不用改規則。

## 5. 抽樣：`xray` module

抽樣規則決定送多少 trace，是控制 X-Ray 成本的主要旋鈕。`application` 的三個變數預設都是 `{}`，什麼都不建；範例在 `application/envs/examples/`：

```hcl
xray_sampling_rules = {
  health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" } # drop health checks
  api    = { priority = 200, fixed_rate = 0.05, reservoir_size = 1, service_name = "alpha-prod-api" }
}

xray_groups = {
  errors = { filter_expression = "fault = true OR error = true" }
  slow   = { filter_expression = "responsetime > 3" }
}
```

- `priority` 數字小的先比對；health check 規則放最前面、`fixed_rate = 0`。
- 沒給的欄位是 `*`。`service_name` 要跟 SDK 回報的服務名稱一致，規則才對得上。
- 建議起點：PoC 100%、一般正式每秒 1 筆加 5%、大流量每秒 1 筆加 1～5%。這些比例都**沒有實測依據**，上線後用實際流量與帳單調。

**remote sampling 的前提**：sampling rule 只對「向 X-Ray 拉規則」的 SDK 或 collector 生效。三件事都要成立：

1. 應用程式的 SDK 設成 X-Ray remote sampler（例如 ADOT Java agent 的 `OTEL_TRACES_SAMPLER=xray`），並指到 collector 的 `awsproxy`（預設 `localhost:2000`）。
2. collector 開了 `awsproxy` extension（上面的設定有）。
3. task role 有 `xray:GetSamplingRules`、`xray:GetSamplingTargets`（`iam-app` 的 `tracing` policy 有）。

應用程式如果用 SDK 端的固定比例（`OTEL_TRACES_SAMPLER=traceidratio`，project-a 的做法），sampling rule 不會生效，抽樣只看 SDK 設定。

## 6. log 告警：`log-metric-alarm`

應用程式在發生重要事件時印一行 log，`log-metric-alarm` 把它轉成指標並接告警，告警送到 `foundation` 的 `alarm_topic_arn`。設定在 `application` 的 `log_alarms`，key 是服務名稱，log group 自動取那個服務的：

```hcl
log_alarms = {
  api = {
    audit_write_failed = {
      pattern     = "{ $.event = \"audit_write_failed\" }"
      metric_name = "AuditWriteFailed"
      description = "The api could not write an audit record. Check the database connection and the api task logs."
    }
  }
}
```

- 應用程式印 JSON log（一行一個 JSON 物件）時，用 CloudWatch 的 JSON 篩選語法 `{ $.欄位 = "值" }`，欄位名稱照應用程式的 log 格式。範例檔用的是純文字比對 `"\"audit_write_failed\""`，log 不是 JSON 時用這種。
- `description` 寫「代表什麼、先查哪裡」，收到告警的人只會先看到這一段。
- 沒寫的欄位用 module 預設：一分鐘內出現一次就告警、沒有資料視為正常。
- 告警在印出事件後多久轉 ALARM、email 收不收得到，**未驗證**（設計文件 §7.3 第 13 項）。

## 驗證怎麼做

改完 `iam-app` 與 `application` 後，在專案 repo 裡離線跑兩個 stack 的測試（見 [`project-infra-standard.md`](./project-infra-standard.md)〈驗證〉）。mock 驗不到的是 collector 真的送得出 trace、remote sampling 真的生效、IAM 真的夠，這些要部署到沙箱帳號，用一次真實請求確認 X-Ray console 有 trace、health check 沒有進來。
