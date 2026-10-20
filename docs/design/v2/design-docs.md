# infra-platform v2 設計文件：第二份範本 example2

> 狀態：使用者已拍板（§3），可以進入實作；實作步驟見 [`implement-process.md`](./implement-process.md)。
> 範圍：把一個已上線專案（下稱 project-b）的 Terraform 改寫成本 repo 的第二份範本 `templates/example2`，缺的 module 先補進 registry。
> 之後每整合一個專案都照 [`integration-playbook.md`](./integration-playbook.md) 做；這份只寫 example2 的設計。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「v1 §x.y」指 [`../v1/design-docs.md`](../v1/design-docs.md) 的章節。

## 1. 結論

project-b 是 11 個 Terraform stack、約 240 個原生 resource 的專案（ALB＋WAF、ECS、Aurora＋RDS Proxy、ElastiCache、AgentCore、Lambda、bastion）。它幾乎沒有用 module：唯一的 module 是自己寫的 `ssm-publish`。

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
2. **本 repo 的靜態規則會擋掉原本的寫法**：S3 規定 `data "aws_ssm_parameter"` 只能出現在 `ssm-read`（原本每個 stack 都直接讀，連 bastion 讀 AMI 公開參數也是）；S4 規定 `aws_iam_*` 只能出現在 IAM module（原本有 `aws_iam_instance_profile`、`aws_iam_role_policy_attachment`）。
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
| D8 | 保留「樹 B 由外部發布」的完整示意，但不用環境名稱判斷：`stacks.sh` 的 `EXTERNAL_SHARED_ENVS`（預設空的）列出樹 B 由外部發布、不跑 bridge 的環境；bastion 用 `bastion.enabled` 開關（dev 開、sit 關）；import bucket 開關；eval-batch 只在 dev | 這是 project-b 跟 project-infra 最不一樣的地方；改成開關後 code 裡不需要出現其他環境名稱 |

### 3.2 planner 判斷、使用者未反對

| # | 決策 |
|---|---|
| J1 | 新 module 命名 `elasticache-redis`、`waf-web-acl`、`lambda-function`、`ec2-bastion`、`vpc-peering`、`metric-alarm`，跟 `log-metric-alarm`、`s3-bucket` 的命名方式一致 |
| J2 | ECS 的 scheduled action 與自訂 step scaling 擴充在 `ecs-service`，不另做 module：scalable target 由 `ecs-service` 擁有，另一個 module 再建一次會衝突。ElastiCache 的 shard autoscaling 包在 `elasticache-redis` 裡 |
| J3 | WAF 與 ALB 的關聯沿用 `alb` 的 `web_acl_arn`；WAF logging 放進 `waf-web-acl`，從 postdeploy 搬到 loadbalancer |
| J4 | managed policy attachment 改寫成收窄的 inline policy（project-infra 的 RDS monitoring role 就是這樣做）；`iam-role` 只加 instance profile |
| J5 | 拿掉遷移期的寫法：只在部分 AZ 的額外 subnet、public 路由表上的 inline peering 路由、`terraform_data.vpc_identity`、`name_prefix` 覆寫、guardrail 的過渡版本、postdeploy 的跨帳號 alias provider、SNS 的 https 訂閱 |
| J6 | 安全收窄優先於照抄：data store 與 ALB 的 SG 不給全開 egress；secret 的 `recovery_window_in_days` 從 0 改成 7；WAF log 預設遮蔽 `authorization`、`cookie` 與 origin verify header；origin verify 的值只能從 `TF_VAR_origin_verify_header_value` 給，tfvars 不准出現；Lambda 的 S3 invoke permission 必須帶 `source_account`；bastion 固定 IMDSv2、沒有 public IP、沒有 key pair |
| J7 | example2 裡同一個 module 只用一條版本線：擴充過的 6 個一律 `~> 0.2.0`，其餘 `~> 0.1.0` |
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

原本 `alb` 只建 listener，target group 與規則由 `ecs-service` 建，而且一個服務只能有一條規則。project-b 是一個 target group 配四條規則，條件含 header。

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

mock 驗不到、要真實環境才能確認的推論：`function_arn` 的 `depends_on` 確實讓下游在授權後才建；peering 還在等對方接受時能不能先建 route；AL2023 AMI 的名稱篩選條件。

已知限制（寫進各 module 的 README）：

- `elasticache-redis` 固定 `ignore_changes = [num_node_groups]`，讓 autoscaling 調整 shard 數；所以建好之後改 `num_node_groups` 不會生效，autoscaling 改變 shard 數後 member 告警也會跟實際不符。
- `elasticache-redis` 用 TLS＋security group，不設 AUTH token。這跟 project-b 一致，列為已知的安全取捨。

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
| `postdeploy` | `api`、`worker` 的服務告警與 dashboard；stream backlog、沒有 consumer 的告警；persistence 事件、rate-limit fail-open 的 log 告警；AgentCore 的 X-Ray trace delivery | `ecs-service-alarms`、`metric-alarm`、`log-metric-alarm`、`log-delivery` |

除了 `foundation` 的兩個 secret 容器，stack 裡沒有原生 AWS resource，S8 例外清單不用加項目（D5）。`terraform_data` 只用來放 precondition，不受 S8 管。

### 5.3 apply 順序（D1）

| 順序 | stack | 讀 | 發布 |
|---|---|---|---|
| 1 | `containerimage` | 無 | 服務與 Runtime 清單、各 ECR URL／ARN |
| 2 | `foundation` | 無 | 告警 topic、secret ARN |
| 3 | `network` | containerimage | VPC、各層 subnet、各 SG、peering |
| 4 | `database` | foundation、network | DB endpoint、Proxy endpoint、secret ARN、Redis endpoint |
| 5 | `iam` | foundation、containerimage、database | 各 role ARN |
| 6 | `bridge` | 前面所有 stack | 樹 B；`EXTERNAL_SHARED_ENVS` 裡的環境不跑 |
| 7 | `loadbalancer` | 樹 B | `alb_arn_suffix`、`target_group_arn_suffixes`、`waf_web_acl_name` |
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
- env 檔從 `<stack>/envs/<env>.{tfvars,tfbackend}` 讀。原本集中在 `envs/<env>/` 的寫法會讓 S6（從目錄層級推 stack 名稱）失敗。
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

## 6. `validate.sh` 與 CI

- `tf_stack_glob` 改成 `tf_stack_roots`（用 `templates/*/infra/terraform` 找）。目錄掃描、S8 範圍、token 檢查、`-lockfile=readonly` 都改成迭代這個陣列。
- S5 改成每份範本各自比對 `common.tf`。
- `canon()` 遇到外部客戶 repo 時維持對應到 project-infra，因為 S8 只用 stack 名稱比對。
- Step 6a 改成迭代 `"$dir"/envs/*.tfvars`，不再寫死 `dev prod`；project-infra 的行為不變。
- 靜態階段新增：每份範本有 `check-ssm-contract.sh` 就跑；`*.sh` 跑 `bash -n`，有裝 `shellcheck` 就加跑。
- `ci.yml` 的 Registry versions glob 改成涵蓋所有範本，表格多一欄範本名稱。`timeout-minutes` 先維持 30，量測後如果不夠再調。
- 驗收：改完後 project-infra 的結果要跟改之前相同。

## 7. 風險

| # | 風險 | 處理 |
|---|---|---|
| R1 | `elasticache-redis` 的 `ignore_changes = [num_node_groups]` 讓建好之後改 shard 數不生效，autoscaling 後 member 告警會過期 | 寫進 README |
| R2 | database stack 裡 Proxy role 的 policy 要用 cluster 的 secret，`rds` 的 Proxy 又要這個 role，可能形成循環依賴 | B3 的 `terraform validate` 會抓到；有循環就改成用命名規則組 secret ARN |
| R3 | CloudFront prefix list 當 ALB 入口會大量佔用 SG 規則配額 | dev、sit 的 tfvars 預設不用 |
| R4 | ElastiCache 沒有 AUTH token，只靠 TLS 與 SG | 已知取捨，寫進 README |
| R5 | CI 時間會增加 11 個 stack 的 tests | B6 量測，必要時調 `timeout-minutes` |
| R6 | `rds` 在 Aurora 模式下必填 `connections_threshold` | tfvars 給佔位值，註明要依 instance class 調整 |
| R7 | 去機密漏網 | 照 playbook §4 掃描，PR 送出前與合併前各跑一次 |
