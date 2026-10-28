# 專案 infra 範本：參考資料

這份是 [README.md](./README.md) 的參考資料，收 SSM 合約、單一決定點、規格調整、客戶自管資源與第一次部署的 runbook。設計理由與每個 module 的介面見 [`docs/design/v1/design-docs.md`](../../../docs/design/v1/design-docs.md) 第 5 章。

## stack 的檔案

每個 stack 都有同一組檔案，全部進版控：

| 檔案 | 用途 |
|---|---|
| `versions.tf`、`providers.tf` | Terraform 與 provider 版本、空的 `backend "s3" {}`、`allowed_account_ids`、`default_tags` |
| `common.tf` | `project`、`env`、`aws_region`、`expected_account_id`、帳號對照表。9 個 stack 必須一字不差，`scripts/validate.sh` 會比對 |
| `variables.tf` | 這個 stack 自己的變數，不放其他 stack 的 ARN 或 id |
| `ssm-inputs.tf`、`ssm-outputs.tf` | 讀上游值（`ssm-read`）、發布給下游的值（`ssm-publish`） |
| `envs/<env>.tfvars`、`envs/<env>.tfbackend` | 非機密設定與 state 位置 |
| `tests/` | `terraform test`，全部用 mock provider，不需要 AWS 憑證 |
| `.terraform.lock.hcl` | provider lock 檔 |

`network`、`data`、`agent`、`loadbalancer`、`application` 另有 `envs/examples/{poc,standard,high}.tfvars`，是依流量調整規格的範例，本身不 apply，複製成 `envs/<env>.tfvars` 再改。`scripts/validate.sh` 會拿每個範例各跑一次測試。

## apply 順序的讀取來源

下游只讀上游發布的 key。apply 照 README〈apply 順序〉，destroy 反過來。順序寫在 `terraform/stacks.sh` 的 `ORDER`（單行），`stacks.sh` 與〈SSM 合約〉的檢查都讀它；改順序就改那一行，並同步 README 與下表。每個 stack 發布哪些 key 見〈SSM 合約〉。

| 順序 | stack | 讀（來源 stack） |
|---|---|---|
| 1 | `foundation` | 無 |
| 2 | `containerimage` | foundation |
| 3 | `network` | foundation、containerimage |
| 4 | `iam-base` | foundation、containerimage（含 `mirrored_images`、`agent_runtimes` 與各 mirror、各 Runtime 的 ARN） |
| 5 | `data` | foundation、network、iam-base |
| 6 | `agent` | foundation、containerimage、network、iam-base、data |
| 7 | `iam-app` | foundation、containerimage、network、iam-base、data、agent |
| 8 | `loadbalancer` | foundation、network |
| 9 | `application` | 前面的 stack（`iam-app/tracing`、`iam-app/agent_access` 一律讀；有服務被追蹤時才另讀 `network/nat`、`network/interface_endpoints`，映像用 mirror 時再讀 `containerimage/mirrored_images` 與 `ecr_mirror_adot_collector_url`；`agent_access` 有列服務時才讀 `agent/*` 與 `network/nat`、`network/interface_endpoints`） |

- `agent` 什麼都沒開也一定要在 `iam-app` 之前 apply，因為 `iam-app` 讀它發布的 key。Runtime、Memory、guardrail 的權限在 `iam-app` 才附加，指向 `agent` 建好的確切 ARN（跟 RDS Proxy 一樣是兩段式）。
- `agent` 什麼都沒開時也發布 key，值是空的 JSON；`application` 不發布任何 key。
- 第一次部署有 Knowledge Base 時，`agent` 要分兩段 apply，見〈Knowledge Base 第一次部署：兩段式步驟〉。
- 已部署過、還沒有 LLM 相關 key 的環境，升級時也從 `containerimage` 開始逐一 apply，不能跳過 `agent`：`iam-base`、`iam-app`、`application` 一律讀 `containerimage/agent_runtimes`、`network/agent_data_access`、`agent/*`，上游還沒發布時 plan 會讀不到 SSM 參數而失敗。什麼都沒開時，這一輪只多出這些 SSM 參數。
- destroy 前要先做三件事，不然會失敗：ALB 與資料庫的 `deletion_protection` 改成 `false` 並 apply；清空 ECR repository（`force_delete = false`）；清空兩個 log bucket（`force_destroy = false`）。

## 日常操作與環境切換

環境由四個彼此獨立的選擇決定：

| 選擇 | 怎麼指定 | 忘了換的後果 |
|---|---|---|
| AWS 身分 | `aws-vault exec <profile> --` | 打到錯的帳號（會被 `allowed_account_ids` 擋下） |
| backend | `-backend-config=envs/<env>.tfbackend` | 讀寫到別的環境的 state |
| 變數 | `-var-file=envs/<env>.tfvars` | 用錯的設定規劃 |
| 工作目錄 | `TF_DATA_DIR=.terraform-<env>` | 沿用上一個環境的 backend 設定與 provider 快取 |

`terraform/stacks.sh` 依 env 一起選好後三個；手打 `terraform` 時四個都要自己對齊。指令見 README〈部署〉。

- 換環境一律 `init -reconfigure`，不要用 `-migrate-state`（它會把 state 搬過去）。
- 環境名稱只有一層：`env` 同時用在檔名、資源名稱、SSM 路徑與 state key。
- `expected_account_id` 沒有預設值，並且要在 `common.tf` 的 `accounts_by_env` 登記過；漏帶 tfvars 或帳號不符，plan 之前就停。
- state key 固定是 `<project>-<env>/<stack>/terraform.tfstate`，`scripts/validate.sh` 會檢查每份 `.tfbackend`。

## 單一決定點

兩個以上的 stack 都要知道的開關，只由上游一個 stack 決定並發布；下游讀進來後用 precondition 檢查自己的設定跟它一致，不一致時 plan 失敗。這樣就不會 apply 出「security group 以為有 HTTPS、ALB 實際只開 HTTP」這類組合。

| 決定點 | 決定者 | 誰讀 | 下游怎麼檢查或使用 |
|---|---|---|---|
| `containerimage/services` | `containerimage` 的 `services` | `network`、`iam-base`、`iam-app`、`application` | `network` 與 `application` 的服務設定 key 必須相同；`iam-app` 的 `ecs_exec_services` 必須是它的子集 |
| `containerimage/mirrored_images` | `containerimage` 的 `mirrored_images` | `iam-base` | execution role 的 ECR 拉取權限涵蓋這些 mirror repository，沒有 mirror 時不變 |
| `network/alb_https` | `network` 的 `alb_ingress.https` | `loadbalancer` | 有沒有給 `certificate_arn`，必須跟 `enabled` 一致 |
| `network/db_proxy` | `network` 的 `data_stores.db.proxy` | `data` | `enabled` 為 true 才把 `proxy` 傳給 `rds` |
| `network/data_access` | `network` 各服務的 `data_access` | `iam-app`、`application` | 名單上的服務，task role 才能讀資料庫 secret，也才拿得到 `DB_*` 環境變數 |
| `iam-app/ecs_exec_<service>` | `iam-app` 的 `ecs_exec_services` | `application` | 直接當 `enable_execute_command`，`application` 自己沒有這個變數 |
| `iam-app/tracing` | `iam-app` 的 `tracing` | `application` | 名單上的服務，task role 才有 X-Ray 的四個動作，也才會掛 ADOT collector sidecar 與 OTEL 環境變數；`application` 自己沒有追蹤開關，只有 collector 映像的 `adot_collector`。名單必須是 `containerimage/services` 的子集 |
| `containerimage/agent_runtimes` | `containerimage` 的 `agent_runtimes` | `network`、`iam-base`、`agent`、`iam-app` | `network` 與 `agent` 的 Runtime 設定 key 必須相同 |
| `network/agent_data_access` | `network` 各 Runtime 的 `data_access` | `agent`、`iam-app` | 名單上的 Runtime 才有連資料庫的 security group 規則、`DB_*` 環境變數與讀資料庫 secret 的權限；`PUBLIC` 的 Runtime 不得在名單上 |
| `iam-base/agent_service_roles` | `iam-base` 的 `agent_service_roles` | `agent` | 有 Knowledge Base 時要含 `knowledge_base`，有 Gateway 時要含 `gateway` |
| `data/database` 的 `data_api` | `data` 的 `db.data_api` | `agent` | 有 Knowledge Base 時必須是 Aurora 而且 `data_api = true` |
| `agent/models` | `agent` 的 `models` | `iam-app`、`application` | `invoke_arns` 是模型 IAM Resource 的唯一來源，`iam-app` 不自己拼 ARN |
| `agent/bedrock_invoke` | `agent` 的 `bedrock_invoke` | `iam-app`、`application` | 啟用時模型權限換成 `sts:AssumeRole`，並注入 `BEDROCK_INVOKE_*` |
| `agent/agent_runtime_<rt>` 的 `tracing` | `agent` 的 `agent_runtimes[*].tracing` | `iam-app` | 開了的 Runtime，execution role 才有 X-Ray 動作（含 `xray:PutSpans`） |
| `agent/agent_runtime_<rt>` 的 `workload_identity` | `agent` 的 `agent_runtimes[*].workload_identity`（預設 `false`） | `iam-app` | 開了的 Runtime，execution role 才有 `bedrock-agentcore:GetWorkloadAccessToken*`；只有 Runtime 經 AgentCore Identity 呼叫外部服務時才開 |
| `agent/knowledge_bases` 的 `ready` | `agent` 的 `knowledge_bases[*].database_user_ready` | `iam-app`、`application` | `false` 時只有 secret 與語料 bucket，`id`、`arn` 是 `null`；KB role 的權限照樣附加。`agent` 擋掉 Runtime 用還沒 ready 的 KB；`iam-app` 的 `agent_access` 在 ready 之前不要列它 |
| `iam-app/agent_access` | `iam-app` 的 `agent_access` | `application` | 有列的服務 task role 才有 `bedrock`／`bedrock-agentcore` 動作，也才注入 Runtime ARN、模型 id、guardrail id、KB id |

## SSM 合約

路徑是 `/<project>/<env>/<stack>/<key>`，整個專案只有一棵樹。純量用 `String`，清單用 `StringList`（逗號串接），可有可無或多欄位的值用 `String` 裝 JSON。SSM 只放非機密值，secret 只放 ARN。服務名稱裡的 `-` 在 key 裡換成 `_`（服務 `order-api` 的 security group key 是 `sg_order_api_id`）。

| stack | key | 型別 | 內容 |
|---|---|---|---|
| `foundation` | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn` | String | ARN |
| `foundation` | `alb_log_bucket_arn` | String | ALB access log bucket 的 ARN（`loadbalancer` 用 `log-delivery` 接 vended delivery） |
| `containerimage` | `services` | StringList | 服務名稱 |
| `containerimage` | `ecr_<service>_url`、`ecr_<service>_arn` | String | repository URL 與 ARN |
| `containerimage` | `mirrored_images` | String（JSON 陣列） | 放外部映像副本的 repository 名稱，沒有時是 `[]`。SSM 不收空的 StringList，所以用 JSON；`iam-base` 靠它知道要讀哪些 `ecr_mirror_*` |
| `containerimage` | `ecr_mirror_<name>_url`、`ecr_mirror_<name>_arn` | String | 外部映像副本 repository 的 URL 與 ARN；沒有設 `mirrored_images` 就不存在。`<name>` 的 `-` 換成 `_` |
| `network` | `vpc_id`、`vpc_cidr` | String | `vpc_cidr` 是主要 CIDR |
| `network` | `azs` | StringList | AZ 順序；所有 `subnet_*` 清單都照這個順序 |
| `network` | `subnet_ids_<tier>`、`subnet_cidrs_<tier>` | StringList | tier 至少有 `public`、`app`、`data`，名稱不可改 |
| `network` | `sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id` | String | `sg_db_proxy_id` 一律發布，沒開 Proxy 時它沒有任何規則 |
| `network` | `sg_vpce_id` | String | 有 interface endpoint 時才發布，下游目前不讀 |
| `network` | `interface_endpoints` | String（JSON 陣列） | 已建的 interface endpoint 服務名稱（已排序），沒有時 `[]`。`application` 在有服務被追蹤、而且 `nat.mode` 是 `none` 時，檢查它含 `xray`、`ecr.api`、`ecr.dkr` |
| `network` | `nat` | String（JSON） | `{"mode":"per_az","ids":["nat-..."]}`；`none` 時 `ids` 為 `[]`；登記既有 VPC（模式 A）時是 `{"mode":"external","ids":[]}` |
| `network` | `alb_https`、`db_proxy` | String（JSON） | `{"enabled":true}` |
| `network` | `data_access` | String（JSON） | `{"db":["api","worker"]}` |
| `iam-base` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` | String | role ARN |
| `data` | `database` | String（JSON） | 見下 |
| `iam-app` | `role_<service>_task_arn` | String | task role ARN |
| `iam-app` | `ecs_exec_<service>` | String（JSON） | `{"enabled":false}` |
| `iam-app` | `tracing` | String（JSON 陣列） | 要追蹤的服務名稱（已排序），沒有時 `[]`。SSM 不收空的 StringList，所以用 JSON |
| `loadbalancer` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` | String | 有憑證時 `listener_arn` 是 HTTPS listener，否則是 HTTP；`listener_protocol` 是 `HTTPS` 或 `HTTP` |
| `containerimage` | `agent_runtimes` | String（JSON 陣列） | AgentCore Runtime 名稱（已排序），沒有時 `[]` |
| `containerimage` | `ecr_agent_<rt>_url`、`ecr_agent_<rt>_arn` | String | Runtime 的 repository；只有設了 `agent_runtimes` 才存在 |
| `network` | `sg_agent_<rt>_id` | String | Runtime 的 security group |
| `network` | `agent_data_access` | String（JSON） | `{"db":["assistant"]}`，沒有時 `{}` |
| `iam-base` | `role_agent_<rt>_execution_arn` | String | Runtime execution role |
| `iam-base` | `role_bedrock_kb_arn`、`role_agentcore_gateway_arn` | String | 只有 `agent_service_roles` 含 `knowledge_base`／`gateway` 才存在 |
| `iam-base` | `agent_service_roles` | String（JSON 陣列） | `["gateway","knowledge_base"]` 的子集合（已排序），沒有時 `[]` |
| `agent` | `agent_runtime_<rt>` | String（JSON） | Runtime 的 `arn`、`id`、`name`、`execution_role_arn` 與它能用的 `models`、`memories`、`guardrails`、`knowledge_bases`（key 清單）、`gateway`、`tracing`、`workload_identity` |
| `agent` | `models` | String（JSON） | `{"<key>":{"model_id":…,"invoke_arns":[…]}}`，沒有時 `{}` |
| `agent` | `guardrails` | String（JSON） | `{"<key>":{"id":…,"arn":…,"version":"DRAFT","profile_id":…}}`，沒有時 `{}`；`CLASSIC` 的 `profile_id` 是 `null` |
| `agent` | `agent_memories` | String（JSON） | `{"<key>":{"id":…,"arn":…}}`，沒有時 `{}` |
| `agent` | `knowledge_bases` | String（JSON） | `{"<key>":{"ready":…,"id":…,"arn":…,"embedding_model":…,"bucket_name":…,"bucket_arn":…,"inclusion_prefixes":{…},"data_source_ids":{…},"credentials_secret_arn":…}}`，沒有時 `{}`；`tfvars` 裡每個 KB 都有一筆，`database_user_ready = false` 時 `ready` 是 `false`、`id` 與 `arn` 是 `null`、`data_source_ids` 是 `{}`；`data_source_ids` 是 data source key → id，跑 `StartIngestionJob` 用；`credentials_secret_arn` 是 `agent` 建的 `<project>-<env>-kb-<key>-db` 的 ARN，不是 secret 的值 |
| `agent` | `agentcore_gateway`、`bedrock_invoke` | String（JSON） | `{"enabled":false}` 或 `{"enabled":true,...}`；Gateway 的 `lambda_arns` 與 `tool_schema_arns`（Lambda target 工具定義的 S3 物件 ARN）給 `iam-app` 附加權限 |
| `iam-app` | `agent_access` | String（JSON） | 服務 → `{runtimes, models, guardrails, knowledge_bases}`，沒有時 `{}` |

`data/database` 有資料庫時：

```json
{
  "enabled": true,
  "deployment": "aurora_serverless",
  "port": 5432,
  "name": "app",
  "secret_arn": "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-...",
  "app_endpoint": "...",
  "app_reader_endpoint": "...",
  "writer_endpoint": "...",
  "reader_endpoint": "...",
  "proxy_endpoint": null,
  "has_reader": false,
  "cluster_arn": "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db",
  "data_api": false
}
```

沒有資料庫時是 `{"enabled":false}`。應用程式只讀 `app_endpoint`、`app_reader_endpoint`、`port`、`name`、`secret_arn` 這五個，有沒有開 Proxy、資料庫是哪種型態由 `rds` module 決定。其餘欄位給維運與除錯用（例如直接連 writer 跑 migration）；`cluster_arn`（`rds` 型態是 `null`）與 `data_api` 給 `agent` 的 Knowledge Base 與 `iam-app` 的 KB role 用。新增欄位是相容的；刪除或改名欄位要當成破壞性變更，並同時改所有讀取端。

### 合約檢查

`terraform/check-ssm-contract.sh` 只讀 HCL 與 tfvars，不跑 terraform、不連 AWS。本 repo 的 `scripts/validate.sh` 每次都會跑它，複製出去之後也能直接執行。它檢查兩件事：

1. 每個 stack 讀的 `"<stack>/<key>"`，都要由 `ORDER` 裡更早的 stack 發布，而且型別一致（`String` 或 `StringList`）。
2. 同一個 env，各 stack `envs/<env>.tfvars` 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名（沒寫的略過）。

它只看得懂下面的寫法，看不懂的不算讀取也不算發布，所以新增 stack 或改 key 時照這樣寫，樣式要寫成字串字面值：

- 發布：`ssm-outputs.tf` 的 `published_strings`／`published_lists`，可以是 map 或 `merge(...)`。map 的 key 是發布的 key；`{ for ... : "sg_${k}_id" => ... }` 這種參數發布一個樣式。
- 讀取：stack 裡所有 `.tf` 的字串 `"<stack>/<key>"`，第一段要是 `ORDER` 裡的 stack。寫在名稱以 `lists` 結尾的 map 或 `merge(...)` 裡（`ssm_input_lists`、`lists = ...`）算 `StringList`，其他算 `String`。
- 依 tfvars 算出來的 key 用樣式比對：每個 `${...}` 當成萬用字元，讀的樣式要被發布的樣式涵蓋（例如讀 `iam-base/role_agent_${k}_execution_arn` 由 `role_${k}_arn` 涵蓋）。

**限制**：它不知道 tfvars 裡實際有哪些服務，所以抓不到「讀了某個服務的 key，但上游沒有這個服務」；這種錯會在 `plan` 時由 `ssm-read` 讀不到參數而失敗。

## 開啟 LLM 與 AgentCore

`agent` stack 預設沒有任何 Runtime、模型、guardrail、Memory、Gateway、Knowledge Base，只發布空的 SSM key。怎麼開 Runtime、guardrail 為什麼要用 STANDARD tier、Knowledge Base 的資料庫帳號與 migration SQL，見 [`docs/guides/llm-agentcore.md`](../../../docs/guides/llm-agentcore.md)。

## 開啟 X-Ray 追蹤

預設不追蹤：`iam-app` 的 `tracing` 是空集合，`application` 的 task definition 沒有 sidecar、沒有 OTEL 環境變數，task role 沒有任何 `xray:` 動作。照 apply 順序分三步開：

1. **`iam-app`：決定哪些服務要追蹤。** `envs/<env>.tfvars` 寫 `tracing = ["api"]`（必須是 `containerimage/services` 裡的名稱，寫錯 plan 會停）。被列的服務，task role 拿到 `xray:PutTraceSegments`、`xray:PutTelemetryRecords`、`xray:GetSamplingRules`、`xray:GetSamplingTargets`（X-Ray 只支援 `Resource = "*"`），沒列的一個都沒有。apply 後發布 `iam-app/tracing`。
2. **`application`：指定 collector 映像。** `envs/<env>.tfvars` 加 `adot_collector = { tag = "v0.43.1", source = "public" }`。`tag` 必須明確，不接受 `latest`；有服務被追蹤時必填，沒有時可以不寫。apply 後，被追蹤的服務多一個 `adot-collector` sidecar（`essential = false`，掛了不會讓 task 重啟），主 container 多 `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` 與 `OTEL_SERVICE_NAME=<project>-<env>-<service>`，應用程式的 OTel SDK 讀這兩個變數即可。collector 設定在 `application/adot-collector.yaml`。
3. **沒有 NAT 時改用 mirror 加 endpoint。** `network/nat` 的 `mode` 是 `none` 時，task 拉不到 ECR Public，也送不出 trace，`application` 要求同時滿足下面兩項，不符合時 plan 會停並列出缺哪一項：
   - `adot_collector.source = "mirror"`，而且 `containerimage` 的 `mirrored_images` 含 `adot-collector`。先 apply `containerimage` 與 `iam-base`，把映像複製進 `<project>-<env>-mirror-adot-collector`（用同一個 `tag`），步驟見 [`docs/guides/observability.md`](../../../docs/guides/observability.md)。
   - `network` 的 `interface_endpoints.services` 含 `xray`、`ecr.api`、`ecr.dkr`，apply `network` 之後才會發布到 `interface_endpoints`。

另外：

- 客戶自管 VPC（模式 A，`nat.mode` 是 `external`）時 NAT 由客戶負責，範本不檢查。客戶 VPC 沒有 NAT 時，要自己準備 mirror 映像、三個 interface endpoint，並且 **VPC 要有 S3 gateway endpoint**（ECR 映像的 layer 存在 S3，範本不管客戶 VPC 的 gateway endpoint）。自建 VPC 的 `modules/vpc` 預設就有 S3 gateway endpoint。
- 服務的 security group 本來就開 443 對外，endpoint 的 security group 也對 VPC CIDR 開 443，追蹤不用新增 security group 規則。
- 抽樣規則（`application` 的 `xray_sampling_rules`、`xray_groups`）跟追蹤開關無關；規則的 `service_name` 要寫 `<project>-<env>-<service>`，跟 `OTEL_SERVICE_NAME` 一致。sampling rule 只對向 X-Ray 拉規則的 SDK 或 collector 生效，條件見 observability 指南。
- `application/envs/examples/high.tfvars` 有 `adot_collector` 與抽樣規則的示範。
- 整套接線都沒有在真實帳號驗證過，見〈驗證〉。

## 依流量調整規格

規格放在範例 tfvars，不放進 module。

| | PoC | 一般正式 | 大流量 |
|---|---|---|---|
| VPC CIDR | `/20`：public `/26`、app `/24`、data `/27` | `/19`：public `/24`、app `/22`、data `/26` | `/16`：public `/24`、app `/20`、data `/26` |
| AZ | 2 | 2 | 3 |
| NAT | `single`（沒有對外流量可用 `none`） | `per_az` | `per_az` |
| interface endpoint | 無（只有 S3 gateway endpoint） | `ecr.api`、`ecr.dkr`、`logs`、`secretsmanager`、`kms` | 再加 `ssm`、`ssmmessages`、`xray`；需要時加 `bedrock-runtime` |
| flow log | 關 | 開（S3） | 開（S3） |
| RDS | `rds` 單一 AZ；或 `aurora_serverless` 0.5 到 4 ACU | `aurora_serverless` 2 到 16 ACU 加 1 個 reader | `aurora` `db.r7g.xlarge`、2 個 reader |
| 備份與刪除保護 | 1 天、關 | 14 天、開 | 14 天、開 |
| ALB | 可只開 HTTP（來源要收窄）、不開 access log | HTTPS、access log、可掛 WAF | 同左，長連線服務 `idle_timeout` 設 300 |
| RDS Proxy | 不開 | 開 | 開 |
| X-Ray 抽樣 | 100% | 5%，health check 設 0 | 1%，health check 設 0 |
| log 告警 | 不開 | 開 | 開 |

- 大流量的 RDS 規格與各抽樣比例都沒有實測依據，只是起點，第一個用到的專案要自己量。`rds` 型態（一般 RDS）也沒有任何專案實際用過。
- 沒有憑證的 ALB 不准對 `0.0.0.0/0` 開 80：`alb_ingress` 在 `https = false` 時會擋掉 `0.0.0.0/0` 與 `::/0`，只能開給 CloudFront 的 managed prefix list 或指定的 CIDR。

## 客戶自管資源

客戶自己管一部分資源時，我們只部署其餘部分。

| | 模式 A：客戶管 VPC，我們管 security group | 模式 B：整個 stack 由客戶管 |
|---|---|---|
| 適用 | 客戶有既有 VPC 規範，但讓我們開 security group | 客戶的網路團隊連 security group 都要自己管 |
| 做法 | `network` 的 tfvars 不給 `vpc`，改給 `existing = { vpc_id, subnet_ids }`（`subnet_ids` 是 tier 對 subnet 清單，依 AZ 順序，三個 tier 的 subnet 數量要相同） | 該環境不放這個 stack 的 `envs/<env>.tfbackend` 與 `envs/<env>.tfvars` |
| 發布 key | `network` 照常發布同一組 key | 客戶照〈SSM 合約〉發布，包括 JSON 欄位 |
| 下游 | 不變 | 不變 |

模式 A：

- 用 data source 確認 VPC 與 subnet 存在，並檢查 VPC 有開 `enable_dns_support` 與 `enable_dns_hostnames`；沒開時 `private_dns_enabled` 的 interface endpoint 無法解析，plan 會停。
- interface endpoint 與 security group 仍由我們建；endpoint 的 `allowed_cidrs` 是客戶 VPC 全部已關聯的 CIDR（含 secondary），放在 `subnet_tier` 指定的 tier（預設 `app`，不可是 `public`）。
- 路由、internet gateway、NAT、gateway endpoint、default security group 一律不碰，`nat` 發布 `{"mode":"external","ids":[]}`。
- `azs` 取自 `app` tier subnet 的 AZ；三個 tier 的 subnet 要用同一個 AZ 順序，程式不檢查。

模式 B 與其他交接事項：

- 該環境沒有 `envs/<env>.*` 檔案就無法 `init`，所以不會誤跑。
- 建議客戶在給我們的部署 role 上，對客戶擁有的路徑明確 Deny `ssm:PutParameter` 與 `ssm:DeleteParameter`。
- 客戶的部署 role 不能改 IAM 時，`iam-base` 與 `iam-app` 一定要交給客戶（模式 B）。
- 跨帳號部署用 `providers.tf` 的 `deploy_role_arn`，空字串代表用呼叫者自己的身分。

## RDS Proxy 第一次部署：兩段式步驟（未驗證）

Proxy 建立時，它的 role 還沒有讀 secret 的權限（`iam-app` 在資料庫建好之後才附加）。AWS 這時是讓建立失敗，還是建立成功、等 policy 附加後才連得上，**沒有實測過**。兩種結果的做法：

| 實測結果 | 做法 |
|---|---|
| 建立成功，`iam-app` apply 之後才連得上 | 照正常順序 apply。`data` apply 完到 `iam-app` apply 完之間 Proxy 連不上，這時應用程式還沒部署，沒有影響 |
| 建立失敗 | 第一次部署先把 `network` 的 `data_stores.db.proxy` 設成 `false`，照順序跑到 `iam-app`；再改成 `true`，依序 apply `network`、`data`。`iam-app` 的 policy 在第一輪就已附加到 Proxy role，第二輪不用再跑它 |

第二輪 apply 之後，`database` JSON 的 `app_endpoint` 會換成 Proxy endpoint。應用程式已經部署的話，要重新 apply `application`，`DB_HOST` 才會跟著換。

預設是 dev 不開 Proxy、prod 開。有 AWS 沙箱帳號之後先驗證這一項，把結果寫回這一節。

## Knowledge Base 第一次部署：兩段式步驟

`agent` 替每個 KB 建一個 Secrets Manager secret `<project>-<env>-kb-<key>-db`，用 `foundation` 的專案 KMS key 加密。它跟 `foundation` 的 `app` secret 一樣只建容器、不含值，帳密不進 tfvars、SSM 與 state，值由專案寫入。Bedrock 建 KB 時會不會檢查資料庫帳號**沒有實測過**，所以照「會檢查」排成兩段：`knowledge_bases[*].database_user_ready` 預設 `false`，只建 secret 與語料 bucket，不建 KB。

| 步驟 | 誰 | 做什麼 |
|---|---|---|
| 1 | 範本 | `data` 設 `db.data_api = true`、`iam-base` 的 `agent_service_roles` 含 `knowledge_base`，照順序 apply 到 `data` |
| 2 | 範本 | `agent` 的 `knowledge_bases` 加上這個 KB，`database_user_ready` 不寫（`false`），`agent_runtimes` 先不列它；apply `agent`，再 apply `iam-app`（KB role 拿到讀這個 secret、語料 bucket、Data API 的權限） |
| 3 | 專案 | 寫入 secret 的值：`aws secretsmanager put-secret-value --secret-id <project>-<env>-kb-<key>-db --secret-string file://<檔案>`，內容是 `{"username":"bedrock_kb_user","password":"<隨機產生>"}`。密碼用 `aws secretsmanager get-random-password` 產生，經檔案傳入、用完刪掉，不進 shell history |
| 4 | 專案 | 用 master 帳號跑 migration：建 `bedrock_kb_user`、schema、表與授權（design §4.30），再執行 `ALTER ROLE bedrock_kb_user PASSWORD '<secret 裡的值>'`。密碼從 secret 讀出來直接送進 psql，不寫進 migration 檔 |
| 5 | 範本 | `database_user_ready = true`，要用它的 Runtime 在 `agent_runtimes[*].knowledge_bases` 列上；依序 apply `agent`（建 KB 與 data source）、`iam-app`（Runtime 與服務的 `bedrock:Retrieve*` 指向 KB 的 ARN）、`application` |
| 6 | 專案 | 上傳文件到語料 bucket，呼叫 `StartIngestionJob` |

- 換密碼時 `put-secret-value` 與 `ALTER ROLE` 要一起做，secret 沒有自動輪替。
- `agent` destroy 後 secret 會留在 30 天的復原期，期間重建同名 secret 會撞名。

## 升級：secret 改由 `secrets-manager-secret` 建立

這一版起，`foundation` 的 `app` secret 與 `agent` 每個 KB 的資料庫帳號 secret 都改由 `secrets-manager-secret` module 建立。名稱、說明、KMS key 都沒變，復原期明確寫成原本的 AWS 預設 30 天。module 會在 secret 加上 `Name` tag，所以 plan 會看到一筆 tag 的 in-place 更新。

- `foundation`：`moved` block 會把 `aws_secretsmanager_secret.app` 搬到 `module.app_secret`，直接 apply 即可。plan 若出現 destroy 或 create secret，先停下來確認。
- `agent`：KB 的 key 由 tfvars 決定，範本寫不出逐一對應的 `moved`，Terraform 也不接受把整組 `for_each` resource 搬進 `for_each` module。已經建過 KB secret 的環境，在 apply 新版 `agent` 之前，對 `knowledge_bases` 的每個 key 跑一次：

  ```sh
  terraform state mv 'aws_secretsmanager_secret.kb_db["<kb>"]' 'module.kb_db_secret["<kb>"].aws_secretsmanager_secret.this'
  ```

  跑完再 plan，secret 只能有 tag 的 in-place 更新，不能有 destroy 或 create。沒搬就 apply 的話，Terraform 會刪掉舊 secret（進入 30 天復原期）再建同名 secret，因為撞名而失敗。

## 驗證

本 repo 的 `scripts/validate.sh` 對每個 stack 跑 `terraform fmt`、靜態規則（IAM 只在兩個 IAM module、SSM 讀寫只在 `ssm-read` 與 `ssm-publish`、`common.tf` 一致、state key 格式、範本 stack 不宣告原生 resource）、`init -backend=false`、`validate`、`test`、`tflint`，並對 `envs/dev.tfvars`、`envs/prod.tfvars`、每個範例檔各跑一次測試。全程不需要 AWS 憑證，也不執行 `plan` 或 `apply`。

mock 驗不到的事（IAM 實際權限、AWS API 的參數檢查、資源配額、apply 的時序、private DNS 與 NAT 的實際流量）要在真實帳號補驗，清單見設計文件第 7.2、7.3 節。已知還沒實際驗證過的設定：

- `kms-key` 給 CloudWatch Logs、CloudWatch、SNS 的 key policy 條件。
- Enhanced Monitoring 的 inline policy 是否足夠（`RDSOSMetrics` 有沒有資料）。
- X-Ray sampling rule 是否被 SDK 或 collector 的 remote sampling 採用。
- 範本接好的 ADOT collector（`application/adot-collector.yaml`）在真實 task 裡是否 healthy、X-Ray console 是否看得到 trace；`v0.43.1` 這個 tag 在 ECR Public 上是否存在。
- 沒有 NAT 時，mirror 映像加 `ecr.api`、`ecr.dkr`、`xray` endpoint 與 S3 gateway endpoint 是否真的拉得到映像、送得出 trace。
- 範本的 prefix list ID（`pl-58a04531`，CloudFront origin-facing，ap-northeast-1）請以你的 region 實際查到的值為準。

## 已知風險

- 應用程式直接用資料庫的 master secret，這是第一版的已知風險：master 帳號權限最大，應用程式被打穿時影響整個資料庫。緩解方式：只有 `data_access` 名單上的服務能讀，而且 secret 由 task role 自己讀，不經過共用的 execution role。之後要補應用程式專用帳號，或改用 Proxy 的 IAM 認證。
- 範本沒有建 WAF Web ACL，只提供 `web_acl_arn` 讓 ALB 關聯既有的 Web ACL。
- 範本沒有 Redis、部署 workflow、state bucket 本身。
