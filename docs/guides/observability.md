# 觀測性：ADOT sidecar、X-Ray 與 log 告警

結論：範本已經把 X-Ray 追蹤接好，預設關閉。要開，照三步：`iam-app` 的 `tracing` 列出要追蹤的服務（task role 拿到 X-Ray 的四個動作）、`application` 的 `adot_collector` 指定 collector 映像（被追蹤的服務才掛 ADOT collector sidecar 並設 OTLP 環境變數）、沒有 NAT 時改用 mirror 映像並在 `network` 加 endpoint。抽樣用 `application` 的 `xray_sampling_rules` 控制成本，log 裡的事件用 `log_alarms` 接告警。

「要不要追蹤」只有一個決定點：`iam-app/tracing`。`application` 沒有自己的追蹤開關，所以不會出現「掛了 collector 但 task role 沒有權限」或反過來。範本預設不開，沒有服務被追蹤時，task definition 跟沒有這個功能時完全一樣。設計理由見 design 決策 36（推翻決策 32 的後半句）與 §4.20、§5.3〈追蹤〉。

以下都沒有在真實帳號驗證過，對應設計文件 §7.3 第 13 項。這份 guide 不會被 CI 驗證，HCL 片段以範本的檔案為準：`iam-app/task-roles.tf`、`application/tracing.tf`、`application/adot-collector.yaml`。

## 整體分工

| 要做的事 | 在哪個 stack | 怎麼設 |
|---|---|---|
| 決定哪些服務要追蹤、給 task role X-Ray 權限 | `iam-app` | `tracing = ["api"]`，發布 `iam-app/tracing`；`application` 只讀不設 |
| 掛 ADOT collector sidecar、設 OTLP endpoint 與服務名稱 | `application` | 範本已接好；只需要 `adot_collector = { tag, source }` |
| collector 設定檔 | `application` | `adot-collector.yaml`，要改就改這個檔 |
| collector 映像能被拉到 | `containerimage` 的 `mirrored_images` 加 `iam-base`（拉私有 ECR 時），或 `network` 有 NAT（拉 ECR Public 時） | `source = "mirror"` 或 `"public"` |
| X-Ray 的 interface endpoint（沒有 NAT 時必要，有 NAT 時想走私網也可以） | `network` | `interface_endpoints.services` 加 `xray` |
| 抽樣規則與 group | `application` | `xray_sampling_rules`、`xray_groups` |
| log 事件告警 | `application` | `log_alarms` |

## 開追蹤的三個步驟

順序就是 apply 順序（`iam-app` 在 `application` 之前）。

### 1. `iam-app`：`tracing`

`envs/<env>.tfvars`：

```hcl
tracing = ["api"]
```

- 型別是 `set(string)`，預設空集合。名稱必須是 `containerimage/services` 裡的名稱，寫了不存在的服務 plan 會停（`terraform_data.tracing_services_are_known`）。
- 被列的服務，task role 多一個 `tracing` inline policy：`xray:PutTraceSegments`、`xray:PutTelemetryRecords`、`xray:GetSamplingRules`、`xray:GetSamplingTargets`，`Resource = "*"`（這四個動作不支援 resource-level 權限）。沒被列的服務一個 `xray:` 動作都沒有。
- 發布 `iam-app/tracing`，值是排序過的 JSON 陣列的 String，例如 `["api"]`；沒有追蹤時是 `[]`。
- 這四個 X-Ray 動作在 `iam-base`、`iam-app` 測試的 `wildcard_resource_allowlist` 允許清單裡，其他動作搭配 `*` 仍然會被擋。

collector 如果也送 metric（例如 `awsemf` exporter 寫 CloudWatch Logs），task role 還要 `logs:CreateLogStream`、`logs:PutLogEvents`、`logs:DescribeLogStreams`，Resource 限定那個 log group，不要給 `*`。範本的 collector 設定只送 trace，不需要這組權限。

### 2. `application`：`adot_collector`

`envs/<env>.tfvars`：

```hcl
adot_collector = { tag = "v0.43.1", source = "public" }
```

- `tag` 必須明確，不接受 `latest`；有服務被追蹤時這個變數必填，沒有被追蹤時可以不寫。`v0.43.1` 是 `modules/ecs-service/examples/adot-sidecar/` 在用的版本，**沒有確認這個 tag 在 ECR Public 上存在**，用之前先查。
- `source = "public"`：映像是 `public.ecr.aws/aws-observability/aws-otel-collector:<tag>`，task 要能經 NAT 連到 ECR Public。
- `source = "mirror"`：映像是 `containerimage/ecr_mirror_adot_collector_url` 加 `:<tag>`，`containerimage` 的 `mirrored_images` 必須含 `adot-collector`（不含時 plan 會停）。複製映像的步驟見下一節。

被追蹤的服務會得到：

- 一個 `adot-collector` sidecar，欄位跟 `modules/ecs-service/examples/adot-sidecar/main.tf` 逐行相同（見下表）。
- 主 container 多兩個環境變數：`OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317`（同一個 task 的 container 共用網路介面，localhost 到得了 collector）與 `OTEL_SERVICE_NAME=<project>-<env>-<service>`。應用程式的 OTel SDK 讀這兩個變數即可，不用另外設定。服務名稱跟 `xray_sampling_rules` 的 `service_name` 要寫的名稱一致。

沒被追蹤的服務 `sidecars = []`，環境變數也不變，task definition 跟沒有這個功能時一致（`application` 測試鎖住）。

### 3. 沒有 NAT 時：mirror 映像加 endpoint

`network/nat` 的 `mode` 是 `none` 時，`application` 在有服務被追蹤的情況下，要求三件事同時成立，缺任何一項 plan 就停，錯誤訊息會列出缺什麼：

1. `adot_collector.source = "mirror"`。
2. `containerimage` 的 `mirrored_images` 含 `adot-collector`，映像已複製進去（下一節）。
3. `network` 的 `interface_endpoints.services` 含 `xray`、`ecr.api`、`ecr.dkr`（見〈network：X-Ray 的 interface endpoint〉）。`network` 把已建的清單發布成 `network/interface_endpoints`，`application` 讀它來檢查。

另外需要 S3 gateway endpoint（ECR 映像的 layer 存在 S3）：自建 VPC 的 `modules/vpc` 預設就有，不用處理；客戶自管 VPC（模式 A）要自己確認，範本不檢查。

`nat.mode` 是 `external`（模式 A，客戶自管 VPC）時，NAT 由客戶負責，範本不擋。客戶的 VPC 沒有 NAT 時，要自己照上面三項準備。`single`、`per_az` 不檢查。

## collector 映像從哪裡拉

| 來源 | 需要什麼 |
|---|---|
| ECR Public（`public.ecr.aws/aws-observability/aws-otel-collector`） | ECR Public 拉映像不需要 execution role 的 ECR 權限，但 task 所在的 subnet 要能經 NAT 出去；`nat_mode = "none"` 或客戶 VPC 沒有對外路由時拉不到。**未驗證** |
| 複製到專案自己的 ECR（`source = "mirror"`） | 映像推進專案的 mirror repository；`iam-base` 的 execution role 拉取權限已涵蓋 mirror repository（讀 `containerimage/mirrored_images`），私網環境再加 `ecr.api`、`ecr.dkr` interface endpoint 與 S3 gateway endpoint |

沒有 NAT 的環境一定要走第二種。

### 把 collector 映像放進 mirror repository

下面四步都在已經跑過 `foundation` 的環境做。

**1. `containerimage` 的 tfvars 加 mirror**

```hcl
# infra/terraform/containerimage/envs/<env>.tfvars
mirrored_images = ["adot-collector"]
```

名稱必須是 `adot-collector`（`application` 照這個名稱找）。Repository 名稱是 `<project>-<env>-mirror-adot-collector`（例如 `alpha-dev-mirror-adot-collector`），設定跟服務的 repository 相同：tag 不可覆蓋（`IMMUTABLE`）、推上去就掃描、KMS 加密、同一組 lifecycle。

**2. 先 apply `containerimage`，再 apply `iam-base`**

順序不能反：`iam-base` 讀的是 `containerimage/mirrored_images` 與 `containerimage/ecr_mirror_adot_collector_arn`，`containerimage` 還沒發布時 `iam-base` 的 plan 會讀不到。`containerimage` 的 `terraform output mirror_repository_urls` 會印出 repository URL。`iam-base` 的 plan 應該只有 execution role 的 inline policy 一個變更：`PullImagesFromProjectRepositories` 的 Resource 多出 mirror 的 ARN。

**3. 把映像複製進 mirror repository**

由有網路的人或 CI 做，用上游版本號當 tag（repository 是 `IMMUTABLE`，同一個 tag 推第二次會被拒絕，所以不要用 `latest`）。版本號跟 `application` 的 `adot_collector.tag` 一致（下例 `v0.43.1`）：

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

**4. `application` 指向 mirror**

```hcl
adot_collector = { tag = "v0.43.1", source = "mirror" }
```

repository URL 不用寫：`application` 從 `containerimage/ecr_mirror_adot_collector_url` 讀，再接上 `tag`。

### 替代方案：ECR pull-through cache

ECR 的 pull-through cache 規則讓帳號自己的 ECR 在第一次被拉取時，自動從 ECR Public 抓一份進來，不需要人或 CI 複製映像，也不用管 tag。但目前這個 repo 沒有管 `aws_ecr_pull_through_cache_rule` 的 module，要用就得新增一個（還要處理 execution role 多出的 `ecr:CreateRepository`、`ecr:BatchImportUpstreamImage` 權限，以及第一次拉取時要連得到上游），第一版不做。需要時先用上面的 mirror 做法。

## 範本接的 sidecar 與 example 逐行對照

`application/tracing.tf` 的 `local.collector_sidecars` 每一個欄位，跟 `modules/ecs-service/examples/adot-sidecar/main.tf` 的 `sidecars = [{ ... }]` 完全相同，只有映像的 tag 與來源由 `adot_collector` 決定：

| 欄位 | example | 範本 |
|---|---|---|
| 名稱 | `name               = "adot-collector"` | 相同 |
| 映像 | `public.ecr.aws/aws-observability/aws-otel-collector:v0.43.1` | `adot_collector` 決定 tag 與來源（public 或 mirror） |
| essential | `essential          = false` | 相同 |
| CPU | `cpu                = 128` | 相同 |
| 記憶體 | `memory_reservation = 256` | 相同 |
| 設定 | `environment        = { AOT_CONFIG_CONTENT = local.collector_config }` | 內容來自 `file("adot-collector.yaml")` |
| port | `port_mappings      = [{ container_port = 4317 }]` | 相同 |
| health check | `health_check       = { command = ["CMD", "/healthcheck"] }` | 相同 |
| 等待條件 | `app_depends_on     = "START"` | 相同 |
| 主 container | `environment = { OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317" }` | 相同的值，併進既有的 `environment`，另加 `OTEL_SERVICE_NAME` |

### 為什麼 `essential = false`

collector 只負責送 trace，不在請求路徑上。`essential = true` 時 collector 一掛掉，ECS 會停掉整個 task 重開，等於追蹤元件的故障變成服務中斷。設成 `false`，collector 掛了只是少一段時間的 trace，主 container 照常服務。參考來源 project-c 的寫法是 `true`（`project-c-app/modules/app-service/ecs-standard.tf`），這裡刻意不同。

`app_depends_on = "START"` 讓主 container 等 collector 啟動後才啟動，減少開機時第一批 trace 送不出去的機會；用 `START` 而不是 `HEALTHY`，是不讓 collector 的健康狀態卡住服務啟動。

## collector 設定：`application/adot-collector.yaml`

設定檔內容：

```yaml
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
```

幾個注意：

- `/healthcheck` 是 ADOT 映像內建的檢查程式，它查的是 `health_check` extension，所以設定檔一定要開這個 extension，否則 health check 一直不健康（因為 `essential = false` 加 `START`，不影響服務，但 console 會顯示 unhealthy）。範本的設定已經開了。**未驗證**。
- `filter/health` 用的 attribute 名稱取決於 SDK 的 semantic convention 版本：新版是 `url.path`，舊版是 `http.target`，兩個都寫。health check 路徑不是 `/health` 時改這個檔。
- `memory_limiter` 的上限要小於 `memory_reservation`（256 MiB）。sidecar 的 CPU 與記憶體從 task 的 `cpu`／`memory` 裡分，task 預設 512／1024，掛了 collector 之後主 container 能用的就少了這一塊。
- 設定用 `environment`（`AOT_CONFIG_CONTENT`）帶，不學 project-c 存成 SSM parameter 再用 `secrets` 讀：設定不是機密，而且範本規定 `aws_ssm_parameter` 只能由 `ssm-publish` 建。設定太大放不進環境變數時，改成把設定烤進自己的 collector 映像。
- `awsproxy` extension 讓 SDK 能經 collector 向 X-Ray 拉 sampling rule（見〈抽樣〉）。

## `network`：X-Ray 的 interface endpoint

沒有 NAT，或希望 trace 不經網際網路時，在 `network` 的 tfvars 加上 `xray`；沒有 NAT 時 mirror 映像還需要 `ecr.api`、`ecr.dkr`：

```hcl
interface_endpoints = {
  services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms", "xray"]
}
```

範本的大流量範例（`network/envs/examples/high.tfvars`）已經包含 `xray`。endpoint 的 SG 只開 443 給 VPC CIDR，服務 SG 的 egress 443 本來就開著，不用改規則。`network` 會把已建的服務清單發布成 `network/interface_endpoints`，沒有時是 `[]`。

## 抽樣：`xray` module

抽樣規則決定送多少 trace，是控制 X-Ray 成本的主要旋鈕，跟追蹤開關無關。`application` 的三個變數預設都是 `{}`，什麼都不建；範例在 `application/envs/examples/`（`high.tfvars` 同時示範了 `adot_collector`）：

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
- 沒給的欄位是 `*`。`service_name` 要跟 `OTEL_SERVICE_NAME` 一致（`<project>-<env>-<service>`），規則才對得上。
- 建議起點：PoC 100%、一般正式每秒 1 筆加 5%、大流量每秒 1 筆加 1～5%。這些比例都**沒有實測依據**，上線後用實際流量與帳單調。

**remote sampling 的前提**：sampling rule 只對「向 X-Ray 拉規則」的 SDK 或 collector 生效。三件事都要成立：

1. 應用程式的 SDK 設成 X-Ray remote sampler（例如 ADOT Java agent 的 `OTEL_TRACES_SAMPLER=xray`），並指到 collector 的 `awsproxy`（預設 `localhost:2000`）。
2. collector 開了 `awsproxy` extension（範本的設定有）。
3. task role 有 `xray:GetSamplingRules`、`xray:GetSamplingTargets`（`iam-app` 的 `tracing` policy 有）。

應用程式如果用 SDK 端的固定比例（`OTEL_TRACES_SAMPLER=traceidratio`，project-a 的做法），sampling rule 不會生效，抽樣只看 SDK 設定。

## log 告警：`log-metric-alarm`

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

改完 `iam-app`、`application`、`network` 後，在專案 repo 裡離線跑三個 stack 的測試（見 [`project-infra-standard.md`](./project-infra-standard.md)〈驗證〉）。測試鎖住的是：被追蹤的服務恰好有四個 X-Ray 動作、沒被追蹤的服務一個都沒有、`application` 的 sidecar 只出現在被追蹤的服務、沒有追蹤時 task definition 不變、沒有 NAT 的安全網。mock 驗不到的是 collector 真的送得出 trace、remote sampling 真的生效、IAM 真的夠、沒有 NAT 時映像真的拉得到，這些要部署到沙箱帳號，用一次真實請求確認 X-Ray console 有 trace、health check 沒有進來。
