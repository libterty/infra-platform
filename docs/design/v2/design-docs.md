# infra-platform v2 設計文件：第二份範本 example2

> 狀態：使用者已拍板（§3），可以進入實作；實作步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：把一個已上線專案（下稱 project-b）的 Terraform 改寫成本 repo 的第二份範本 `templates/example2`，缺的 module 先補進 registry。
> 之後每整合一個專案都照 [`integration-playbook.md`](./integration-playbook.md) 做；這份只寫 example2 的設計。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「v1 §x.y」指 [`../v1/design-docs.md`](../v1/design-docs.md) 的章節。

## 1. 結論

project-b 拆成 11 個 Terraform stack（ALB＋WAF、ECS、Aurora＋RDS Proxy、ElastiCache、AgentCore、Lambda、bastion），幾乎都直接寫原生 resource，很少用 module。

這次分兩個 PR 做：

- **PR-A（module）**：新增 6 個 module，各發 `0.1.0`：`metric-alarm`、`vpc-peering`、`ec2-bastion`、`lambda-function`、`elasticache-redis`、`waf-web-acl`。另外擴充 6 個既有 module，各發 `0.2.0`：`iam-role`、`s3-bucket`、`rds`、`alb`、`ecs-service`、`log-metric-alarm`。合併後手動打 12 個 tag、補 GitHub Release、到 HCP 登記 6 個新 module。registry 從 26 個 module 變 32 個。
- **PR-B（範本）**：`templates/example2/infra/terraform/` 保留 project-b 的 11 個 stack 拆法，每個 resource 都改成呼叫 registry module；SSM 一律走 `ssm-publish`／`ssm-read`。`scripts/validate.sh` 與 CI 改成支援多份範本。

擴充的 module 預設值維持原本行為，既有消費端換版後 plan 零差異。project-infra 寫的是 `~> 0.1.0`（等於 `< 0.2.0`），不會自動吃到 0.2.0。

全部只做離線驗證：`fmt`、`tflint`、`init -backend=false`、`validate`、`terraform test` 搭配 `mock_provider`。**不做 `plan`／`apply`、不做帶 backend 的 `init`，也不碰任何 AWS 帳號**。

不做：

- 真實環境的部署驗證。
- dev、sit 以外的環境（D7）。
- 修改 project-b 本身。
- 改 project-infra 範本。它只會因為 `validate.sh` 改成支援多範本而受影響，驗收時要確認它的結果跟改之前相同。

## 2. 核對 project-b 時發現、會影響設計的事

1. **兩棵 SSM 樹**。前段 stack 發布到樹 A（`/<project>/<env>/<stack>/<key>`）；後段 stack（loadbalancer、agent、application、operation）只讀樹 B（一個共用前綴底下的扁平 key）。樹 B 可以由外部發布，也可以由 `bridge` stack 把樹 A 轉寫過去。
2. **本 repo 的靜態規則會擋掉直接寫原生 resource 的做法**：S3 規定 `data "aws_ssm_parameter"` 只能出現在 `ssm-read`，連讀 AMI 公開參數也一樣；S4 規定 `aws_iam_*` 只能出現在 IAM module，instance profile 與 policy attachment 都要改走 module。
3. **`validate.sh` 寫死只看 project-infra**：`tf_stack_glob`、S5、S8、token 檢查、`-lockfile=readonly`、`canon()` 都綁在它上面；Step 6a 只跑 `dev prod` 兩個 env；`ci.yml` 的 Registry versions glob 也寫死。
4. **既有 module 對不上的地方**，列在 §4.1 各 module 底下。
5. **原本的 tests 直接斷言 resource**，例如 `aws_lambda_function.<name>`。改成呼叫 module 後只能斷言 stack 的 locals 與 module 輸出，所以 tests 要照 project-infra 的寫法重寫，不能直接搬。

## 3. 決策

### 3.1 使用者拍板（2026-10-20）

| # | 決策 | 理由 |
|---|---|---|
| D0-1 | 缺 module 的資源先補 module、發版、到 HCP 登記，範本再引用；不在 stack 裡寫原生 resource | 範本要示範「全部走 registry」 |
| D0-2 | 全面泛化：專案名、env、服務名、帳號、網段、網域、ARN、bucket、guardrail 內容、ticket 編號、業務背景註解全部換掉 | repo 是 public |
| D0-3 | 保留 project-b 的 11 個 stack 拆法 | 當作跟 project-infra 不同拆法的第二個例子 |
| D0-4 | tests、envs、`stacks.sh`、`check-ssm-contract.sh` 都帶過來，換成佔位值，接進 `validate.sh` 與 CI | |
| D0-5 | module 一個 PR、範本一個 PR | 範本 CI 對 registry 驗證，module 要先發布 |
| D1 | apply 順序改成 `containerimage foundation network database iam bridge loadbalancer agent application operation postdeploy`；樹 B 由外部發布的環境跳過 bridge | 讀樹 B 的 stack 必須排在 bridge 之後 |
| D2 | 後段 stack 之間也走 SSM：loadbalancer、agent、application 也發布 `ssm-outputs.tf`，下游從樹 A 讀 | 符合 ADR-0003，不手抄 ARN |
| D3 | 樹 B 是 `/<project>-shared/<env>/infra/<snake_key>`，subnet 這類清單用 StringList | 沿用 `ssm-publish`／`ssm-read` 現有的 validation，不做破壞性變更 |
| D4 | 12 個版本照 v0.1.1 的先例手動批次發：改 manifest，合併後在同一個 commit 打 annotated tag，補 GitHub Release | release-please 還不能開 PR，這條流程沒實測過 |
| D5 | 原本跨服務的 CloudWatch dashboard 拿掉，改用 `ecs-service-alarms` 每個服務各自的 dashboard | 不必在 S8 加例外 |
| D6 | `log-metric-alarm` 擴充成可以只建 metric filter、不建告警（0.2.0），ETL 的三個計數指標完整保留 | |
| D7 | 環境只有 `dev`、`sit`：`envs/dev.*`、`envs/sit.*`，`accounts_by_env = { dev, sit }`。code、tfvars、tests、註解、commit 都不出現 dev、sit 以外的環境名稱 | 真實環境名稱會透露來源專案的部署方式 |
| D8 | 保留「樹 B 由外部發布」的完整示意，但不用環境名稱判斷：`stacks.sh` 的 `EXTERNAL_SHARED_ENVS`（預設空的）列出樹 B 由外部發布、不跑 bridge 的環境；bastion 用 `bastion.enabled` 開關（dev 開、sit 關）；import bucket 開關；eval-batch 只在 dev | 這是 example2 跟 project-infra 最不一樣的地方；改成開關後 code 裡不需要出現其他環境名稱 |

### 3.2 planner 判斷、使用者未反對

| # | 決策 |
|---|---|
| J1 | 新 module 命名 `elasticache-redis`、`waf-web-acl`、`lambda-function`、`ec2-bastion`、`vpc-peering`、`metric-alarm`，跟 `log-metric-alarm`、`s3-bucket` 的命名方式一致 |
| J2 | ECS 的 scheduled action 與自訂 step scaling 擴充在 `ecs-service`，不另做 module：scalable target 由 `ecs-service` 擁有，另一個 module 再建一次會衝突。ElastiCache 的 shard autoscaling 包在 `elasticache-redis` 裡 |
| J3 | WAF 與 ALB 的關聯沿用 `alb` 的 `web_acl_arn`；WAF logging 放進 `waf-web-acl`，從 postdeploy 搬到 loadbalancer |
| J4 | managed policy attachment 改寫成收窄的 inline policy（project-infra 的 RDS monitoring role 就是這樣做）；`iam-role` 只加 instance profile |
| J5 | 範本只放穩定狀態需要的資源，遷移期與過渡用的寫法一律不帶過來 |
| J6 | 範本一律用收窄的安全預設：data store 與 ALB 的 SG 不給全開 egress；secret 的 `recovery_window_in_days` 是 7；WAF log 預設遮蔽 `authorization`、`cookie` 與 origin verify header；origin verify 的值只能從 `TF_VAR_origin_verify_header_value` 給，tfvars 不准出現；Lambda 的 S3 invoke permission 必須帶 `source_account`；bastion 固定 IMDSv2、沒有 public IP、沒有 key pair |
| J7 | example2 裡同一個 module 只用一條版本線：擴充過的 6 個一律 `~> 0.2.0`（`alb` 修 bug 後改 `~> 0.3.0`），其餘 `~> 0.1.0` |
| J8 | agent 的環境變數改成通用名，避開 `agentcore-runtime` 對 `TOKEN` 這類名稱的 secret 檢查 |
| J9 | `check-ssm-contract.sh` 只留範本特有的兩項檢查，跟 `validate.sh` 重複的交給 `validate.sh` |

## 4. Module

慣例照 v1 §4.1 與 [`releasing-modules.md`](../../guides/releasing-modules.md)：

- 檔案：`main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`CHANGELOG.md`、`examples/basic/`、`tests/*.tftest.hcl`（每個都有 `mock_provider "aws"`）。
- `versions.tf` 寫 `aws >= 6.0, < 7.0`；不寫 provider、backend、lock file。
- module 不互相呼叫、不用 `enable_xxx` 開關、只收完整的 `name`；`tags` 會 merge 上 `Name`。
- 只要建告警，`sns_topic_arns` 就是必填。
- `.tf` 的註解、description、error_message 用英文；README、CHANGELOG 用台灣繁體中文。
- 一個 commit 只動一個 module 目錄。每條 validation 都要有正反兩個 run。

### 4.1 擴充既有 module（`feat`，各發 0.2.0）

預設值維持原本行為：既有 tests 一個都不改就要全過。

**`iam-role` 0.1.1 → 0.2.0**
- 新增 `instance_profile_name`（string，預設 null，格式 `^[\w+=,.@-]{1,128}$`）；不是 null 才建 `aws_iam_instance_profile`。
- 新增輸出 `instance_profile_name`、`instance_profile_arn`，沒建時是 null。
- tests：預設不建、給名稱就建而且綁這個 role、名稱不合法被拒。

**`s3-bucket` 0.1.1 → 0.2.0**
- `versioning = object({ noncurrent_expiration_days = optional(number, 30) })`，預設 null。開啟時建 `aws_s3_bucket_versioning`，lifecycle 加 `noncurrent_version_expiration` 與清 delete marker 的規則。不能跟 `log_delivery` 一起用。
- `expiration_prefix`（預設 null）：null 時 filter 維持空的；有值時過期規則只套用在這個 prefix。
- `lambda_notifications = map(object({ function_arn, events = optional(list(string), ["s3:ObjectCreated:*"]), filter_prefix = optional(string), filter_suffix = optional(string) }))`，預設 `{}`；非空才建 `aws_s3_bucket_notification`。`function_arn` 必須是 Lambda ARN。
- 清舊版本與 delete marker 是獨立的一條規則，涵蓋整個 bucket、不受 `expiration_prefix` 限制：`expired_object_delete_marker` 不能跟 `days` 放在同一個 expiration 區塊。
- tests：預設時 versioning 與 notification 都是 0 個、lifecycle filter 是空的；versioning、prefix、notification 各自開啟；validation 組合。

**`rds` 0.1.1 → 0.2.0**
- `static_parameter_names`（set(string)，預設 `[]`），跟內建的 `shared_preload_libraries` 取聯集，這些參數用 `pending-reboot`。原本只認 `shared_preload_libraries`，其他 static 參數（例如 `cron.database_name`）會被送成 `immediate`，apply 時失敗。
- 新增輸出 `log_group_name`（PostgreSQL log group）。
- tests：列入清單的參數用 `pending-reboot`、預設行為不變、`log_group_name` 輸出正確。

**`alb` 0.1.0 → 0.2.0**

原本 `alb` 只建 listener，target group 與規則由 `ecs-service` 建，而且一個服務只能有一條規則。example2 需要一個 target group 配多條規則，條件含 header。

- `vpc_id`（預設 null；`target_groups` 非空時必填）。
- `target_groups = map(object({ port, protocol_version = optional("HTTP1"), deregistration_delay = optional(300), health_check = optional(object({ path = "/health", matcher = "200", interval = 15, timeout = 5, healthy_threshold = 2, unhealthy_threshold = 3 }), {}) }))`。
- `listener_rules = map(object({ priority, target_group, path_patterns = optional([]), host_headers = optional([]), require_origin_verify = optional(false) }))`，掛在 HTTPS listener；沒有憑證時掛 HTTP listener。`require_origin_verify` 要明確打開（2026-10-20 使用者決定）：原本預設 `true`，沒設 header 時規則會默默沒有 header 條件。
- `origin_verify_header_name`（預設 null）與 `origin_verify_header_value`（`sensitive = true`）分成兩個變數：包成一個物件的話，`var.x == null` 會變成 sensitive，不能拿來當 `for_each`。
- validation：規則指到的 target group 要存在；priority 不重複；每條規則至少一個 path pattern 或 host header；條件值合計不超過 5（ALB 上限，`require_origin_verify = true` 的 header 算 1 個）；`require_origin_verify = true` 但沒給 `origin_verify_header_name` 時拒絕；`"${name}-${key}"` 不超過 32 字元；header 的 name 與 value 要一起給或一起不給。
- 輸出：`target_group_arns`、`target_group_arn_suffixes`（map）。
- tests：既有 3 個測試檔不改就要全過；新增 target group 與規則數量、header 條件有無、各條 validation。

**`ecs-service` 0.1.0 → 0.2.0**
- `system_controls`（map(string)，預設 `{}`）：空的時候 container definition 不出現這個 key，task definition 跟原本完全相同。
- `autoscaling.policy` 新增 `"custom"`：不建內建的 CPU／step policy，只建下面兩種。
- `autoscaling.scheduled_actions = map(object({ schedule, timezone = optional("UTC"), min_capacity, max_capacity }))` → `aws_appautoscaling_scheduled_action`。
- `autoscaling.step_policies`：每條有比較運算、門檻、評估期間，用 `metric`（單一 metric）或 `queries`（metric math）二選一，加上 `adjustments = list(object({ lower, upper, change }))`。建 `aws_appautoscaling_policy` 與觸發它的 `aws_cloudwatch_metric_alarm`（`alarm_actions` 指向 policy ARN）。
- validation：`metric` 與 `queries` 二選一；scheduled 的 `min <= max`，而且不超過 `autoscaling.max_capacity`；key 必須是 snake_case。
- `scheduled_actions`、`step_policies` 三種 policy 都能搭配，不限 `custom`；step policy 的資源名稱帶 `step-` 前綴，避免跟內建 policy 重名。
- tests：預設 task definition 不變、`custom` 不建 CPU policy、metric math 型的 step policy、scheduled action。
- CHANGELOG 註明：設了 `system_controls` 會產生新的 task definition revision，觸發一次部署。

**`log-metric-alarm` 0.1.0 → 0.2.0**（D6）
- 新增 `metrics = map(object({ pattern, metric_name, metric_value = optional("1"), default_value = optional(0) }))`，預設 `{}`：只建 metric filter，不建告警。
- `sns_topic_arns` 改成只有 `alarms` 非空時必填；`alarms`、`sns_topic_arns` 都有預設值（`{}`、`[]`）。
- 同一個 key 不能同時出現在 `alarms` 與 `metrics`；`alarms`、`metrics`、`sns_topic_arns` 三個都空時拒絕。原本設計是「`alarms`、`metrics` 都空就拒絕」，但 0.1.0 有「`alarms = {}` 加上 SNS 時什麼都不建」的既有行為與測試，所以縮小成三個都空才拒絕。
- 輸出新增 `metric_names`（map，涵蓋 `alarms` 與 `metrics` 兩邊的 key）。
- tests：只給 `metrics` 時不建告警、不需要 SNS；`alarms` 的既有行為不變；key 重複被拒。

### 4.2 新 module（各發 0.1.0）

| module | 主要輸入 | 主要輸出 | 必寫的 tests |
|---|---|---|---|
| `metric-alarm` | `name_prefix`；`alarms = map(object({ description, comparison_operator, threshold, evaluation_periods = 1, datapoints_to_alarm, treat_missing_data = "notBreaching", metric = optional(...), queries = optional(list(...)) }))`；`sns_topic_arns`（必填）；`tags` | `alarm_arns`、`alarm_names` | `metric` 與 `queries` 二選一；alarm 與 OK 都送 SNS；命名 `<prefix>-<key>`；沒給 SNS 被拒 |
| `vpc-peering` | `name`、`vpc_id`、`vpc_cidr`、`peer_vpc_id`、`peer_owner_id`（12 位數）、`peer_region`（預設 null）、`route_table_ids`、`peer_cidrs`、`tags` | `peering_connection_id` | `auto_accept = false`，只建請求端，對端要由對方接受（寫在 README）；route 的 key 用 index 加 CIDR，ID 未知時也能 plan；拒絕 `0.0.0.0/0`；`peer_cidrs` 跟 `vpc_cidr` 重疊時 precondition 失敗；ID 格式 |
| `ec2-bastion` | `name`、`subnet_id`、`security_group_ids`（至少 1 個）、`instance_profile_name`、`instance_type = "t4g.nano"`、`architecture = "arm64"`（或 `x86_64`）、`root_volume_size = 8`、`tags` | `instance_id`、`private_ip`、`ami_id` | AMI 用 `data "aws_ami"` 找 AL2023（S3 不准在 `ssm-read` 以外讀 SSM 參數）；固定 IMDSv2 required、hop limit 1、不配 public IP、root volume 加密 gp3；沒有 `key_name` 輸入，只走 SSM Session Manager；`ignore_changes = [ami]` |
| `lambda-function` | `name`、`image_uri`（只收 ECR，要有 tag 或 digest，拒絕 `latest`）、`role_arn`、`architectures = ["arm64"]`、`memory_size`、`timeout`、`reserved_concurrent_executions`、`environment`（名稱像 secret 的檢查照 `agentcore-runtime`）、`vpc`（可選）、`log_retention_days = 30`、`log_kms_key_arn`、`log_format = "Text"`、`permissions = map(object({ principal, source_arn, source_account = optional, action = "lambda:InvokeFunction" }))`、`tags` | `function_name`、`function_arn`（`depends_on` 所有 permission，讓 S3 notification 一定在授權後才建）、`invoke_arn`、`log_group_name` | 只支援 container image；`logging_config` 指到 module 自己建的 log group；principal 必須是 `*.amazonaws.com`；`s3.amazonaws.com` 必須給 `source_account`；`source_arn` 必填 |
| `elasticache-redis` | `name`（≤40）、`description`、`engine_version`、`node_type`、`port = 6379`、`subnet_ids`、`security_group_ids`、`num_node_groups = 1`、`replicas_per_node_group = 1`（≥1）、`parameters`（merge 在 `cluster-enabled = yes` 之上，family 由 major 版本推得）、`snapshot_retention_limit = 0`、`apply_immediately = false`、`kms_key_arn`、`log_retention_days`、`autoscaling`（可選：`min_shards`、`max_shards`、`target_cpu = 70`）、`alarm_config`（`memory_percent = 80`、`evictions_threshold` 可選）、`sns_topic_arns`（必填） | `configuration_endpoint`、`port`、`replication_group_id`、`member_clusters`、`arn`、`log_group_names`、`alarm_arns` | at-rest 與 transit 加密固定開、沒有開關；automatic failover 與 multi-AZ 固定開；`cache.t*` 不能配 autoscaling；每個 member 一條 memory 告警；沒給 `evictions_threshold` 不建 evictions 告警；member id 推導用 precondition 核對 |
| `waf-web-acl` | `name`、`kill_switch`（可選：`action = "count"` 或 `"block"`、`response_json`）、`rate_limit`（可選：`limit`、`allowlist_cidrs = []`）、`managed_rule_groups = list(object({ name, vendor = "AWS", count_overrides = [] }))`、`body_size_exempt_path_prefixes = []`、`logging`（可選：`retention_days = 14`、`kms_key_arn`、`redacted_headers = ["authorization", "cookie"]`）、`tags` | `web_acl_arn`、`web_acl_name`、`ip_set_arn`、`log_group_name` | 只支援 REGIONAL；priority 依固定順序產生；allowlist 為空時不建 IP set；有 body-size 例外時，common rule set 必須已經把 `SizeRestrictions_BODY` 設成 count，否則拒絕；logging 的 log group 名稱是 `aws-waf-logs-<name>`；`redacted_headers` 要能加入 origin verify header；不建 association |

Phase A2 的實作差異（2026-10-20）：

- `metric-alarm`：預設 `period = 300`、`statistic = "Average"`、`GreaterThanOrEqualToThreshold`；AWS 服務的基本指標多半 1 或 5 分鐘一筆，60 秒容易落在 INSUFFICIENT_DATA。`sns_topic_arns` 一律必填，`alarms = {}` 時不建任何東西。不支援 percentile、anomaly detection、composite alarm。
- `vpc-peering`：Terraform 1.15 沒有 `cidrcontains`，重疊檢查改用 `cidrsubnet`／`cidrhost` 比對較短 prefix 的網段，放在 `peer_cidrs` 的 validation。為了測「route table ID 還不知道時也能 plan」，多一個測試 fixture `tests/fixtures/unknown-ids/`。
- `ec2-bastion`：`instance_type` 跟 `architecture` 不搭時拒絕，用家族名稱判斷（世代數字後有 `g` 是 Graviton）；舊的 `a1` 會被誤擋。`ami_id` 輸出的是目前查到的最新 AMI，不一定是實際在用的（`ignore_changes = [ami]`）。root volume 用帳號預設的 EBS KMS key。
- `lambda-function`：預設 `memory_size = 512`、`timeout = 30`；`source_arn` 的資源部分不能以萬用字元開頭；`action` 只能是單一 `lambda:<Action>`；`name` 只收小寫與連字號。tests 依主題拆成 4 個檔。

Phase A3 的實作差異（2026-10-20）：

- `waf-web-acl` 的 allowlist 只讓名單內的 IP 跳過 rate limit（rate 規則加 `NOT ip_set_reference` 的 scope-down），managed rules 與 body size 照樣檢查；不用 allow 規則，因為 allow 會結束評估、跳過所有規則（使用者 2026-10-20 決定）。
- `waf-web-acl` 的 `redacted_headers` 跟 `authorization`、`cookie` 取聯集，傳 `[]` 也不會關掉這兩個的遮蔽；名稱轉小寫。
- `waf-web-acl` 的 priority 用固定欄位：kill switch 10、rate limit 30、managed rule groups 從 100 起依清單順序、body size 1000；少一條規則時其他規則不位移。body size 上限固定 8192 bytes。kill switch 給了就要明確選 `action`，`response_json` 只有 `block` 能給。allowlist 拒絕 `0.0.0.0/0` 與 IPv6。
- `elasticache-redis`：Redis 6 的 parameter group family 是 `redis6.x`，7 是 `redis7`，其他 major 拒絕。`kms_key_arn` 同時用在 at-rest 加密與兩個 log group。evictions 告警也是每個 member 一條。`subnet_ids` 至少 2 個、`replicas_per_node_group` 最多 5。member id 的 precondition：沒有 autoscaling 時推導集合要等於實際 `member_clusters`（所以改 `num_node_groups` 會直接 apply 失敗，不會默默沒效果）；有 autoscaling 時只要求有交集。

mock 驗不到、要真實環境才能確認的推論（A3）：ElastiCache member id 命名規則 `<name>-<shard 4 位>-<node 3 位>`、shard autoscaling 的 metric 與 dimension 名稱、`redis6.x` family；WAF body size 規則的 `oversize_handling = "MATCH"`、巢狀 statement 深度；WAF logging 需要 apply 身分有 `logs:PutResourcePolicy`。

mock 驗不到、要真實環境才能確認的推論（A2）：`function_arn` 的 `depends_on` 確實讓下游在授權後才建；peering 還在等對方接受時能不能先建 route；AL2023 AMI 的名稱篩選條件。

已知限制（寫進各 module 的 README）：

- `elasticache-redis` 固定 `ignore_changes = [num_node_groups]`，讓 autoscaling 調整 shard 數；所以建好之後改 `num_node_groups` 不會生效，autoscaling 改變 shard 數後 member 告警也會跟實際不符。
- `elasticache-redis` 用 TLS＋security group，不設 AUTH token，列為已知的安全取捨。

### 4.3 發版與 HCP 登記（D4）

1. `release-please-config.json` 的 `packages` 加 6 個新 module。`.release-please-manifest.json` 加 6 個 `"0.1.0"`，6 個擴充的 module 改成 `"0.2.0"`。
2. 每個 CHANGELOG 寫 `## 0.x.0（未發布）`，格式照 v0.1.1 那批。`README.md` 的 module 表加 6 列，徽章照現有格式。
3. PR-A 合併後，在驗收通過的 commit 上打 12 個 annotated tag（6 個 `<m>-v0.1.0`、6 個 `<m>-v0.2.0`）。tag 清單從 manifest 讀出來，不手寫；push 只推這 12 個 tag；用 `gh release create <tag> --notes-file` 補 GitHub Release，不設 latest。**打 tag、push、建 Release 之前先問使用者。**
4. 照 [`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 的 API 迴圈登記，已登記的會跳過，只新增 6 個。狀態變成 `setup_complete` 後，用 §4 的暫存目錄 `terraform get` 確認 32 個 module 都抓得到、版本正確（只連 registry，不碰 AWS）。

## 5. 範本 example2

### 5.1 目錄

```
templates/example2/infra/
├── README.md                   # 樹 A／樹 B 合約、apply 順序、環境切換、樹 B 由外部發布的模式
└── terraform/
    ├── stacks.sh               # 依序跑各 stack（§5.5）
    ├── check-ssm-contract.sh   # 靜態合約檢查（§5.5）
    └── <stack>/                # 11 個，順序見 §5.3
        ├── common.tf           # 11 份一字不差（S5）
        ├── versions.tf  providers.tf  variables.tf  outputs.tf
        ├── ssm-inputs.tf       # module "in"（樹 A）；後段 stack 另有 module "shared"（樹 B）
        ├── ssm-outputs.tf      # module "ssm_publish"
        ├── guards.tf           # terraform_data 的 precondition（有需要的 stack 才有）
        ├── <主題>.tf           # module 呼叫（§5.2）
        ├── .terraform.lock.hcl
        ├── envs/{dev,sit}.tfvars  envs/{dev,sit}.tfbackend   # 佔位值
        └── tests/              # mock_provider "aws"；斷言 locals 與 module 輸出
```

`common.tf` 照 project-infra 的寫法：`project`、`env`、`aws_region`、`expected_account_id`、`accounts_by_env = { dev = ["111111111111"], sit = ["222222222222"] }`，另外多一個 `shared_ssm_prefix = "/${var.project}-shared/${var.env}"`（樹 B）。`providers.tf` 照 project-infra（`deploy_role_arn` 預設 `""`）。

### 5.2 每個 stack 用到的 module

擴充過的 6 個用 `~> 0.2.0`，其餘用 `~> 0.1.0`（J7）。

| stack | 內容 | module |
|---|---|---|
| `containerimage` | ECR：`api`、`worker`、`import-extract`、`import-load`、`agent`；保留「沿用既有 repository」模式（`data "aws_ecr_repository"`，data source 不受 S8 管） | `ecr-repository`、`ssm-publish` |
| `foundation` | 告警 SNS（只有 email）；兩個 secret 容器（原生 resource，已在 S8 例外清單） | `sns-alarm-topic`、`ssm-publish` |
| `network` | VPC（public、app、agent、db 四層，NAT per AZ 或關閉，S3 gateway endpoint）；Bedrock interface endpoint；所有 security group；可選的 VPC peering；NAT 告警 | `vpc`、`vpc-interface-endpoints`、`security-group`、`vpc-peering`、`metric-alarm`、`ssm-read`、`ssm-publish` |
| `database` | Aurora PostgreSQL（pg_cron、`static_parameter_names`、RDS Proxy、Enhanced Monitoring、連線數告警）；Proxy 與 monitoring 的 role；兩組 Redis（`rate-limit`、`stream`）；partition 維護失敗的 log 告警 | `rds`、`iam-role`、`elasticache-redis`、`log-metric-alarm` |
| `iam` | ECS、Lambda、AgentCore 的 role 用一個 roles map 加 for_each；policy 用 `jsonencode` 寫在 locals，方便測試；eval-batch 的 role 只在 `env == "dev"` 時建 | `iam-role`、`ssm-read`、`ssm-publish` |
| `bridge` | 讀樹 A，寫樹 B（`ssm_prefix = local.shared_ssm_prefix`、`stack = "infra"`）；guard：值非空、subnet 至少 2 個 | `ssm-read`、`ssm-publish` |
| `loadbalancer` | ALB：target group `api`，規則 `api_stream`、`api_quota`、`api_admin`，加上有開關的 `dev_page`；WAF 與 WAF logging；ALB access log bucket | `alb`、`waf-web-acl`、`s3-bucket` |
| `agent` | guardrail（每個 profile 一支，另有 output guardrail）、AgentCore Runtime 與 Memory、Runtime 的 log delivery | `bedrock-guardrail`、`agentcore-runtime`、`agentcore-memory`、`log-group`、`log-delivery` |
| `application` | ECS cluster；`api`、`worker` 兩個服務。autoscaling 從 postdeploy 搬過來：api 用 target tracking、連線數 step policy、scheduled action；worker 用 `custom`，依 backlog 高低兩條 step policy。保留 CloudFront managed prefix list 的 data source | `ecs-cluster`、`ecs-service` |
| `operation` | bastion（role 帶 `instance_profile_name`，inline policy 等同 SSM core 的最小權限）；兩個 Lambda；import bucket（versioning、`expiration_prefix`、`lambda_notifications`）；eval-batch bucket；import ETL 的計數指標（D6） | `iam-role`、`ec2-bastion`、`lambda-function`、`s3-bucket`、`log-metric-alarm` |
| `postdeploy` | `api`、`worker` 的服務告警與 dashboard；stream backlog、沒有 consumer 的告警；資料寫入事件、rate-limit fail-open 的 log 告警；AgentCore 的 X-Ray trace delivery | `ecs-service-alarms`、`metric-alarm`、`log-metric-alarm`、`log-delivery` |

除了 `foundation` 的兩個 secret 容器，stack 裡沒有原生 AWS resource，S8 例外清單不用加項目（D5）。`terraform_data` 只用來放 precondition，不受 S8 管。

### 5.3 apply 順序（D1）

| 順序 | stack | 讀 | 發布 |
|---|---|---|---|
| 1 | `containerimage` | 無 | 服務與 Runtime 清單、各 ECR URL／ARN |
| 2 | `foundation` | 無 | 告警 topic、secret ARN |
| 3 | `network` | foundation | VPC、各層 subnet、各 SG、peering |
| 4 | `database` | foundation、network | DB endpoint、Proxy endpoint、secret ARN、Redis endpoint |
| 5 | `iam` | foundation、containerimage、database | 各 role ARN |
| 6 | `bridge` | 前面所有 stack | 樹 B；`EXTERNAL_SHARED_ENVS` 裡的環境不跑 |
| 7 | `loadbalancer` | 樹 B | `alb_arn_suffix`、`target_group_arn_suffixes`、`api_target_group_arn` |
| 8 | `agent` | 樹 B | Runtime 與 Memory 的 ARN／id、guardrail |
| 9 | `application` | 樹 B、loadbalancer、agent | cluster 名稱、各服務名稱與 log group |
| 10 | `operation` | 樹 B | bucket、Lambda 名稱 |
| 11 | `postdeploy` | 樹 B、loadbalancer、application、agent | 不發布 |

destroy 反過來。後段 stack（7–11）只讀樹 B 與其他後段 stack 的樹 A key，不直接讀前段 stack；這樣樹 B 改由外部發布時，後段 stack 照樣能跑。

### 5.4 SSM 合約

- **樹 A**：`/<project>/<env>/<stack>/<key>`。生產端是前段 5 個 stack，加上 D2 的 loadbalancer、agent、application。
- **樹 B**：`/<project>-shared/<env>/infra/<snake_key>`，一般由 bridge 發布，`EXTERNAL_SHARED_ENVS` 裡的環境由外部發布；外部要發布的 key 清單寫在範本 README。比原本多兩個 key：`alarm_topic_arn`、`bastion_sg`，因為樹 B 由外部發布時，後段 stack 讀不到 foundation 與 network。
- 每個 stack 都改讀 `module.in` 與 `module.shared` 的 `strings`、`lists`，不再直接寫 `data "aws_ssm_parameter"`。

### 5.5 `stacks.sh` 與 `check-ssm-contract.sh`

**`stacks.sh`**
- ORDER 照 §5.3；`all` 遇到 `EXTERNAL_SHARED_ENVS` 裡的環境自動跳過 bridge。
- env 檔從 `<stack>/envs/<env>.{tfvars,tfbackend}` 讀。S6 從目錄層級推 stack 名稱，所以 env 檔要放在各 stack 底下，不能集中放在一個共用的 `envs/` 目錄。
- 保留 `validate` 動作（`init -backend=false`）。`init`、`plan`、`apply`、`destroy` 動作也保留給使用者自己用；本 repo 的開發與 CI 不跑這些。

**`check-ssm-contract.sh`** 只檢查兩件事，ORDER 直接從 `stacks.sh` 讀，不另寫一份：
1. 消費端讀的每個 `<stack>/<key>`，生產端在 ORDER 裡排在它前面，而且確實發布這個 key。樹 B 的 `infra/` 前綴對應到 bridge。解析 `ssm-read` 的輸入與 `ssm-publish` 的 `published_strings`、`published_lists`。
2. 同一個 env 裡，各 stack tfvars 共用的 key 值必須一致。

原本的其他項目跟 S5、S3、S2 重複，或是遷移期用的，拿掉。

### 5.6 tests

照 project-infra 的寫法：每個 stack 一份 `tests/<stack>.tftest.hcl` 加 `tests/tfvars/tfvars.tftest.hcl`，全部用 `mock_provider "aws"`，斷言 locals 與 module 的輸入、輸出。要保留的情境：

- `application`：`forwarded_allow_ips` 的三種信任模式。
- `agent`：guardrail profile 的組合。
- `operation`：Lambda 的資源上限、`bastion.enabled = false` 時不建 bastion、eval-batch 只在 dev。
- `iam`：eval-batch role 只在 dev。
- `bridge`：值是空的被拒、subnet 不足被拒、樹 B 的 key 集合正確。
- `postdeploy`：各功能開關互相獨立。

### 5.7 B2 骨架跟上面不同的地方

- **發布的 key 先用註解列出**：骨架階段沒有資源可以接 `module "ssm_publish"`，硬寫只能放假值。所以 `ssm-outputs.tf` 只有 `# planned_strings: ...`、`# planned_lists: ...` 註解，`check-ssm-contract.sh` 把它們當成已發布；B3–B5 加上真的 `published_strings`、`published_lists` 時要同一個 PR 把註解換掉。讀的 key 不需要值，直接寫成真的 `ssm-inputs.tf`（`module "in"`、`module "shared"`）。
- **沒有東西可讀或發布的 stack 不放對應的檔案**：`containerimage`、`foundation` 沒有 `ssm-inputs.tf`，`postdeploy` 沒有 `ssm-outputs.tf`。
- **key 名稱**：§5.4 的 `bastion_sg` 寫成 `bastion_sg_id`，跟其他 security group 一致；`loadbalancer` 多發布 `api_target_group_arn`，因為 `application` 註冊 ECS 服務需要完整的 ARN，suffix 不夠。各 stack 的 key 是 B2 先定的清單，B3–B5 可以調整，`check-ssm-contract.sh` 會抓出對不上的地方。B3 之後又改了兩處：`app_secret_arn`、`signing_secret_arn` 改名為 `signing_private_key_secret_arn`、`signing_public_key_secret_arn`；`lambda_role_arn` 拆成 `import_extract_role_arn`、`import_load_role_arn`（見 §5.8）。
- **`common.tf`**：三個前綴 local（`name_prefix`、`ssm_prefix`、`shared_ssm_prefix`）加 `tflint-ignore: terraform_unused_declarations`，因為 11 份一字不差，但不是每個 stack 都用得到每個前綴。
- **`check-ssm-contract.sh` 多檢查兩個細節**：讀的型別（strings 或 lists）要跟發布的一致；tfvars 的 `env` 要等於檔名。兩者都屬於 §5.5 的第 1、2 項。
- **`stacks.sh`**：多一個 `--dry-run`（只印指令）；`validate` 用另一個 data directory `.terraform-<env>-validate` 並加 `-lockfile=readonly`，避免蓋掉 `init` 留下的 backend 設定、也不改 lock 檔。`ORDER=(...)` 必須寫在同一行，因為 `check-ssm-contract.sh` 用 grep 解析它。
- **tests**：每個 stack 有 `tests/common.tftest.hcl`（帳號、env、`deploy_role_arn` 的 validation 正反各案例）與 `tests/tfvars/tfvars.tftest.hcl`；11 份內容相同。

### 5.8 B3（前段 5 個 stack）的實作差異

2026-10-20 完成 containerimage、foundation、network、database、iam。跟 §5.2、§5.3、§5.7 不同的地方：

**合約**

- 發布的 key 全部沿用 §5.7 的清單，沒有改名。新增一個：`network` 多發布 `db_proxy_sg_id`（RDS Proxy 用自己的 security group，資料庫只收 Proxy 的連線），只有 `database` 讀。
- `network` 讀的 key 從 `containerimage/services` 改成 `foundation/alarm_topic_arn`：network 沒有任何東西要依服務清單決定（SG 是依層，不是依服務），NAT 告警卻需要告警 topic。
- `bastion_sg_id` 永遠發布：SG 一律建立（沒有規則就沒有任何路徑），`bastion_enabled = true` 才加上連 Proxy 與 Redis 的規則。operation 的 `bastion.enabled` 要跟 network 的 `bastion_enabled` 一致，沒有東西檢查這點。
- foundation 發布的 secret key 以內容命名：`signing_private_key_secret_arn`（private key，只有 api 的 task role 能讀）、`signing_public_key_secret_arn`（public key，api 與 worker 讀）。B2 的清單原本叫 `app_secret_arn`、`signing_secret_arn`，名稱跟內容對不上，B3 之後改名，並同步改 bridge、application 骨架的 key 清單。
- 兩個 import Lambda 各有自己的 role，發布 `import_extract_role_arn`、`import_load_role_arn`（取代 B2 清單的 `lambda_role_arn`，bridge 與 operation 的 key 清單已同步）。import-extract 由上傳觸發：讀 `incoming/*`、寫 `extracted/*`、呼叫兩個 embedding 模型，不碰資料庫，所以沒有 secret 與 KMS 權限。import-load 讀 `extracted/*` 並讀資料庫 secret，不能寫 bucket、不能呼叫模型。兩者都有各自 log group 的寫入權與 VPC ENI 權限。
- `containerimage` 發布的 `ecr_repository_urls`、`ecr_repository_arns` 是 JSON（鍵是映像名稱，包含 Runtime），`agent_runtimes` 是 JSON 陣列；`peering_connections` 是 JSON 物件（沒有 peering 時是 `{}`）。Redis endpoint 是 `host:port`。
- ECR repository 名稱是 `<project>-<image>`，不帶 env：兩個 env 共用同一個帳號時，一邊建、另一邊用 `adopt_existing = true` 沿用。

**後段 stack 必須遵守的命名規則**（iam 先於它們 apply，讀不到資源，所以用命名規則組 ARN，沒有東西檢查兩邊一致）

| 資源 | 名稱 | 建立的 stack |
|---|---|---|
| import bucket、eval-batch bucket；import bucket 的 prefix：`incoming/`（上傳，觸發 import-extract）、`extracted/`（import-extract 的輸出，import-load 讀） | `<project>-<env>-import-<account>`、`<project>-<env>-eval-batch-<account>` | operation |
| Lambda log group | `/aws/lambda/<project>-<env>-import-extract`、`/aws/lambda/<project>-<env>-import-load` | operation |
| ECS log group | `/ecs/<project>-<env>-*` | application |
| AgentCore Runtime、Memory | `<project>_<env>_<runtime>`、`<project>_<env>_memory`（連字號換成底線） | agent |
| 自訂 metric namespace | `<Project>/<env>`（`title(project)`，例如 `Example/dev`） | database、operation、postdeploy |

**R2 沒有循環**：Proxy role 的 policy 用 `module.db.master_user_secret_arn`，`rds` 的 Proxy 用 `module.proxy_role.arn`。secret ARN 來自 cluster resource，role ARN 只被 Proxy 的 resource 用，而 Proxy 在 cluster 之後才建，所以圖上沒有環。Proxy role 與 monitoring role 各自一個 `iam-role` 呼叫（不用 for_each），避免 monitoring role 被拉進 secret 的相依鏈。`terraform validate` 與 `tests/graph.tftest.hcl`（不 override `module.db`，讓真實的 module 一起 plan）都通過。

**安全收窄與例外**

- 資料庫與 ALB 的 SG 沒有全開 egress：ALB 只能到 app SG 的 `app_port`；db、cache 完全沒有 egress；Proxy 只能到 db。app、agent、bastion 的 443 egress 在 NAT 關閉時改成 VPC CIDR 加 S3 prefix list（ECR 的 image layer 從 S3 下載）。
- 沒有 `kms:Decrypt` 的萬用資源：database 與 iam 用 `data "aws_kms_alias"` 查 `alias/aws/secretsmanager` 的 key ARN，並限定 `kms:ViaService`。
- IAM policy 的 `Resource = "*"` 只有 AWS 不支援 resource-level 的動作：`ecr:GetAuthorizationToken`、X-Ray、`ssmmessages`、Lambda 的 EC2 network interface、`cloudwatch:PutMetricData`（用 namespace 條件限制）。tests 列出完整清單，多一項就失敗。
- `eval_batch` role 只在 `env == "dev"` 建立，`eval_batch_model_id` 在 dev 必填。
- 加上 `aws:ResourceAccount` 條件的只有 eval-batch 的 S3 權限；其他 role 的 S3 權限是 bucket 命名規則組出來的具體 ARN。

**tests 的寫法**

- `tests/common.tftest.hcl` 的 `variables` 區塊加上該 stack 的必填變數（containerimage 的 `services`、database 的 `redis` 等），否則帳號檢查連 plan 都過不了；有 `module "in"` 的 stack 另外在 `common` 與 `tfvars` 兩份測試加 `override_module`，因為 mock 讀 SSM 會回傳隨機字串，過不了 module 的格式檢查。所以這兩份不再是 11 份一字不差。
- network 有兩份測試：`network.tftest.hcl` 把 `module.vpc` 換成固定輸出，`layout.tftest.hcl` 讓真實的 `vpc` module 驗子網路配置有沒有重疊。database 的 `graph.tftest.hcl` 同理。
- `database` 經 `rds` module 用到 `random`，lock 檔因此多一個 provider。

**mock 驗不到、要真實環境才能確認的推論**

- Proxy role 的 policy 在不指定 CMK 時，`kms:Decrypt` 限定 `alias/aws/secretsmanager` 的 key 加 `kms:ViaService` 是否足夠；`alias/aws/secretsmanager` 要在帳號裡有人用過預設 key 建過 secret 才存在（foundation 先 apply，所以成立）。
- RDS Enhanced Monitoring role 收窄到 `RDSOSMetrics` log group 是否足夠（跟 project-infra 同一個未驗證的假設）。
- AgentCore Runtime role 與 `aws:SourceArn` 的形狀（`arn:aws:bedrock-agentcore:<region>:<account>:*`）、`runtime/<name>-*` 與 `memory/<name>-*` 的 ARN 形狀。
- pg_cron 的 log 告警靠 SQL 寫出 `partition_maintenance_failed`、`partition_maintenance_heartbeat`、`default_partition_not_empty` 三個字串；這是跟應用程式 SQL 的約定，沒有東西檢查。
- 沒有 NAT 時 app、agent 還缺 ECR、CloudWatch Logs、Secrets Manager 的 interface endpoint（network 只建 Bedrock 的三個），tfvars 預設 `per_az`。
- `connections_threshold` 是佔位值（dev 300、sit 1400），要依 instance class 的 `max_connections` 調整。

### 5.9 B4（bridge）的實作差異

- B4 完成時樹 B 發布 25 個 key（21 個 String、4 個 StringList；B5 之後見 §5.10），正好等於後段 5 個 stack 的 `module "shared"` 讀的聯集，B2 的清單沒有多也沒有少，所以沒有任何前段 key 被省略。
- `published_strings`、`published_lists` 逐 key 寫成 `key = module.in.strings["key"]`，不用 for 運算式：`check-ssm-contract.sh` 靠 grep 解析 key。
- guard 有三條：String 不可為空、`*_subnet_ids` 至少 2 個、`agent_runtimes`（陣列）與 `ecr_repository_urls`（物件）是合法 JSON；錯誤訊息列出有問題的 key。`module "ssm_publish"` 加 `depends_on` 指向這三個 guard，否則 `ssm-publish` 自己的 validation 會先擋下空字串，訊息沒有指出是哪個 key。
- 外部發布者的 key 合約寫在 `templates/example2/infra/README.md`「樹 B 的 key 合約」。
- tests 多一份 `tests/bridge.tftest.hcl`；`common` 與 `tfvars` 兩份測試也要 `override_module`，理由同 §5.8。run 層級的 `override_module` 不能引用 `module.in`，所以失敗案例各自寫出完整的 fixture。

### 5.10 B5（後段 5 個 stack）的實作差異

2026-10-20 完成 loadbalancer、agent、application、operation、postdeploy。11 個目錄 `scripts/validate.sh` 全過。

**命名規則對照**（iam 用命名規則組 ARN，下表每一列都有 test 斷言）

| iam 的來源（`iam/policies.tf`） | 後段建出的名稱 | stack | 一致 |
|---|---|---|---|
| ECS log group `/ecs/<project>-<env>-*` | `/ecs/<project>-<env>-api`、`/ecs/<project>-<env>-worker`（`ecs-service` 預設的 `/ecs/<name>`） | application | 是 |
| Lambda log group `/aws/lambda/<project>-<env>-import-extract`、`-import-load` | `lambda-function` 建的 `/aws/lambda/<name>`，name 同上 | operation | 是 |
| import bucket `arn:aws:s3:::<project>-<env>-import-<account>`，prefix `incoming/`（讀）、`extracted/`（寫、讀） | bucket 名稱同左；S3 通知的 prefix 也是 `incoming/`、`extracted/` | operation | 是 |
| eval-batch bucket `<project>-<env>-eval-batch-<account>`，只在 dev | 名稱同左，`var.env == "dev"` 才建 | operation | 是 |
| AgentCore Runtime `runtime/<project>_<env>_<runtime>-*`（連字號換底線） | `<project>_<env>_<runtime>` | agent | 是 |
| AgentCore Memory `memory/<project>_<env>_memory-*` | `<project>_<env>_memory` | agent | 是 |
| 自訂 metric namespace `<Project>/<env>`（worker 的 `PutMetricData` 條件） | worker 的 backlog 告警、operation 的 ETL 指標、postdeploy 的 stream 與 log 告警都用 `title(project)/env` | application、operation、postdeploy | 是 |
| import-extract、import-load 各用自己的 role | `lambda-function` 的 `role_arn` 各自取 `import_extract_role_arn`、`import_load_role_arn` | operation | 是 |
| `bedrock:ApplyGuardrail` 的資源 `guardrail/*` | guardrail 由 `bedrock-guardrail` 建，名稱 `<project>-<env>-input-<profile>`、`<project>-<env>-output` | agent | 是；api task 與 Runtime 的 role 另有 `guardrail-profile/<id>`（region 用 `*`），id 由 iam 與 agent 各一個變數 `guardrail_cross_region_profile_id`，`check-ssm-contract.sh` 比對兩邊的 tfvars |
| Runtime 的 log group 授權 `/aws/bedrock-agentcore/runtimes/<name>-*` | 不一致：Runtime 的 application log 另建 `/aws/vendedlogs/bedrock-agentcore/<name>`，由 log delivery 寫入，不經過 Runtime 的 role | agent | 不影響（那條授權是給 Runtime 自己預設 log group 用的），但實際行為只能在真實環境確認 |

**合約調整**（後段 stack 自己的讀取與發布；database、bridge 的改動見下面「樹 B 變成 26 個 key」）

- agent 不讀 `alarm_topic_arn`；多發布 `agent_memory_arn`（postdeploy 的 Memory trace 需要完整 ARN）與 `guardrail_ids`（JSON：每個 profile 加 `output`）。`agent_runtime_arns` 是 JSON 物件，鍵是 Runtime 名稱。
- application 多讀 `loadbalancer/alb_arn_suffix`（requests_per_target 與連線數的 metric 要用）與 `agent/guardrail_ids`；不讀 `agent_memory_id` 與 `alarm_topic_arn`（用不到）；多發布 `api_max_capacity`、`worker_max_capacity`、`stream_length_cap`，讓 postdeploy 的告警跟著同一組數字。
- loadbalancer 發布的 `target_group_arn_suffixes` 是 JSON 物件（鍵是 target group key）。
- operation 多讀 `ecr_repository_urls`、`db_proxy_endpoint`、`db_secret_arn`、`db_name`；不讀 `vpc_id`、`alarm_topic_arn`（用不到）。
- postdeploy 多讀 application 的 `worker_log_group_name` 與三個數字、agent 的 `agent_memory_arn`；不讀 `waf_web_acl_name`、`stream_redis_id`；這兩個 key 沒有人讀，已經不發布（loadbalancer 與 database→bridge 各拿掉一個）。
- 沒有任何後段需要、而前段與 bridge 沒提供的 key：VPC CIDR 用 `data "aws_vpc"` 以 `vpc_id` 查。
- **樹 B 變成 26 個 key**（22 個 String、4 個 StringList）：database 多發布 `db_name` 與 `stream_shard_count`（stream 那組 Redis 的 `num_node_groups`），bridge 原樣轉寫；拿掉 `stream_redis_id`。agent、application、operation 都從樹 B 讀 `db_name`，application 讀 `stream_shard_count`，不再各留一份變數。設了 autoscaling 的 stream Redis，`stream_shard_count` 只是起始值。

**各 stack 的設計決定**

- loadbalancer：`alb` module 用 `web_acl_arn == null` 當 count，Web ACL 跟 ALB 在同一個 stack 建時，ARN 在 plan 還不知道，會報 `Invalid count argument`。B5 先用 `format("%s", ...)` 繞過；使用者決定直接修 module，發 `alb-v0.3.0`（PR #12，新增 `web_acl = object({ arn = string })`，物件是不是 null 在 plan 時就知道），範本改用 `web_acl = { arn = module.waf.web_acl_arn }` 與 `~> 0.3.0`，拿掉繞法。ALB 加 `depends_on = [module.alb_logs]`，確保 bucket policy 先於 ALB。origin verify 的值變數沒有預設值、`sensitive`、至少 16 字元；tests 讀 tfvars 檔內容斷言沒有賦值。WAF logging 一律開（原本在 postdeploy 有開關）。
- agent：guardrail 的 profile 是 `default`、`profile_a`；內容（topic、詞彙、拒絕文案）全是示意。輸入 guardrail 只評估輸入，輸出 guardrail 只評估輸出且沒有 prompt attack。Runtime 經 Proxy 連資料庫：環境變數 `AGENT_DB_HOST`、`AGENT_DB_NAME`、`AGENT_DB_SSLMODE` 與 `AGENT_DB_AUTH_ARN`（只放 secret 的 ARN，值由 Runtime role 自己讀；名稱避開 agentcore-runtime 對 SECRET、TOKEN 這類字的檢查）。
- application：`FORWARDED_ALLOW_IPS` 由變數 `trusted_proxies` 決定，三種值 `any`、`vpc`、`vpc_and_cdn`；VPC CIDR 用 `data "aws_vpc"` 查（tree B 沒有 `vpc_cidr`）。task 拿到的是 secret 的 ARN（環境變數名稱以 `_ARN` 結尾），值由 task role 自己取：execution role 沒有 secret 權限。api 與 worker 都設 TCP keepalive 的 `system_controls`。ECS Exec 用獨立的 `enable_execute_command`，不跟 bastion 綁在一起。
- operation：`bastion_enabled` 用平的 tfvars key（不是 `bastion.enabled`），這樣 `check-ssm-contract.sh` 的 awk 解析得到；import bucket 沒有開關（Lambda 的觸發與 iam 的授權都依賴它）。import-load 由 `extracted/` 加 `ready.json` 後綴觸發，`ready.json` 由 import-extract 寫，是跟應用程式的約定。ETL 指標共四個：import-load 的 rejected、failed、succeeded，加上 import-extract 的 rejected（各自一個 `log-metric-alarm` 呼叫，因為 filter 掛在各自的 log group）。
- postdeploy：四個功能（service 告警與 dashboard、stream 告警、log 告警、trace delivery）各有開關，預設全關，tfvars 全開。dashboard 沒有獨立開關：`ecs-service-alarms` 一定會建告警。

**mock 驗不到、要真實環境才能確認的推論**

- `format()` 讓 `alb` 的 count 在 plan 能決定：核心行為，但沒有對真實 provider 跑過。
- ALB 加 access log 時 AWS 會試寫一個測試物件：`depends_on` 是否足以讓 bucket policy 先到位。
- WAF logging 需要 apply 身分有 `logs:PutResourcePolicy`（同 A3）。
- `/aws/vendedlogs/...` 當 log delivery 的目的地，與 Runtime 的 `APPLICATION_LOGS` delivery 能否建立。
- S3 通知：`incoming/`（無後綴）與 `extracted/` 加 `ready.json` 不重疊，S3 在 apply 時才會驗。
- bastion 的 inline policy（Session Manager 的最小動作集合）是否足夠 agent 註冊與開 session；沒有 `ssm:ListAssociations` 等管理動作。
- Lambda 放進 VPC 後，只靠 app security group 與 NAT 或 endpoint 的出口能否呼叫 Bedrock、S3、Secrets Manager。
- 連線數的 step policy 用 metric math，`ecs-service` 的 `queries` 欄位是否被 provider 接受。
- guardrail 的 `STANDARD` tier 加 cross-region profile 在 apply 的實際行為。

**使用者已決定的事項（2026-10-20）**

1. iam 補上 `guardrail-profile/<id>` 的授權（api task、Runtime 兩個 role），id 放變數、兩邊 tfvars 由 `check-ssm-contract.sh` 比對。
2. Runtime 連資料庫：由 database 發布 `db_name`、`stream_shard_count`，bridge 轉寫，agent、application、operation 從樹 B 讀。
3. 沒人讀的 `stream_redis_id`、`waf_web_acl_name` 不再發布。
4. 補回 import-extract 的 rejected 指標。

**技術債**

- `app_port` 在 network、loadbalancer、application 各有一份變數，靠預設值一致；`SHARED_CONFIG_KEYS` 只比對 `bastion_enabled` 與 `guardrail_cross_region_profile_id`。
- `check-ssm-contract.sh` 的 `bastion_enabled`、`guardrail_cross_region_profile_id` 檢查沒有自動化 fixture（腳本不在 `validate.sh` 的測試範圍）；B5 用暫存複本改 tfvars 手動驗過會失敗。
- 把 `ecs-service-alarms` 的 dashboard 與告警綁在同一個 module 呼叫，無法只開 dashboard。

## 6. `validate.sh` 與 CI

- `tf_stack_glob` 改成 `tf_stack_roots`（用 `templates/*/infra/terraform` 找）。目錄掃描、S8 範圍、token 檢查、`-lockfile=readonly` 都改成迭代這個陣列。
- S5 改成每份範本各自比對 `common.tf`。
- `canon()` 遇到外部客戶 repo 時維持對應到 project-infra，因為 S8 只用 stack 名稱比對。
- Step 6a 改成迭代 `"$dir"/envs/*.tfvars`，不再寫死 `dev prod`；project-infra 的行為不變。
- 靜態階段新增：每份範本有 `check-ssm-contract.sh` 就跑；`*.sh` 跑 `bash -n`，有裝 `shellcheck` 就加跑。
- `ci.yml` 的 Registry versions glob 改成涵蓋所有範本，表格多一欄範本名稱。`timeout-minutes` 先維持 30，量測後如果不夠再調。
- 驗收：改完後 project-infra 的結果要跟改之前相同。
- B6 新增 S10（規則表在 v1 design §5.6）：範本 stack 的 `.terraform.lock.hcl`，每個 `provider` 區塊至少要有 2 個 `h1:`。來由：B3 在 macOS 用 `init -backend=false` 寫的 lock 只有 darwin 的 `h1:`，CI（linux，從 plugin cache 安裝）因此失敗，本機驗不到，只能靠靜態檢查補上。客戶 repo 的 stack 照 S5 的做法一起檢查。

## 7. 風險

| # | 風險 | 處理 |
|---|---|---|
| R1 | `elasticache-redis` 的 `ignore_changes = [num_node_groups]` 讓建好之後改 shard 數不生效，autoscaling 後 member 告警會過期 | 寫進 README |
| R2 | database stack 裡 Proxy role 的 policy 要用 cluster 的 secret，`rds` 的 Proxy 又要這個 role，可能形成循環依賴 | B3 已驗證：沒有循環（見 §5.8），不需要改用命名規則 |
| R3 | CloudFront prefix list 當 ALB 入口會大量佔用 SG 規則配額 | dev、sit 的 tfvars 預設不用 |
| R4 | ElastiCache 沒有 AUTH token，只靠 TLS 與 SG | 已知取捨，寫進 README |
| R5 | CI 時間會增加 11 個 stack 的 tests | B6 量測，必要時調 `timeout-minutes` |
| R6 | `rds` 在 Aurora 模式下必填 `connections_threshold` | tfvars 給佔位值，註明要依 instance class 調整 |
| R7 | 去機密漏網 | 照 playbook §4 掃描，PR 送出前與合併前各跑一次 |
