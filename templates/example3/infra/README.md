# 範本 example3：example2 的 EKS 版

> 狀態：13 個 stack、範例 chart 與部署腳本都已完成，離線驗證通過（`scripts/validate.sh`，見文末〈驗證〉）。還沒有在真實帳號或叢集 apply 過；〈驗證〉的「雲端整合待驗證」表與〈已知限制〉列的事，第一次 apply 時要逐項確認。設計見 [`docs/design/v4/design-docs.md`](../../../docs/design/v4/design-docs.md)，實作紀錄見 [`implement-process.md`](../../../docs/design/v4/implement-process.md)。

這份範本跟 [`templates/example2`](../../example2/infra/README.md) 是同一個專案，api 與 worker 改跑在 EKS Auto Mode 上。其他部分（資料庫、AgentCore、bastion、Lambda、告警）沿用 example2：一個專案拆成 13 個 Terraform stack，stack 之間只透過 SSM Parameter Store 傳值，stack 本身只呼叫 registry 的 module，唯一自己宣告的 AWS resource 是 `foundation` 的 Secrets Manager secret 容器。

api 與 worker 不由 Terraform 部署。Terraform 準備好叢集、namespace、Pod Identity、target group，把部署需要的值寫進 SSM；CI 用 [`deploy/values-from-ssm.sh`](../deploy/values-from-ssm.sh) 讀 SSM，再用 Helm 部署 [`deploy/charts/app`](../deploy/charts/app)。

## 跟 example2 的差異

| 部分 | example2 | example3 |
|---|---|---|
| api、worker 跑在哪 | ECS Fargate，`application` 建 cluster 與 service | EKS Auto Mode。`eks-cluster` 建叢集，`eks-addons` 裝平台元件，CI 用 Helm 部署 |
| pod 的 AWS 權限 | ECS task role、execution role、ECS Exec | Pod Identity（`api_pod`、`worker_pod` role），沒有 ECS Exec；`kubectl exec` 由 access entry 管 |
| 網路 | task 掛 `app` SG | NodeClass 層級的 Pod SG（同一個 `app` SG）、node 另掛 `node` SG、NetworkPolicy `DefaultDeny` |
| ALB 與 target group | ECS service 註冊進 `api` target group | Terraform 仍擁有 ALB 與 target group，pod 由 AWS Load Balancer Controller 的 TargetGroupBinding 註冊 |
| 擴縮 | ECS target tracking、step scaling、排程 | KEDA：api 看 CPU、每個 target 的請求數、連線數；worker 看 stream backlog。沒有排程擴縮 |
| 告警 | `ecs-service-alarms`（含 dashboard、到達上限） | `eks-workload-alarms`（Ready 低於期望、CrashLoop、重啟、Pending、OOM、ALB），沒有 dashboard |
| log | `/ecs/<project>-<env>-*` | Container Insights 的 `/aws/containerinsights/<cluster>/application` |
| image tag | tfvars，Terraform 部署 | CI 決定，`values-from-ssm.sh --image-tag` |
| canary | 沒有 | `loadbalancer` 的 `canary`（預設關閉）與斷路器 |

## 目錄

```
templates/example3/
├── deploy/
│   ├── values-from-ssm.sh       # SSM 部署合約 → chart 的 values
│   └── charts/app/              # api、worker 的範例 chart，一個 release 一個工作負載
└── infra/
    ├── README.md
    └── terraform/
        ├── stacks.sh                # 依序跑各 stack
        ├── check-ssm-contract.sh    # 靜態檢查 SSM 合約與 tfvars 一致性
        ├── containerimage/          # ECR
        ├── foundation/              # 告警 SNS、secret 容器
        ├── network/                 # VPC、subnet、security group、endpoint、可選的 VPC peering
        ├── database/                # Aurora PostgreSQL、RDS Proxy、Redis
        ├── iam/                     # Lambda、Runtime 與 EKS 的 role
        ├── bridge/                  # 把樹 A 轉寫成樹 B
        ├── eks-cluster/             # EKS 叢集、access entry、Pod Identity、EKS 合約
        ├── eks-addons/              # NodeClass／NodePool、NetworkPolicy、LB Controller、KEDA、CloudWatch 採集
        ├── loadbalancer/            # ALB、WAF、可選的 canary 與斷路器
        ├── agent/                   # Bedrock guardrail、AgentCore
        ├── application/             # 部署合約（不建資源）
        ├── operation/               # bastion、Lambda、bucket
        └── postdeploy/              # 工作負載、stream、log 告警與 trace
```

每個 stack 都有同一組檔案：

| 檔案 | 用途 |
|---|---|
| `versions.tf`、`providers.tf` | Terraform 與 provider 版本、空的 `backend "s3" {}`、`allowed_account_ids`、`default_tags`（含 `Stack`）。`eks-addons` 另有 helm provider |
| `common.tf` | `project`、`env`、`aws_region`、`expected_account_id`、帳號對照表、各種前綴。13 個 stack 必須一字不差，`scripts/validate.sh` 會比對 |
| `variables.tf` | 這個 stack 自己的變數，不放其他 stack 的 ARN 或 id |
| `ssm-inputs.tf`、`ssm-outputs.tf` | 讀上游值、發布給下游的值。沒有東西要讀或發布的 stack 沒有對應的檔案 |
| `envs/<env>.tfvars`、`envs/<env>.tfbackend` | 非機密設定與 state 位置，都進版控；佔位值，複製後要改 |
| `tests/` | `terraform test`，全部用 mock provider，不需要任何 AWS 憑證；`application` 另有 `check-deploy-values.sh` |
| `.terraform.lock.hcl` | 進版控，每個 provider 都有 darwin 與 linux 的 hash |

### 各 stack 建什麼

| stack | 建的東西 |
|---|---|
| `containerimage` | ECR repository：`api`、`worker`、`import-extract`、`import-load`、`traffic-breaker`、`agent`。名稱是 `<project>-<image>`，不帶 env；兩個 env 共用同一個帳號時，一邊建、另一邊設 `adopt_existing = true` 沿用 |
| `foundation` | 告警 SNS topic（只有 email 訂閱）、簽章 key 的兩個 secret 容器（值在 Terraform 外面寫） |
| `network` | VPC 四層 subnet（public、app、agent、db），app subnet 帶 NodeClass 用的 `eks-node`、`eks-pod` tag；NAT（每個 AZ 一個，或關閉）、S3 gateway endpoint、Bedrock interface endpoint，沒有 NAT 時再加 EKS 需要的 endpoint；所有 security group（含 `node`、`eks_api`）、可選的 VPC peering、NAT 告警 |
| `database` | Aurora PostgreSQL（含 RDS Proxy、Enhanced Monitoring）、兩組 Redis（`rate-limit`、`stream`）、連線數告警、partition 維護的 log 告警 |
| `iam` | Lambda 與 AgentCore 的 role；EKS 的叢集、node、api、worker、LB Controller、KEDA、CloudWatch 採集 7 個 role；`eval_batch` role 只在 `dev` 建 |
| `bridge` | 把樹 A 的 key 原樣寫到樹 B，不建其他東西 |
| `eks-cluster` | EKS 叢集（只有 private endpoint、Auto Mode 不用內建 NodePool）、secrets 加密的 KMS key、access entry、Pod Identity association |
| `eks-addons` | `app` 與 `system` 兩組 NodeClass／NodePool、NetworkPolicy controller 與 `system` 的 NetworkPolicy、AWS Load Balancer Controller、KEDA、CloudWatch 採集（Container Insights 與 Fluent Bit）、app namespace、CRD 權限併進 edit |
| `loadbalancer` | ALB、listener 規則、WAF 與 WAF log、ALB access log（bucket 與 `log-delivery`）；設了 `canary` 才有第二個 target group、加權 rule 與斷路器 |
| `agent` | Bedrock guardrail、AgentCore Runtime 與 Memory、Runtime 的 log delivery |
| `application` | 不建資源，只發布部署合約 |
| `operation` | bastion（可關）、兩個 import Lambda、import bucket、eval-batch bucket（只在 `dev`）、ETL 指標 |
| `postdeploy` | 工作負載告警、stream 告警、log 告警、trace delivery；四個功能各有開關 |

環境只有 `dev` 與 `sit`。帳號對照表在 `common.tf` 的 `accounts_by_env`，`state` bucket 在 `.tfbackend` 裡是 `<state-bucket>`，複製出去後換成真正的 bucket。

## apply 順序

依賴是單向的：下游只讀上游發布的 key。apply 照下表由上往下，destroy 反過來。順序只定義在 `stacks.sh` 的 `ORDER`，`check-ssm-contract.sh` 也從那裡讀。

| 順序 | stack | 讀 | 發布 |
|---|---|---|---|
| 1 | `containerimage` | 無 | 服務清單、Runtime 清單、ECR URL 與 ARN |
| 2 | `foundation` | 無 | 告警 topic、secret ARN |
| 3 | `network` | foundation | VPC、各層 subnet 與 CIDR、各 security group、peering |
| 4 | `database` | foundation、network | 資料庫與 Proxy endpoint、secret ARN、Redis endpoint |
| 5 | `iam` | foundation、containerimage、database | 各 role ARN |
| 6 | `bridge` | 前面所有 stack（樹 A） | 樹 B |
| 7 | `eks-cluster` | 樹 B | 版本化的 EKS 合約（見〈EKS 合約〉） |
| 8 | `eks-addons` | eks-cluster、樹 B | 不發布。要從 VPC 或可連通的網路執行（見〈執行環境〉） |
| 9 | `loadbalancer` | 樹 B | ALB 與 target group 的識別、完整的 target group ARN、WAF 名稱；開了 canary 時另外發布 `api_canary_target_group_arn` |
| 10 | `agent` | 樹 B | Runtime 的 ARN、Memory 的 id 與 ARN、guardrail 的 id |
| 11 | `application` | 樹 B、loadbalancer、agent | 部署合約與 stream 長度上限（見〈部署合約〉） |
| 12 | `operation` | 樹 B | bucket、Lambda 名稱 |
| 13 | `postdeploy` | 樹 B、eks-cluster、loadbalancer、application、agent | 不發布；四個功能各有開關，預設全關 |

`application` 之後、`postdeploy` 之前，CI 要先部署一次 api 與 worker（見〈部署〉）：`postdeploy` 的 log 告警要等 Container Insights 的 log group 存在。

`eks-cluster` 排在 `bridge` 之後只是這份範本自己的順序，不是限制：叢集另外發布版本化的 EKS 合約，其他專案要共用這個叢集時直接讀那組 key。

實際的 key 以各 stack 的 `ssm-inputs.tf`、`ssm-outputs.tf` 為準。

## 執行環境

叢集只有 private endpoint，所以要呼叫 Kubernetes API 的操作要在 VPC 或可連通的網路裡跑。範本不建 runner。

| 操作 | 在哪裡執行 |
|---|---|
| `eks-addons` 的 apply、CI 的 Helm 部署 | VPC 或可連通的網路（self-hosted runner、VPC 內的 CodeBuild、VPN、bastion） |
| 其他 stack（含 `eks-cluster`） | 任何能呼叫 AWS API 的地方，跟 example2 相同 |

VPC 或可連通的網路要滿足：

- **DNS**：能解析叢集的 private endpoint。在 VPC 內用 VPC 的 resolver；在 VPC 外要有 Route 53 Resolver inbound endpoint 或等效的轉發。
- **路由**：到 app subnet（控制平面 ENI 所在）的路由。
- **SG**：`network` 的 `k8s_api_sources` 列出 runner 的 SG 或 CIDR，`eks_api` SG 只放行這些來源的 443。預設是空的，也就是誰都連不到。
- **AWS 權限**：`eks:DescribeCluster`，以及產生 token 用的 STS 呼叫。
- **Kubernetes 授權**：`eks-cluster` 的 access entry。跑 `eks-addons` 的身分必須是 `addons_apply_principal_arn`（叢集管理者）；CI 是 `ci_deploy_principal_arn`，只有 `app_namespace` 的 `AmazonEKSEditPolicy`。`eks-addons` 的 `deploy_role_arn` 有值時，helm provider 的 `aws eks get-token` 會帶 `--role-arn`。
- **chart 來源**：`eks-addons` 要能從網路抓 LB Controller、KEDA、CloudWatch observability 的 chart（`aws.github.io`、`kedacore.github.io`、`aws-observability.github.io`）。完全沒有對外連線時，要在 `eks-addons` stack 傳 module 的 `chart_repository_overrides`，指到內部的 mirror。

另外兩個 apply 身分要的權限：

- `eks-cluster`：EKS 用 apply 身分建立 secrets 加密的 KMS grant，這個身分要有那把 key 的 `kms:CreateGrant`、`kms:DescribeKey`（key policy 有帳號 root 的 statement，用 IAM 給就好）。
- `loadbalancer` 開了斷路器時：建 Lambda、IAM role 與 CloudWatch alarm 的權限。

## SSM 合約：樹 A 與樹 B

- **樹 A**：`/<project>/<env>/<stack>/<key>`。前段 stack 與 eks-cluster、loadbalancer、agent、application 發布到這裡，下游用 `ssm-read` 讀。
- **樹 B**：`/<project>-shared/<env>/infra/<key>`，一個共用前綴底下的扁平 key。`bridge` 之後的 stack 只讀樹 B（外加其他後段 stack 的樹 A key），不直接讀前段 stack。這樣樹 B 改由外部發布時，後段 stack 照樣能跑。

Type 只有 `String` 與 `StringList`，沒有 `SecureString`：secret 都在 Secrets Manager，SSM 只放 ARN。JSON 是 `String` 裡的內容格式，欄位由發布它的 stack 的 `terraform test` 以 `jsondecode` 斷言。

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
| `app_sg_id` | app 層的 security group（也是 Pod SG） | eks-addons、operation |
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

### EKS 合約

`/<project>/<env>/eks-cluster/<key>`，全部是 String。其他專案要共用這個叢集時讀這組 key，不必經過 `bridge`。

| key | 內容 |
|---|---|
| `contract_version` | 目前是 `1`。拿掉 key 或改變意義才升版，加 key 不升；`eks-addons` 與 `values-from-ssm.sh` 遇到不認得的版本直接失敗 |
| `cluster_name` | 叢集名稱，固定是 `<project>-<env>`（`iam` 的 Pod Identity trust 綁這個名稱） |
| `cluster_endpoint` | private endpoint URL |
| `cluster_ca_data` | base64 的 CA |
| `cluster_sg_id` | EKS 建的 cluster SG |
| `service_cidr` | service CIDR；CoreDNS 在它的 `.10` |
| `app_namespace` | api、worker 的 namespace（預設 `app`），CI 只能部署到這裡 |
| `api_service_account`、`worker_service_account` | ServiceAccount 名稱（預設 `api`、`worker`），Pod Identity association 綁這兩個名稱 |

### 部署合約

`/<project>/<env>/application/<key>`，全部是 String。CI 只讀這組與 EKS 合約。

| key | 內容 |
|---|---|
| `app_port` | api 的 container port |
| `vpc_cidr` | VPC CIDR，chart 的 NetworkPolicy 用 |
| `api_target_group_arn` | api 的 target group，TargetGroupBinding 綁這個 |
| `api_image_repository`、`worker_image_repository` | ECR repository URL，tag 由 CI 給 |
| `api_environment_json`、`worker_environment_json` | JSON 物件，環境變數名稱 => 字串值。secret 只放 ARN，pod 用自己的 Pod Identity role 取值 |
| `api_scaling_json` | JSON：`min_replicas`、`max_replicas`、`cpu_target_percent`、`requests_per_target`、`streams_per_replica`、`region`、`alb_arn_suffix`、`target_group_arn_suffix` |
| `worker_scaling_json` | JSON：`min_replicas`、`max_replicas`、`backlog_per_replica`（`stream_length_cap / 4`）、`region`、`metric_namespace`、`metric_name`、`dimension_name`、`dimension_value` |
| `stream_length_cap` | 每個 shard 的 stream 長度上限，`postdeploy` 的 backlog 告警用 |

`loadbalancer` 開了 canary 時另外發布 `/<project>/<env>/loadbalancer/api_canary_target_group_arn`，只給 CI 讀。

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

發布（`<stack>/ssm-outputs.tf`）：`locals` 的 `published_strings`、`published_lists`，map 的 key 就是發布的 key，每個 key 從行首開始、`=` 前面沒有其他東西；值可以跨多行，但值裡的大括號要成對。只給 CI 讀、有條件才發布的 key（`loadbalancer` 的 `canary_strings`）另外放，再 `merge` 進 `ssm_publish`，`check-ssm-contract.sh` 看不到它們；CI 讀的 key 由 `application/tests/check-deploy-values.sh` 比對。

```hcl
locals {
  published_strings = {
    alarm_topic_arn = module.alarm_topic.topic_arn
  }
  published_lists = {}
}
```

骨架階段還沒有資源可以接時，`ssm-outputs.tf` 只寫 `# planned_strings: <key>...` 與 `# planned_lists: <key>...` 註解行，列出打算發布的 key；`check-ssm-contract.sh` 把它們當成已發布。加上 `module "ssm_publish"` 與 `published_*` 時，同一個 PR 把註解行換掉，不要兩種並存。

## check-ssm-contract.sh

```bash
bash infra/terraform/check-ssm-contract.sh
```

這支腳本只檢查下面兩件事。其他規則（`common.tf` 一致、`data "aws_ssm_parameter"` 的位置、tfbackend 的 key）由 `scripts/validate.sh` 負責，`validate.sh` 也會呼叫這支腳本。

1. 每個被讀取的 `<stack>/<key>`：發布它的 stack 在 `ORDER` 裡排在讀它的 stack 前面，真的有發布這個 key，而且型別（strings 或 lists）相同。樹 B 的 `infra/<key>` 對應到 `bridge`。
2. 同一個 env 裡，各 stack 的 tfvars 在 `SHARED_CONFIG_KEYS`（`project`、`env`、`aws_region`、`expected_account_id`、`deploy_role_arn`、`bastion_enabled`、`guardrail_cross_region_profile_id`、`nat_mode`）上的值一致，而且 `env` 等於檔名。沒設某個 key 的 stack 不參與比對，所以 `bastion_enabled` 只比對 network 與 operation，`guardrail_cross_region_profile_id` 只比對 iam 與 agent，`nat_mode` 只比對 network 與 eks-addons。

出錯時，訊息會指出是哪個 stack 的哪個 key。

## stacks.sh

```bash
cd infra/terraform
./stacks.sh <env> <stack|all> <init|validate|plan|apply|destroy|output> [--yes] [--dry-run] [-- <terraform 參數>...]
```

- env 檔從 `<stack>/envs/<env>.tfvars`、`<stack>/envs/<env>.tfbackend` 讀。
- `TF_DATA_DIR=.terraform-<env>`，`init` 一律 `-reconfigure`。
- `validate` 做 `init -backend=false -lockfile=readonly` 再 `validate`，用另一個 data directory `.terraform-<env>-validate`，不會蓋掉 `init` 留下的 backend 設定，**也不會改 `.terraform.lock.hcl`**：lock 對不上就失敗，不會悄悄重寫。
- `all` 依 `ORDER` 跑，`destroy all` 反向；任何一個 stack 失敗就停。`all` 會跑到 `eks-addons`，所以整串要在〈執行環境〉說的網路裡跑。
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

## 部署

CI 每次部署 api 與 worker，都從 SSM 重新產生 values。執行的身分是 `eks-cluster` 的 `ci_deploy_principal_arn`，網路條件見〈執行環境〉，AWS 權限要有：

- 兩個前綴的 `ssm:GetParametersByPath`：`/<project>/<env>/eks-cluster/`、`/<project>/<env>/application/`。部署 canary 時另外要 `/<project>/<env>/loadbalancer/`。
- `eks:DescribeCluster`。

```bash
cluster="example-dev"
aws eks update-kubeconfig --name "$cluster" --region ap-northeast-1

for c in api worker; do
  templates/example3/deploy/values-from-ssm.sh --project example --env dev --component "$c" --image-tag 1.2.3 >"$c.json"
  helm upgrade --install "$c" templates/example3/deploy/charts/app -n "$(jq -r .namespace "$c.json")" -f "$c.json" --atomic
done
```

- release 名稱固定是 `api`、`worker`。Deployment 與 container 用 release 名稱，`postdeploy` 的告警依這兩個名稱找工作負載。
- namespace 與 ServiceAccount 名稱照 SSM 給的值，chart 在 release namespace 跟 `app_namespace` 不同時直接失敗，避免 Pod Identity 對不上。
- chart 只有 ClusterIP Service，不建 Ingress 或 `type: LoadBalancer` 的 Service；TargetGroupBinding 不帶 `networking`，SG 規則仍由 Terraform 管。
- 副本數由 KEDA 的 ScaledObject 管，Deployment 不寫 `replicas`。縮容：穩定 900 秒、每 600 秒最多減 1 個。
- 副本上限 `api_max_capacity`、`worker_max_capacity` 決定最多開幾條連線：每個副本都會開 DB proxy 與 Redis 連線。調高之前先確認「副本數 × 每個副本的連線數」不超過 RDS Proxy 與 Redis 的上限。
- CI 的 Edit 權限能建 TargetGroupBinding 與 ScaledObject，是因為 `eks-addons` 開了 `aggregate_crd_roles`，把這兩種 CRD 的權限併進內建的 `edit`。

## canary

`loadbalancer` 的 `canary` 預設 `null`，這時不建任何 canary 相關資源。

```hcl
canary = {
  weight  = 10                              # 0–100，給 api-canary 的比例，其餘給 api
  breaker = { image_tag = "0.1.0" }         # weight > 0 一定要有
}
```

- 設了 `canary`：多一個 `api-canary` target group，api 的三條 rule（`/api/stream`、`/api/quota`、`/api/admin`）依權重轉送；`dev_page` 不加權。
- 設了 `breaker`：每條加權 rule 一組 alarm（canary target group 的 5xx 錯誤率與健康主機數），任何一個觸發就由 Lambda 把那條 rule 的 canary 權重改成 0，stable 維持原本的權重（例如 90），所以流量全部進 stable。Lambda 的 image 是 `<project>-traffic-breaker:<image_tag>`，程式碼在 [`modules/lb-traffic-breaker/lambda`](../../../modules/lb-traffic-breaker/lambda)，要用 arm64 build 後推上去。
- `weight > 0` 卻沒有 `breaker`、target group 名稱超過 32 字元（`<project>-<env>-alb-api-canary`）時，plan 直接擋下。

ALB 不會因為 canary 是空的或不健康就把流量轉走，所以權重只能在 canary 有健康的 target 之後才調高。流程：

1. tfvars 設 `canary = { weight = 0, breaker = {...} }`，apply `loadbalancer`。
2. CI 部署 canary release，綁到 canary target group，共用 api 的 ServiceAccount：
   ```bash
   templates/example3/deploy/values-from-ssm.sh --project example --env dev --component api --image-tag 1.3.0 --canary >api-canary.json
   helm upgrade --install api-canary templates/example3/deploy/charts/app -n app -f api-canary.json --atomic
   ```
3. 確認 `api-canary` target group 有健康的 target，再把 `weight` 調高、apply。之後每次調整都是改 tfvars 再 apply。
4. 驗證完成：stable release 換成新的 image、`weight` 改回 0 並 apply，再 `helm uninstall api-canary`。要完全拿掉 canary 資源時把 `canary` 設回 `null`。

斷路器觸發之後：

1. SNS 通知到人。確認 rule 上有 `traffic-breaker/tripped` tag，而且權重只剩 stable。
2. **先把 tfvars 的 `weight` 改成 0 並 apply，才可以做其他 apply。** Terraform 擁有權重的設定值，下一次 apply 會把權重改回 tfvars 的值；這一步沒做，任何人 apply 都會把流量送回壞掉的 canary。Terraform 偵測不到這個狀況，只能靠流程。
3. 再處理 canary release（修好重新部署，或 `helm uninstall api-canary`）。
4. Lambda 失敗時權重沒改到，alarm 也不會再次呼叫 Lambda；收到通知後看 `/aws/lambda/<project>-<env>-traffic-breaker` 的 log，必要時手動改權重。

canary 的 Deployment 沒有工作負載告警，只有斷路器的 alarm；log 告警依 container 名稱 `api` 比對，canary 的 log 也算在內。

## IP 預算

node 與 pod 都在 app subnet，每個 AZ 一個 /19（8,187 個可用 IP）。估算方式（design K2）：

```
每個 AZ 需要的 IP ≈ 同時存在的 node 數 × (1 + 每台 node 的 /28 prefix 數 × 16)
```

以這份範本的上限估：`app` pool 100 vCPU、`system` pool 16 vCPU，最小用 2 vCPU 的 node 算是 58 台；drift 替換或 consolidation 時新舊 node 並存，抓 1.5 倍是 87 台。假設全部落在同一個 AZ、每台 node 用 4 個 prefix（64 個 pod IP），需要 87 × 65 = 5,655 個 IP，在 /19 之內。調高 CPU 上限或改用很多小 node 時要重算；不夠的話，在 `network` 的 `vpc_subnets` 加一個 pod 專用的 tier。這是推算，Auto Mode 實際配 prefix 的方式要在真實叢集確認。

## 不進 tfvars 的值

`loadbalancer` 的 origin verify 值（CDN 加在 origin 請求上的 header 值）只能從環境變數給：`export TF_VAR_origin_verify_header_value=<至少 16 字元>`，跟 CDN 送的是同一個值。tfvars 只放 header 名稱；變數是 `sensitive`、沒有預設值，所以少了它 plan 直接失敗。這個值會寫進 state（ALB 規則的條件），state 的存取權限要照機密管。WAF log 會遮蔽這個 header。

## 環境切換

手打 `terraform` 時，環境由四個彼此獨立的選擇決定：AWS 身分（`aws-vault exec <profile> --`）、backend（`-backend-config=envs/<env>.tfbackend`）、變數（`-var-file=envs/<env>.tfvars`）、工作目錄（`TF_DATA_DIR=.terraform-<env>`）。`stacks.sh` 把後三個綁在一起，只剩 AWS 身分要自己換；`allowed_account_ids` 會擋下打到錯的帳號。

## 複製出去之後要改什麼

範本裡的值都是佔位，複製到專案 repo 後照下面順序改：

1. **module 的 `source`**：從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）。用自己的 organization 就換掉這段前綴；拿不到 HCP token 時改成 `git::...?ref=<module>-v<semver>`。一次改完的指令見 `docs/guides/consuming-modules.md`。
2. **帳號表**：`common.tf` 的 `accounts_by_env` 目前是 `111111111111`（dev）與 `222222222222`（sit）。填真實帳號，13 個 stack 同步改，保持一字不差。
3. **state bucket**：每份 `envs/*.tfbackend` 的 `bucket` 是 `<state-bucket>`，換成真實 bucket；`key` 的 `example-` 前綴換成自己的 `project`（格式 `<project>-<env>/<stack>/terraform.tfstate`，`validate.sh` 會檢查）。
4. **tfvars 的佔位值**：每份 `envs/*.tfvars` 的 `project`、`expected_account_id`，以及：
   - `foundation`：`alarm_emails`（現在是 `ops@example.com`）。
   - `network`：`vpc_cidr`、`azs`、`alb_ingress`（現在是文件用的 `203.0.113.0/24`）、`k8s_api_sources`（runner 的 SG 或 CIDR）。
   - `eks-cluster`：`kubernetes_version`（現在是 `1.36`，選仍在標準支援的版本）、`cluster_admin_principal_arns`、`addons_apply_principal_arn`、`ci_deploy_principal_arn`（三者不能重複）。
   - `eks-addons`：`nat_mode` 跟 `network` 相同；需要時調 `app_pool_cpu_limit`、`system_pool_cpu_limit`。
   - `loadbalancer`：`origin_verify_host_headers`、`rate_limit_allowlist_cidrs`（現在是 `198.51.100.0/24`）、需要時加 `canary`。
   - `application`：`cors_allow_origins`、副本數上下限與擴縮目標。
   - `operation` 與 `agent`：映像 tag。
   - `database`：`db_instance_class`、`connections_threshold`（約為該 instance class 的 `max_connections` 的 80%，換 class 就要重算）、Redis 的 node type。
   - `agent`：`model_id`、`backend_mode`（目前是 `fake`）、`guardrail_cross_region_profile_id`。
5. **origin verify 的值**：不放 tfvars。`export TF_VAR_origin_verify_header_value=<至少 16 字元>`，見上面「不進 tfvars 的值」。
6. **guardrail 的內容**：`agent/guardrails.tf` 的 denied topic、詞彙、拒絕文案都只是示意，換成自己產品的政策。module 不建 guardrail 版本，apply 的內容就是線上生效的政策。
7. **chart**：`deploy/charts/app` 是範例。health check 只是 TCP；CPU、記憶體在 `values.yaml` 的 `resources`；NetworkPolicy 放行的資料庫與 Redis port 在 `dataPorts`。
8. **命名規則**：`iam` 比後段 stack 先 apply，讀不到資源，所以用命名規則組 ARN。兩邊是否一致沒有東西檢查，只有各 stack 的 test 會斷言。改任何一邊的名稱，另一邊要一起改：
   - EKS 叢集：`<project>-<env>`（`eks-cluster`；`iam` 的 Pod Identity trust 與 LB Controller policy 用它）。
   - import bucket：`<project>-<env>-import-<account>`，prefix `incoming/`、`extracted/`；eval-batch bucket：`<project>-<env>-eval-batch-<account>`（`operation`）。
   - Lambda log group：`/aws/lambda/<project>-<env>-import-extract`、`-import-load`（`operation`）。
   - AgentCore Runtime 與 Memory：`<project>_<env>_<runtime>`、`<project>_<env>_memory`，連字號換成底線（`agent`）。
   - 自訂 metric namespace：`<Project>/<env>`（`application`、`operation`、`postdeploy`）。
   - 設計依據見 `docs/design/v2/design-docs.md` §5.8、§5.10 與 `docs/design/v4/design-docs.md` §8。
9. **`SHARED_CONFIG_KEYS`**：`network` 與 `operation` 的 `bastion_enabled` 要一致，`iam` 與 `agent` 的 `guardrail_cross_region_profile_id` 要一致，`network` 與 `eks-addons` 的 `nat_mode` 要一致；`check-ssm-contract.sh` 會比對。`app_port` 在 `network`、`loadbalancer`、`application` 各有一份變數，靠預設值一致，改的時候三處一起改，沒有東西檢查。

## destroy 之前

`stacks.sh <env> all destroy` 會依反向順序跑，但遇到下面幾種情況會停下來，要先處理（預設值取自各 module 與 stack）：

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| CI 部署的 Helm release | Terraform 不管 | 先 `helm uninstall api worker`（與 `api-canary`）。留著的話，`eks-addons` 拿掉 LB Controller 之後 TargetGroupBinding 的 finalizer 沒人處理，namespace 會卡住 |
| EKS 叢集（`eks-cluster`） | `deletion_protection = true` | 先在 module 呼叫加 `deletion_protection = false` 並 apply，再 destroy |
| secrets 加密的 KMS key（`eks-cluster`） | 刪除等待 30 天 | alias 會立刻刪除，key 在等待期間不能用、可以取消刪除。叢集刪掉之後才 destroy，不然叢集的 secrets 解不開 |
| Aurora cluster（`database`） | `deletion_protection = true`；`skip_final_snapshot = false`，會留 final snapshot | 先把 `deletion_protection = false` apply 進去，再 destroy。不要 final snapshot 就同時設 `skip_final_snapshot = true`（`dev.tfvars` 就是這樣設） |
| ALB（`loadbalancer`） | `deletion_protection = true` | 同上，先 apply `deletion_protection = false` |
| ECR repository（`containerimage`） | module 固定 `force_delete = false` | repository 裡有映像會刪不掉，先清空映像；沿用既有 repository 的 env 不會建它，也不會刪它 |
| S3 bucket（`operation` 的 import 與 eval-batch bucket、`loadbalancer` 的 access log bucket） | `force_destroy = false` | bucket 不是空的會刪不掉。先清空（含舊版本與刪除標記），確認資料不需要再刪 |
| Secrets Manager secret（`foundation`） | `recovery_window_in_days = 7` | 刪除後保留 7 天，期間不能用同名重建；secret 的值是在 Terraform 外面寫的，刪了就沒有，要先備份 |
| Redis（`database`） | module 沒有設定 final snapshot | 要保留資料就先手動做 snapshot |
| Container Insights 的 log group | Fluent Bit 自己建，不在 state 裡 | destroy 不會刪，要自己刪 `/aws/containerinsights/<cluster>/*` |

`bridge` 之後的 stack（7–13）只依賴樹 B，所以要先 destroy 它們，再 destroy `bridge`。`stacks.sh` 的反向順序已經照這樣排；單獨 destroy 某個 stack 時要自己注意順序。destroy 不會刪掉不是這份範本建的東西（外部發布的樹 B、state bucket 本身、CI 部署的 release）。

## 已知限制

下面都是 mock 驗不到的推論，第一次 apply 時要逐項確認。EKS 部分的理由見 `docs/design/v4/design-docs.md` §11，其他見 `docs/design/v2/design-docs.md` §5.8、§5.10。

- **EKS 的網路**：node 與 pod 共用 app subnet 是否可行（〈IP 預算〉）；`app` SG 為 kubelet 探測與 CoreDNS 補的規則是否足夠；NetworkPolicy `DefaultDeny` 下，kubelet 探測、系統元件的 webhook 與 metrics 是否都放行；沒有 NAT 時 interface endpoint 是否齊全（Auto Mode、KEDA、CloudWatch 採集都會打 AWS API）。
- **Auto Mode**：一個內建 NodePool 都不開時，NodeClass／NodePool 的 CRD 是否一定存在；`amazon-vpc-cni` ConfigMap 是否已經存在（存在的話 Helm 建立會失敗）；兩個 load balancing controller 並存時不會搶同一個 Service 或 Ingress。
- **權限**：LB Controller 的官方 policy 能不能對 Terraform 建的 target group 做 `RegisterTargets`；CI 的 Edit 是否真的帶到 TargetGroupBinding 與 ScaledObject（`aggregate_crd_roles`）；叢集 role 的 BlockStorage policy 名稱（`AmazonEKSBlockStoragePolicy`）。
- **Pod Identity**：association 早於 namespace 與 ServiceAccount 存在時的行為；應用程式的 AWS SDK 要支援 Pod Identity 的 container credentials provider。
- **helm provider**：用 SSM 讀到的 endpoint 與 CA 設定，真實 plan 是否沒問題。
- **擴縮與告警**：KEDA 依 CloudWatch 指標擴縮對長連線（SSE）的效果；Container Insights 的 log 格式（`log_processed`、`kubernetes.*`）是否跟 filter 一致；application log group 由 Fluent Bit 建立、保留期是永久，`postdeploy` 的 log 告警要等它存在才 apply 得過；`tcp_keepalive_*` sysctl 是否被允許。
- **IAM 與 policy 的形狀**（沿用 example2）：RDS Proxy role 的 `kms:Decrypt` 限定 `alias/aws/secretsmanager` 的 key 加 `kms:ViaService` 是否足夠；Enhanced Monitoring role 收窄到 `RDSOSMetrics` log group 是否足夠；AgentCore Runtime role 的 `aws:SourceArn` 與 `runtime/<name>-*`、`memory/<name>-*` 的 ARN 形狀；bastion 的 Session Manager 最小權限。
- **ALB 與 WAF**（沿用 example2）：ALB access log 用 `log-delivery` 的 vended delivery，`depends_on` 是否足以讓 bucket policy 先到位，以及 apply 身分建 delivery 需要的權限；WAF logging 需要 apply 身分有 `logs:PutResourcePolicy`。
- **AgentCore 與 Bedrock**（沿用 example2）：`/aws/vendedlogs/...` 當 log delivery 的目的地、Runtime 的 `APPLICATION_LOGS` delivery 能否建立；guardrail 的 `STANDARD` tier 加 cross-region profile 的實際行為。
- **跟應用程式的約定**（沿用 example2）：pg_cron 的 log 告警靠 SQL 寫出 `partition_maintenance_failed`、`partition_maintenance_heartbeat`、`default_partition_not_empty` 三個字串；import-load 由 `extracted/` 加 `ready.json` 後綴觸發。這兩項沒有東西檢查。
- **canary 告警一建立就會響**：`healthy-hosts` 告警把沒有資料當成不健康（`treat_missing_data = "breaching"`），canary target group 還沒有 pod 時就進入 ALARM 並發 SNS；流量本來就不在 canary，Lambda 不做任何事。開 canary 時先部署 canary pod，或接受這一次的通知。
- **健康檢查路徑**：target group 檢查 `/health`（`loadbalancer/alb.tf`），範例 chart 的 readiness 只做 TCP 檢查。應用程式必須在 `app_port` 回應 `/health`，否則 pod 顯示 Ready、target 卻是 unhealthy。
- **技術債**：`bastion_enabled`、`guardrail_cross_region_profile_id`、`nat_mode` 的一致性檢查沒有自動化 fixture；`app_port` 的三份變數沒有一致性檢查。

## 驗證

```bash
scripts/validate.sh templates/example3
```

做 `fmt`、靜態規則（含 lock 檔每個 provider 要有 darwin 與 linux 兩個 `h1:` hash 的 S10）、`check-ssm-contract.sh`、`bash -n` 與 shellcheck、本地 chart 的 `helm lint` 與 `helm template`，然後每個 stack 跑 `init -backend=false`、`validate`、`terraform test`，對 `dev`、`sit` 兩份 tfvars 各跑一次 `tests/tfvars`，最後跑 `tests/check-*.sh`。全部離線，不需要 AWS 憑證；stack 從 HCP private registry 抓 module，需要 registry token；沒有 helm 時 chart 的檢查會印「略過」。

### 靜態驗證通過（2026-10-23）

| 項目 | 結果 |
|---|---|
| `scripts/validate.sh templates/example3` | 13 個 stack、362 個 `terraform test` run 全過；fmt、靜態規則、S10 通過 |
| `check-ssm-contract.sh` | 13 個 stack、2 個 env 通過；`nat_mode` 不一致時會失敗 |
| `application/tests/check-deploy-values.sh` | 通過：腳本讀的 key 都有被發布；api、worker、canary 的 values 經 `helm lint`、`helm template` 並斷言 manifest；不認得的合約版本、缺 key、canary 沒開、ARN 格式錯都會失敗 |
| `helm lint`、`helm template` | `deploy/charts/app`（預設值與腳本產生的 values） |
| shellcheck | `values-from-ssm.sh`、`check-deploy-values.sh` 沒有警告 |
| 突變測試 | C3–C7 每個 Phase 都做，改壞的地方都被測試或合約檢查抓到（明細見 implement-process） |
| 保密比對 | example3 全目錄跑過去機密 pattern 與來源字串反向比對 |

### 雲端整合待驗證

要真實帳號與叢集，這個里程碑沒有做。逐項的前提、指令、預期結果與紀錄方式見 [`docs/guides/cloud-verification-example3.md`](../../../docs/guides/cloud-verification-example3.md)。

| 項目 | 怎麼確認 |
|---|---|
| node 加入叢集 | `eks-addons` apply 後，`app` 與 `system` NodePool 能開出 node，node role 的 EC2 access entry 生效 |
| DNS | pod 實際用的 resolver 是 service CIDR 的 `.10`，`DefaultDeny` 下 UDP 與 TCP 53 都通 |
| Pod Identity | api、worker 取得憑證並讀到 Secrets Manager 的 secret；KEDA、LB Controller、CloudWatch 採集都拿到自己的 role |
| TargetGroupBinding | pod 註冊進 Terraform 的 target group；刪除 binding 後 target group 還在 |
| KEDA | 依 CPU、RequestCountPerTarget、ActiveConnectionCount、StreamBacklogMax 擴縮，縮容照 900／600 秒的規則 |
| CloudWatch 採集 | Container Insights 指標與 log 涵蓋 `app` 與 `system` node；log 欄位符合 `postdeploy` 的 filter |
| 告警 | `eks-workload-alarms` 每一條、stream 與 log 告警都能觸發 |
| no-NAT | `nat_mode = "none"` 時，node、pod、controller 都只經 interface endpoint 就能運作 |
| canary | 權重調整、斷路器觸發後 canary 權重變成 0、流量全部進 stable、`traffic-breaker/tripped` tag、觸發後的處理流程 |
| CI 權限 | `AmazonEKSEditPolicy` 能建 TargetGroupBinding、ScaledObject、TriggerAuthentication、NetworkPolicy |
