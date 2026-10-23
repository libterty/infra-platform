# 範本 example3：example2 的 EKS 版

> 改寫中：這份目前是 example2 的原樣複本，ECS 會照 [`docs/design/v4/`](../../../docs/design/v4/design-docs.md) 逐步換成 EKS（進度見 [`implement-process.md`](../../../docs/design/v4/implement-process.md)）。下面的內容在改完之前仍是 example2 的說明。
>
> 狀態：11 個 stack 都已完成，離線驗證通過（`scripts/validate.sh`）；還沒有在真實帳號 apply 過，「已知限制」列的推論都要在第一次 apply 時確認。設計見 [`docs/design/v2/design-docs.md`](../../../docs/design/v2/design-docs.md) 第 5 章。

這份範本把一個專案拆成 11 個 Terraform stack，示範跟 `templates/project-infra` 不同的拆法：資料庫、IAM、ALB、AgentCore、ECS、bastion 與告警各自獨立，stack 之間只透過 SSM Parameter Store 傳值。完成後，stack 本身只呼叫 registry 的 module，唯一自己宣告的 AWS resource 是 `foundation` 的 Secrets Manager secret 容器。

## 目錄

```
infra/
├── README.md
└── terraform/
    ├── stacks.sh                # 依序跑各 stack
    ├── check-ssm-contract.sh    # 靜態檢查 SSM 合約與 tfvars 一致性
    ├── containerimage/          # ECR
    ├── foundation/              # 告警 SNS、secret 容器
    ├── network/                 # VPC、subnet、security group、可選的 VPC peering
    ├── database/                # Aurora PostgreSQL、RDS Proxy、Redis
    ├── iam/                     # 各服務與 Runtime 的 role
    ├── bridge/                  # 把樹 A 轉寫成樹 B
    ├── loadbalancer/            # ALB、WAF
    ├── agent/                   # Bedrock guardrail、AgentCore
    ├── application/             # ECS cluster、服務、autoscaling
    ├── operation/               # bastion、Lambda、bucket
    └── postdeploy/              # 服務告警與 dashboard
```

每個 stack 都有同一組檔案：

| 檔案 | 用途 |
|---|---|
| `versions.tf`、`providers.tf` | Terraform 與 provider 版本、空的 `backend "s3" {}`、`allowed_account_ids`、`default_tags`（含 `Stack`） |
| `common.tf` | `project`、`env`、`aws_region`、`expected_account_id`、帳號對照表、各種前綴。11 個 stack 必須一字不差，`scripts/validate.sh` 會比對 |
| `variables.tf` | 這個 stack 自己的變數，不放其他 stack 的 ARN 或 id |
| `ssm-inputs.tf`、`ssm-outputs.tf` | 讀上游值、發布給下游的值。沒有東西要讀或發布的 stack 沒有對應的檔案 |
| `envs/<env>.tfvars`、`envs/<env>.tfbackend` | 非機密設定與 state 位置，都進版控；佔位值，複製後要改 |
| `tests/` | `terraform test`，全部用 mock provider，不需要任何 AWS 憑證 |
| `.terraform.lock.hcl` | 進版控 |

### 各 stack 建什麼

| stack | 建的東西 |
|---|---|
| `containerimage` | ECR repository：`api`、`worker`、`import-extract`、`import-load`、`agent`。名稱是 `<project>-<image>`，不帶 env；兩個 env 共用同一個帳號時，一邊建、另一邊設 `adopt_existing = true` 沿用 |
| `foundation` | 告警 SNS topic（只有 email 訂閱）、簽章 key 的兩個 secret 容器（值在 Terraform 外面寫） |
| `network` | VPC 四層 subnet（public、app、agent、db）、NAT（每個 AZ 一個，或關閉）、S3 gateway endpoint、Bedrock interface endpoint、所有 security group、可選的 VPC peering、NAT 告警 |
| `database` | Aurora PostgreSQL（含 RDS Proxy、Enhanced Monitoring）、兩組 Redis（`rate-limit`、`stream`）、連線數告警、partition 維護的 log 告警 |
| `iam` | ECS、Lambda、AgentCore 各 role 與 policy；`eval_batch` role 只在 `dev` 建 |
| `bridge` | 把樹 A 的 key 原樣寫到樹 B，不建其他東西 |
| `loadbalancer` | ALB、listener 規則、WAF 與 WAF log、ALB access log（bucket 與 `log-delivery`） |
| `agent` | Bedrock guardrail、AgentCore Runtime 與 Memory、Runtime 的 log delivery |
| `application` | ECS cluster、`api` 與 `worker` 服務、autoscaling |
| `operation` | bastion（可關）、兩個 import Lambda、import bucket、eval-batch bucket（只在 `dev`）、ETL 指標 |
| `postdeploy` | 服務告警與 dashboard、stream 告警、log 告警、trace delivery；四個功能各有開關 |

環境只有 `dev` 與 `sit`。帳號對照表在 `common.tf` 的 `accounts_by_env`，`state` bucket 在 `.tfbackend` 裡是 `<state-bucket>`，複製出去後換成真正的 bucket。

## apply 順序

依賴是單向的：下游只讀上游發布的 key。apply 照下表由上往下，destroy 反過來。順序只定義在 `stacks.sh` 的 `ORDER`，`check-ssm-contract.sh` 也從那裡讀。

| 順序 | stack | 讀 | 發布 |
|---|---|---|---|
| 1 | `containerimage` | 無 | 服務清單、Runtime 清單、ECR URL 與 ARN |
| 2 | `foundation` | 無 | 告警 topic、secret ARN |
| 3 | `network` | foundation | VPC、各層 subnet、各 security group、peering |
| 4 | `database` | foundation、network | 資料庫與 Proxy endpoint、secret ARN、Redis endpoint |
| 5 | `iam` | foundation、containerimage、database | 各 role ARN |
| 6 | `bridge` | 前面所有 stack（樹 A） | 樹 B |
| 7 | `eks-cluster` | 樹 B | 版本化的 EKS 合約：叢集名稱、endpoint、CA、cluster SG、service CIDR、app namespace 與 ServiceAccount 名稱 |
| 8 | `eks-addons` | eks-cluster、樹 B | 不發布；Auto Mode 的 NodeClass 與 NodePool、NetworkPolicy、LB Controller、KEDA、CloudWatch 採集、app namespace。要從 VPC 或可連通的網路執行 |
| 9 | `loadbalancer` | 樹 B | ALB 與 target group 的識別、完整的 target group ARN、WAF 名稱；開了 canary 時另外發布 `api_canary_target_group_arn` |
| 10 | `agent` | 樹 B | Runtime 的 ARN、Memory 的 id 與 ARN、guardrail 的 id |
| 11 | `application` | 樹 B、loadbalancer、agent | 不建資源；部署合約（port、VPC CIDR、api target group、image repository、環境變數與擴縮的 JSON）與 stream 長度上限 |
| 12 | `operation` | 樹 B | bucket、Lambda 名稱 |
| 13 | `postdeploy` | 樹 B、eks-cluster、loadbalancer、application、agent | 不發布；四個功能各有開關，預設全關 |

實際的 key 以各 stack 的 `ssm-inputs.tf`、`ssm-outputs.tf` 為準。

## SSM 合約：樹 A 與樹 B

- **樹 A**：`/<project>/<env>/<stack>/<key>`。前段 stack 與 loadbalancer、agent、application 發布到這裡，下游用 `ssm-read` 讀。
- **樹 B**：`/<project>-shared/<env>/infra/<key>`，一個共用前綴底下的扁平 key。loadbalancer、agent、application、operation、postdeploy 只讀樹 B（外加其他後段 stack 的樹 A key），不直接讀前段 stack。這樣樹 B 改由外部發布時，後段 stack 照樣能跑。

樹 B 由誰寫：

- 預設由 `bridge` stack 讀樹 A 再寫過去（`ssm_prefix = local.shared_ssm_prefix`、`stack = "infra"`）。
- 列在 `stacks.sh` 的 `EXTERNAL_SHARED_ENVS` 裡的 env，樹 B 由外部發布：`stacks.sh <env> all` 自動跳過 `bridge`，單獨指定 `bridge` 會報錯。外部要發布的 key 見下表，名稱、型別（String 或 StringList）都要一致。`EXTERNAL_SHARED_ENVS` 預設是空的，所有 env 都跑 `bridge`。

### 樹 B 的 key 合約（給外部發布者）

`/<project>-shared/<env>/infra/<key>` 底下要有下面 33 個 key。少了任何一個，讀它的後段 stack 在 plan 就會失敗。不在表裡的 key 不需要發布。值的來源是樹 A 的同名 key（`bridge` 原樣轉寫）。

String（28 個，值不可為空）：

| key | 內容 | 讀的 stack |
|---|---|---|
| `alarm_topic_arn` | 告警 SNS topic ARN | loadbalancer、postdeploy |
| `signing_private_key_secret_arn` | 簽章 private key 的 secret ARN | application |
| `signing_public_key_secret_arn` | 簽章 public key 的 secret ARN | application |
| `agent_runtimes` | JSON 陣列，Runtime 名稱 | agent |
| `ecr_repository_urls` | JSON 物件，映像名稱 => repository URL | loadbalancer、agent、application、operation |
| `vpc_id` | VPC id | eks-addons、loadbalancer、application |
| `alb_sg_id` | ALB 的 security group | loadbalancer |
| `app_sg_id` | app 層的 security group | eks-addons、operation |
| `agent_sg_id` | agent 層的 security group | agent |
| `bastion_sg_id` | bastion 的 security group | operation |
| `db_proxy_endpoint` | RDS Proxy endpoint | agent、application、operation |
| `db_secret_arn` | 資料庫 secret ARN | agent、application、operation |
| `db_name` | 資料庫名稱 | agent、application、operation |
| `rate_limit_redis_endpoint` | `host:port` | application |
| `stream_redis_endpoint` | `host:port` | application |
| `stream_shard_count` | stream Redis 的 shard 數（字串） | application |
| `import_extract_role_arn` | import-extract Lambda role | operation |
| `import_load_role_arn` | import-load Lambda role | operation |
| `agent_runtime_role_arn` | AgentCore Runtime role | agent |
| `eks_api_sg_id` | 控制平面 ENI 的 security group | eks-cluster |
| `eks_cluster_role_arn` | EKS 叢集 role | eks-cluster |
| `eks_node_role_arn` | Auto Mode node role | eks-cluster、eks-addons |
| `api_pod_role_arn` | api 的 Pod Identity role | eks-cluster |
| `worker_pod_role_arn` | worker 的 Pod Identity role | eks-cluster |
| `lb_controller_role_arn` | AWS Load Balancer Controller 的 role | eks-cluster |
| `keda_role_arn` | KEDA operator 的 role | eks-cluster |
| `cloudwatch_agent_role_arn` | CloudWatch agent 與 Fluent Bit 的 role | eks-cluster |
| `node_sg_id` | EKS node 的 security group | eks-addons |

StringList（5 個，逗號分隔）：

| key | 內容 | 讀的 stack |
|---|---|---|
| `services` | 服務名稱 | application |
| `public_subnet_ids` | public subnet，至少 2 個 | loadbalancer |
| `app_subnet_ids` | app subnet，至少 2 個 | eks-cluster、operation |
| `agent_subnet_ids` | agent subnet，至少 2 個 | agent |
| `app_subnet_cidrs` | app subnet 的 CIDR（控制平面 ENI 與 interface endpoint 所在） | eks-addons |

`bridge` 在 apply 前用 `guards.tf` 檢查：String 不可為空、`*_subnet_ids` 至少 2 個、`agent_runtimes` 與 `ecr_repository_urls` 是合法 JSON。外部發布者也應該照這幾條驗過再寫。

### 合約的寫法慣例

`check-ssm-contract.sh` 用 grep 與 awk 解析 HCL 的固定寫法，所以要照下面的格式寫，不然它看不到。

讀（`<stack>/ssm-inputs.tf`）：在 `locals` 裡用四個固定名稱的 map，每個 key 一行，值是 `"<stack>/<key>"`。每個 map 必須是多行的 `= {` 開頭；空的 map 直接不寫。

```hcl
locals {
  ssm_input_strings = {            # 樹 A，String
    alarm_topic_arn = "foundation/alarm_topic_arn"
  }
  ssm_input_lists = {              # 樹 A，StringList
    db_subnet_ids = "network/db_subnet_ids"
  }
  shared_input_strings = {         # 樹 B，String；stack 段固定是 infra
    vpc_id = "infra/vpc_id"
  }
  shared_input_lists = {           # 樹 B，StringList
    app_subnet_ids = "infra/app_subnet_ids"
  }
}
```

`module "in"` 讀樹 A（`ssm_prefix = local.ssm_prefix`），`module "shared"` 讀樹 B（`ssm_prefix = local.shared_ssm_prefix`）。

發布（`<stack>/ssm-outputs.tf`）：`locals` 的 `published_strings`、`published_lists`，map 的 key 就是發布的 key，每個 key 從行首開始、`=` 前面沒有其他東西；值可以跨多行，但值裡的大括號要成對。

```hcl
locals {
  published_strings = {
    alarm_topic_arn = module.alarm_topic.topic_arn
  }
  published_lists = {}
}
```

骨架階段（B2）還沒有資源可以接，所以 `ssm-outputs.tf` 只有 `# planned_strings: <key>...` 與 `# planned_lists: <key>...` 註解行，列出打算發布的 key；`check-ssm-contract.sh` 把它們當成已發布。加上 `module "ssm_publish"` 與 `published_*` 時，同一個 PR 把註解行換掉，不要兩種並存。

## check-ssm-contract.sh

```bash
bash infra/terraform/check-ssm-contract.sh
```

這支腳本只檢查下面兩件事。其他規則（`common.tf` 一致、`data "aws_ssm_parameter"` 的位置、tfbackend 的 key）由 `scripts/validate.sh` 負責，`validate.sh` 也會呼叫這支腳本。

1. 每個被讀取的 `<stack>/<key>`：發布它的 stack 在 `ORDER` 裡排在讀它的 stack 前面，真的有發布這個 key，而且型別（strings 或 lists）相同。樹 B 的 `infra/<key>` 對應到 `bridge`。
2. 同一個 env 裡，各 stack 的 tfvars 在 `SHARED_CONFIG_KEYS`（`project`、`env`、`aws_region`、`expected_account_id`、`deploy_role_arn`、`bastion_enabled`、`guardrail_cross_region_profile_id`）上的值一致，而且 `env` 等於檔名。沒設某個 key 的 stack 不參與比對，所以 `bastion_enabled` 只比對 network 與 operation，`guardrail_cross_region_profile_id` 只比對 iam 與 agent。

出錯時，訊息會指出是哪個 stack 的哪個 key。

## stacks.sh

```bash
cd infra/terraform
./stacks.sh <env> <stack|all> <init|validate|plan|apply|destroy|output> [--yes] [--dry-run] [-- <terraform 參數>...]
```

- env 檔從 `<stack>/envs/<env>.tfvars`、`<stack>/envs/<env>.tfbackend` 讀。
- `TF_DATA_DIR=.terraform-<env>`，`init` 一律 `-reconfigure`。
- `validate` 做 `init -backend=false -lockfile=readonly` 再 `validate`，用另一個 data directory `.terraform-<env>-validate`，不會蓋掉 `init` 留下的 backend 設定，**也不會改 `.terraform.lock.hcl`**：lock 對不上就失敗，不會悄悄重寫。
- `all` 依 `ORDER` 跑，`destroy all` 反向；任何一個 stack 失敗就停。
- `--yes` 讓 `apply`、`destroy` 加 `-auto-approve`；`--dry-run` 只印指令、不執行 terraform，換環境或動手前先看一次最安全。
- `--` 之後的參數原樣交給 `plan`、`apply`、`destroy`、`output`。
- `EXTERNAL_SHARED_ENVS` 是 `stacks.sh` 開頭的 bash 陣列，不是環境變數。要讓某個 env 的樹 B 改由外部發布，把 env 名稱加進去，例如 `EXTERNAL_SHARED_ENVS=(sit)`；`check-ssm-contract.sh` 不看這個陣列，檢查時仍把 `bridge` 當成樹 B 的生產端。

```bash
cd infra/terraform
./stacks.sh dev all plan --dry-run        # 只看會跑哪些指令
./stacks.sh dev network plan              # 單一 stack
./stacks.sh dev all apply --yes           # 依序 apply，不再詢問
./stacks.sh dev all destroy               # 反向 destroy，先看下面「destroy 之前」
```

## 不進 tfvars 的值

`loadbalancer` 的 origin verify 值（CDN 加在 origin 請求上的 header 值）只能從環境變數給：`export TF_VAR_origin_verify_header_value=<至少 16 字元>`，跟 CDN 送的是同一個值。tfvars 只放 header 名稱；變數是 `sensitive`、沒有預設值，所以少了它 plan 直接失敗。這個值會寫進 state（ALB 規則的條件），state 的存取權限要照機密管。WAF log 會遮蔽這個 header。

## 環境切換

手打 `terraform` 時，環境由四個彼此獨立的選擇決定：AWS 身分（`aws-vault exec <profile> --`）、backend（`-backend-config=envs/<env>.tfbackend`）、變數（`-var-file=envs/<env>.tfvars`）、工作目錄（`TF_DATA_DIR=.terraform-<env>`）。`stacks.sh` 把後三個綁在一起，只剩 AWS 身分要自己換；`allowed_account_ids` 會擋下打到錯的帳號。

## 複製出去之後要改什麼

範本裡的值都是佔位，複製到專案 repo 後照下面順序改：

1. **module 的 `source`**：從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）。用自己的 organization 就換掉這段前綴；拿不到 HCP token 時改成 `git::...?ref=<module>-v<semver>`。一次改完的指令見 `docs/guides/consuming-modules.md`。
2. **帳號表**：`common.tf` 的 `accounts_by_env` 目前是 `111111111111`（dev）與 `222222222222`（sit）。填真實帳號，11 個 stack 同步改，保持一字不差。
3. **state bucket**：每份 `envs/*.tfbackend` 的 `bucket` 是 `<state-bucket>`，換成真實 bucket；`key` 的 `example-` 前綴換成自己的 `project`（格式 `<project>-<env>/<stack>/terraform.tfstate`，`validate.sh` 會檢查）。
4. **tfvars 的佔位值**：每份 `envs/*.tfvars` 的 `project`、`expected_account_id`，以及：
   - `foundation`：`alarm_emails`（現在是 `ops@example.com`）。
   - `network`：`vpc_cidr`、`azs`、`alb_ingress`（現在是文件用的 `203.0.113.0/24`）。
   - `loadbalancer`：`origin_verify_host_headers`、`rate_limit_allowlist_cidrs`（現在是 `198.51.100.0/24`）。
   - `application`：`cors_allow_origins`、各映像的 `*_image_tag`；`operation` 與 `agent` 也有映像 tag。
   - `database`：`db_instance_class`、`connections_threshold`（約為該 instance class 的 `max_connections` 的 80%，換 class 就要重算）、Redis 的 node type。
   - `agent`：`model_id`、`backend_mode`（目前是 `fake`）、`guardrail_cross_region_profile_id`。
5. **origin verify 的值**：不放 tfvars。`export TF_VAR_origin_verify_header_value=<至少 16 字元>`，見上面「不進 tfvars 的值」。
6. **guardrail 的內容**：`agent/guardrails.tf` 的 denied topic、詞彙、拒絕文案都只是示意，換成自己產品的政策。module 不建 guardrail 版本，apply 的內容就是線上生效的政策。
7. **命名規則**：`iam` 比後段 stack 先 apply，讀不到資源，所以用命名規則組 ARN。兩邊是否一致沒有東西檢查，只有各 stack 的 test 會斷言。改任何一邊的名稱，另一邊要一起改：
   - import bucket：`<project>-<env>-import-<account>`，prefix `incoming/`、`extracted/`；eval-batch bucket：`<project>-<env>-eval-batch-<account>`（`operation`）。
   - Lambda log group：`/aws/lambda/<project>-<env>-import-extract`、`-import-load`（`operation`）。
   - ECS log group：`/ecs/<project>-<env>-*`（`application`）。
   - AgentCore Runtime 與 Memory：`<project>_<env>_<runtime>`、`<project>_<env>_memory`，連字號換成底線（`agent`）。
   - 自訂 metric namespace：`<Project>/<env>`（`application`、`operation`、`postdeploy`）。
   - 設計依據見 `docs/design/v2/design-docs.md` §5.8、§5.10。
8. **`SHARED_CONFIG_KEYS`**：`network` 與 `operation` 的 `bastion_enabled` 要一致，`iam` 與 `agent` 的 `guardrail_cross_region_profile_id` 要一致；`check-ssm-contract.sh` 會比對。`app_port` 在 `network`、`loadbalancer`、`application` 各有一份變數，靠預設值一致，改的時候三處一起改，沒有東西檢查。

## destroy 之前

`stacks.sh <env> all destroy` 會依反向順序跑，但遇到下面幾種情況會停下來，要先處理（預設值取自各 module 與 stack）：

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| Aurora cluster（`database`） | `deletion_protection = true`；`skip_final_snapshot = false`，會留 final snapshot | 先把 `deletion_protection = false` apply 進去，再 destroy。不要 final snapshot 就同時設 `skip_final_snapshot = true`（`dev.tfvars` 就是這樣設） |
| ALB（`loadbalancer`） | `deletion_protection = true` | 同上，先 apply `deletion_protection = false` |
| ECR repository（`containerimage`） | module 固定 `force_delete = false` | repository 裡有映像會刪不掉，先清空映像；沿用既有 repository 的 env 不會建它，也不會刪它 |
| S3 bucket（`operation` 的 import 與 eval-batch bucket、`loadbalancer` 的 access log bucket） | `force_destroy = false` | bucket 不是空的會刪不掉。先清空（含舊版本與刪除標記），確認資料不需要再刪 |
| Secrets Manager secret（`foundation`） | `recovery_window_in_days = 7` | 刪除後保留 7 天，期間不能用同名重建；secret 的值是在 Terraform 外面寫的，刪了就沒有，要先備份 |
| Redis（`database`） | module 沒有設定 final snapshot | 要保留資料就先手動做 snapshot |

`bridge` 之後的 stack（7–13）只依賴樹 B，所以要先 destroy 它們，再 destroy `bridge`。`stacks.sh` 的反向順序已經照這樣排；單獨 destroy 某個 stack 時要自己注意順序。destroy 不會刪掉不是這份範本建的東西（外部發布的樹 B、state bucket 本身）。

## 已知限制

下面都是 mock 驗不到的推論，沒有在真實帳號驗證過，第一次 apply 時要逐項確認。完整清單與理由見 `docs/design/v2/design-docs.md` §5.8、§5.10。

- **IAM 與 policy 的形狀**：RDS Proxy role 的 `kms:Decrypt` 限定 `alias/aws/secretsmanager` 的 key 加 `kms:ViaService` 是否足夠（那個 alias 要先有人用預設 key 建過 secret 才存在，`foundation` 先 apply 所以成立）；Enhanced Monitoring role 收窄到 `RDSOSMetrics` log group 是否足夠；AgentCore Runtime role 的 `aws:SourceArn` 與 `runtime/<name>-*`、`memory/<name>-*` 的 ARN 形狀；bastion 的 Session Manager 最小權限是否足夠註冊與開 session。
- **ALB 與 WAF**：`alb` 的 count 依 Web ACL 物件是否為 null 決定，沒有對真實 provider 跑過；ALB access log 改用 `log-delivery` 的 vended delivery，`depends_on` 是否足以讓 bucket policy 在建 delivery 之前到位，以及 apply 身分建 delivery 需要的權限（`logs:PutDeliverySource` 等）；WAF logging 需要 apply 身分有 `logs:PutResourcePolicy`。
- **AgentCore 與 Bedrock**：`/aws/vendedlogs/...` 當 log delivery 的目的地、Runtime 的 `APPLICATION_LOGS` delivery 能否建立；Runtime 的預設 log group 授權與實際行為可能不一致；guardrail 的 `STANDARD` tier 加 cross-region profile 的實際行為。
- **網路**：沒有 NAT 時，app 與 agent 還缺 ECR、CloudWatch Logs、Secrets Manager 的 interface endpoint（`network` 只建 Bedrock 的三個）；Lambda 放進 VPC 後，只靠 app security group 與 NAT 或 endpoint 的出口能否呼叫 Bedrock、S3、Secrets Manager。
- **S3 通知**：`incoming/`（無後綴）與 `extracted/` 加 `ready.json` 不重疊，S3 在 apply 時才會驗。
- **autoscaling**：連線數的 step policy 用 metric math，`ecs-service` 的 `queries` 欄位是否被 provider 接受。
- **跟應用程式的約定**：pg_cron 的 log 告警靠 SQL 寫出 `partition_maintenance_failed`、`partition_maintenance_heartbeat`、`default_partition_not_empty` 三個字串；import-load 由 `extracted/` 加 `ready.json` 後綴觸發，`ready.json` 由 import-extract 寫。這兩項沒有東西檢查。
- **技術債**：`bastion_enabled`、`guardrail_cross_region_profile_id` 的一致性檢查沒有自動化 fixture；`ecs-service-alarms` 的 dashboard 與告警綁在同一個 module 呼叫，無法只開 dashboard。

## 驗證

```bash
scripts/validate.sh templates/example3/infra/terraform
```

做 `fmt`、靜態規則（含 lock 檔每個 provider 要有 darwin 與 linux 兩個 `h1:` hash 的 S10）、`check-ssm-contract.sh`、`bash -n` 與 shellcheck，然後每個 stack 跑 `init -backend=false`、`validate`、`terraform test`，並對 `dev`、`sit` 兩份 tfvars 各跑一次 `tests/tfvars`。全部離線，不需要 AWS 憑證；stack 從 HCP private registry 抓 module，需要 registry token。
