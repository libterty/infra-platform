# infra-platform v1 設計文件

> 狀態：使用者已拍板（§9.2），可以進入實作；實作步驟見 [`implement-process.md`](./implement-process.md)
> 範圍：第一版（ECS 試行，加上 VPC、RDS、ALB 組成的最小三層架構）
> 文中路徑若沒有特別說明，都相對於 `<workspace>/`。
> 增補（2026-10-15）：LLM 與 AgentCore 的 7 個 module、範本的 `agent` stack、`rds` 的 Data API（§4.23–§4.31、§5.3〈增補：`agent` stack〉、決策 37–50）。設計已拍板，尚未實作，步驟見 implement-process 的 Phase 11–16。標「增補」的段落是這次加的，其餘是 v1 原文。

## 1. 結論

infra-platform 是Terraform private registry 的範例 repo。它用「Git tag 版本化的 monorepo」發布共用 module，讓各專案用 `?ref=<module>-v<semver>` 釘版本引用，不再每個專案各寫一套 VPC、資料庫、ECS、告警、跨 stack 傳值的程式碼。

第一版做出一個最小的三層架構：ALB 放 public subnet，ECS 服務（AP 層）與資料庫（DB 層）放 private subnet。內容是：

- 19 個 module，起始版本都是 `v0.1.0`：
  - 網路與入口：`vpc`、`vpc-interface-endpoints`、`alb`
  - 資料：`rds`（一個 module 支援一般 RDS、Aurora、Aurora Serverless v2 三種型態，RDS Proxy 是選項）
  - 運算：`ecs-cluster`、`ecs-service`、`ecs-service-alarms`
  - 共用基礎：`kms-key`、`ecr-repository`、`s3-bucket`、`sns-alarm-topic`、`security-group`
  - IAM：`iam-role`、`iam-role-policy`
  - 觀測性：`log-group`、`log-metric-alarm`、`xray`（`ecs-service` 另有通用的 `sidecars` 可以掛 ADOT collector）
  - 跨 stack 傳值：`ssm-publish`、`ssm-read`
- 範本的 stack 只呼叫 module，不寫原生 AWS resource；例外只有一個（`foundation` 的 secret 容器），明列在 §5.3。整個 repo 只有 `iam-role` 與 `iam-role-policy` 兩個 module 建 IAM。
- 1 份 8 個 stack 的專案 infra 範本：照 project-a 的 state 拆法，修掉已知的坑；在本 repo 內用相對路徑引用 module；附 PoC／一般正式／大流量三組範例 tfvars（§5.11）。
- 使用與發版文件、3 份 ADR、CI 與 release 設定。
- **增補（決策 37 起）**：再加 7 個 LLM 與 AgentCore 的 module（`bedrock-guardrail`、`bedrock-inference-profile`、`agentcore-runtime`、`agentcore-memory`、`agentcore-gateway`、`log-delivery`、`bedrock-knowledge-base`，首版一律 `v0.1.1`），module 合計 26 個；範本加第 9 個 stack `agent`，預設關閉；`rds` 加 Data API 與兩個輸出，發 `rds-v0.1.1`；`s3-bucket` 加不過期的選項，發 `s3-bucket-v0.1.1`（決策 51、52、54）；`iam-role` 加 `trust.source_arn`，也發 `iam-role-v0.1.1`（決策 56），`v0.1.1` 合計 10 個。上面「19 個 module」「8 個 stack」是 v1 原本的範圍，19 個 tag 不動（§4.23、§5.3）。

全部只做離線驗證（`fmt`、`tflint`、`init -backend=false`、`validate`、`terraform test` 搭配 `mock_provider`），**不做 `plan`／`apply`，也不碰任何 AWS 帳號**。

第一版不做：

- registry 與工具：HCP Terraform 或自架 registry；terraform-docs、pre-commit 的自動化（只提供設定檔）。
- AP 層共用元件（core app team 的東西另開 repo）。
- 網路：IPv6、private NAT、Transit Gateway、VPC peering。
- 資料庫：一般 RDS 的 read replica、RDS Multi-AZ DB cluster（第四種型態）、同一個 Aurora cluster 混用 provisioned 與 serverless instance；應用程式專用的 DB 帳號與 Proxy 的 IAM 認證（第一版用 master secret，風險見 §8.2）。
- WAF 的 Web ACL 本身（`alb` 只收 `web_acl_arn` 做關聯）。
- 真實環境的部署驗證（§7.3）。

### 1.1 repo 目錄

```
infra-platform/
├── README.md                      # 入口：這是什麼、四個團隊怎麼用、文件地圖
├── .gitignore                     # docs/slides/、.terraform*/、*.tfstate*、crash.log 等
├── .github/
│   ├── CODEOWNERS                 # 團隊邊界（§6.3）
│   └── workflows/
│       ├── ci.yml                 # fmt、tflint、init -backend=false、validate、test（mock，無 AWS 憑證）
│       └── release.yml            # release-please：per-module tag 與 CHANGELOG
├── release-please-config.json
├── .release-please-manifest.json
├── .tflint.hcl
├── .pre-commit-config.yaml        # 本機未安裝 pre-commit，只提供設定，不在本次驗證
├── scripts/
│   ├── validate.sh                # 對每個 module、example、template stack 跑 fmt/init -backend=false/validate/test 與靜態規則
│   └── vendor-modules.sh          # FDE 交付用：把指定 tag 的 module 複製進客戶 repo 並改寫 source
├── modules/
│   ├── vpc/
│   ├── vpc-interface-endpoints/
│   ├── alb/
│   ├── rds/
│   ├── kms-key/
│   ├── ecr-repository/
│   ├── s3-bucket/
│   ├── iam-role/
│   ├── iam-role-policy/
│   ├── security-group/
│   ├── log-group/
│   ├── log-metric-alarm/
│   ├── xray/
│   ├── ssm-read/
│   ├── ecs-cluster/
│   ├── ecs-service/
│   ├── ecs-service-alarms/
│   ├── sns-alarm-topic/
│   ├── bedrock-guardrail/           # 增補（§4.24–§4.30）
│   ├── bedrock-inference-profile/   # 增補
│   ├── agentcore-runtime/           # 增補
│   ├── agentcore-memory/            # 增補
│   ├── agentcore-gateway/           # 增補
│   ├── log-delivery/                # 增補
│   ├── bedrock-knowledge-base/      # 增補
│   └── ssm-publish/
│       （每個都有 main.tf variables.tf outputs.tf versions.tf README.md CHANGELOG.md examples/<情境>/ tests/*.tftest.hcl）
├── templates/
│   └── project-infra/
│       └── infra/terraform/<stack>/...   # §5；8 個 stack（增補後 9 個，加 agent），用相對路徑引用 ../../../../../modules/<name>
└── docs/
    ├── design/
    │   └── v1/
    │       ├── design-docs.md            # 本文件
    │       └── implement-process.md      # 實作步驟
    ├── guides/
    │   ├── consuming-modules.md
    │   ├── project-infra-standard.md
    │   ├── releasing-modules.md
    │   ├── delivering-to-customer.md
    │   ├── team-roles.md
    │   ├── observability.md              # ADOT sidecar、X-Ray 權限與抽樣的整套做法（§4.20）
    │   └── llm-agentcore.md              # 增補（Phase 15）：guardrail、Runtime、Memory、Gateway、KB 的整套做法與 KB 的 SQL
    ├── adr/                              # MADR
    │   ├── 0001-git-tag-monorepo-as-private-registry.md
    │   ├── 0002-split-state-by-owner-and-change-rate.md
    │   └── 0003-cross-stack-values-via-ssm-only.md
    └── slides/                           # 不進 git
```

## 2. 背景與目標

### 2.1 現況：同一件事各寫一套，品質落差大

| 現象 | 事實 | 來源 |
|---|---|---|
| project-c 的告警沒有人收 | `cloudwatch-alarms.tf` 宣告 22 個 `aws_cloudwatch_metric_alarm`，`alarm_actions` 出現 0 次；告警會變紅，但不會通知任何人 | `project-c-app/modules/app-platform/cloudwatch-alarms.tf` |
| project-c 的 SNS topic 跟告警沒接上 | infra 層建了 alarm group topic 與 email 訂閱，app 層的告警沒引用 | `project-c-infra/modules/infra-platform/sns.tf` |
| 只有 project-a 有 dashboard | project-c 兩個 repo 都沒有 `aws_cloudwatch_dashboard` | `project-a/infra-v2/terraform/postdeploy/dashboard.tf` |
| autoscaling 兩種寫法 | project-a 用 target tracking（每 target 300 request、CPU 60%）；project-c 用 step scaling（CPU／記憶體 ≥70% 分三階 +1／+2／+3） | `project-a/infra-v2/terraform/postdeploy/ecs-autoscaling.tf`、`project-c-app/modules/app-service/ecs-autoscaling.tf` |
| 跨 stack 傳值兩種寫法 | project-a 只走 SSM；project-c 用 `terraform_remote_state` | `project-a/infra-v2/terraform/application/ssm-inputs.tf`、`project-c-app/environments/*/project-*/service/main.tf` |
| provider 版本不一致 | project-c 同一個專案 sit／prod 釘 `6.44`，uat 是 `~> 6.0` | `project-c-app/environments/{sit,uat,prod}/project-c/service/providers.tf` |
| module 共用只能靠 submodule | project-b 用 git submodule 引用 project-c 的 app module，沒有版本號 | `project-b/.gitmodules` |
| 各 repo 都沒有 tflint、terraform-docs | — | 三個 repo 的根目錄 |

共同的好做法也存在，這次直接收進 module 當預設值：Fargate＋awsvpc、ARM64、`initProcessEnabled`、`stopTimeout = 120`、部署 min 100％／max 200％、私有子網不配公有 IP、`ignore_changes = [desired_count]`、execution role 與 task role 分開、每個服務一個 log group。

### 2.2 長期目標：四個團隊

| 團隊 | 長期職責 | 跟這個 repo 的關係 |
|---|---|---|
| platform team（基礎設施平台） | 維護共用 module、CI、發版、安全基線 | 擁有 `modules/`、`.github/`、`docs/adr/` |
| core app team（AP 層核心） | AP 層共用元件（SDK、服務範本） | 這個 repo 不放 AP 程式，只預留 CODEOWNERS 與交接點；未來比照本 repo 的發版模式另開 repo |
| 專案 app team（多元專案 AP） | 各專案的服務與 infra | 複製 `templates/project-infra/` 到自己的 repo，釘版本引用 module |
| 專案 FDE team（前線部署） | 交付到客戶環境 | 用 `scripts/vendor-modules.sh`、providers mirror、客戶自管資源的 SSM 合約 |

### 2.3 這個 repo 怎麼成為前身

簡報（`infra-platform/docs/slides/terraform-split/v7/07-infra-core-framework.pptx`）的敘事是「先從 ECS 開始、先試行」。第一版以 ECS 為主，再補上 VPC、ALB、RDS 湊成最小三層架構，以及 KMS、ECR、S3、IAM、SSM 讀取這些每個專案都會用到的基礎 module，用一個專案範本證明「引用 → 升版 → 交付」整條路走得通。四個團隊還沒拆，這個 repo 先用 CODEOWNERS 與文件把邊界畫出來；團隊成立時，邊界不用重畫，只要把 team slug 填進去。

## 3. Registry 設計

### 3.1 機制：Git tag monorepo

一個 repo 放所有 module（`modules/<name>/`），每個 module 各自打 tag、各自有 CHANGELOG。不架 registry server，GitHub 就是 registry。

選這個方式的理由（完整取捨寫在 `docs/adr/0001-git-tag-monorepo-as-private-registry.md`）：

- 零基礎設施：不用維護 registry 服務、不用額外帳號。
- Terraform 原生支援 Git source，不用改工具鏈。
- 目錄與 tag 一開始就照 registry 規範，之後要換 HCP Terraform 或 boring-registry 時，module 程式碼不用動。

### 3.2 tag 格式

```
<module>-v<MAJOR>.<MINOR>.<PATCH>
例：ecs-service-v1.0.0、ssm-publish-v1.2.3
```

- 這是 release-please manifest 模式的預設格式（`<component>-v<version>`），也對得上 HCP Terraform private registry 的 Module Tag Prefix。
- 不用帶斜線的 `ecs-service/v1.0.0`：HCP 是否支援沒有查證，斜線在 URL 的 `?ref=` 也容易出錯。
- `scripts/vendor-modules.sh` 與 CI 用 `^(vpc|vpc-interface-endpoints|alb|rds|kms-key|ecr-repository|s3-bucket|iam-role|iam-role-policy|security-group|log-group|log-metric-alarm|xray|ssm-read|ecs-cluster|ecs-service|ecs-service-alarms|sns-alarm-topic|ssm-publish|bedrock-guardrail|bedrock-inference-profile|agentcore-runtime|agentcore-memory|agentcore-gateway|log-delivery|bedrock-knowledge-base)-v[0-9]+\.[0-9]+\.[0-9]+$` 檢查 tag；module 名稱清單從 `modules/` 目錄讀，不手寫。
- 增補：上面那條 regex 已加上決策 37 的 7 個 module（implement-process Phase 12，README 的 module 清單同時更新）。

### 3.3 消費端寫法

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v1.0.0"
  # ...
}
```

- `<org>`、`<repo>` 是 GitHub 的 org 與 repo 名稱，尚未提供（§9.3 待補資訊）。文件與範本一律用佔位符，不要先寫死。
- `//modules/ecs-service` 是 repo 內子目錄；`?ref=` 指 tag。
- 私有 repo 的認證：本機用 `gh auth setup-git` 或 SSH（`git::ssh://git@github.com/<org>/<repo>.git//modules/ecs-service?ref=...`）；CI 用唯讀的 GitHub App token 或 deploy key。**Terraform 本身沒有 registry token 這一層，憑證全靠 git。**
- 同一個 root 裡引用多個 module 時，各自釘各自的 tag，不需要對齊版本。

### 3.4 限制

| 限制 | 影響 | 對策 |
|---|---|---|
| Git source 不支援 `version = "~> 1.2"`，只能用 `ref` 釘死 | 不能自動吃 patch 版 | 升版是一個明確的 PR：改 `ref`、跑 plan、看 CHANGELOG。這在第一版是優點，不是缺點 |
| tag 可以被移動或刪除 | 同一個 `ref` 可能指到不同程式碼 | GitHub ruleset 保護 `*-v*` tag 不可刪改；要求更嚴格的專案可以改釘 commit SHA，並在註解寫對應的 tag |
| 每次 `terraform init` 都會 clone 整個 repo | 下載量隨 repo 變大 | 第一版 module 少，不處理；變大時是升級到真 registry 的訊號之一 |
| Terraform 不支援 GitHub Packages／OCI | 不能用 GitHub Packages 當 registry | 只有 OpenTofu 1.10 支援 `oci://`，不在本次範圍 |

### 3.5 版本規則（semver）

判斷標準是**既有消費端把 `ref` 換成新版、不改自己的程式碼，`terraform plan` 會看到什麼**。

| 等級 | 定義 | Terraform module 的具體例子 |
|---|---|---|
| MAJOR | 消費端必須改程式碼，或 plan 會出現 replace／destroy | 刪除或改名變數、output；新增沒有預設值的必填變數；把 `optional()` 改成必填；收緊 validation（例如 `name` 上限從 26 改成 20）；改變 resource address 卻沒有 `moved` 區塊；改會觸發 replace 的屬性預設值（例如 target group 的命名格式、log group 名稱預設、`cpu_architecture` 預設從 ARM64 改 X86_64）；提高 `required_version` 或 AWS provider 的大版本下限（例如 `>= 7.0`） |
| MINOR | 消費端不用改程式碼，plan 可能有 in-place 變更或新增資源 | 新增有預設值、且預設維持原行為的變數；新增 output；放寬 validation；調整告警門檻預設值（in-place update）；新增只在新變數有給值時才建立的資源 |
| PATCH | 消費端換版後 plan 零差異 | 修 bug 且不改介面；用 `moved` 區塊重構 resource address；改 description、README、測試 |

補充規則：

- **in-place 變更要寫進 CHANGELOG**。MINOR 版如果會讓既有資源 in-place 更新（例如告警門檻從 80 改 85），CHANGELOG 必須寫出消費端 plan 會看到哪幾個資源、哪個屬性變了。
- **ECS task definition 的變更要特別標註**。task definition 只要內容變就會產生新 revision，ECS 會滾動部署。不會 replace 資源位址，算 MINOR，但 CHANGELOG 要寫「會觸發一次部署」。
- **起始版本**：19 個 module 都從 `v0.1.0` 開始（已拍板，§9.2），因為還沒在真實 AWS apply 過。0.x 期間 MINOR 可以有破壞性變更，CHANGELOG 要寫清楚。§7.3 的實環境驗證做完才升 `v1.0.0`。
- **增補的版本（決策 54）**：增補動到的 9 個 module 都打 `<module>-v0.1.1`，在 Phase 16 的驗收 commit 上手動打：決策 37 的 7 個新 module，加上 `rds`（Data API 與兩個新輸出，§4.31）與 `s3-bucket`（不過期的選項，§4.32）。7 個新 module 沒有 `v0.1.0`。`rds`、`s3-bucket` 的變更照上表是 MINOR，本來該發 `0.2.0`；這一次照使用者決定用 `0.1.1`，只限這一次，之後的版本照上表。19 個既有的 `v0.1.0` tag 留在原本的 commit，不移動；~~其他 17 個 module 只有 `v0.1.0`~~ 決策 56 起 `iam-role` 也發 `iam-role-v0.1.1`（`trust.source_arn`，同樣是照上表該發 MINOR 而刻意用 `0.1.1`），`v0.1.1` 合計 10 個，其他 16 個 module 只有 `v0.1.0`。
- **第一個 tag 由人手動打**：`.release-please-manifest.json` 把 19 個 module 都登記為 `0.1.0`，release-please 會把它當成已經發過，不會產生 `<module>-v0.1.0`。所以第一次發版前，由 platform team 在整體驗收通過的 commit 上手動打 19 個 `<module>-v0.1.0` tag；之後的版本才交給 release-please。

### 3.6 升級到真 registry 的路徑

觸發條件：需要版本範圍（`~>`）、專案數變多導致每個專案都要手動追 patch、或 clone 時間影響 CI。

| 選項 | 適合 | 怎麼接 | 注意 |
|---|---|---|---|
| HCP Terraform Free 的 private registry | 不想自己維運 | 每個 module 在 HCP 登記一次：VCS 指到這個 repo、Source Directory 填 `modules/<name>`、Tag Prefix 填 `<name>-v` | Free 方案有 500 個 managed resource 上限（這個上限算的是 HCP 管理的 state，只用 registry 時是否計入沒有查證） |
| boring-registry（自架，S3 當後端） | 資料不能出自有或客戶環境 | CI 在打 tag 後把 module 打包上傳 S3，registry 服務實作 module registry protocol | 要自己維運服務與認證 |

消費端改法（兩種一樣）：

```hcl
# 之前
source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v1.2.0"

# 之後
source  = "<registry-host>/<namespace>/ecs-service/aws"
version = "~> 1.2"
```

module 程式碼不用改。這是第一版就照 standard module structure（`main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`examples/`、`tests/`）的原因。

## 4. Module 設計

### 4.1 共通約定

每個 module 都遵守：

| 項目 | 約定 |
|---|---|
| 目錄 | `main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`CHANGELOG.md`、`examples/<情境>/`（至少一個，例如 `basic`、`https`、`aurora-serverless-proxy`）、`tests/*.tftest.hcl`（可以依主題拆成多檔）；資源多時可以依主題拆 `.tf`（例如 `alarms.tf`、`proxy.tf`） |
| `versions.tf` | `required_version = ">= 1.10"`；`aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }`；**module 裡不寫 `provider` 與 `backend`**。增補：決策 37 的 7 個新 module 例外，用 `>= 6.69, < 7.0`（決策 43、§4.23） |
| 版本範圍 | module 用範圍（`>= 6.0, < 7.0`），root 用 `~> 6.x` 加 `.terraform.lock.hcl` 釘死實際版本 |
| lock 檔 | **module 不提交 `.terraform.lock.hcl`**（Terraform 只採用 root module 的 lock，module 的 lock 對消費端沒有作用）；範本的每個 stack 是 root，要提交 |
| 依賴 | 一律從外部傳入（cluster ARN、role ARN、subnet、SG、topic ARN），module 之間不互相呼叫，平坦組合 |
| IAM | **只有 `iam-role` 與 `iam-role-policy` 兩個 module 建 IAM**（`aws_iam_role`、`aws_iam_role_policy`）。其他 17 個 module（增補後 24 個）不建任何 `aws_iam_*`，需要 role 的地方（ECS execution／task role、RDS Proxy role、Enhanced Monitoring role）一律收 ARN；範本的 stack 也一律透過這兩個 module（§5.4）。由 `scripts/validate.sh` 靜態檢查（§5.6 S4） |
| stack 只呼叫 module | 範本的 stack 不寫原生 AWS resource，只呼叫 module。例外要列在 §5.3〈stack 裡的原生資源〉並寫理由，`scripts/validate.sh` 依這份清單檢查。data source 不算（`data "aws_ssm_parameter"` 除外，只能在 `ssm-read` 裡） |
| 註解與訊息的語言 | `modules/` 底下的 `.tf` 與 `.tftest.hcl`，所有註解、`description`、`error_message` 一律只用英文，不可中英混雜，禁止任何 icon／emoji。註解只寫「程式碼看不出來的原因」，不要寫多。`README.md`、`CHANGELOG.md` 不受這條限制。本文件 HCL 範例裡的中文註解只為了說明，實作時要改成英文或拿掉 |
| inline 規則 | security group 與 route table 一律用獨立資源（`aws_vpc_security_group_ingress_rule`／`egress_rule`、`aws_route`），不用 inline `ingress {}`／`route {}`。inline 寫法對整個 SG／整張表有權威性，客戶在 console 加的規則與路由會在下一次 apply 被靜默刪除（`project-a/docs/reports/2026-09-04-customer-owned-network-and-terraform.md`、`project-a/infra-v2/terraform/network/nat.tf` 的註解） |
| 告警 | 會建告警的 module（`alb`、`rds`、`ecs-service-alarms`）一律必填 `sns_topic_arns`，`alarm_actions` 與 `ok_actions` 都接 |
| 開關 | 不用 `enable_xxx`。資源要不要建，由「相依的輸入有沒有給」決定（例如 `load_balancer = null` 就不建 target group） |
| tags | 每個 module 收 `tags = map(string)`，預設 `{}`，只額外加 `Name`。共通 tag 由 root 的 `default_tags` 處理 |
| 命名 | module 不組命名前綴，收完整的 `name`。命名規則是專案的事（見 §5.9） |
| 不用 timestamp | tag 不放 `timestamp()`（project-c 的 `CreateDate` 要搭配 `ignore_changes` 與 provider `ignore_tags` 才不會每次 plan 都有差異，見 `project-c-app/environments/uat/project-c/service/locals.tf`） |
| null 檢查 | 物件變數的 validation 用條件式 `var.x == null ? true : (...)`，不用 `var.x == null || var.x.attr ...`（Terraform 的 `||` 不短路，會對 null 取屬性而報錯） |

### 4.2 `ecs-cluster`

**用途**：建一個 Fargate 用的 ECS cluster。

**參考來源**：

- 底：`infra-platform/docs/slides/terraform-split/terraform-platform-example/platform/modules/core/main.tf`
- Container Insights、FARGATE＋FARGATE_SPOT、Service Connect namespace、預建 performance log group：`project-c-infra/modules/infra-platform/ecs.tf`
- `containerInsights = "enhanced"`：`project-a/infra-v2/terraform/application/ecs-cluster.tf`

**資源**

| 資源 | 條件 |
|---|---|
| `aws_ecs_cluster.this` | 一律 |
| `aws_ecs_cluster_capacity_providers.this` | 一律（FARGATE、FARGATE_SPOT 都掛上，預設策略由變數決定） |
| `aws_cloudwatch_log_group.container_insights` | `container_insights != "disabled"`；名稱 `/aws/ecs/containerinsights/<name>/performance`。不預建的話 AWS 會自動建立且永不過期 |
| `aws_service_discovery_http_namespace.this` | `service_connect_namespace != null` |

**輸入**

```hcl
variable "name" {
  type        = string
  description = "Cluster name."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be 2-63 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "container_insights" {
  type    = string
  default = "enhanced"
  validation {
    condition     = contains(["disabled", "enabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be disabled, enabled or enhanced."
  }
}

variable "default_capacity_provider_strategy" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [{ capacity_provider = "FARGATE" }]
  validation {
    condition     = length(var.default_capacity_provider_strategy) > 0 && alltrue([for s in var.default_capacity_provider_strategy : contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider)])
    error_message = "Strategy must name FARGATE or FARGATE_SPOT only."
  }
  validation {
    condition     = length([for s in var.default_capacity_provider_strategy : s if s.base > 0]) <= 1
    error_message = "Only one capacity provider may set base > 0."
  }
}

variable "service_connect_namespace" {
  type        = string
  default     = null
  description = "Cloud Map HTTP namespace name for Service Connect; null creates none."
}

variable "log_retention_days" {
  type    = number
  default = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "log_kms_key_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`cluster_name`、`cluster_arn`、`cluster_id`、`service_connect_namespace_arn`（沒建時為 `null`）。

**刻意不做**

- 不建 execution role，也不建任何 IAM 資源。範例的 `core` module 把 execution role 放在 cluster module，還掛 `AmazonECSTaskExecutionRolePolicy`（Resource 是 `*`）。角色歸範本的 `iam-base` stack，見 §5.4、§8.1。
- 不支援 EC2 capacity provider。目前所有專案都是 Fargate。
- 不設 ECS Exec 的 cluster 層 logging 設定。第一版 ECS Exec 預設關閉（見 `ecs-service`）。

### 4.3 `ecs-service`

**用途**：部署一個 Fargate 服務：task definition、service、log group、autoscaling，可選 target group＋listener rule。

**參考來源**

- 預設值（ARM64、`initProcessEnabled`、`stopTimeout = 120`、100／200、circuit breaker＋rollback、`availability_zone_rebalancing`、`ignore_changes = [desired_count]`、target group 由外部傳入）：`project-a/infra-v2/terraform/application/ecs-chat-gateway.tf`
- target tracking：`project-a/infra-v2/terraform/postdeploy/ecs-autoscaling.tf`
- step scaling 的門檻與冷卻、「沒開 autoscaling 也建 scalable target，min = max = desired」：`project-c-app/modules/app-service/ecs-autoscaling.tf`
- secrets `valueFrom`、`propagate_tags = "SERVICE"`、Service Connect：`project-c-app/modules/app-service/ecs-standard.tf`
- 由 module 建 target group＋listener rule：`project-c-app/modules/app-service/alb.tf`、範例的 `platform/modules/ecs-web-service/main.tf`
- Fargate CPU／記憶體組合的 validation：範例的 `platform/modules/ecs-web-service/variables.tf`

**資源**

| 資源 | 條件 |
|---|---|
| `aws_cloudwatch_log_group.this` | 一律 |
| `aws_ecs_task_definition.this` | 一律；單一 container，名稱固定 `app` |
| `aws_ecs_service.this` | 一律；`lifecycle { ignore_changes = [desired_count] }` |
| `aws_appautoscaling_target.this` | **一律**。`autoscaling = null` 時 `min = max = desired_count`，讓改 `desired_count` 真的生效（因為 service 忽略了 `desired_count`） |
| `aws_appautoscaling_policy.cpu`／`.requests` | `autoscaling.policy = "target_tracking"`；`requests` 只在 `requests_per_target != null` |
| `aws_appautoscaling_policy.step[<key>]` 與 `aws_cloudwatch_metric_alarm.scaling[<key>]`，key 為 `cpu_scale_out`、`cpu_scale_in`、`memory_scale_out`、`memory_scale_in` | `autoscaling.policy = "step"`。scaling 告警 `period = 60`、`treat_missing_data = "notBreaching"`、`alarm_actions` 只接 scaling policy（不接 SNS）；CPU scale-in 用 `LessThanThreshold`，記憶體 scale-in 用 `LessThanOrEqualToThreshold`（照 project-c 的 `< 40`、`<= 50`） |
| `aws_lb_target_group.this`、`aws_lb_listener_rule.this` | `load_balancer.listener_arn != null` |

**輸入**

```hcl
variable "name" {
  type        = string
  description = "Service name; also the task family, log group suffix and target group name prefix."
  validation {
    # 上限 26：target group 名稱是 "<name>-<port>"，AWS 上限 32 字元
    condition     = can(regex("^[a-z][a-z0-9-]{1,25}$", var.name))
    error_message = "name must be 2-26 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cluster_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]+$", var.cluster_arn))
    error_message = "cluster_arn must be a full ECS cluster ARN."
  }
}

variable "image" {
  type        = string
  description = "Image reference with an explicit tag or digest."
  validation {
    condition     = can(regex("^[^\\s:@]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must carry an explicit tag (not latest) or a sha256 digest."
  }
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
  validation {
    condition = contains(lookup({
      "256"  = [512, 1024, 2048]
      "512"  = [1024, 2048, 3072, 4096]
      "1024" = range(2048, 8193, 1024)
      "2048" = range(4096, 16385, 1024)
      "4096" = range(8192, 30721, 1024)
    }, tostring(var.cpu), []), var.memory)
    error_message = "cpu/memory must be a supported Linux Fargate pair (256-4096 CPU units)."
  }
}

variable "cpu_architecture" {
  type    = string
  default = "ARM64"
  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "container_port" {
  type        = number
  default     = null
  description = "Required when load_balancer or service_connect is set; null for workers without a port."
  validation {
    condition     = var.container_port == null ? true : (var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port)
    error_message = "container_port must be an integer from 1 to 65535."
  }
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "Env var name => Secrets Manager or SSM SecureString ARN (Secrets Manager may append :json-key::)."
  validation {
    condition     = alltrue([for v in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", v))])
    error_message = "Every secret must be a Secrets Manager or SSM parameter ARN."
  }
}

variable "execution_role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}

variable "task_role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}

variable "network" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  validation {
    condition     = length(distinct(var.network.subnet_ids)) >= 2 && length(var.network.security_group_ids) >= 1
    error_message = "Give at least two distinct subnets (different AZs) and one security group."
  }
}

variable "capacity_provider_strategy" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [{ capacity_provider = "FARGATE" }]
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "autoscaling" {
  type = object({
    min_capacity = number
    max_capacity = number
    policy       = optional(string, "target_tracking")
    target_tracking = optional(object({
      cpu_percent         = optional(number, 60)
      requests_per_target = optional(number) # ALBRequestCountPerTarget；需要 load_balancer.alb_arn_suffix
      scale_in_cooldown   = optional(number, 300)
      scale_out_cooldown  = optional(number, 60)
    }), {})
    step = optional(object({
      cpu_scale_out_threshold    = optional(number, 70)
      cpu_scale_in_threshold     = optional(number, 40)
      memory_scale_out_threshold = optional(number, 70)
      memory_scale_in_threshold  = optional(number, 50)
      scale_out_step_size        = optional(number, 10)
      scale_out_cooldown         = optional(number, 180)
      scale_in_cooldown          = optional(number, 300)
    }), {})
  })
  default     = null
  description = "null keeps a fixed task count of desired_count."
  validation {
    condition = var.autoscaling == null ? true : (
      contains(["target_tracking", "step"], var.autoscaling.policy) &&
      var.autoscaling.min_capacity >= 1 &&
      var.autoscaling.max_capacity >= var.autoscaling.min_capacity
    )
    error_message = "policy must be target_tracking or step, and 1 <= min_capacity <= max_capacity."
  }
}

variable "load_balancer" {
  type = object({
    # 模式一（project-a）：外部已建好 target group，只傳 ARN
    target_group_arn = optional(string)
    # 模式二（project-c／範例）：module 建 target group 與 listener rule
    listener_arn  = optional(string)
    vpc_id        = optional(string)
    priority      = optional(number)
    host_headers  = optional(list(string), [])
    path_patterns = optional(list(string), [])
    health_check = optional(object({
      path                = optional(string, "/health")
      matcher             = optional(string, "200")
      interval            = optional(number, 10)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    # 兩種模式共用：requests_per_target 與告警需要
    alb_arn_suffix = optional(string)
  })
  default = null
  validation {
    condition = var.load_balancer == null ? true : (
      (var.load_balancer.target_group_arn != null) != (var.load_balancer.listener_arn != null)
    )
    error_message = "Set exactly one of target_group_arn or listener_arn."
  }
  validation {
    condition = var.load_balancer == null ? true : (
      var.load_balancer.listener_arn == null ? true : (
        var.load_balancer.vpc_id != null && var.load_balancer.priority != null &&
        length(var.load_balancer.host_headers) + length(var.load_balancer.path_patterns) > 0
      )
    )
    error_message = "listener_arn mode needs vpc_id, priority and at least one host_headers or path_patterns entry."
  }
}

# 只在 load_balancer 不為 null 時套用；沒有 LB 時 service 的 grace period 傳 null
variable "health_check_grace_period_seconds" {
  type    = number
  default = 180
}

variable "container_health_check" {
  type = object({
    command      = list(string)
    interval     = optional(number, 10)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 60)
  })
  default = null
}

variable "service_connect" {
  type = object({
    namespace_arn = string
    dns_name      = optional(string) # null 時用 var.name
  })
  default = null
}

variable "enable_execute_command" {
  type    = bool
  default = false
}

variable "log_group_name" {
  type    = string
  default = null # null 時為 /ecs/<name>
}

variable "log_retention_days" {
  type    = number
  default = 30
  # validation 同 ecs-cluster
}

variable "log_kms_key_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

跨變數的 validation（Terraform 1.9 起可以引用其他變數，1.10 以上一定可用）：

- `load_balancer != null` 或 `service_connect != null` 時，`container_port` 不得為 null。
- `autoscaling.target_tracking.requests_per_target != null` 時，`load_balancer.alb_arn_suffix` 不得為 null。
- `autoscaling != null` 時，`desired_count` 必須介於 `min_capacity` 與 `max_capacity` 之間。

**固定行為（不開變數）**

| 項目 | 值 | 為什麼不開 |
|---|---|---|
| 啟動型態 | Fargate、awsvpc、`assign_public_ip = false` | 現有專案全部如此；要公有 IP 代表設計有問題 |
| 部署 | min 100％、max 200％、circuit breaker＋rollback | 三個來源一致 |
| container | `initProcessEnabled = true`、`stopTimeout = 120`、log driver `awslogs` 且 `mode = "non-blocking"` | project-a 已在正式站驗證過 non-blocking |
| service | `propagate_tags = "SERVICE"`、`availability_zone_rebalancing = "ENABLED"`、`wait_for_steady_state = false` | `wait_for_steady_state = true` 會讓 apply 卡到服務穩定，失敗時 circuit breaker 已經會 rollback |
| target group | 名稱 `<name>-<container_port>`、`target_type = "ip"`、`protocol = "HTTP"`、`create_before_destroy = true` | 名稱帶 port，改 port 時新舊名稱不同，`create_before_destroy` 才成立。範例用 `name_prefix = "svc-"`，在 console 與告警維度裡分不出是哪個服務 |
| 步進式擴縮 | 三階 +1／+2／+3，scale-in −1，評估期 1 分鐘／5 分鐘 | 照 project-c；門檻與冷卻開在 `autoscaling.step` |

region 不另外收變數，從 `cluster_arn` 第四段拆出（`awslogs-region` 用它）；log driver 另外固定 `awslogs-stream-prefix = "app"`、`max-buffer-size = "25m"`（照 project-a）；port mapping 與 Service Connect 的 port name 固定為 `app`。

**輸出**：`service_name`、`service_arn`（取 `aws_ecs_service.this.id`，provider 的 ECS service `id` 就是 ARN）、`cluster_name`（從 ARN 拆出）、`task_definition_arn`、`task_definition_family`、`container_name`（固定 `app`）、`log_group_name`、`log_group_arn`、`target_group_arn`（模式一回傳傳入值、模式二回傳建立的、沒有 LB 時 `null`）、`target_group_arn_suffix`（從 ARN 拆出，給告警用）、`autoscaling_resource_id`（`service/<cluster>/<service>`）。

**刻意不做**

- 不建 security group。服務的 SG 由 `network` stack 建好，經 SSM 傳到 `application`，從 `network.security_group_ids` 傳入（見上方 `network` 變數）。
- 不建任何 IAM 資源（role、policy、attachment 都不建），只收 `execution_role_arn` 與 `task_role_arn`。execution role 在範本的 `iam-base` stack、task role 在 `iam-app` stack 建好，ARN 經 SSM 傳到 `application` stack 再傳進來（project-a 的做法）。範例的 `ecs-web-service` 在 module 裡建一個沒有任何 policy 的 task role，專案要加權限只能在 module 外另掛，反而分散。客戶自管 IAM 時（例如 project-a prod b2c 的 deploy role 被明確 Deny 改 IAM），module 自建 role 會直接 apply 失敗；收 ARN 就接得上。最小權限的測試因此放在範本的 `iam-base`／`iam-app` stack（§5.4、§7.1），不在這個 module。
- SG 放在 `network` stack 是 project-a 的做法（`project-a/infra-v2/terraform/network/security-groups.tf`），這樣 ALB SG 與服務 SG 的規則在同一個地方看得到。
- 多 container 用通用的 `sidecars` 支援（§4.20），不寫死 ADOT。
- 不做排程擴縮（project-a 的 `backend_scheduled_scaling`）與自訂指標的 step scaling（project-a 的 SSE 連線數）。這些是專案特有的，消費端可以用輸出的 `autoscaling_resource_id` 在 module 外自己加 policy。
- 不收 `readonlyRootFilesystem`。第一版不確定各專案映像能不能唯讀，列入之後的 MINOR。

### 4.4 `ecs-service-alarms`

**用途**：替一個 ECS 服務建標準告警組合，全部接到 SNS；可選建 dashboard。

**參考來源**

- 告警組合、門檻、`alarm_config` 加 `optional()` 的寫法：`project-c-app/modules/app-platform/cloudwatch-alarms.tf`、`variables.tf`（`alarm_config`）
- `alarm_actions` 與 `ok_actions` 都接、到達最大容量告警：`project-a/infra-v2/terraform/postdeploy/alarms.tf`
- dashboard：`project-a/infra-v2/terraform/postdeploy/dashboard.tf`

**告警清單**

| key | 指標 | 條件 | 週期 | 缺資料 | 建立條件 |
|---|---|---|---|---|---|
| `cpu_high` | `AWS/ECS` CPUUtilization（Average） | ≥ `ecs.cpu_threshold`（80） | 300 秒 × 1 | missing | 一律 |
| `memory_high` | `AWS/ECS` MemoryUtilization | ≥ `ecs.memory_threshold`（80） | 300 秒 × 1 | missing | 一律 |
| `cpu_missing` | `AWS/ECS` CPUUtilization | < 0（只靠缺資料觸發） | 60 秒 × 2 | breaching | 一律 |
| `memory_missing` | `AWS/ECS` MemoryUtilization | < 0 | 60 秒 × 2 | breaching | 一律 |
| `tasks_below_desired` | Container Insights `DesiredTaskCount − RunningTaskCount` | > 0，5 中 3 | 60 秒 | notBreaching | 一律 |
| `cpu_throttling` | Container Insights `CpuUtilized / CpuReserved` | > `container.cpu_throttling_threshold`（0.9），3 中 2 | 300 秒 | notBreaching | 一律 |
| `memory_pressure` | Container Insights `MemoryUtilized / MemoryReserved` | > `container.memory_pressure_threshold`（0.85），3 中 2 | 300 秒 | notBreaching | 一律 |
| `at_max_capacity` | Container Insights RunningTaskCount（Maximum） | ≥ `max_capacity` | 60 秒 × 5 | notBreaching | `max_capacity != null` |
| `target_5xx_ratio` | `HTTPCode_Target_5XX_Count / RequestCount` | > `alb.target_5xx_ratio_threshold`（0.01） | 300 秒 × 1 | notBreaching | `load_balancer != null` |
| `target_4xx_ratio` | `HTTPCode_Target_4XX_Count / RequestCount` | > `alb.target_4xx_ratio_threshold`（0.05），3 中 2 | 300 秒 | notBreaching | `load_balancer != null` |
| `latency_p95` | `TargetResponseTime` p95 | > `alb.latency_p95_threshold_ms`（800）/ 1000 | 300 秒 × 3 | notBreaching | `load_balancer != null` |
| `unhealthy_hosts` | `HealthyHostCount`（Minimum） | < `alb.healthy_host_min`（1），3 中 2 | 60 秒 | notBreaching | `load_balancer != null` |
| `target_connection_errors` | `TargetConnectionErrorCount`（Sum） | > 0 | 300 秒 × 1 | notBreaching | `load_balancer != null` |

實作把上表所有告警集中在一個資源 `aws_cloudwatch_metric_alarm.this[<key>]`（`for_each` 一張告警定義表，key 同上表），新增告警只要加一列定義；告警名稱 `<name>-<key>`。

跟 project-c 的差別：project-c 的 Container Insights 告警是 cluster 層級，ALB 告警只看單一 ALB；這裡全部帶 `ServiceName` 或 `TargetGroup` 維度，一個服務一組。service 層級的 `CpuUtilized`／`CpuReserved` 維度是否在 `enhanced` 與 `enabled` 兩種模式都有，要等有 AWS 環境時確認（§7.3）。

**輸入**

```hcl
variable "name" {
  type        = string
  description = "Alarm name prefix, usually the service name; alarms are named <name>-<key>."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,200}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens."
  }
}

variable "cluster_name" { type = string }
variable "service_name" { type = string }

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions. Required: an alarm nobody receives is not an alarm."
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "load_balancer" {
  type = object({
    alb_arn_suffix          = string # app/<name>/<id>
    target_group_arn_suffix = string # targetgroup/<name>/<id>
  })
  default = null
  validation {
    condition     = var.load_balancer == null ? true : (startswith(var.load_balancer.alb_arn_suffix, "app/") && startswith(var.load_balancer.target_group_arn_suffix, "targetgroup/"))
    error_message = "Use ARN suffixes: app/... and targetgroup/... (CloudWatch dimension format)."
  }
}

variable "max_capacity" {
  type    = number
  default = null
}

variable "alarm_config" {
  type = object({
    ecs = optional(object({
      cpu_threshold    = optional(number, 80)
      memory_threshold = optional(number, 80)
    }), {})
    container = optional(object({
      cpu_throttling_threshold  = optional(number, 0.9)
      memory_pressure_threshold = optional(number, 0.85)
    }), {})
    alb = optional(object({
      target_5xx_ratio_threshold = optional(number, 0.01)
      target_4xx_ratio_threshold = optional(number, 0.05)
      latency_p95_threshold_ms   = optional(number, 800)
      healthy_host_min           = optional(number, 1)
    }), {})
  })
  default = {}
}

variable "dashboard_name" {
  type        = string
  default     = null
  description = "null creates no dashboard."
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

`alarm_config` 跟 project-c 的結構一樣，但拿掉 `enabled`：要不要告警不是 module 的選項。`target_group_arn_suffix` 要求帶 `targetgroup/` 前綴，避免 project-a 那種「同一個值在 autoscaling 不帶、在告警要帶」的雙格式（見 `project-a/infra-v2/terraform/postdeploy/ecs-autoscaling.tf` 的 `startswith` 註解）。

**輸出**：`alarm_arns`（`map(string)`，key 同上表）、`alarm_names`、`dashboard_arn`（沒建時 `null`）。

**刻意不做**

- **ALB 整體的告警**（`HTTPCode_ELB_5XX_Count`）。這些只有 `LoadBalancer` 維度，多個服務共用一個 ALB 時，每個服務各建一份會重複，所以放在 `alb` module，一個 ALB 只建一份（§4.8）。
- 資料庫的告警放在 `rds` module（§4.9）；Bedrock、ElastiCache 的告警（project-c 有）不在第一版範圍。
- `insufficient_data_actions`。缺資料的情況已經用 `*_missing` 告警以 breaching 處理。
- 告警嚴重度分級（P1／P2）與分 topic 路由。第一版所有告警送同一組 `sns_topic_arns`；要分級時，消費端呼叫兩次 module 或在 MINOR 版加 `severity` 對照。

### 4.5 `sns-alarm-topic`

**用途**：建一個告警用 SNS topic 與 email 訂閱。

**參考來源**：`project-c-infra/modules/infra-platform/sns.tf`（alarm group＋email 訂閱）、`project-a/infra-v2/terraform/foundation/alarms.tf`（單一 topic＋email／https 訂閱）。

**設計選擇**：一次呼叫一個 topic。project-c 用一個 `alarm_groups` map 在 module 裡建多個 topic；這裡改成要多個群組時在 root 用 `for_each` 呼叫 module。module 介面比較小，測試也比較單純。

**資源**：`aws_sns_topic.this`、`aws_sns_topic_subscription.email`（`for_each` email 清單）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,256}$", var.name))
    error_message = "name must be 1-256 letters, digits, hyphens or underscores."
  }
}

variable "email_subscriptions" {
  type    = list(string)
  default = []
  validation {
    condition     = alltrue([for e in var.email_subscriptions : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry must be an email address."
  }
}

variable "kms_master_key_id" {
  type        = string
  default     = null
  description = "Customer managed KMS key ARN; its key policy must let cloudwatch.amazonaws.com use it."
  validation {
    condition     = var.kms_master_key_id == null ? true : var.kms_master_key_id != "alias/aws/sns"
    error_message = "alias/aws/sns cannot be used: CloudWatch alarms cannot publish to a topic encrypted with the AWS managed key."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`topic_arn`、`topic_name`、`subscription_arns`。

**刻意不做**

- 不管 topic policy。同帳號的 CloudWatch 告警用預設 policy 即可發布；跨帳號發布不在第一版範圍。
- 不建 KMS key。key 屬於 `foundation` stack（多個資源共用），這裡只收 ARN。
- 不做 Lambda／https／Slack／Chatbot 訂閱。消費端可以用輸出的 `topic_arn` 自己加。

注意：email 訂閱建立後是「待確認」狀態，收件人要點確認信才會收到告警。`terraform apply` 成功不代表通知會到。

### 4.6 `ssm-publish`

**用途**：把一個 stack 要給下游的值寫進 SSM Parameter Store，路徑 `<ssm_prefix>/<stack>/<key>`。這是專案範本裡**唯一**可以宣告 `aws_ssm_parameter` 的地方。

**參考來源**：`project-a/infra-v2/terraform/modules/ssm-publish/`（介面原樣保留：`ssm_prefix`、`stack`、`strings`、`lists`；輸出 `names`、`arns`）。

**跟 project-a 的差別**：補上 validation、description 不寫死 `infra-v2/terraform/...` 路徑、空字串與含逗號的 list 元素在 plan 前就擋掉。

**資源**：`aws_ssm_parameter.string`（`type = "String"`）、`aws_ssm_parameter.list`（`type = "StringList"`，以逗號串接），都是 `tier = "Standard"`、寫 `insecure_value`。

**輸入**

```hcl
variable "ssm_prefix" {
  type        = string
  description = "/<project>/<env>"
  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "stack" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.stack))
    error_message = "stack must be lowercase letters, digits or hyphens."
  }
}

variable "strings" {
  type    = map(string)
  default = {}
  validation {
    condition     = alltrue([for k, v in var.strings : can(regex("^[a-z][a-z0-9_]*$", k)) && length(v) > 0 && length(v) <= 4096])
    error_message = "Keys must be snake_case; values must be 1-4096 chars (SSM rejects empty strings; wrap optional values in JSON)."
  }
}

variable "lists" {
  type    = map(list(string))
  default = {}
  validation {
    condition     = alltrue([for k, v in var.lists : can(regex("^[a-z][a-z0-9_]*$", k)) && length(v) > 0 && alltrue([for e in v : length(e) > 0 && !strcontains(e, ",")])])
    error_message = "Keys must be snake_case; lists must be non-empty and elements must not contain commas."
  }
}
```

另加一條 validation：`strings` 與 `lists` 的 key 不得重複（兩者會寫到同一層路徑）。

**輸出**：`names`、`arns`（`map(string)`，key 為參數 key）。

**刻意不做**

- 不支援 `SecureString`。secret 不進 SSM，走 Secrets Manager（§5.6、§8.2）。
- 不負責讀取。讀取由配對的 `ssm-read` module 負責（§4.13），兩者的路徑與 key 規則相同。

### 4.7 `vpc`

**用途**：建一個 VPC 與它的 subnet、IGW、NAT、route table、gateway endpoint、flow log。interface endpoint 不在這裡，由 `vpc-interface-endpoints`（§4.21）負責。tier 的數量與切法由呼叫端決定，module 不寫死「三層」。

**參考來源**

- subnet 依 tier 分、`cidrsubnet` 自動切：`project-a/infra-v2/terraform/network/vpc.tf`、`subnets-app.tf`
- 三種 tier 的路由（public 走 IGW、private 走 NAT、db 只有 local）、S3 gateway endpoint 關聯全部私有路由表：`project-a/docs/spec/infra.md`〈網路網段與子網配置模型〉、`project-a/infra-v2/terraform/network/nat.tf`、`vpc-endpoints.tf`
- 明確指定每個 subnet 的 CIDR、tier 名稱：`project-c-infra/environments/{uat,prod}/network/terraform.tfvars`（`ingress`／`ecs`／`db`／`egress` 四個 tier）

**要修掉的坑**：project-a 的 `ecs_app` 與 `agent_app` 用不同的 `newbits` 從同一個 VPC CIDR 切，只放得下兩個 AZ，第三個 AZ 會跟別的 subnet 靜默重疊，只能靠一條寫死的 precondition 擋（`project-a/infra-v2/terraform/network/subnets-app.tf` 的 `two_az_layout_ok`）。這裡改成把所有 subnet 的 CIDR 換成起訖整數，兩兩比對不重疊，不管怎麼切都擋得住。

**資源**

| 資源 | 條件 | 說明 |
|---|---|---|
| `aws_vpc.this` | 一律 | `enable_dns_support`、`enable_dns_hostnames` 都開（interface endpoint 的 private DNS 需要） |
| `aws_default_security_group.this` | 一律 | 不宣告任何規則，等於把 default SG 的規則清空，避免有資源誤用它 |
| `aws_subnet.this` | `for_each`，key 為 `"<tier>/<az>"` | 不用 `count`：增減 AZ 時 index 會位移，造成 subnet 重建 |
| `aws_internet_gateway.this` | 有 public tier 時 | — |
| `aws_eip.nat`、`aws_nat_gateway.this` | `nat_mode = "single"`：1 顆，放在第一個 AZ 的 public subnet；`"per_az"`：每個 AZ 一顆；`"none"`：不建 | — |
| `aws_route_table.this`、`aws_route_table_association.this` | 每個 subnet 一張表，key 同 subnet | 統一一 subnet 一表，`per_az` 才能讓每個 AZ 走自己的 NAT |
| `aws_route.public_igw` | public tier 的每張表 | `0.0.0.0/0` → IGW |
| `aws_route.private_nat` | private tier 的每張表，`nat_mode != "none"` | `single`：全部指向同一顆；`per_az`：指向同 AZ 那顆 |
| （isolated tier） | — | 只有 local 路由 |
| `aws_vpc_endpoint.gateway` | `for_each = gateway_endpoints` | 關聯所有 private 與 isolated tier 的路由表 |
| `aws_flow_log.this` | `flow_log != null` | 只支援 S3，不需要 IAM role |

路由一律用 `aws_route` 獨立資源，不寫 inline `route {}`（§4.1）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cidr" {
  type = string
  validation {
    condition = (
      can(cidrnetmask(var.cidr)) &&
      cidrsubnet(var.cidr, 0, 0) == var.cidr &&
      tonumber(split("/", var.cidr)[1]) >= 16 &&
      tonumber(split("/", var.cidr)[1]) <= 24
    )
    error_message = "cidr must be an IPv4 network address from /16 to /24 (e.g. 10.20.0.0/20)."
  }
}

variable "azs" {
  type = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 to 4 distinct availability zones."
  }
}

variable "subnets" {
  description = "Tier name => layout. Give either newbits + netnum_base (auto split) or cidrs (az => cidr), never both."
  type = map(object({
    type        = string                # public | private | isolated
    newbits     = optional(number)
    netnum_base = optional(number)
    cidrs       = optional(map(string)) # key 必須涵蓋每一個 AZ
  }))
  validation {
    condition     = alltrue([for k, v in var.subnets : can(regex("^[a-z][a-z0-9_]*$", k)) && contains(["public", "private", "isolated"], v.type)])
    error_message = "Tier names must be snake_case and type must be public, private or isolated."
  }
  validation {
    condition = alltrue([for v in values(var.subnets) :
      v.cidrs != null ? (v.newbits == null && v.netnum_base == null) : (v.newbits != null && v.netnum_base != null)
    ])
    error_message = "Each tier needs exactly one of: newbits + netnum_base, or cidrs."
  }
  validation {
    condition     = length([for v in values(var.subnets) : v if v.type == "public"]) <= 1
    error_message = "At most one public tier."
  }
}

variable "nat_mode" {
  type    = string
  default = "single"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single or per_az."
  }
}

variable "gateway_endpoints" {
  type    = set(string)
  default = ["s3"]
  validation {
    condition     = alltrue([for e in var.gateway_endpoints : contains(["s3", "dynamodb"], e)])
    error_message = "gateway_endpoints accepts only s3 and dynamodb."
  }
}

variable "flow_log" {
  type = object({
    destination_arn = string                  # S3 bucket ARN（可帶 /prefix）
    traffic_type    = optional(string, "ALL") # ACCEPT | REJECT | ALL
  })
  default = null
  validation {
    condition = var.flow_log == null ? true : (
      can(regex("^arn:aws[a-z-]*:s3:::", var.flow_log.destination_arn)) &&
      contains(["ACCEPT", "REJECT", "ALL"], var.flow_log.traffic_type)
    )
    error_message = "flow_log supports S3 destinations only; traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

跨變數 validation 與 precondition（放在 `aws_vpc.this` 的 `lifecycle.precondition`）：

| 檢查 | 失敗時的訊息重點 |
|---|---|
| 某個 tier 用 `cidrs` 時，`keys(cidrs)` 必須等於 `azs` | 少給或多給 AZ |
| 自動切時，`netnum_base + length(azs) <= pow(2, newbits)` | 槽位不夠 |
| `nat_mode != "none"` 時必須有 public tier | NAT 沒地方放 |
| 所有 subnet 都在 VPC CIDR 內 | 切出界 |
| 所有 subnet 的 CIDR 兩兩不重疊 | 把每個 CIDR 換成 `[起始整數, 結束整數]`（IP 四段乘 256 的冪次相加；結束 = 起始 + 2^(32−prefix) − 1），對每一對檢查 `end_a < start_b || end_b < start_a` |

**自動切的建議切法**：每個 tier 預留 4 個 AZ 的槽位（`netnum_base` 以 4 為間隔），之後從 2 個 AZ 加到 3、4 個時，既有 subnet 不用動。範本的範例（§5.11）照這個切。

**增減 AZ 時 CIDR 會不會變（實作確認）**：subnet 的 key 是 `"<tier>/<az>"`，增減 AZ 時既有的 key 不變。但自動切的槽位是照 AZ 在 `azs` 清單裡的**位置**算的（`cidrsubnet(cidr, newbits, netnum_base + index)`，`modules/vpc/locals.tf`）：在清單尾端加 AZ、或移除最後一個 AZ，其他 subnet 的 CIDR 不變；**移除中間的 AZ，後面 AZ 的 CIDR 會位移，subnet 會重建**。要固定每個 AZ 的 CIDR，就用明確指定的 `cidrs`。module README 已寫明。

實作另外多了兩條檢查：`cidrs` 的值必須是合法 IPv4 CIDR；自動切時 `newbits >= 1`、`netnum_base >= 0`、切出的 subnet 不得小於 `/28`。

**輸出**

| 輸出 | 型別 | 說明 |
|---|---|---|
| `vpc_id`、`vpc_cidr` | `string` | — |
| `azs` | `list(string)` | 原樣回傳，下游依這個順序對應清單 |
| `subnet_ids` | `map(list(string))` | tier => 依 `azs` 順序的 subnet id |
| `subnet_cidrs` | `map(list(string))` | 同上，CIDR |
| `route_table_ids` | `map(list(string))` | 同上，route table id |
| `nat_gateway_ids` | `list(string)` | 依 AZ 順序；`none` 時為 `[]`，`single` 時只有 1 個 |

**範本固定的三個 tier 名稱**：`public`（type `public`）、`app`（type `private`）、`data`（type `isolated`；DB 需要對外連線時改 `private`）。這三個名稱寫進 SSM 合約（§5.6），不可更改；要加 tier 可以，名稱不能跟這三個衝突。

**為什麼 IGW、NAT、gateway endpoint 留在 `vpc`，interface endpoint 拆出去**（決策 34）：IGW、NAT、gateway endpoint 實際上都是路由，要跟 `vpc` 自己建的 route table 放在一起。拆出去的話，`per_az` 的 NAT 對應到錯的 route table 也不會報錯，加 AZ 時要同時改兩個 module。客戶自管 VPC 時，路由由客戶管，我們不該碰：project-a 的 public route table 用 inline `route {}`，每次 apply 都把客戶加的 peering 路由刪掉（`project-a/docs/reports/2026-09-04-customer-owned-network-and-terraform.md`）。interface endpoint 不碰路由，拆成 `vpc-interface-endpoints`（§4.21）之後，network stack 在自建 VPC 與客戶已建好的 VPC 兩種情況都能呼叫它。

**default SG**：`aws_default_security_group.this` 留在 `vpc`。它不是新建的 SG，而是接管這個 VPC 本來就有的那一個並清空規則，生命週期跟 VPC 綁在一起，而且只有建 VPC 的 module 該碰它。§5.6 S4 把它單獨列出：`aws_default_security_group` 只准出現在 `modules/vpc/`；客戶自管 VPC（模式 A）時，我們不呼叫 `vpc`，也就不會去清空客戶 VPC 的 default SG。

**刻意不做**：interface endpoint 與它的 SG（拆到 `vpc-interface-endpoints`，§4.21）；IPv6、private NAT、Transit Gateway 與 VPC peering 的路由（§1）；NACL（用 SG 就夠，NACL 是無狀態的，調錯很難查）；flow log 送 CloudWatch Logs（要多一個 IAM role，而只有 `iam-role` 能建 IAM）；流量規格 preset（放範本的範例 tfvars，§5.11）。

### 4.8 `alb`

**用途**：建一個 Application Load Balancer、listener（預設回 404）、ALB 整體的告警，可選 access log 與 WAF 關聯。target group 與 listener rule 由 `ecs-service` 建（§4.3 模式二）。

**參考來源**

- ALB、listener、預設 fixed-response、TLS 1.3 policy 與 80→443 轉址的規格：`project-a/infra-v2/terraform/loadbalancer/alb.tf`、`project-a/docs/spec/infra.md`〈入口負載平衡器與 WAF 防護〉（注意 project-a 實作只有 HTTP:80，見 §9.4）
- access log bucket 只能用 SSE-S3：`project-a/infra-v2/terraform/loadbalancer/access-logs.tf` 的註解
- ELB 5xx 告警：`project-c-app/modules/app-platform/cloudwatch-alarms.tf`（`alb_elb_5xx`）

**資源**

| 資源 | 條件 |
|---|---|
| `aws_lb.this` | 一律；`load_balancer_type = "application"`、`drop_invalid_header_fields = true` |
| `aws_lb_listener.https` | `certificate_arn != null`；443、`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`、預設 action 回 404 |
| `aws_lb_listener_certificate.additional` | `for_each = additional_certificate_arns` |
| `aws_lb_listener.http` | 一律；有憑證時預設 action 為 301 轉到 HTTPS，沒有憑證時預設 action 回 404（本文 `Not Found`） |
| `aws_wafv2_web_acl_association.this` | `web_acl_arn != null` |
| `aws_cloudwatch_metric_alarm.elb_5xx` | 一律；名稱 `<name>-elb-5xx`，`HTTPCode_ELB_5XX_Count` 的 `Sum`，`comparison_operator = "GreaterThanOrEqualToThreshold"`（門檻預設 1，等於「大於 0」），`evaluation_periods = 1`，`treat_missing_data = "notBreaching"` |

預設 action 回 404（`text/plain`）而不是 project-a 的 403：沒有對應的路由就是「找不到」，不是「被禁止」。這只是回應碼的選擇，安全性相同。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 letters, digits or hyphens, not starting or ending with a hyphen nor starting with internal-."
  }
}

variable "internal" {
  type    = bool
  default = false
}

variable "subnet_ids" {
  type        = list(string)
  description = "public tier subnets (internal = true: app tier)."
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  type = list(string)
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Give at least one security group (created by the network stack)."
  }
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = "ACM certificate. null opens HTTP:80 only; the network stack must then narrow the ALB security group."
  validation {
    condition     = var.certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "additional_certificate_arns" {
  type    = set(string)
  default = []
}

variable "idle_timeout" {
  type    = number
  default = 60
  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be 1-4000 seconds."
  }
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "access_logs" {
  type = object({
    bucket = string           # SSE-S3 加密的 bucket 名稱（不是 ARN）
    prefix = optional(string) # null 時寫在 bucket 根目錄
  })
  default = null
}

variable "web_acl_arn" {
  type    = string
  default = null
  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl_arn))
    error_message = "web_acl_arn must be a regional WAFv2 Web ACL ARN."
  }
}

variable "sns_topic_arns" {
  type = list(string)
  # validation 同 ecs-service-alarms：至少一個 SNS ARN
}

variable "alarm_config" {
  type = object({
    elb_5xx_threshold = optional(number, 1)  # 一個 period 內的 HTTPCode_ELB_5XX_Count 總和
    period            = optional(number, 60)
  })
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

跨變數 validation：`additional_certificate_arns` 非空時 `certificate_arn` 不得為 null。

**輸出**：`alb_arn`、`alb_arn_suffix`（`app/<name>/<id>`，給告警與 `requests_per_target`）、`alb_dns_name`、`alb_zone_id`、`listener_arn`（有憑證時是 HTTPS listener，否則是 HTTP listener）、`listener_protocol`（`"HTTPS"` 或 `"HTTP"`）、`alarm_arns`。

**怎麼接**：`listener_arn` 接到 `ecs-service.load_balancer.listener_arn`；`alb_arn_suffix` 接到 `ecs-service.load_balancer.alb_arn_suffix` 與 `ecs-service-alarms.load_balancer.alb_arn_suffix`。

**刻意不做**

- 不建 security group。ALB 的 SG 由 `network` stack 建，沒有憑證時的收窄規則也在那裡檢查（§5.3、§8.4）。
- 不建 Web ACL，只做關聯。Web ACL 的規則每個專案不同，由專案自己建。
- 不建 access log 的 bucket。bucket 在 `foundation`（§5.3），只能用 SSE-S3：ALB 的 log delivery 不支援 customer managed KMS，設了 log 會無聲遺失。
- 不建 target group 與 listener rule（`ecs-service` 負責）。
- 不支援 NLB、mutual TLS、Cognito／OIDC 認證 action。

### 4.9 `rds`

**用途**：建一個 PostgreSQL 資料庫，三種型態擇一：一般 RDS（`rds`）、Aurora provisioned（`aurora`）、Aurora Serverless v2（`aurora_serverless`）。RDS Proxy 是選項。不管哪種型態，輸出的端點與識別碼格式都一樣，下游不用知道選了哪種。

**參考來源**

- Aurora cluster、`manage_master_user_password`、參數群組與四個預設參數、`random_id` 的 final snapshot 後綴、Proxy（`SECRETS` auth、`require_tls`、`max_connections_percent = 50`、read-only endpoint）：`project-a/infra-v2/terraform/database/rds.tf`、`rds-proxy.tf`
- Proxy 的兩條告警（borrowed > 80％、pinned > 20％）：`project-a/infra-v2/terraform/database/alarms.tf`、`variables.tf`
- Serverless v2 的 ACU 範圍、CPU／FreeableMemory／DatabaseConnections／ReplicaLag 告警與門檻、Serverless 的 `max_connections` 推算公式：`project-c-app/modules/app-platform/rds.tf`、`cloudwatch-alarms.tf`、`variables.tf`（`alarm_config.aurora`）

**型態與資源**

| 資源 | `rds` | `aurora` | `aurora_serverless` |
|---|---|---|---|
| `aws_db_subnet_group.this` | ✓ | ✓ | ✓ |
| `aws_db_parameter_group.rds`（family `postgres<major>`） | ✓ | | |
| `aws_db_instance.this[0]` | ✓ | | |
| `aws_rds_cluster_parameter_group.this`（family `aurora-postgresql<major>`） | | ✓ | ✓ |
| `aws_db_parameter_group.aurora_instance`（family `aurora-postgresql<major>`；`instance_parameters` 非空才建） | | 選用 | 選用 |
| `aws_rds_cluster.this[0]` | | ✓ | ✓（加 `dynamic "serverlessv2_scaling_configuration"`） |
| `aws_rds_cluster_instance.this`（`count = 1 + reader_count`，index 0 是 writer；識別碼 `<name>-writer`、`<name>-reader-N`） | | 指定的 class | `db.serverless` |
| `aws_cloudwatch_log_group.postgresql` | `/aws/rds/instance/<name>/postgresql` | `/aws/rds/cluster/<name>/postgresql` | 同 aurora |
| `random_id.final_snapshot` | ✓ | ✓ | ✓ |
| Proxy 一組（見下） | `proxy != null` | `proxy != null` | `proxy != null` |
| 告警（見下） | ✓ | ✓ | ✓ |

實作細節（以 `modules/rds/` 為準）：

- 型態切換用 `count`，所以 `aws_db_instance`、`aws_rds_cluster` 的位址都帶 `[0]`。
- 一般 RDS 的 instance 識別碼就是 `name`；Aurora 的 instance 是 `<name>-writer`、`<name>-reader-1`、`<name>-reader-2`……，告警的 key 與名稱也帶這個後綴（例如 `cpu_high_writer`）。
- 因為 final snapshot 的 `random_id`，`versions.tf` 多宣告 `hashicorp/random >= 3.0`。
- 參數群組裡只有 `shared_preload_libraries` 用 `apply_method = "pending-reboot"`，其他參數 `immediate`。Aurora 的 instance 參數群組只放呼叫端給的 `instance_parameters`，不含四個預設參數（預設參數在 cluster 參數群組）。
- Proxy 的 read-only endpoint 名稱是 `<name>-ro`；Performance Insights 沿用 `kms_key_arn`；Aurora 的 `promotion_tier` writer 為 0、reader 為 1。
- validation 比本節列的多，例如 `performance_insights_retention_days` 只收 AWS 接受的值（7、731，或 31 的倍數且不超過 713）、`monitoring.interval` 只收 1、5、10、15、30、60；以 `modules/rds/variables.tf` 為準。`sns_topic_arns` 的 ARN regex 結尾是 `.+`，比 `alb`、`ecs-service-alarms` 的 `[A-Za-z0-9_-]+` 寬（§9.4 D17）。

`aurora` 與 `aurora_serverless` 共用同一組資源位址，互換時是就地修改（instance class 在 provisioned 與 `db.serverless` 之間切換）。`rds` 與 Aurora 互換是 destroy 加 create，會被 `deletion_protection` 擋下；這屬於資料遷移，不是改一個變數，README 要寫清楚。兩種互換的實際行為 mock 驗不到，列在 §7.3。

**固定行為（不開變數）**

| 項目 | 值 |
|---|---|
| 引擎 | PostgreSQL（`postgres`／`aurora-postgresql`） |
| 密碼 | `manage_master_user_password = true`，密碼由 RDS 放在 Secrets Manager；**module 沒有任何 password 變數** |
| 加密與網路 | `storage_encrypted = true`、`publicly_accessible = false` |
| snapshot | `copy_tags_to_snapshot = true`；final snapshot 名稱 `<name>-final-<random_id>`，避免重建時撞名 |
| 預設參數 | `log_min_duration_statement = 500`、`log_lock_waits = 1`、`rds.force_ssl = 1`、`shared_preload_libraries = pg_stat_statements`；呼叫端給的同名參數會覆蓋 |
| log | export `postgresql`，log group 預先建立（才能控制保留天數與 KMS） |
| Performance Insights | 開啟，保留天數由變數控制 |
| 端點 | 一般 RDS 一律用 `aws_db_instance.this.address`，不用 `.endpoint`（後者是 `host:port`） |

**輸入（共用）**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,49}$", var.name)) && !strcontains(var.name, "--") && !endswith(var.name, "-")
    error_message = "name must start with a letter, use lowercase letters, digits and single hyphens, and be at most 50 chars."
  }
}

variable "deployment" {
  type = string
  validation {
    condition     = contains(["rds", "aurora", "aurora_serverless"], var.deployment)
    error_message = "deployment must be rds, aurora or aurora_serverless."
  }
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major.minor, e.g. 16.4."
  validation {
    condition     = can(regex("^1[3-7]\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be major.minor for PostgreSQL 13-17."
  }
}

variable "database_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be lowercase letters, digits or underscores, starting with a letter."
  }
}

variable "master_username" {
  type    = string
  default = "dbadmin"
}

variable "subnet_ids" {
  type        = list(string)
  description = "data tier subnets."
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "DB security group(s), created by the network stack."
}

variable "kms_key_arn" {
  type    = string
  default = null # null 用 AWS managed key（aws/rds）
}

variable "master_user_secret_kms_key_arn" {
  type    = string
  default = null # null 用 aws/secretsmanager
}

variable "backup_retention_days" {
  type    = number
  default = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be 1-35."
  }
}

variable "backup_window" {
  type    = string
  default = "18:00-19:00" # UTC，台灣 02:00-03:00
}

variable "maintenance_window" {
  type    = string
  default = "sun:19:00-sun:20:00" # UTC，台灣週一 03:00-04:00
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "cluster_parameters" {
  type    = map(string)
  default = {} # deployment = "rds" 時必須為空
}

variable "instance_parameters" {
  type    = map(string)
  default = {}
}

variable "performance_insights_retention_days" {
  type    = number
  default = 7
}

variable "monitoring" {
  type = object({
    interval = optional(number, 60) # 1, 5, 10, 15, 30, 60
    role_arn = string               # iam-base 的 role_rds_monitoring_arn
  })
  default = null # null 不開 Enhanced Monitoring
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_kms_key_arn" {
  type    = string
  default = null
}

variable "sns_topic_arns" {
  type = list(string)
  # validation 同 ecs-service-alarms：至少一個 SNS ARN
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸入（型態專屬）**：選了哪個型態就必須給那個物件，另外兩個必須是 null（交叉 validation，Terraform 1.9 以上）。

```hcl
variable "rds" {
  type = object({
    instance_class        = string           # 例：db.t4g.small
    allocated_storage     = optional(number, 20)
    max_allocated_storage = optional(number) # null 不開 storage autoscaling
    multi_az              = optional(bool, false)
    storage_type          = optional(string, "gp3")
  })
  default = null
}

variable "aurora" {
  type = object({
    instance_class = string                # 例：db.r7g.large；不可為 db.serverless
    reader_count   = optional(number, 1)
  })
  default = null
}

variable "serverless" {
  type = object({
    min_capacity = number                  # ACU，0.5 為單位
    max_capacity = number
    reader_count = optional(number, 0)
  })
  default = null
}
```

| validation | 條件 |
|---|---|
| 型態物件相符 | `deployment = "rds"` ⇔ `rds != null`，另外兩個為 null；其餘兩種型態同理 |
| Aurora 的 class | `aurora.instance_class != "db.serverless"`，且以 `db.` 開頭 |
| ACU | `0 <= min_capacity <= max_capacity <= 256`，且兩者都是 0.5 的倍數。`min_capacity = 0`（閒置自動暫停）是 AWS 較新的功能，跟 engine 版本有關，**未驗證**（§7.3） |
| reader 數 | `0 <= reader_count <= 15` |
| 一般 RDS 沒有 cluster 參數 | `deployment = "rds"` 時 `cluster_parameters` 必須為空 |
| 版本對應 family | `<major>` 取自 `engine_version` 第一段 |

**Proxy**

```hcl
variable "proxy" {
  type = object({
    security_group_ids           = list(string) # network stack 的 sg_db_proxy_id
    role_arn                     = optional(string) # 實質必填，由下面的 validation 擋 null；iam-base 的 role_rds_proxy_arn
    require_tls                  = optional(bool, true)
    idle_client_timeout          = optional(number, 1800)
    max_connections_percent      = optional(number, 50)
    max_idle_connections_percent = optional(number, 25)
    debug_logging                = optional(bool, false)
  })
  default = null
  validation {
    condition     = var.proxy == null ? true : (var.proxy.role_arn != null && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.proxy.role_arn)))
    error_message = "proxy.role_arn is required and must be an IAM role ARN (created in the iam-base stack)."
  }
}
```

`role_arn` 宣告成 `optional(string)` 再用 validation 擋 null，而不是直接寫 `string`：必填屬性缺漏時，Terraform 會在型別轉換階段就報錯，`expect_failures` 抓不到，負向測試就鎖不住「忘了給 role」這件事。改成 optional 加 validation，缺漏會變成 `var.proxy` 的 validation 失敗，測試可以用 `expect_failures = [var.proxy]` 斷言。

開啟時建立：

| 資源 | 說明 |
|---|---|
| `aws_db_proxy.this` | `engine_family = "POSTGRESQL"`；`auth` 用 `SECRETS`，`secret_arn` 指向 master secret，`iam_auth = "DISABLED"`；放在同一組 data tier subnet |
| `aws_db_proxy_default_target_group.this` | 連線池參數 |
| `aws_db_proxy_target.this` | `rds` 用 `db_instance_identifier`；Aurora 用 `db_cluster_identifier` |
| `aws_db_proxy_endpoint.read_only` | 只有 Aurora 且 `reader_count > 0` 時建立，`target_role = "READ_ONLY"` |
| `aws_cloudwatch_log_group.proxy` | `/aws/rds/proxy/<name>` |

module 不建 Proxy 的 role，也不幫它附加讀 secret 的 policy。role 的 trust 由 `iam-base` 建，讀 secret 的 policy 由 `iam-app` 在 secret 存在之後附加（§5.4）。

**告警**（`alarm_actions`、`ok_actions` 都接 `sns_topic_arns`）

| key | 指標與維度 | 條件（預設） | 建立條件 | 來源 |
|---|---|---|---|---|
| `cpu_high` | `CPUUtilization`，每個 instance（`DBInstanceIdentifier`） | ≥ 80％，300 秒 × 3 | 一律 | project-c `aurora_cpu_high` |
| `freeable_memory_low` | `FreeableMemory`，每個 instance | ≤ 200 MB，60 秒 × 15 | 一律 | project-c `aurora_mem_low` |
| `connections_high` | `DatabaseConnections`（rds：`DBInstanceIdentifier`；Aurora：`DBClusterIdentifier`） | ≥ `connections_threshold`，300 秒 3 中 2 | 一律（門檻見下） | project-c `aurora_conn_high` |
| `replica_lag_high` | `AuroraReplicaLag`（`DBClusterIdentifier`） | ≥ 1000 ms，300 秒 3 中 2 | Aurora 且 `reader_count > 0` | project-c `aurora_replica_lag` |
| `proxy_borrowed_high` | `100 × DatabaseConnectionsCurrentlyBorrowed / MaxDatabaseConnectionsAllowed`（`ProxyName`） | > 80％，60 秒 × 5 | `proxy != null` | project-a `rds_proxy_connections_saturating` |
| `proxy_pinned_high` | `100 × DatabaseConnectionsCurrentlySessionPinned / MaxDatabaseConnectionsAllowed` | > 20％，60 秒 × 5 | `proxy != null` | project-a `rds_proxy_session_pinned` |

```hcl
variable "alarm_config" {
  type = object({
    cpu_threshold                = optional(number, 80)
    freeable_memory_bytes        = optional(number, 209715200)
    connections_threshold        = optional(number) # 見下
    replica_lag_threshold_ms     = optional(number, 1000)
    proxy_borrowed_percent       = optional(number, 80)
    proxy_pinned_percent         = optional(number, 20)
  })
  default = {}
}
```

`connections_threshold`：`aurora_serverless` 沒給時由 module 推算為 `floor(min(max_capacity × 2 GiB ÷ 9,531,392, 5000) × 0.8)`（project-c 的公式，`project-c-app/modules/app-platform/cloudwatch-alarms.tf`；5000 的上限是 PostgreSQL `max_connections` 預設公式的上限）；`rds` 與 `aurora` 的 `max_connections` 取決於 instance class 的記憶體，module 離線算不出來，**validation 要求呼叫端必填**。這是我的判斷，見 §9.1。

**輸出**

| 輸出 | 說明 |
|---|---|
| `writer_endpoint` | rds：instance `address`；Aurora：cluster `endpoint` |
| `reader_endpoint` | rds：等於 writer；Aurora：cluster `reader_endpoint` |
| `has_reader` | rds：`false`；Aurora：`reader_count > 0` |
| `proxy_endpoint` | 沒開 Proxy 時為 `null` |
| `app_endpoint` | 開 Proxy 時是 `proxy_endpoint`，否則是 `writer_endpoint` |
| `app_reader_endpoint` | 有 Proxy 的 read-only endpoint 就用它；有 Proxy 但沒有 read-only endpoint 時用 `proxy_endpoint`；沒開 Proxy 時用 `reader_endpoint` |
| `port` | 5432 |
| `master_user_secret_arn` | `master_user_secret[0].secret_arn` |
| `db_identifier`、`identifier_type` | `identifier_type` 是 `"instance"` 或 `"cluster"` |
| `cluster_id` | rds 時為 `null` |
| `instance_ids` | 依序，index 0 是 writer |
| `cloudwatch_dimension` | `{ name = "DBInstanceIdentifier" 或 "DBClusterIdentifier", value = ... }`，給專案自己加告警或 dashboard |
| `arn`、`resource_id` | — |
| `alarm_arns` | `map(string)` |

**刻意不做**：一般 RDS 的 read replica；RDS Multi-AZ DB cluster（第四種型態）；同一個 cluster 混用 provisioned 與 serverless instance；應用程式專用帳號與 Proxy 的 IAM 認證（§8.2）；MySQL；IAM（Proxy 與 Enhanced Monitoring 的 role 都從外部傳入）；`random_password`（`scripts/validate.sh` 會擋，§7.1）。

### 4.10 `kms-key`

**用途**：建一把對稱式 customer managed key（CMK）、它的 key policy 與 alias。專案共用的那把由 `foundation` 呼叫一次。

**參考來源**

- `aws_kms_key` 加 `aws_kms_alias`、`deletion_window_in_days = 30`、key policy 第一段固定給帳號 root：`project-c-infra/modules/infra-platform/kms.tf`、`kms-policies.tf`
- 依服務加 statement、用 `kms:ViaService` 條件限縮：同上 `kms-policies.tf` 的 `DbLifecycleDecryptViaSecretsManager`
- project-a 沒有自建 CMK，secret 用 AWS managed key `alias/aws/secretsmanager`（`project-a/infra-v2/terraform/foundation/secrets.tf`）

**資源**：`aws_kms_key.this`、`aws_kms_key_policy.this`、`aws_kms_alias.this`。

**固定行為**

| 項目 | 值 | 理由 |
|---|---|---|
| key 類型 | `SYMMETRIC_DEFAULT`、`ENCRYPT_DECRYPT`、單一 region | 第一版只有加密用途 |
| 自動輪替 | `enable_key_rotation = true` | 不開放關閉 |
| key policy 第一段 | 帳號 root（`arn:aws:iam::<account>:root`）`kms:*` | 少了這段，IAM policy 無法再授權這把 key，key 可能變成沒人管得了。這是 AWS 的預設寫法，project-c 也是 |
| 服務 statement | 每個服務 principal 一段，`Resource = "*"`（key policy 裡的 `*` 指這把 key 本身） | — |
| alias | `alias/<name>` | — |

**輸入**

```hcl
variable "name" {
  type        = string
  description = "Key alias without the alias/ prefix."
  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]{1,250}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-250 chars of letters, digits, /, _ or -, and must not start with aws/."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "deletion_window_in_days" {
  type    = number
  default = 30
  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "administrator_arns" {
  type        = list(string)
  default     = []
  description = "Extra IAM principals allowed to administer the key. The account root is always included."
  validation {
    condition     = alltrue([for a in var.administrator_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[^*]+$", a))])
    error_message = "administrator_arns must be IAM role or user ARNs; wildcards are not allowed."
  }
}

variable "service_principals" {
  type = map(object({
    actions = optional(list(string), ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default     = {}
  description = "Service principal (e.g. logs.ap-northeast-1.amazonaws.com) => actions and conditions it gets on this key."
  validation {
    condition     = alltrue([for k in keys(var.service_principals) : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", k))])
    error_message = "Keys must be AWS service principals ending in .amazonaws.com; * is not allowed."
  }
  validation {
    condition     = alltrue(flatten([for v in values(var.service_principals) : [for a in v.actions : a != "*" && a != "kms:*"]]))
    error_message = "Service principals must not get * or kms:*."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`key_arn`、`key_id`、`alias_name`、`alias_arn`。

**key policy 的組成（以 `modules/kms-key/main.tf` 為準）**，依序是：

| Sid | 何時有 | principal | Action |
|---|---|---|---|
| `EnableAccountRoot` | 一律，永遠第一段 | 帳號 root | `kms:*` |
| `AllowKeyAdministration` | `administrator_arns` 非空 | `administrator_arns` | `kms:Create*`、`kms:Describe*`、`kms:Enable*`、`kms:List*`、`kms:Put*`、`kms:Update*`、`kms:Revoke*`、`kms:Disable*`、`kms:Get*`、`kms:Delete*`、`kms:TagResource`、`kms:UntagResource`、`kms:ScheduleKeyDeletion`、`kms:CancelKeyDeletion`（管理動作，沒有 `Encrypt`／`Decrypt`） |
| `AllowService<principal 去掉非英數字元>` | `service_principals` 每個 key 一段，例如 `logs.ap-northeast-1.amazonaws.com` → `AllowServicelogsapnortheast1amazonawscom` | 該服務 | 輸入的 `actions`；`conditions` 依 `test` 分組成 `Condition` |

Sid 只能用英數字元，所以從 principal 去掉 `.` 與 `-`。同一個服務的多個條件如果 `test` 與 `variable` 都相同，後面那個會蓋掉前面的，呼叫端要自己合併 `values`。

**範本 `foundation` 給的服務**：`logs.<region>.amazonaws.com`（條件 `ArnLike kms:EncryptionContext:aws:logs:arn = arn:aws:logs:<region>:<account>:log-group:*`）、`cloudwatch.amazonaws.com`（告警發布到加密的 SNS）、`sns.amazonaws.com`、`rds.amazonaws.com`、`secretsmanager.amazonaws.com`（後兩者通常靠 `kms:ViaService` 走 IAM 授權即可，是否需要放進 key policy 依實測決定）。每個服務接受哪些條件 key 各不相同，這張清單**未在實環境驗證**（§7.3）。

**刻意不做**：非對稱 key、multi-region key、外部金鑰材料、grant 管理、對 `*` principal 開放（validation 擋）。

### 4.11 `ecr-repository`

**用途**：建一個 ECR repository 與它的 lifecycle policy。一次呼叫一個 repository，`containerimage` 用 `for_each` 對每個服務呼叫一次。

**參考來源**

- `IMMUTABLE`、`scan_on_push`、KMS 加密：`project-c-infra/modules/infra-platform/ecr.tf`（project-c 的 `force_delete = true`，這裡改成固定 `false`）
- lifecycle policy 的寫法：`project-a/infra-v2/terraform/containerimage/ecr.tf`（project-a 是 `MUTABLE`、保留最近 N 個、`force_delete = true`，這三項都不沿用）

**資源**：`aws_ecr_repository.this`、`aws_ecr_lifecycle_policy.this`。

**固定行為**

| 項目 | 值 | 理由 |
|---|---|---|
| `image_tag_mutability` | `IMMUTABLE` | 同一個 tag 不能被覆蓋，部署才可追溯 |
| `image_scanning_configuration.scan_on_push` | `true` | — |
| `force_delete` | `false` | 還有映像時 destroy 會失敗，不會連映像一起刪 |
| lifecycle 規則 | 規則 1：`tagStatus = "untagged"`、`sinceImagePushed` 超過 `untagged_expire_days` 天就刪；規則 2：`tagStatus = "any"`、`imageCountMoreThan` 超過 `keep_count` 就刪舊的 | `tagged` 規則在 ECR 必須搭配 tag 前綴或樣式，用 `any` 搭配優先序較單純 |

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 256 && can(regex("^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$", var.name))
    error_message = "name must be a valid ECR repository name (lowercase, digits, . _ - and / separators)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for image encryption. null uses AES256."
}

variable "lifecycle_rules" {
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default = {}
  validation {
    condition     = var.lifecycle_rules.untagged_expire_days >= 1 && var.lifecycle_rules.keep_count >= 1
    error_message = "untagged_expire_days and keep_count must be at least 1."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`repository_url`、`arn`、`name`、`registry_id`。

注意：已經存在的 repository 改 `kms_key_arn`（加密設定）會讓 repository 重建，映像會跟著消失。這屬於 MAJOR 等級的變更，要先把映像搬走。

**刻意不做**：repository policy（跨帳號拉映像）、replication、pull-through cache、enhanced scanning（Inspector）。

### 4.12 `s3-bucket`

**用途**：建一個給 log 用的 S3 bucket：封鎖公開存取、加密、生命週期、只允許 TLS，以及依輸入加上 log delivery 的寫入權限。`foundation` 用它建 flow log bucket 與 ALB access log bucket。

**參考來源**

- ALB access log 的 bucket：`project-a/infra-v2/terraform/loadbalancer/access-logs.tf`。兩個重點都沿用：加密必須是 AES256（ALB 不支援 CMK，設了 log 會無聲消失）；舊 region（例如 `ap-northeast-1`）要給「該 region 的 ELB 服務帳號」寫入權限，只給服務主體會 Access Denied，所以兩種 principal 都給。
- 封鎖公開存取、AES256、lifecycle：`project-c-infra/modules/infra-platform/s3.tf`

**資源**：`aws_s3_bucket.this`、`aws_s3_bucket_public_access_block.this`、`aws_s3_bucket_ownership_controls.this`、`aws_s3_bucket_server_side_encryption_configuration.this`、`aws_s3_bucket_lifecycle_configuration.this`、`aws_s3_bucket_policy.this`；`log_delivery` 含 `alb_access_logs` 時另讀 `data "aws_elb_service_account"`。

**固定行為**

| 項目 | 值 |
|---|---|
| 封鎖公開存取 | 四項全開 |
| object ownership | `BucketOwnerEnforced`（停用 ACL） |
| 只允許 TLS | bucket policy 一律有一段 `Deny`，條件 `aws:SecureTransport = false` |
| lifecycle | 過期天數由變數決定；未完成的 multipart upload 7 天後清除 |
| bucket policy 的 `depends_on` | 等 public access block 建好（照 project-a 的寫法，避免 policy 先套用時被判為公開） |
| SSE-KMS 時 | `bucket_key_enabled = true`（`kms_key_arn` 有給時才開），減少對 KMS 的呼叫次數與費用；SSE-S3 時為 `false` |

**log delivery 的 statement**（`log_delivery` 決定加哪些）

| 值 | principal | action 與 resource | 條件 |
|---|---|---|---|
| `alb_access_logs` | ① 該 region 的 ELB 服務帳號（`data.aws_elb_service_account`）② `logdelivery.elasticloadbalancing.amazonaws.com` | `s3:PutObject` on `<bucket>/*AWSLogs/<account>/*` | ② 加 `aws:SourceAccount` |
| `vpc_flow_logs` | `delivery.logs.amazonaws.com` | `s3:PutObject` on `<bucket>/AWSLogs/<account>/*`；`s3:GetBucketAcl` on bucket | `aws:SourceAccount`；PutObject 另加 `s3:x-amz-acl = bucket-owner-full-control` |

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-63 chars of lowercase letters, digits or hyphens; dots are not allowed (they break TLS virtual-host addressing)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "null uses SSE-S3 (AES256). ALB access log buckets must stay on SSE-S3."
}

variable "expiration_days" {
  type    = number
  default = 90
  validation {
    condition     = var.expiration_days >= 1 && var.expiration_days <= 3650
    error_message = "expiration_days must be between 1 and 3650."
  }
}

variable "log_delivery" {
  type        = set(string)
  default     = []
  description = "Log sources allowed to write: alb_access_logs, vpc_flow_logs."
  validation {
    condition     = alltrue([for v in var.log_delivery : contains(["alb_access_logs", "vpc_flow_logs"], v)])
    error_message = "log_delivery accepts alb_access_logs and vpc_flow_logs."
  }
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

跨變數 validation：`log_delivery` 含 `alb_access_logs` 時，`kms_key_arn` 必須是 null。錯誤訊息寫明「ALB access log delivery does not support SSE-KMS; logs would be dropped silently」。這條把「ALB log bucket 只能 SSE-S3」從文件約定變成程式擋。

**輸出**：`bucket_name`、`arn`、`bucket_regional_domain_name`。

**刻意不做**：versioning、replication、object lock、bucket 本身的 access logging、event notification、CORS、跨帳號寫入。第一版的用途只有 log，這些都用不到。

增補（決策 51、54）：`s3-bucket-v0.1.1` 加 `never_expire`，讓 KB 的語料 bucket 可以不過期，見 §4.32。上面的介面是 `v0.1.0` 的樣子，不改寫。

### 4.13 `ssm-read`

**用途**：跟 `ssm-publish` 配對的讀取 module。給 key 清單，回傳字串與清單。範本每個 stack 的 `ssm-inputs.tf` 改成呼叫它，不再各自寫 `data "aws_ssm_parameter"` 與 `split()`。

**參考來源**：`project-a/infra-v2/terraform/application/ssm-inputs.tf`（`data "aws_ssm_parameter"` 加 `for_each`、讀 `insecure_value`）；`ssm-publish` 的路徑與 key 規則（§4.6）。

**資源**：`data "aws_ssm_parameter" "this"`，`for_each` 為 `strings` 與 `lists` 的值去重後的集合。沒有任何 resource。

**輸入**

```hcl
variable "ssm_prefix" {
  type        = string
  description = "/<project>/<env>, same as ssm-publish."
  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "strings" {
  type        = map(string)
  default     = {}
  description = "Local name => \"<stack>/<key>\" for String parameters."
  validation {
    condition     = alltrue([for v in values(var.strings) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}

variable "lists" {
  type        = map(string)
  default     = {}
  description = "Local name => \"<stack>/<key>\" for StringList parameters."
  validation {
    condition     = alltrue([for v in values(var.lists) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}
```

**輸出**：`strings`（`map(string)`，key 為本地名稱）、`lists`（`map(list(string))`，以逗號切開）。

**行為**：只讀 `insecure_value`。參數不存在時 plan 直接失敗，這是刻意的：上游還沒 apply 或客戶還沒發布，不應該繼續規劃。JSON 值（例如 `database`）放在 `strings`，由呼叫端 `jsondecode()`；module 不猜哪些值是 JSON。

**刻意不做**：讀 `SecureString`（secret 不進 SSM）、預設值（缺 key 就該失敗）、遞迴讀整個路徑（`aws_ssm_parameters_by_path` 會讓讀取清單變成隱性的）。

### 4.14 `iam-role`

**用途**：建一個 IAM role：trust policy 加 inline policy。**整個 repo 只有這個 module 與 `iam-role-policy`（§4.15）可以建 IAM 資源**，範本的 stack 也一律透過它們。不得使用 `aws_iam_role_policies_exclusive` 這類獨佔管理 inline policy 的資源，否則會刪掉 `iam-role-policy` 附加的 policy。

**參考來源**

- trust 只給服務主體、inline policy、不掛 AWS managed policy：`project-a/infra-v2/terraform/iam/ecs-roles.tf`（project-a 用 `data "aws_iam_policy_document"`；這裡改收 `jsonencode` 產生的字串，理由見 §5.4）
- 反例：project-c 掛了 `AmazonBedrockFullAccess` 等 managed policy（`project-c-infra/modules/infra-platform/iam-ecs.tf`），共用 policy 掛到多個 role（`iam-baseline.tf`）；這兩種都不沿用

**資源**：`aws_iam_role.this`、`aws_iam_role_policy.this`（`for_each = inline_policies`）。沒有 `aws_iam_role_policy_attachment`、沒有 `aws_iam_policy`。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars of letters, digits or +=,.@_-."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "trust" {
  type = object({
    service_principals = set(string)       # e.g. ["ecs-tasks.amazonaws.com"]
    source_account     = optional(string)  # adds aws:SourceAccount when set
  })
  validation {
    condition = (
      length(var.trust.service_principals) > 0 &&
      alltrue([for p in var.trust.service_principals : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", p))]) &&
      (var.trust.source_account == null ? true : can(regex("^[0-9]{12}$", var.trust.source_account)))
    )
    error_message = "trust needs at least one AWS service principal (no wildcards); source_account must be a 12-digit account ID."
  }
}

variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "Policy name => policy JSON built with jsonencode()."
  validation {
    condition     = alltrue([for p in values(var.inline_policies) : can(jsondecode(p).Statement[0])])
    error_message = "Each inline policy must be a JSON document with a Statement."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : [
          for a in flatten([try(s.Action, [])]) : a != "*" && !endswith(a, ":*")
        ] if try(s.Effect, "Allow") == "Allow"
      ]
    ]))
    error_message = "Allow statements must not use * or service:* actions."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotAction, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotAction."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotResource, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotResource."
  }
}
```

四條 validation 的作用（`iam-role-policy` 的 `policies` 一字不差，只有變數名不同，另外第一條多一個 `length(var.policies) > 0`）：

| # | 檢查 | 為什麼這樣寫 |
|---|---|---|
| 1 | `can(jsondecode(p).Statement[0])` | `Statement` 必須是非空清單。寫成 `can(jsondecode(p).Statement)` 的話，空清單會通過；`Statement` 寫成單一物件（IAM 允許）也會通過，而第二條的 `for s in ...` 對物件跑的是欄位值，萬用動作就檢查不到 |
| 2 | 迴圈用 `try(jsondecode(p).Statement, [])` | 非 JSON 字串在第一條就會失敗；第二、三條如果直接 `jsondecode`，會變成 hard error，`expect_failures` 接不到，測試只能看到「plan 壞了」而不是「這條 validation 擋下來」 |
| 3 | Allow statement 不准有 `NotAction` | `Allow` 加 `NotAction` 等於「除了這幾個動作以外全部允許」，比 `*` 只少一點，第二條檢查不到。沒寫 `Effect` 時 IAM 視為 `Allow`，所以 `try(s.Effect, "Allow")`；`Deny` 搭配 `NotAction` 是常見的防護寫法，照樣放行 |
| 4 | Allow statement 不准有 `NotResource` | `Allow` 加 `NotResource` 等於「除了這幾個資源以外全部允許」，效果接近 `Resource = "*"`，前三條都檢查不到。寫法比照第三條：沒寫 `Effect` 視為 Allow，`Deny` 搭配 `NotResource` 照樣放行（使用者同意比照 `NotAction`，§9.2 決策 35） |

```hcl

variable "permissions_boundary" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`arn`、`name`、`id`。`arn` 的 output 加 `depends_on = [aws_iam_role_policy.this]`：拿到 ARN 的下游，一定是在 inline policy 都附加之後才開始建（範例的 `core` module 用同樣的手法，見 `infra-platform/docs/slides/terraform-split/terraform-platform-example/platform/modules/core/main.tf`）。

**這個 module 鎖住什麼、鎖不住什麼**

| 鎖得住（module 測試） | 鎖不住（範本 stack 的測試負責） |
|---|---|
| Allow statement 沒有 `*`、沒有 `service:*` 動作 | `Resource = "*"` 是否只用在允許的 action（module 不知道哪些 action 不支援 resource-level） |
| 沒有 AWS managed policy（module 根本不收） | Resource 是否恰為該給的 ARN |
| trust 只給服務主體，不能給 `*` 或任意 AWS principal | 哪個 role 該有哪些權限 |

**刻意不做**：AWS managed policy、customer managed policy（`aws_iam_policy`）、instance profile、trust 給 AWS 帳號或 OIDC（GitHub Actions 的部署 role 不在範本範圍）、`max_session_duration` 調整。

增補（決策 56）：`iam-role-v0.1.1` 在 `trust` 加選填的 `source_arn`，有給時同一段 statement 多一個 `ArnLike` 的 `aws:SourceArn` 條件（可含萬用字元，validation 只要求以 `arn:` 開頭、不含空白）。沒給的既有呼叫端 trust JSON 跟 `v0.1.0` 逐字相同（測試 `source_account_only_policy_unchanged`），換版應該零差異，**沒有用 plan 驗證**。照 §3.5 是 MINOR，比照決策 54 用 `0.1.1`。上面的介面是 `v0.1.0` 的樣子，不改寫。

### 4.15 `iam-role-policy`

**用途**：對一個**已經存在**的 role 附加 inline policy。只建 `aws_iam_role_policy`，不建 role。用在 role 與它的權限必須在不同時間點建立的情況，第一版只有一個：RDS Proxy 的 role 要在資料庫之前存在，讀 master secret 的權限要等 secret 存在後才附加（§5.4）。

**參考來源**：`project-a/infra-v2/terraform/database/rds-proxy.tf`（project-a 在同一個 stack 裡建 role 與 policy，所以 policy 能直接引用 secret ARN；範本把兩者拆到 `iam-base` 與 `iam-app`，才需要這個 module）。

**資源**：`aws_iam_role_policy.this`（`for_each = policies`）。

**輸入**

```hcl
variable "role_arn" {
  type        = string
  description = "Existing role to attach the policies to. Must have no path; the role name is taken from the last ARN segment."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN without a path."
  }
}

variable "policies" {
  type        = map(string)
  description = "Policy name => policy JSON built with jsonencode()."
  validation {
    condition     = length(var.policies) > 0 && alltrue([for p in values(var.policies) : can(jsondecode(p).Statement[0])])
    error_message = "Give at least one policy; each must be a JSON document with a Statement."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : [
          for a in flatten([try(s.Action, [])]) : a != "*" && !endswith(a, ":*")
        ] if try(s.Effect, "Allow") == "Allow"
      ]
    ]))
    error_message = "Allow statements must not use * or service:* actions."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotAction, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotAction."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotResource, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotResource."
  }
}
```

**輸出**：`policy_names`（`list(string)`）、`role_name`。

**跟 `iam-role` 的關係**

- 兩者的四條 policy validation（非空 `Statement` 清單、Allow 不准 `*` 或 `service:*`、Allow 不准 `NotAction`、Allow 不准 `NotResource`，理由見 §4.14）寫法一字不差，只有變數名不同，`iam-role-policy` 的第一條另外要求至少一個 policy。這段邏輯重複在兩個 module 裡是刻意的：Terraform module 之間不能共用 validation，抽成第三個 module 只為了放一段表達式不划算。
- `iam-role` **不得**使用 `aws_iam_role_policies_exclusive` 這類「獨佔管理 inline policy」的資源。用了的話，`iam-role` 每次 apply 都會把 `iam-role-policy` 附加的 policy 刪掉，兩邊互相覆蓋。
- 「只有 `iam-role` 與 `iam-role-policy` 建 IAM」由 §5.6 S4 檢查。

**刻意不做**：建 role、附加 AWS managed policy 或 customer managed policy（`aws_iam_role_policy_attachment`）、有 path 的 role。

### 4.16 `security-group`

**用途**：一次呼叫建一組**互相引用**的 security group 與它們的規則。network stack 用它建 ALB、各服務、DB、Proxy 的 SG，整條 ALB → app → db／proxy 的規則鏈在同一次呼叫裡表達。

**為什麼是「一組」而不是「一個」**：規則鏈是雙向引用的，例如 ALB SG 的 egress 指向 app SG、app SG 的 ingress 又指向 ALB SG。如果 module 一次只建一個 SG，stack 只能用 `for_each` 呼叫同一個 module block，而 module 的引數不能引用自己（`module.sg["app"]` 不能出現在 `module.sg` 的引數裡），Terraform 會報自我引用。把整組 SG 放進同一次呼叫，規則用 SG 的 key 互相指，module 裡面先建 SG、再建規則，就沒有循環。

**參考來源**

- SG 與規則分開、規則一律用獨立的 `aws_vpc_security_group_ingress_rule`／`egress_rule`、不准 inline：`project-a/infra-v2/terraform/network/security-groups.tf`（註解說明 inline 規則會刪掉不歸 Terraform 管的規則）、`security-group-rules.tf`
- 客戶在 SG 上加的規則不會被洗掉的前提，就是沒有 inline 規則：`project-a/docs/reports/2026-09-04-customer-owned-network-and-terraform.md`
- 範例的服務 SG 寫法：`infra-platform/docs/slides/terraform-split/terraform-platform-example/platform/modules/ecs-web-service/main.tf`

**資源**：`aws_security_group.this`（`for_each = security_groups`）、`aws_vpc_security_group_ingress_rule.this`、`aws_vpc_security_group_egress_rule.this`（`for_each` 分別是 `rules` 裡 `type = "ingress"`／`"egress"` 的項目）。沒有 inline `ingress {}`／`egress {}`。Terraform 建立 SG 時會移除 AWS 預設的「全部對外放行」egress，所以沒有寫的方向就是不通。

**輸入**

```hcl
variable "vpc_id" {
  type = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "security_groups" {
  type = map(object({
    name        = string
    description = string
  }))
  description = "Key => security group. Rules refer to groups by this key."
  validation {
    condition     = length(var.security_groups) > 0 && alltrue([for k in keys(var.security_groups) : can(regex("^[a-z][a-z0-9_]*$", k))])
    error_message = "Give at least one security group; keys must be snake_case."
  }
}

variable "rules" {
  type = map(object({
    security_group = string                 # key in security_groups the rule belongs to
    type           = string                 # ingress | egress
    description    = string
    ip_protocol    = optional(string, "tcp")
    from_port      = optional(number)       # null with ip_protocol = "-1"
    to_port        = optional(number)       # defaults to from_port
    # exactly one peer:
    peer_group     = optional(string)       # key in security_groups
    peer_group_id  = optional(string)       # security group outside this call
    cidr_ipv4      = optional(string)
    prefix_list_id = optional(string)
    allow_internet = optional(bool, false)  # required to open ingress to 0.0.0.0/0
  }))
  default     = {}
  description = "Rule key => rule. Keys are stable for_each keys; name them after what the rule allows."
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 |
|---|---|
| 規則屬於存在的 SG | `security_group` 與 `peer_group` 都必須是 `security_groups` 的 key |
| 恰好一個來源／目的地 | `peer_group`、`peer_group_id`、`cidr_ipv4`、`prefix_list_id` 恰好一個非 null |
| type | 只收 `ingress`、`egress` |
| ip_protocol | 只收 `tcp`、`udp`、`-1`（`icmp` 等其他協定第一版不支援） |
| port | `ip_protocol` 是 `tcp`／`udp` 時 `from_port` 必填、`0..65535`，`to_port >= from_port`；`-1` 時兩者都是 null |
| **對全網開放要明說** | `type = "ingress"` 且 `cidr_ipv4 = "0.0.0.0/0"` 時，`allow_internet` 必須是 `true`。避免 DB 或服務的 SG 被一行寫錯的 CIDR 打開 |
| CIDR 格式 | `cidr_ipv4` 必須是合法的 IPv4 CIDR |

**輸出**：`security_group_ids`（`map(string)`，key 同 `security_groups`）、`security_group_arns`。

**tag**：SG 的 `Name` 是 `security_groups` 裡的 `name`；每條規則的 `Name` 是規則在 `rules` 裡的 key（例如 `api_in_alb`），在 console 看規則時就知道它是哪一條。

**範本怎麼表達規則鏈**：network stack 不手寫每一條規則，而是用 `services`、`data_stores`、`alb_ingress` 在 locals 展開成 `rules` map（§5.3）。展開後的樣子：

```hcl
module "sg" {
  source = "../../../../../modules/security-group"
  vpc_id = module.vpc.vpc_id

  security_groups = {
    alb      = { name = "${local.name_prefix}-alb", description = "ALB" }
    api      = { name = "${local.name_prefix}-api", description = "api service" }
    db       = { name = "${local.name_prefix}-db", description = "database" }
    db_proxy = { name = "${local.name_prefix}-db-proxy", description = "RDS Proxy" }
  }

  rules = {
    alb_in_https      = { security_group = "alb", type = "ingress", description = "clients", from_port = 443, cidr_ipv4 = "0.0.0.0/0", allow_internet = true }
    alb_in_http       = { security_group = "alb", type = "ingress", description = "redirect to https", from_port = 80, cidr_ipv4 = "0.0.0.0/0", allow_internet = true }
    alb_out_api       = { security_group = "alb", type = "egress", description = "to api", from_port = 8080, peer_group = "api" }
    api_in_alb        = { security_group = "api", type = "ingress", description = "from alb", from_port = 8080, peer_group = "alb" }
    api_out_https     = { security_group = "api", type = "egress", description = "AWS APIs", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    api_out_proxy     = { security_group = "api", type = "egress", description = "to db proxy", from_port = 5432, peer_group = "db_proxy" }
    db_proxy_in_api   = { security_group = "db_proxy", type = "ingress", description = "from api", from_port = 5432, peer_group = "api" }
    db_proxy_out_db   = { security_group = "db_proxy", type = "egress", description = "to db", from_port = 5432, peer_group = "db" }
    db_in_proxy       = { security_group = "db", type = "ingress", description = "from db proxy", from_port = 5432, peer_group = "db_proxy" }
  }
}
```

**「沒有憑證時 ALB SG 不准對 0.0.0.0/0 開 80」放在 network stack，不放在 module。** 這條要知道兩件事：哪個 SG 是 ALB、ALB 有沒有憑證。兩者都是專案的語意，`security-group` 是通用 module，不知道誰是 ALB，也不該知道憑證。放進 module 就得加一個「這是沒有憑證的 ALB」之類的旗標，等於把 stack 的決定搬進 module。所以：

- module 只負責通用的底線：任何 ingress 要對 `0.0.0.0/0` 開放，都必須明寫 `allow_internet = true`。
- network stack 的 `alb_ingress` validation 負責 ALB 專屬的規則：`https = false` 時 `cidrs` 不得含 `0.0.0.0/0`，展開規則時也就不會出現 `allow_internet = true` 的 80（§5.3、§8.4）。`alb_ingress.https` 同時是發布給 `loadbalancer` 的單一決定點，兩條檢查都綁在同一個值上。

**刻意不做**：IPv6 規則、預設的 egress 放行、一次呼叫只建一個 SG 的介面（理由見上）、NACL。

**已知限制**（validation 擋不到，靠 network stack 的展開邏輯與審查）：

- `cidr_ipv4` 只檢查格式（`^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$` 加 `cidrnetmask()`），不擋主機位元，例如 `10.0.0.5/16` 會通過，AWS 端是否接受**未驗證**。
- 「對全網開放要明說」只比對字串 `0.0.0.0/0`。把它拆成 `0.0.0.0/1` 加 `128.0.0.0/1` 兩條，就能繞過 `allow_internet`。module 擋的是「不小心」，不是「故意」；network stack 的規則由服務清單展開，不會產生這種寫法。

### 4.17 `log-group`

**用途**：建一個 CloudWatch log group，可選 KMS 加密與一個 subscription filter。給 Lambda、應用程式自訂的 log、範本 stack 需要的 log 用。`ecs-service`、`rds` 自己的 log group 仍由它們自己建，不改成呼叫這個 module（module 之間平坦組合，§9.1 J38）。

**參考來源**：`modules/ecs-service/main.tf`、`modules/ecs-cluster/` 的 log group 寫法（保留天數、可選 KMS）；`project-c-infra/modules/infra-platform/ecs.tf` 預建 Container Insights log group 以控制保留天數的理由。

**資源**：`aws_cloudwatch_log_group.this`；`subscription != null` 時加 `aws_cloudwatch_log_subscription_filter.this`，名稱用 `var.name`（一個 log group 只有一個 filter，不會撞名）。

**`role_arn` 的保證範圍**：provider 把 subscription filter 的 `role_arn` 定義成 optional 加 computed。Lambda 目的地時 module 傳 `null`，但在 mock 下 computed 屬性會被填上假值，所以「Lambda 目的地時 `role_arn` 是 null」只能靠程式碼保證，`terraform test` 驗不到（§7.1）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-512 chars of letters, digits, _ . / # or -, and must not start with aws/."
  }
}

variable "retention_days" {
  type        = number
  default     = 30
  description = "Retention in days. Never-expire (0) is not accepted."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_days)
    error_message = "retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key. Its key policy must allow logs.<region>.amazonaws.com."
}

variable "subscription" {
  type = object({
    destination_arn = string                 # Lambda, Kinesis, Firehose or a logs destination
    filter_pattern  = optional(string, "")   # empty forwards every event
    role_arn        = optional(string)       # required for Kinesis and Firehose, built with iam-role
  })
  default = null
  validation {
    condition = var.subscription == null ? true : (
      can(regex("^arn:aws[a-z-]*:(lambda|kinesis|firehose|logs):", var.subscription.destination_arn)) &&
      (can(regex(":(kinesis|firehose):", var.subscription.destination_arn)) ? var.subscription.role_arn != null : true)
    )
    error_message = "destination_arn must be a Lambda, Kinesis, Firehose or logs destination ARN; Kinesis and Firehose need role_arn."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`name`、`arn`。

**刻意不做**：永不過期（`retention_days = 0`，validation 擋）、`INFREQUENT_ACCESS` log class、一個 log group 多個 subscription filter、建立訂閱目的地本身，以及 Lambda 目的地需要的 `aws_lambda_permission`（由擁有那支 Lambda 的 stack 建）。這個 module 不建 IAM：Kinesis／Firehose 需要的 role 由 `iam-role` 建好再傳 `role_arn`。

### 4.18 `log-metric-alarm`

**用途**：從一個 log group 的 log 產生自訂指標，再對指標建告警（metric filter 加 alarm）。一次呼叫處理同一個 log group 的多組 filter 與告警，用 `for_each`。適合「應用程式印出某個事件就代表出事」的訊號，例如 project-a 的 audit 寫入失敗、rate limit fail-open。

**參考來源**：`project-a/infra-v2/terraform/postdeploy/alarms-persistence.tf`（一張 `log_event → metric_name → description` 表，`for_each` 同時建 filter 與 alarm；pattern 用 JSON 欄位比對 `{ $.event = "..." }`；`value = "1"`、`default_value = "0"`；`Sum`、60 秒、`>= 1`、`notBreaching`；`alarm_actions` 與 `ok_actions` 都接 topic；alarm `depends_on` filter）、`postdeploy/alarms.tf` 的 `rate_limit_fail_open`（同樣寫法，但 300 秒、門檻 60）、`database/alarms-partitions.tf`。

**資源**：`aws_cloudwatch_log_metric_filter.this`、`aws_cloudwatch_metric_alarm.this`，兩者都 `for_each = alarms`；provider 的 `metric_transformation.default_value` 是 string，module 收 number、內部用 `tostring()` 轉；metric filter 不支援 tag，只有 alarm 帶 `tags`；alarm `depends_on` filter（指標要先存在，告警才不會一建好就落在 INSUFFICIENT_DATA）。

**輸入**

```hcl
variable "name_prefix" {
  type        = string
  description = "Filter and alarm names are <name_prefix>-<key with _ replaced by ->."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,100}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits or hyphens."
  }
}

variable "log_group_name" {
  type = string
}

variable "namespace" {
  type        = string
  description = "Custom metric namespace, e.g. Alpha/dev. Must not start with AWS/."
  validation {
    condition     = can(regex("^[A-Za-z0-9._/#:-]{1,255}$", var.namespace)) && !startswith(var.namespace, "AWS/")
    error_message = "namespace must be 1-255 valid characters and must not start with AWS/."
  }
}

variable "alarms" {
  type = map(object({
    pattern             = string           # e.g. { $.event = "persistence_write_failed" }
    metric_name         = string
    description         = string           # what it means and what to check first
    metric_value        = optional(string, "1")
    default_value       = optional(number, 0)
    statistic           = optional(string, "Sum")
    period              = optional(number, 60)
    evaluation_periods  = optional(number, 1)
    datapoints_to_alarm = optional(number)
    threshold           = optional(number, 1)
    comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
    treat_missing_data  = optional(string, "notBreaching")
  }))
  description = "Alarm key => log pattern and alarm settings. Keys must be snake_case."
  validation {
    condition     = alltrue([for k, v in var.alarms : can(regex("^[a-z][a-z0-9_]*$", k)) && length(trimspace(v.pattern)) > 0 && length(trimspace(v.description)) > 0])
    error_message = "Keys must be snake_case; pattern and description must not be empty."
  }
  validation {
    condition = alltrue([for v in values(var.alarms) :
      contains(["Sum", "Average", "Maximum", "Minimum", "SampleCount"], v.statistic) &&
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], v.comparison_operator) &&
      contains(["missing", "ignore", "breaching", "notBreaching"], v.treat_missing_data) &&
      (v.period == 10 || v.period == 30 || v.period % 60 == 0) &&
      (v.datapoints_to_alarm == null ? true : v.datapoints_to_alarm <= v.evaluation_periods)
    ])
    error_message = "Use a supported statistic, comparison operator and treat_missing_data; period must be 10, 30 or a multiple of 60; datapoints_to_alarm must not exceed evaluation_periods."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions. Required."
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

`alarms` 可以是空 map，這時什麼都不建；範本的 `application` 就是用這個方式預設不建（§5.3）。

**輸出**：`alarm_arns`、`alarm_names`、`metric_filter_names`（都是 `map(string)`，key 同 `alarms`）。

**刻意不做**：metric filter 的 `dimensions`（跟 `default_value` 不能同時用，第一版選 `default_value` 讓沒有事件時指標是 0，照 project-a）、一次處理多個 log group（多個 log group 就呼叫多次）、composite alarm、anomaly detection。

### 4.19 `xray`

**用途**：建 X-Ray 的 sampling rule 與 group。sampling rule 控制「抓多少」，是追蹤成本的主要開關；group 用 filter expression 把錯誤或慢的 trace 獨立出來看，可選開 X-Ray Insights。

**參考來源**

- `aws_xray_sampling_rule`：`project-b/infra/terraform/modules/agentcore/observability.tf`（`full_sampling`：`fixed_rate = 1.0`、`reservoir_size = 10`、其他欄位 `*`、priority 100）
- project-a 沒有 sampling rule 與 group 的 Terraform。project-a 的抽樣在 SDK 端用 OTEL 環境變數做（`OTEL_TRACES_SAMPLER = parentbased_traceidratio`、`OTEL_TRACES_SAMPLER_ARG`，`project-a/infra-v2/terraform/application/ecs-chat-gateway.tf`），trace 直接送 X-Ray 的 OTLP endpoint；task role 給 `xray:PutTraceSegments`、`PutTelemetryRecords`、`PutSpans`（`project-a/infra-v2/terraform/iam/ecs-roles.tf`）
- project-c 的 ADOT collector 用 `awsxray` exporter，task role 掛 AWS managed policy `AWSXRayDaemonWriteAccess`（`project-c-app/modules/app-service/adot-config/otel-collector-config.yaml`、`modules/app-platform/iam.tf`），範本不沿用 managed policy

**重要**：sampling rule 只對「向 X-Ray 拿抽樣規則」的 SDK 或 collector 生效（X-Ray SDK、或 ADOT／OTEL 用 X-Ray remote sampler）。像 project-a 那樣在 SDK 端用 `traceidratio` 固定比例抽樣的應用程式，**不會**套用這裡的 rule。用了這個 module 的專案要讓 SDK 或 collector 用 remote sampling，task role 也要多給 `xray:GetSamplingRules`、`xray:GetSamplingTargets`。這段行為**沒有在我們的環境實測過**（§7.3）。

**資源**：`aws_xray_sampling_rule.this`（`for_each = sampling_rules`）、`aws_xray_group.this`（`for_each = groups`）。sampling rule 的 `version = 1`、`resource_arn = "*"` 寫死：兩者都是 provider 的必填欄位，`version` 目前只有 1，`resource_arn` 只對 X-Ray SDK 的少數服務整合有意義，第一版不開放。

**輸入**

```hcl
variable "name_prefix" {
  type        = string
  description = "Rule and group names are <name_prefix>-<key>; X-Ray limits both to 32 characters."
}

variable "sampling_rules" {
  type = map(object({
    priority       = number                  # 1-9999, lower wins; the account Default rule is 10000
    fixed_rate     = number                  # 0-1
    reservoir_size = optional(number, 1)     # traces per second before fixed_rate applies
    service_name   = optional(string, "*")
    service_type   = optional(string, "*")
    host           = optional(string, "*")
    http_method    = optional(string, "*")
    url_path       = optional(string, "*")
    attributes     = optional(map(string), {})
  }))
  default = {}
  validation {
    condition = alltrue([for k, v in var.sampling_rules :
      length("${var.name_prefix}-${k}") <= 32 &&
      v.priority >= 1 && v.priority <= 9999 &&
      v.fixed_rate >= 0 && v.fixed_rate <= 1 &&
      v.reservoir_size >= 0
    ])
    error_message = "Rule names must fit 32 chars; priority 1-9999; fixed_rate 0-1; reservoir_size >= 0."
  }
}

variable "groups" {
  type = map(object({
    filter_expression     = string           # e.g. fault = true OR error = true, or responsetime > 3
    insights_enabled      = optional(bool, false)
    notifications_enabled = optional(bool, false)
  }))
  default = {}
  validation {
    condition     = alltrue([for k, v in var.groups : length("${var.name_prefix}-${k}") <= 32 && length(trimspace(v.filter_expression)) > 0])
    error_message = "Group names must fit 32 chars and filter_expression must not be empty."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

跨變數 validation：同一次呼叫裡 `priority` 不得重複（重複時哪條先套用不確定）；`notifications_enabled = true` 時 `insights_enabled` 也必須是 `true`（X-Ray 的限制）。

**輸出**：`sampling_rule_arns`、`group_arns`（`map(string)`）。

**範本範例**（`application/envs/examples/` 的 tfvars，§5.11）：

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

group 本身不省錢，它的用途是把錯誤與慢請求集中看、或開 Insights；成本由 sampling rule 控制。Insights 另外計費。

**刻意不做**：帳號層級的 `Default` sampling rule（AWS 內建，不能用 Terraform 建，也不改它）、X-Ray 加密設定（`aws_xray_encryption_config` 是帳號層級，一個帳號只有一份，不適合放在專案 module）、Resource Policy。不建 IAM：寫入與抽樣權限由 `iam-app` 給 task role。

### 4.20 `ecs-service` 的 `sidecars`（MINOR）

**用途**：讓一個 task 裡除了主 container `app` 之外，再放 sidecar（例如 ADOT collector、log router）。介面通用，**module 不寫死 ADOT**。範本的 `iam-app`、`application`、`network` 已經把 ADOT collector 接好（task role 的 X-Ray 權限、collector 設定與映像、沒有 NAT 時的檢查），預設關閉，只有 `iam-app` 的 `tracing` 列了服務才會建立（§5.3「追蹤」、決策 36）。

**版本**：新增有預設值、預設維持原行為的變數，屬於 MINOR（§3.5）。`ecs-service` 還沒打過第一個 tag（第一個 tag 在整體驗收後手動打，§3.5），所以這項併進第一個版本 `v0.1.0`；如果在打 tag 之後才加，就是 `v0.2.0`。

**參考來源**：`project-c-app/modules/app-service/ecs-standard.tf` 的 ADOT sidecar（`essential = true`、`restartPolicy`、`cpu`、`healthCheck = ["CMD", "/healthcheck"]`、collector 設定經 `secrets` 注入、自己的 log group）。

**輸入**

```hcl
variable "sidecars" {
  type = list(object({
    name               = string
    image              = string
    essential          = optional(bool, false)
    command            = optional(list(string))
    cpu                = optional(number)        # CPU units reserved inside the task size
    memory_reservation = optional(number)        # MiB, soft limit inside the task size
    environment        = optional(map(string), {})
    secrets            = optional(map(string), {}) # env name => Secrets Manager or SSM ARN
    port_mappings = optional(list(object({
      container_port = number
      protocol       = optional(string, "tcp")
    })), [])
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 10)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 10)
    }))
    app_depends_on = optional(string)            # START | HEALTHY | COMPLETE | SUCCESS; null = app does not wait
    log_stream_prefix = optional(string)         # defaults to the sidecar name
  }))
  default     = []
  description = "Extra containers in the task. Empty keeps the task definition identical to a single-container task."
}
```

| validation | 內容 |
|---|---|
| 名稱 | 每個 `name` 符合 `^[a-z][a-z0-9-]{0,62}$`、彼此不重複、不得是 `app` |
| image | 跟主 container 一樣必須帶明確的 tag（不得 `:latest`）或 digest |
| secrets | 每個值都是 Secrets Manager 或 SSM parameter 的 ARN |
| 等待條件 | `app_depends_on` 只收 `START`、`HEALTHY`、`COMPLETE`、`SUCCESS`；`HEALTHY` 時這個 sidecar 必須有 `health_check` |
| port | sidecar 的 `container_port` 不得跟主 container 的 `container_port` 或其他 sidecar 重複（awsvpc 共用一個網路介面） |
| 至少一個 essential | 主 container 永遠是 essential，所以這條自動成立，不另外檢查 |

**行為**

- `container_definitions` 是 `jsonencode(concat([app], sidecars))`。sidecar 的 log 走**同一個** log group 與同一組 awslogs 設定（`non-blocking`、`max-buffer-size`），只有 `awslogs-stream-prefix` 換成 `log_stream_prefix`（預設是 sidecar 名稱），在 console 用 stream 前綴分得開。不另外建 log group。
- 有任何 sidecar 設了 `app_depends_on` 時，主 container 才加 `dependsOn`；**`sidecars = []` 時主 container 的定義一個欄位都不變**，task definition 的 JSON 與加這個變數之前完全一致，不會觸發新 revision。這條是迴歸要求，寫在 §7.1。
- sidecar 統一加 `linuxParameters.initProcessEnabled = true`、`stopTimeout = 120`，跟主 container 一致。
- sidecar 的 CPU／記憶體從 task 的 `cpu`／`memory` 裡分，module 不檢查總和（Fargate 在 API 端會擋，§7.2）。
- sidecar 的映像要能被 execution role 拉、`secrets` 要能被 execution role 讀：這些權限在 `iam-base`，由專案加。

**ADOT 範例放在哪裡**：兩個地方，分工不同。

| 位置 | 內容 | 為什麼放這裡 |
|---|---|---|
| `modules/ecs-service/examples/adot-sidecar/` | 只示範 `sidecars` 怎麼填一個 ADOT collector：映像、`essential = false`（collector 掛掉不應該連帶讓整個 task 重啟、中斷服務；project-c 的寫法是 `true`，這裡刻意不同）、`AOT_CONFIG_CONTENT` 用 `environment` 帶入 collector 設定、health check、`app_depends_on = "START"`、主 container 的 `OTEL_EXPORTER_OTLP_ENDPOINT = http://localhost:4317` | module 的 example 會被 CI 跑 `init -backend=false` 與 `validate`，寫法壞了會被抓到 |
| `docs/guides/observability.md`（新增） | 範本已接好之後怎麼開：`iam-app` 的 `tracing`、`application` 的 `adot_collector`、沒有 NAT 時的 mirror 與 endpoint；collector 設定檔（OTLP receiver、batch、memory_limiter、濾掉 health check、`awsxray` exporter、`health_check` extension）、`xray` module 的 sampling rule 怎麼配與 remote sampling 的前提、log 告警 | 牽涉三個 stack，但接線都在範本裡，預設關閉（決策 36；原本決策 32 把這些留給專案、範本不放，理由是預設關閉的 sidecar 每個專案都要背，使用者要第一版就能用，所以改成範本已接好、預設關閉）。guide 不會被 CI 驗證，所以 HCL 片段要跟 module example 與範本對照 |

collector 設定用 `environment` 帶，不學 project-c 存成 SSM parameter 再用 `secrets` 讀：設定檔不是機密，而範本規定 `aws_ssm_parameter` 只能由 `ssm-publish` 建（§5.6 S2）。設定檔太大放不進環境變數時，改成把設定烤進自己的 collector 映像。


### 4.21 `vpc-interface-endpoints`

**用途**：建 interface endpoint（PrivateLink）與它們共用的 SG。名稱刻意寫成 `vpc-interface-endpoints` 而不是 `vpc-endpoints`：這個 module 只負責 interface endpoint，gateway endpoint（S3、DynamoDB）留在 `vpc`，名稱不寫清楚會讓人以為兩種都在這裡。從 `vpc` 拆出來（決策 34），因為 interface endpoint 不碰路由：只要給 VPC id、subnet id 與允許的 CIDR，就能放進我們自己建的 VPC，也能放進客戶已經建好的 VPC（§5.8 模式 A）。

**參考來源**

- endpoint SG 只對 VPC CIDR 開 443、`private_dns_enabled = true`：原本在 `modules/vpc/endpoints.tf`（拆出前的實作）、`project-a/infra-v2/terraform/network/vpc-interface-endpoints.tf`
- 服務清單：`project-c-infra/environments/uat/platform/terraform.tfvars`（`vpce_interface_config`）

**資源**：`aws_security_group.this`（`Name` 為 `<name>-vpce`）、`aws_vpc_security_group_ingress_rule.https`（`for_each = allowed_cidrs`，`Name` tag 為 `<name>-vpce-https`）、`aws_vpc_endpoint.this`（`for_each = services`）。`services` 是空集合時三種資源都不建。規則是獨立的 rule 資源，沒有 inline；SG 沒有任何 egress 規則（interface endpoint 只需要被連入）。

**輸入**

```hcl
variable "name" {
  type        = string
  description = "Prefix for the security group and endpoint Name tags."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  type = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to reach the endpoints on 443, usually [vpc_cidr]."
  validation {
    condition = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && can(cidrnetmask(c)) && c != "0.0.0.0/0"
    ])
    error_message = "allowed_cidrs needs at least one valid IPv4 CIDR and must not contain 0.0.0.0/0."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "One subnet per AZ for the endpoint network interfaces."
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "services" {
  type        = set(string)
  default     = []
  description = "Service names after com.amazonaws.<region>., e.g. ecr.api. Empty creates nothing."
  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9][a-z0-9.-]*$", s)) && !startswith(s, "com.amazonaws.")])
    error_message = "Service names are the part after com.amazonaws.<region>., e.g. ecr.api."
  }
}

variable "private_dns_enabled" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

**輸出**：`endpoint_ids`（`map(string)`，key 是服務名稱）、`security_group_id`（`services` 為空時是 `null`）。

**`allowed_cidrs` 而不是 `vpc_cidr`**：大多數時候給 `[vpc_cidr]` 就好，但客戶自管的 VPC 可能有 secondary CIDR，或要讓 peering 過來的網段也用這些 endpoint。收清單不會讓呼叫端變複雜，又不用之後為了這個改介面（§9.1 J45）。

**private DNS 的前提**：`private_dns_enabled = true` 需要 VPC 開啟 `enableDnsSupport` 與 `enableDnsHostnames`。我們自己建的 VPC 由 `vpc` module 固定開啟；客戶的 VPC 要由 network stack 檢查（§5.8）。module 本身不檢查，因為它拿不到 VPC 的屬性，讀 `data "aws_vpc"` 會讓 module 多一個 data source 的依賴。

**刻意不做**：gateway endpoint（它們是路由，留在 `vpc`，§4.7）、endpoint policy、一個服務一個 SG、自己決定放哪個 tier（subnet 由呼叫端決定，tier 的檢查在 network stack）。這個 module 不建 IAM。

### 4.22 module 怎麼串：完整三層

下面依 apply 順序列出每個 stack 裡的 module 呼叫，示範一個 module 的輸出怎麼變成下一個 module 的輸入。同一個 stack 內直接引用 module 輸出；跨 stack 一律經過 SSM：寫用 `ssm-publish`，讀用 `ssm-read`（`module.in.strings`、`module.in.lists`，寫法見 §5.6）。stack 裡唯一的原生 resource 是 `foundation` 的 secret 容器（§5.3 例外清單）。

**注意：這段的 `source` 是範本「複製到專案 repo 之後」的樣子。** 在本 repo 裡，範本用相對路徑引用 module（例如 `source = "../../../../../modules/vpc"`），這樣本 repo 才能在 tag 還不存在、repo 還沒上 GitHub 的時候跑 `init -backend=false`、`validate`、`test`。怎麼改見 §5.1〈module 的 source〉。為了篇幅，下面的 `source` 只寫 module 名稱與版本。

```hcl
# ── foundation ───────────────────────────────────────────────
module "kms" {
  source             = "git::https://github.com/<org>/<repo>.git//modules/kms-key?ref=kms-key-v0.1.0"
  name               = local.name_prefix
  service_principals = local.kms_service_principals # logs, cloudwatch, sns ...（§4.10）
}

module "alarm_topic" {
  source              = "git::.../modules/sns-alarm-topic?ref=sns-alarm-topic-v0.1.0"
  name                = "${local.name_prefix}-alarms"
  email_subscriptions = var.alarm_emails
  kms_master_key_id   = module.kms.key_arn
}

module "flow_log_bucket" {
  source       = "git::.../modules/s3-bucket?ref=s3-bucket-v0.1.0"
  name         = "${local.name_prefix}-flow-logs-${local.account_id}"
  log_delivery = ["vpc_flow_logs"]
}

module "alb_log_bucket" {
  source       = "git::.../modules/s3-bucket?ref=s3-bucket-v0.1.0"
  name         = "${local.name_prefix}-alb-logs-${local.account_id}"
  log_delivery = ["alb_access_logs"] # kms_key_arn 必須留 null（module validation 擋）
}

# ── containerimage ───────────────────────────────────────────
module "ecr" {
  source      = "git::.../modules/ecr-repository?ref=ecr-repository-v0.1.0"
  for_each    = toset(var.services)
  name        = "${local.name_prefix}-${each.key}"
  kms_key_arn = module.in.strings["kms_key_arn"]
}

# ── network ──────────────────────────────────────────────────
module "vpc" {
  source              = "git::.../modules/vpc?ref=vpc-v0.1.0"
  name                = local.name_prefix
  cidr                = var.vpc.cidr
  azs                 = var.vpc.azs
  nat_mode            = var.vpc.nat_mode
  subnets             = var.vpc.subnets # 範例 tfvars 見 §5.11；tier 名稱 public／app／data 固定
  flow_log            = var.vpc.flow_log ? { destination_arn = module.in.strings["flow_log_bucket_arn"] } : null
}

module "vpce" {
  source        = "git::.../modules/vpc-interface-endpoints?ref=vpc-interface-endpoints-v0.1.0"
  name          = local.name_prefix
  vpc_id        = module.vpc.vpc_id
  allowed_cidrs = [module.vpc.vpc_cidr]
  subnet_ids    = module.vpc.subnet_ids[var.interface_endpoints.subnet_tier]
  services      = var.interface_endpoints.services # 模式 A 也照樣呼叫，改用 existing 的值（§5.8）
}

module "sg" {
  source          = "git::.../modules/security-group?ref=security-group-v0.1.0"
  vpc_id          = module.vpc.vpc_id
  security_groups = local.security_groups # alb、每個服務、db、db_proxy
  rules           = local.sg_rules        # 由 services、data_stores、alb_ingress 展開（§4.16、§5.3）
}

# ── iam-base ─────────────────────────────────────────────────
module "ecs_execution_role" {
  source = "git::.../modules/iam-role?ref=iam-role-v0.1.0"
  name   = "${local.name_prefix}-ecs-execution"
  trust  = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = local.account_id }
  inline_policies = {
    pull-and-log = jsonencode({ Version = "2012-10-17", Statement = local.execution_statements })
  }
}

module "rds_proxy_role" {
  source = "git::.../modules/iam-role?ref=iam-role-v0.1.0"
  name   = "${local.name_prefix}-rds-proxy"
  trust  = { service_principals = ["rds.amazonaws.com"], source_account = local.account_id }
  # 只有 trust；讀 secret 的 policy 由 iam-app 在 secret 存在後附加（§5.4）
}

# ── data ─────────────────────────────────────────────────────
module "db" {
  source             = "git::.../modules/rds?ref=rds-v0.1.0"
  name               = "${local.name_prefix}-db"
  deployment         = var.db.deployment
  engine_version     = var.db.engine_version
  database_name      = var.db.database_name
  rds                = var.db.rds
  aurora             = var.db.aurora
  serverless         = var.db.serverless
  subnet_ids         = module.in.lists["subnet_ids_data"]
  security_group_ids = [module.in.strings["sg_db_id"]]
  kms_key_arn        = module.in.strings["kms_key_arn"]

  # 有沒有 Proxy 由 network stack 決定（SG 規則在那裡），這裡照著讀
  proxy = jsondecode(module.in.strings["db_proxy"]).enabled ? {
    security_group_ids = [module.in.strings["sg_db_proxy_id"]]
    role_arn           = module.in.strings["role_rds_proxy_arn"]
  } : null

  monitoring     = { role_arn = module.in.strings["role_rds_monitoring_arn"] }
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
}
# ssm-publish 發布 database = jsonencode({ enabled = true, app_endpoint = module.db.app_endpoint, ... })

# ── iam-app ──────────────────────────────────────────────────
locals {
  database = jsondecode(module.in.strings["database"])
}

module "rds_proxy_secret_access" {
  source   = "git::.../modules/iam-role-policy?ref=iam-role-policy-v0.1.0"
  for_each = local.database.enabled ? { proxy = true } : {}
  role_arn = module.in.strings["role_rds_proxy_arn"]
  policies = {
    read-master-secret = jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = local.database.secret_arn },
        {
          Effect    = "Allow", Action = ["kms:Decrypt"], Resource = module.in.strings["kms_key_arn"]
          Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" } }
        },
      ]
    })
  }
}

module "task_role" {
  source   = "git::.../modules/iam-role?ref=iam-role-v0.1.0"
  for_each = toset(module.in.lists["services"])
  name     = "${local.name_prefix}-${each.key}-task"
  trust    = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = local.account_id }
  inline_policies = local.task_policies[each.key] # 依 data_access、ecs_exec_services 組出來，見 §5.4
}

# ── loadbalancer ─────────────────────────────────────────────
module "alb" {
  source             = "git::.../modules/alb?ref=alb-v0.1.0"
  name               = "${local.name_prefix}-alb"
  subnet_ids         = module.in.lists["subnet_ids_public"]
  security_group_ids = [module.in.strings["sg_alb_id"]]
  certificate_arn    = var.certificate_arn
  access_logs        = var.access_logs_enabled ? { bucket = module.in.strings["alb_log_bucket_name"], prefix = local.name_prefix } : null
  sns_topic_arns     = [module.in.strings["alarm_topic_arn"]]
}

# ── application ──────────────────────────────────────────────
locals {
  database = jsondecode(module.in.strings["database"])
}

module "cluster" {
  source = "git::.../modules/ecs-cluster?ref=ecs-cluster-v0.1.0"
  name   = "${local.name_prefix}-app"
}

module "api" {
  source             = "git::.../modules/ecs-service?ref=ecs-service-v0.1.0"
  name               = "${local.name_prefix}-api"
  cluster_arn        = module.cluster.cluster_arn
  image              = "${module.in.strings["ecr_api_url"]}:${var.api_image_tag}"
  container_port     = 8080
  execution_role_arn = module.in.strings["role_ecs_execution_arn"]
  task_role_arn      = module.in.strings["role_api_task_arn"]

  # 開關由 iam-app 決定，跟 task role 的 ssmmessages 權限同一個來源（§5.4）
  enable_execute_command = jsondecode(module.in.strings["ecs_exec_api"]).enabled

  network = {
    subnet_ids         = module.in.lists["subnet_ids_app"]
    security_group_ids = [module.in.strings["sg_api_id"]]
  }

  # DB 連線資訊；application 不需要知道有沒有開 Proxy、是哪種型態
  environment = {
    DB_HOST        = local.database.app_endpoint
    DB_READER_HOST = local.database.app_reader_endpoint
    DB_PORT        = tostring(local.database.port)
    DB_NAME        = local.database.name
    DB_SECRET_ARN  = local.database.secret_arn # task role 讀，見 §5.4、§8.2
  }

  load_balancer = {
    listener_arn   = module.in.strings["listener_arn"]
    vpc_id         = module.in.strings["vpc_id"]
    priority       = 100
    path_patterns  = ["/api/*"]
    alb_arn_suffix = module.in.strings["alb_arn_suffix"]
  }

  desired_count = var.api_desired_count
  autoscaling = {
    min_capacity    = var.api_desired_count
    max_capacity    = var.api_max_capacity
    target_tracking = { requests_per_target = 300 }
  }
}

module "api_alarms" {
  source         = "git::.../modules/ecs-service-alarms?ref=ecs-service-alarms-v0.1.0"
  name           = module.api.service_name
  cluster_name   = module.cluster.cluster_name
  service_name   = module.api.service_name
  sns_topic_arns = [module.in.strings["alarm_topic_arn"]]
  max_capacity   = var.api_max_capacity

  load_balancer = {
    alb_arn_suffix          = module.in.strings["alb_arn_suffix"]
    target_group_arn_suffix = module.api.target_group_arn_suffix
  }

  dashboard_name = "${local.name_prefix}-api"
}
```

告警分在三個地方，各自只建一份：ALB 整體（ELB 5xx）在 `alb`、資料庫在 `rds`、每個服務在 `ecs-service-alarms`。服務的告警直接吃 `module.api` 的輸出，同一次 apply 建立。project-a 的告警放在 `postdeploy` stack，cluster 名稱、service 名稱、target group suffix 都寫在 tfvars（`project-a/infra-v2/terraform/postdeploy/envs/devbox.tfvars`），前面的 stack 換了資源，這份 tfvars 不改，plan 也不會提醒。

上面範例裡的中文註解只為了說明；寫進 `modules/` 底下的 `.tf` 時，註解一律用英文（§4.1）。

### 4.23 增補：LLM 與 AgentCore 的 module（決策 37 起）

這一段是 v1 的增補，不是另一版設計。§4.2–§4.22 的 19 個 module 與它們的 `v0.1.0` tag 不動；下面 7 個新 module 的首版是 `<module>-v0.1.1`，`rds` 為了 Knowledge Base 加 Data API 與兩個輸出（§4.31），發 `rds-v0.1.1`；`s3-bucket` 為了 KB 的語料 bucket 加不過期的選項（§4.32），發 `s3-bucket-v0.1.1`。版本號見決策 54。實作步驟見 implement-process 的 Phase 11–16。

| module | 一句話 | 參考實作 | 有沒有部署過的證據 |
|---|---|---|---|
| `bedrock-guardrail`（§4.24） | 一支 guardrail，tier 預設 `STANDARD` | `project-a/infra-v2/terraform/agent/guardrail.tf` | 有（project-a） |
| `bedrock-inference-profile`（§4.25） | application inference profile，給成本歸屬 | project-c `project-c-app/modules/app-platform/bedrock-inference-profile.tf` | 有（project-c） |
| `agentcore-runtime`（§4.26） | 一個 AgentCore Runtime | `project-a/infra-v2/terraform/agent/runtime.tf` | 有（project-a） |
| `agentcore-memory`（§4.27） | 一個 AgentCore Memory 與內建 strategy | `project-a/infra-v2/terraform/agent/runtime.tf` 的 `aws_bedrockagentcore_memory` | 只有短期記憶（沒有 strategy）部署過 |
| `agentcore-gateway`（§4.28） | MCP Gateway，target 只收 Lambda 與 MCP server | project-b `infra/terraform/modules/agentcore/gateway.tf` | **沒有**：project-b 的 Lambda target 檔頭註明「legacy, currently unused」，OpenAPI target 已停用 |
| `log-delivery`（§4.29） | CloudWatch vended log 的 source、destination、delivery | `project-a/infra-v2/terraform/postdeploy/agentcore-tracing.tf`、`project-a/infra-v2/terraform/agent/logs.tf` | 有（project-a） |
| `bedrock-knowledge-base`（§4.30） | Bedrock Knowledge Base（向量儲存只收 Aurora PostgreSQL pgvector）與 S3 data source | 無 | **沒有**：三個參考專案都沒用過 Bedrock Knowledge Base；project-a 的知識庫是自建 pgvector 加嵌入模型 |

**7 個新 module 共通的約定**：§4.1 全部適用（不建 IAM、不互相呼叫、收完整 `name`、`tags` 只加 `Name`、英文註解、沒有 `enable_xxx`），設計上只有下表一處例外。實作後另有兩處 tag 跟「`tags` 只加 `Name`」不同：~~`bedrock-inference-profile` 的 profile 只帶輸入的 `tags`、不加 `Name`（D31）~~（決策 56 已修：profile 加 `Name = <name_prefix>-<key>`），`log-delivery` 的 delivery 只帶輸入的 `tags`（D35）；以程式碼為準，`log-delivery` 那一處仍列為待統一。

**安全補強（決策 56，`59f647b`～`8ab4b91`）**：模組安全審查之後，下面這些檢查併進同一批 `v0.1.1`（tag 還沒推，重打，見決策 54 的附註）。各 module 的 CHANGELOG 是逐條清單，這裡只列規則：

| 項目 | 內容 | module |
|---|---|---|
| 同帳號 | 新增 `allowed_account_ids`（預設 `[]`，`nullable = false`，只收 12 位數字）；跨帳號的資源要明列才放行，用 `aws_caller_identity` 做 precondition（變數 validation 讀不到 data source）。檢查對象：Gateway 的 Lambda target、Runtime 映像的 ECR registry、log-delivery 的 source 與 `CWL` 目的地（S3 bucket ARN 不帶帳號，不檢查）、KB data source 的 `bucket_owner_account_id`（改為必填）。KB 的 cluster 與 secret 另外要求同帳號同 region，沒有 `allowed_account_ids` 可放行；inference profile 的 `copy_from` 是 `inference-profile` 時必須同帳號，而且不准 `*` | `agentcore-gateway`、`agentcore-runtime`、`log-delivery`、`bedrock-knowledge-base`、`bedrock-inference-profile` |
| `role_arn` | 三個 module 同一條 regex：`^arn:aws[a-z-]*:iam::<12 位>:role(/<段>)*/<名稱>$`，允許 path、不允許空的一段（解掉 D36 的不一致） | `agentcore-runtime`、`agentcore-gateway`、`bedrock-knowledge-base` |
| KMS key ARN | 只收 `key/<uuid>` 與多區域的 `key/mrk-<32 位 hex>`；alias、單獨的 key id、`*` 都擋 | `bedrock-guardrail`、`agentcore-memory`、`agentcore-gateway`、`bedrock-knowledge-base` |
| guardrail PII | `pii_entities` 的 key 只收 aws provider 6.69.0 的 31 種類型；README 建議用 SCP 或 permission boundary 把 `bedrock:UpdateGuardrail`、`bedrock:DeleteGuardrail` 限給部署用的 role（module 不建） | `bedrock-guardrail` |
| JWT | `allowed_audience`、`allowed_clients` 不准空字串或只有空白的項目 | `agentcore-runtime`、`agentcore-gateway` |
| Runtime 標頭 | `request_header_allowlist` 擋 `Cookie`、`Proxy-Authorization`、`Host`、`X-Amz-Security-Token`、`X-Amz-Date`（不分大小寫）；`Authorization` 只在有 `jwt_authorizer` 時可以轉 | `agentcore-runtime` |
| Runtime 環境變數 | 名稱含 `SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`／`APIKEY`、`PRIVATE_KEY`／`PRIVATEKEY`、`CREDENTIAL`（不分大小寫）就擋，例外是名稱以 `_ARN` 結尾而且值以 `arn:` 開頭（範本的 `DB_SECRET_ARN` 因此照樣通過）。取代 J62 的「不做」；`:latest` 改成不分大小寫 | `agentcore-runtime` |
| log bucket | `never_expire = true` 搭配非空的 `log_delivery` 被擋：log bucket 一定要過期 | `s3-bucket` |
| trust | `trust.source_arn`（選填）在同一段 statement 加 `ArnLike` 的 `aws:SourceArn`；沒給的呼叫端 trust JSON 跟 0.1.0 逐字相同（測試 `source_account_only_policy_unchanged`），沒有用 plan 驗證 | `iam-role`（因此加入 `v0.1.1`，決策 56） |

| 項目 | 例外 | 理由 |
|---|---|---|
| `versions.tf` | aws `>= 6.69, < 7.0`，不是 `>= 6.0, < 7.0` | `aws_bedrockagentcore_*` 在 6.0 不存在（project-a 在 5.100.0 確認過不存在，`project-a/docs/adr/0016-bedrock-interface-endpoints-and-agentcore-memory.md`），寫 `>= 6.0` 等於宣告一個做不到的相容範圍。6.69.0 是唯一實際查過 schema 的版本（範本 8 個 stack 的 lock 檔也是 6.69.0）。之後逐版查出真正的最低版本，放寬下限是 MINOR（§3.5 的「放寬」）。決策 43 |

**schema 查證**：下面每個介面都對過 aws provider 6.69.0 的 `terraform providers schema -json`。schema 不帶 enum 允許值、名稱規則與數值範圍，這些 validation 照 AWS 文件或參考實作寫，**沒有實測的一律在 validation 旁標「未實測」**，列進 §7.3。

### 4.24 `bedrock-guardrail`

**用途**：建一支 Bedrock guardrail。一次呼叫一支；同一個專案要多支（例如輸入、輸出各一支，或依專館分組），由 root 用 `for_each` 呼叫（比照 §9.1 J1）。

**參考來源**

- `project-a/infra-v2/terraform/agent/guardrail.tf`（`tier_config` 第 43–46、107–110、163–166 行；空 policy 不送第 144–145 行；名稱與 topic 數的 precondition 第 224–232 行）
- `project-a/docs/guide/guide-data-scientist.md`〈五條紅線〉〈三個實測踩過的坑〉（第 266–300 行）

**資源**：`aws_bedrock_guardrail.this`。`data "aws_region"`、`data "aws_caller_identity"`、`data "aws_partition"` 組 guardrail profile ARN（測試用 `override_data`）；region 取 `data.aws_region.current.region`，不用 provider 6.x 已 deprecated 的 `.name`（D30）。

**example**：`examples/basic`（`STANDARD` 加 profile）、`examples/zh-tw-standard`（中文 topic 與 content filter）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,50}$", var.name))
    error_message = "name must be 1-50 characters of letters, digits, hyphens or underscores."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "blocked_input_message" {
  type        = string
  description = "Text returned instead of the prompt when the input is blocked."
}

variable "blocked_output_message" {
  type        = string
  description = "Text returned instead of the model output when the output is blocked."
}

variable "tier" {
  type        = string
  default     = "STANDARD"
  description = "STANDARD or CLASSIC. CLASSIC evaluates English only; non-English text passes unchecked."
  validation {
    condition     = contains(["STANDARD", "CLASSIC"], var.tier)
    error_message = "tier must be STANDARD or CLASSIC."
  }
}

variable "cross_region_profile_id" {
  type        = string
  default     = null
  description = "Guardrail profile id, e.g. apac.guardrail.v1:0. Required for STANDARD. No API validates it; a wrong id only fails on the first real request."
  validation {
    condition = var.tier == "STANDARD" ? (
      var.cross_region_profile_id != null && can(regex("^[a-z]+(-[a-z]+)?\\.guardrail\\.v[0-9]+:[0-9]+$", var.cross_region_profile_id))
    ) : var.cross_region_profile_id == null
    error_message = "STANDARD needs cross_region_profile_id like apac.guardrail.v1:0; CLASSIC must leave it null."
  }
}

variable "content_filters" {
  type = map(object({                            # key: SEXUAL | VIOLENCE | HATE | INSULTS | MISCONDUCT | PROMPT_ATTACK
    input_strength  = string                     # NONE | LOW | MEDIUM | HIGH
    output_strength = string
    input_action    = optional(string, "BLOCK")  # BLOCK | NONE
    output_action   = optional(string, "BLOCK")
    input_enabled   = optional(bool, true)
    output_enabled  = optional(bool, true)
  }))
  default = {}
}

variable "denied_topics" {
  type = map(object({
    definition = string                          # the only place to state exclusions; examples are positive only
    examples   = optional(list(string), [])
  }))
  default = {}
}

variable "words" {
  type    = list(string)
  default = []
}

variable "managed_word_lists" {
  type    = set(string)                          # PROFANITY only (validated)
  default = []
}

variable "pii_entities" {
  type = map(object({                            # key: entity type, e.g. EMAIL, PHONE
    action         = string                      # BLOCK | ANONYMIZE
    input_enabled  = optional(bool, true)
    output_enabled = optional(bool, true)
  }))
  default = {}
}

variable "regexes" {
  type = map(object({
    pattern     = string
    action      = string                         # BLOCK | ANONYMIZE
    description = optional(string)
  }))
  default = {}
}

variable "contextual_grounding" {
  type = object({
    grounding_threshold = optional(number)       # 0-0.99; at least one of the two must be set
    relevance_threshold = optional(number)
  })
  default = null
}

variable "kms_key_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 | 依據 |
|---|---|---|
| 名稱 | 1–50 個 `[0-9A-Za-z_-]` | `project-a/infra-v2/terraform/agent/guardrail.tf:224-227` |
| tier 與 profile | `STANDARD` 必須給 `cross_region_profile_id`，格式像 `apac.guardrail.v1:0`；`CLASSIC` 必須是 null。格式 regex 只照 project-a 用過的一個值推出來，**未實測**其他 profile id 的形狀 | `project-a/docs/guide/guide-data-scientist.md:280-292` |
| content filter | key 只收 6 種；strength 只收 `NONE`／`LOW`／`MEDIUM`／`HIGH`；action 只收 `BLOCK`／`NONE`；**`PROMPT_ATTACK` 的 `output_strength` 必須是 `NONE`**（API 會拒絕其他值） | `project-a/docs/guide/guide-data-scientist.md`〈五條紅線〉 |
| topic 數 | `denied_topics` 不得超過 30 個；`definition` 不得是空字串 | `project-a/infra-v2/terraform/agent/guardrail.tf:229-232` |
| 至少一種 policy | `content_filters`、`denied_topics`、`words`、`managed_word_lists`、`pii_entities`、`regexes`、`contextual_grounding` 至少一個非空。**寫成 `aws_bedrock_guardrail.this` 的 lifecycle precondition，不是變數的 validation**，測試的 `expect_failures` 指向那個 resource（D30） | Bedrock 不收沒有任何 policy 的 guardrail（**未實測**，照 API 文件） |
| PII 與 regex 的 action | 只收 `BLOCK`、`ANONYMIZE` | 照 API 文件，**未實測** |
| grounding 門檻 | 0 到 0.99；給了 `contextual_grounding` 就至少要有一個門檻（兩個都 null 時被擋，D30） | 照 API 文件，**未實測** |
| managed word list | 只收 `PROFANITY`（D30） | AWS 目前只有這一種 managed word list |

**行為**

- `tier_config = [{ tier_name = var.tier }]` **同時**放在 `content_policy_config` 與 `topic_policy_config`。在 provider 6.69.0 裡 `tier_config` 是 list 型別的屬性，不是 block，所以寫成指派而不是 `tier_config { ... }`（D30）。`tier_config` 在 schema 是 optional 加 computed：省略時 AWS 給 `CLASSIC`，之後的 plan 也不會出現差異，所以一律明寫。
- 每個 topic 的 `type` 寫死 `"DENY"`（目前唯一的值），不開成輸入。
- `tier = "STANDARD"` 時 `cross_region_config.guardrail_profile_identifier` 是 `arn:<partition>:bedrock:<region>:<account>:guardrail-profile/<id>`（照 `project-a/infra-v2/terraform/agent/guardrail.tf:21`）。
- 每個 policy 區塊在對應輸入為空時整塊不送（dynamic block）：Bedrock 拒收空清單（`project-a/infra-v2/terraform/agent/guardrail.tf:144-145`）。`topic_policy_config` 只有在 `denied_topics` 非空時才送，`tier_config` 跟著它走。
- topic 沒有 `input_enabled`／`output_enabled`（schema 沒有這兩個欄位），要只作用在某一側，就把它放在只有那一側會呼叫的那支 guardrail。

**輸出**：`guardrail_id`、`guardrail_arn`、`name`、`version`（永遠是 `"DRAFT"`，寫死在 output，不讀 resource 的 `version`）、`cross_region_profile_arn`（`CLASSIC` 時是 null）、`cross_region_profile_id`。

**要修掉的坑**

| project-a 的坑 | 這裡怎麼做 |
|---|---|
| 省略 `tier_config` 就是 `CLASSIC`，中文完全不擋，`status: READY`、plan 乾淨 | 預設 `STANDARD`，兩個 policy 都帶；要 `CLASSIC` 必須明寫 |
| `STANDARD` 的 profile id 寫錯，apply 照樣成功，要到第一個真實請求才失敗 | validation 只擋得到格式；README 寫明「只有實際呼叫驗得到」，§7.3 第 15 項 |
| 發佈 guardrail 版本之後，apply 只改 `DRAFT`，實際生效的是舊版，plan 乾淨 | **module 不建 `aws_bedrock_guardrail_version`**，`version` 輸出固定 `DRAFT`；靜態規則 S9 擋整個 repo 出現這個 resource（§5.6，決策 46） |
| input 那支加 PII 遮罩，`ANONYMIZE` 也回 `GUARDRAIL_INTERVENED`，整輪被擋 | 不做成 validation（判斷在應用程式），README 與 guide 寫警告 |

**刻意不做**：`aws_bedrock_guardrail_version`（上表）；IAM（`bedrock:ApplyGuardrail` 在範本的 `iam-app`，§5.4 增補）；`input_modalities`／`output_modalities`（第一版只處理文字）；managed word list 以外的 word list 的 `*_action`（全部用預設的 `BLOCK`，需要時 MINOR）。

### 4.25 `bedrock-inference-profile`

**用途**：建 application inference profile。用途只有一個：成本歸屬。每個 profile 帶自己的 tag，呼叫端把 profile ARN 當 `modelId` 傳，Cost Explorer 就能依 tag 拆出這個專案、這個用途的模型費用。

**參考來源**：`project-c-app/modules/app-platform/bedrock-inference-profile.tf`（檔頭註解第 9–16 行：`copy_from` 必須是 foundation model 或 system inference profile 的完整 ARN；名稱上限 64 字）。

**資源**：`aws_bedrock_inference_profile.this`（`for_each = profiles`）。

**輸入**

```hcl
variable "name_prefix" {
  type        = string
  description = "Profile names are <name_prefix>-<key>."
}

variable "profiles" {
  type = map(object({
    copy_from   = string                         # foundation-model or system inference-profile ARN
    description = optional(string)
  }))
  validation {
    condition = alltrue([for k, v in var.profiles :
      length("${var.name_prefix}-${k}") <= 64 &&
      can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+:([0-9]{12})?:(foundation-model|inference-profile)/.+$", v.copy_from))
    ])
    error_message = "Names must fit 64 chars; copy_from must be a foundation-model or inference-profile ARN."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

名稱字元規則照 AWS 文件（`^([0-9a-zA-Z:.][ _-]?)+$`，所以不能連續兩個 `-`），實作成 `profiles` 的第二條 validation，**未實測**。64 字上限 provider 6.69.0 自己也會擋，module 先擋是為了讓錯誤指到 `profiles`。`copy_from` 的 regex 只收 `foundation-model/`、`inference-profile/`，application inference profile 的 ARN（`application-inference-profile/`）會被擋，有測試鎖住（D31）。`profiles` 沒有預設值也可以是空 map：空 map 時什麼都不建（範本的 `agent` 預設就是這樣）。

`tags` 原樣套到每個 profile，**不加 `Name`**（跟 §4.1 不同，D31）。

**輸出**：`arns`、`ids`（`map(string)`，key 同 `profiles`）。

**刻意不做**：模型使用權（`aws_bedrock_foundation_model_agreement`、`aws_bedrock_use_case_for_model_access`：逐帳號、牽涉 Marketplace 訂閱，profile 是 `ACTIVE` 不代表能呼叫，`project-a/docs/runbook/runbook-cross-account-bedrock.md:20-33`）；provisioned throughput；IAM（呼叫 profile 的權限在 `iam-app`，ARN 由 `agent` 的 `models` 統一組，§5.3 增補）。

### 4.26 `agentcore-runtime`

**用途**：建一個 AgentCore Runtime（容器型 artifact）。

**參考來源**

- `project-a/infra-v2/terraform/agent/runtime.tf`（VPC 模式、`lifecycle_configuration` 兩個值一起送，第 91–107 行；`TRACELOOP_TRACE_CONTENT = "false"`，第 22 行）
- `project-a/infra-v2/terraform/agent/variables.tf`（映像 tag 由 Terraform 擁有，第 189–192 行；lifecycle 範圍 60–1209600，第 194–226 行）
- `project-a/infra-v2/terraform/iam/ssm-inputs.tf:49`（Runtime 名稱只能用底線）

**資源**：`aws_bedrockagentcore_agent_runtime.this`。不建 `aws_bedrockagentcore_agent_runtime_endpoint`：AWS 自帶的 `DEFAULT` endpoint 夠用，project-a 也只用它（J53）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores (no hyphens), at most 48 chars."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN without a path."
  }
}

variable "container_uri" {
  type        = string
  description = "ECR image with an explicit tag or digest. Terraform owns the tag: change it here and apply."
  validation {
    condition = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+(:[A-Za-z0-9_.-]{1,128}|@sha256:[0-9a-f]{64})$", var.container_uri)) && !endswith(var.container_uri, ":latest")
    error_message = "container_uri must be an ECR image with an explicit tag (not latest) or a sha256 digest."
  }
}

variable "network" {
  type = object({
    mode               = optional(string, "VPC")  # VPC | PUBLIC
    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])
  })
  nullable    = false
  description = "VPC by default. PUBLIC must be written out; it bypasses security groups and VPC endpoints."
}

variable "session_lifecycle" {
  type = object({
    idle_session_timeout = optional(number, 900)   # seconds
    max_lifetime         = optional(number, 28800)
  })
  default     = {}
  nullable    = false
  description = "Always sent as a pair: the API replaces the whole lifecycle configuration, so a missing value silently falls back to the AWS default."
}

variable "protocol" {
  type     = string
  default  = "HTTP"                              # HTTP | MCP | A2A
  nullable = false
}

variable "environment_variables" {
  type     = map(string)
  default  = {}
  nullable = false                               # empty map is sent as null (D32)
}

variable "jwt_authorizer" {
  type = object({
    discovery_url    = string
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default     = null
  description = "null keeps the default IAM (SigV4) inbound auth."
}

variable "request_header_allowlist" {
  type     = set(string)
  default  = []
  nullable = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

變數名用 `session_lifecycle` 不用 `lifecycle`：`lifecycle` 是 Terraform 保留給 module block 的名稱，不能當變數名。

| validation | 內容 | 依據 |
|---|---|---|
| 名稱 | 字母開頭、只有字母數字底線、最多 48 字 | 底線規則：`project-a/infra-v2/terraform/iam/ssm-inputs.tf:49`；48 字照 AWS 文件，**未實測** |
| 映像 | ECR URI，明確 tag 或 digest，不得 `:latest` | 跟 `ecs-service` 同一條規則（§4.3）；Terraform 擁有 tag（決策 45） |
| 網路模式 | `mode` 只收 `VPC`、`PUBLIC`；`VPC` 時 `subnet_ids` 至少 2 個且不重複、`security_group_ids` 1–5 個且不重複（D32）；`PUBLIC` 時兩者都必須是空的 | 決策 42。subnet 下限 2 是本 repo 的高可用慣例（跟 `rds`、`vpc-interface-endpoints` 一致），不是 AWS 的下限；SG 上限 5 照 AWS 文件，**未實測** |
| lifecycle | 兩個值都在 60–1209600 之間，且 `idle_session_timeout <= max_lifetime` | 範圍：`project-a/infra-v2/terraform/agent/variables.tf:208`；大小關係照 API 文件，**未實測** |
| protocol | 只收 `HTTP`、`MCP`、`A2A` | 照 API 文件，**未實測**；project-a 沒有設（用預設），project-b 用過 `HTTP`、`MCP` |
| JWT | `discovery_url` 以 `https://` 開頭、以 `/.well-known/openid-configuration` 結尾；`allowed_audience` 與 `allowed_clients` 至少一個非空 | 照 API 文件，**未實測** |

**行為**

- `lifecycle_configuration = [{ idle_runtime_session_timeout = ..., max_lifetime = ... }]` 兩個值一律一起送。底層 `update-agent-runtime` 是 PUT，少送一個就靜默回到 AWS 預設；project-a 實測過帶 60 讀回 60、不帶讀回 900（`project-a/infra-v2/terraform/agent/variables.tf:194-226` 的說明）。預設值維持 AWS 的 900／28800（決策 48）。
- `network_configuration.network_mode = var.network.mode`；`VPC` 時才有 `network_mode_config { subnets, security_groups }`。
- `jwt_authorizer = null` 時不送 `authorizer_configuration`；`allowed_audience`、`allowed_clients` 其中一個是空集合時，那一個送 `null`。`request_header_allowlist` 為空時不送 `request_header_configuration`。
- `environment_variables` 是空 map 時送 `null`。理由是推測：空 map 讀回來可能是 null，送 `{}` 會讓每次 plan 都有差異；**未實測**（D32、§7.3 第 18 項）。
- **不用 `ignore_changes`**：映像 tag 由 Terraform 擁有，換版只改 `container_uri` 再 apply；繞過 Terraform 直接呼叫 API 換映像，下一次 apply 會退版（`project-a/docs/runbook/runbook-agentcore.md:129,146-148,193`）。project-b 的做法相反（`ignore_changes`，CI 直接更新，`project-b/infra/terraform/modules/agentcore/main.tf:345`），不採用（決策 45）。

**`idle_session_timeout` 的取捨**（寫進 README 與 description）：拉長不會改善冷啟動。project-a 的量測是冷配置約 11.5 秒，而帳號的 session 存量有上限，idle 越長、同時佔用的 session 越多，能撐的流量越少（`project-a/docs/reports/2026-09-19-first-turn-ttft-cold-provisioning/README.md`）。要降冷啟動是應用程式層的 session 分片（project-a ADR-0043），module 不做。

**輸出**：`runtime_arn`、`runtime_id`、`runtime_name`、`runtime_version`、`workload_identity_arn`（`workload_identity_details[0].workload_identity_arn`，空清單時是 null）。

**刻意不做**：execution role（範本 `iam-base` 用 `iam-role` 建）；ECR repository、SG（範本的 `containerimage`、`network`）；log 與 trace 的 delivery（`log-delivery`）；endpoint 資源；`code_configuration`（S3 程式碼型 artifact）與 `filesystem_configuration`；session 分片（應用程式的事）；環境變數的「看起來像 secret」檢查（J62：只能是猜測，會給錯誤的安全感；secret 一律放 Secrets Manager，環境變數只放 ARN）。

### 4.27 `agentcore-memory`

**用途**：建一個 AgentCore Memory，可選加上內建的長期記憶 strategy。

**參考來源**：`project-a/infra-v2/terraform/agent/runtime.tf:72-78`（只有短期記憶，沒有 strategy）、`project-a/infra-v2/terraform/agent/variables.tf:228-237`（事件保留 3–365 天；module 的下限是 7，見下方 validation 表與 D33）。

**資源**：`aws_bedrockagentcore_memory.this`、`aws_bedrockagentcore_memory_strategy.this`（`for_each = strategies`，預設 `{}`，等於 project-a 的現況：只有短期記憶）。strategy 的 `name` 就是 `strategies` 的 key；`namespaces` 輸入送進 provider 的 `namespace_templates`（provider 6.69.0 把 strategy 的 `namespaces` 標成 deprecated），輸入名稱不變（D33）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores, at most 48 chars."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "event_expiry_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "Days a short-term event is kept, 7-365. Changing it only affects events written afterwards."
  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365 && floor(var.event_expiry_days) == var.event_expiry_days
    error_message = "event_expiry_days must be a whole number between 7 and 365."
  }
}

variable "strategies" {
  type = map(object({                            # key: strategy name, same rule as var.name
    type        = string                         # SEMANTIC | SUMMARIZATION | USER_PREFERENCE
    namespaces  = list(string)                   # e.g. /actors/{actorId}/facts; sent as namespace_templates
    description = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "kms_key_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 | 依據 |
|---|---|---|
| 名稱 | 同 Runtime 的底線規則 | 照 API 文件，**未實測** |
| 保留天數 | ~~3–365 的整數~~ 已被 D33 取代：**7–365 的整數** | 上限與整數：`project-a/infra-v2/terraform/agent/variables.tf:228-237`。下限 7：aws provider 6.69.0 在 plan 階段就擋 7 以下的值（`value must be between 7 and 365, got: 3`，主 agent 實測）；API 文件與 project-a 寫的 3 用這個 provider 版本送不出去 |
| strategy 名稱 | `strategies` 的 key 就是 strategy 名稱，規則同 Memory 名稱 | 照 API 文件，**未實測**（D33） |
| strategy 型別 | 只收 `SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE` | 照 API 文件，**未實測**；三個參考專案都沒用過 strategy |
| namespace | 每個 strategy 至少一個、以 `/` 開頭 | 照 API 文件，**未實測** |

`event_expiry_days` 預設 90，不是 project-a 的 365：保留期限越長，個資留存的範圍越大，預設取中間值，要更長的專案明寫。這是判斷，不是實測結果（J52）。

**輸出**：`memory_id`、`memory_arn`、`strategy_ids`（`map(string)`）。

**刻意不做**：`CUSTOM` 與 self-managed strategy（`configuration` 區塊）。schema 裡 `configuration.extraction`／`consolidation` 除了 `model_id` 還必填 `append_to_prompt`，而且自訂模型要另外給 `memory_execution_role_arn`，範本就得多一個 role 與它的權限；三個參考專案都沒用過，第一版不做，需要時 MINOR（J52）。另外不做 Kinesis stream delivery、`indexed_key`、trace delivery（交給 `log-delivery`）、IAM。

### 4.28 `agentcore-gateway`

**用途**：建一個 AgentCore Gateway（MCP）與它的 target。target 只收兩種：Lambda、MCP server（決策 40）。

**參考來源**：`project-b/infra/terraform/modules/agentcore/gateway.tf`（`protocol_type = "MCP"`、`authorizer_type = "AWS_IAM"`、`supported_versions = ["2025-03-26"]`；Lambda target 用 `gateway_iam_role` credential）。**這份參考沒有在任何環境實際使用過**：檔頭寫 Lambda target「legacy, currently unused」；OpenAPI target 經 VPC Lattice 在雙帳號跨 region 的配置走不通，已停用（第 109–113 行）。所以這個 module 的每一條行為都只有 schema 與 AWS 文件當依據。

**資源**：`aws_bedrockagentcore_gateway.this`、`aws_bedrockagentcore_gateway_target.this`（`for_each = targets`）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z-]{0,98}[0-9A-Za-z])?$", var.name))
    error_message = "name must be letters, digits and single hyphens, at most 100 chars."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "role_arn" {
  type = string                                  # IAM role ARN, same validation as agentcore-runtime
}

variable "authorizer" {
  type = object({
    type             = string                    # AWS_IAM | CUSTOM_JWT
    discovery_url    = optional(string)
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default  = { type = "AWS_IAM" }
  nullable = false
}

variable "mcp" {
  type = object({
    supported_versions = optional(set(string), ["2025-03-26"])
    search_type        = optional(string)        # SEMANTIC, or null for none
  })
  default  = {}
  nullable = false
}

variable "kms_key_arn" {
  type    = string
  default = null
}

variable "targets" {
  type = map(object({
    type        = string                         # lambda | mcp_server
    description = optional(string)

    # type = lambda: exactly one of tool_schema_s3_uri and tools
    lambda_arn         = optional(string)
    tool_schema_s3_uri = optional(string)
    tools = optional(list(object({
      name        = string
      description = string
      properties = optional(map(object({         # flat input schema; nested types go through tool_schema_s3_uri
        type        = string                     # string | number | integer | boolean | object | array
        description = optional(string)
        required    = optional(bool, false)
      })), {})
    })))

    # type = mcp_server
    endpoint = optional(string)                  # https URL
  }))
  default  = {}                                  # key: target name
  nullable = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 | 依據 |
|---|---|---|
| 名稱 | gateway 與 target 名稱：英數與單一 `-`（不得有連續的 `--`、不得以 `-` 開頭或結尾），最多 100 字；target 名稱就是 `targets` 的 key | 照 API 文件，**未實測**；「不得有 `--`」是實作時補上的（D34） |
| authorizer | `type` 只收 `AWS_IAM`、`CUSTOM_JWT`，**不收 `NONE`**；`CUSTOM_JWT` 時 `discovery_url` 必填（`https://`、`/.well-known/openid-configuration` 結尾）且 `allowed_audience`／`allowed_clients` 至少一個非空；`AWS_IAM` 時這三個必須是 null 或空 | 不收 `NONE`：沒有認證的 Gateway 等於把背後的工具開給任何拿得到 URL 的人 |
| target 型別 | `type` 只收 `lambda`、`mcp_server` | 決策 40 |
| 型別對應的欄位 | `lambda`：`lambda_arn` 必填（Lambda function ARN，可帶 alias 或版本的 qualifier，D34），`tool_schema_s3_uri` 與非空的 `tools` 恰好一個；`endpoint` 必須是 null。`mcp_server`：`endpoint` 必填且是 `https://` URL；`lambda_arn`、`tool_schema_s3_uri`、`tools` 都必須是 null | 一個 target 只能是一種 |
| inline 工具 | `tools` 非空時每個 `name` 不重複、`description` 非空；`properties[*].type` 只收 JSON Schema 的 6 種基本型別 | — |
| S3 URI | `tool_schema_s3_uri` 是 `s3://<bucket>/<key>`，只有 bucket 沒有 key 的被擋（D34） | — |
| role | `role_arn` 是不帶 path 的 IAM role ARN，同 `agentcore-runtime` | — |
| `mcp.search_type` | 沒有 validation，值原樣送出 | 允許值未查證（D34） |

**為什麼 Lambda 的工具定義是「S3 URI 或扁平的 `tools`」**：schema 查證發現 Lambda target 的 `tool_schema.inline_payload` 不是一個 JSON 字串，而是多層的 block（`input_schema` → `property` → `items` → …，第三層之後才是 `properties_json`／`items_json` 字串）。要收任意 JSON Schema 就得寫遞迴的 dynamic block，而 Terraform 沒有遞迴。所以 module 收兩種：工具的輸入只有一層屬性時用 `tools`（project-b 的寫法就是一層）；需要巢狀型別時，把完整的工具定義放在 S3，給 `tool_schema_s3_uri`。MCP server target 不受影響：它的 inline payload 是字串，但 MCP server 的工具清單由 server 自己回報，第一版不收 inline payload（§9.4 D23、J54）。

**行為**

- `protocol_type = "MCP"` 寫死；`authorizer_type = var.authorizer.type`；`AWS_IAM` 時不送 `authorizer_configuration`。
- Lambda target 一律帶 `credential_provider_configuration { gateway_iam_role {} }`：Gateway 用自己的 role 呼叫 Lambda，權限（`lambda:InvokeFunction`）在範本的 `iam-app` 附加到 gateway role。
- MCP server target 不帶 `credential_provider_configuration`。**AWS 是否接受不帶 outbound 認證的 MCP server target，未實測**（§7.3 第 20 項）；如果不接受，MCP server target 在 credential provider module 做出來之前無法使用，到時候要回頭找使用者決定。
- `search_type = null` 時 `protocol_configuration.mcp` 不送 `search_type`。
- `tools` 寫法的每個工具一律送 `input_schema { type = "object" }`，`properties` 是空 map 時也送（只是沒有 `property`）。AWS 收不收沒有屬性的 `input_schema`、以及 `type = "array"`／`"object"` 的屬性不帶 `items`／`properties`，都**未實測**（D34、§7.3 第 20 項）。

**輸出**：`gateway_id`、`gateway_arn`、`gateway_url`、`target_ids`（`map(string)`）。

**刻意不做**：credential provider（API key、OAuth；要把 secret 交給 AgentCore，之後若做，另開 module，只用 `api_key_secret_config` 或 write-only 欄位，值不進 state）；OpenAPI、Smithy、API Gateway、`http` 型 target；`private_endpoint`（VPC Lattice）；interceptor、policy engine；IAM。

### 4.29 `log-delivery`

**用途**：建 CloudWatch Logs 的 vended log 三件組：delivery source（哪個資源、哪種 log）、delivery destination（送到哪）、delivery（把兩者接起來）。AgentCore 的 Runtime、Memory、Gateway 都靠它把 application log 送進 log group、把 trace 送進 X-Ray。名稱不叫 `agentcore-logs`：這三個資源是 CloudWatch 的通用機制，其他服務也用同一套。

**參考來源**：`project-a/infra-v2/terraform/postdeploy/agentcore-tracing.tf`（`TRACES` → `XRAY`；`replace_triggered_by` 第 34–40、61–67 行）、`project-a/infra-v2/terraform/agent/logs.tf`（`APPLICATION_LOGS` → log group）。

**資源**：`aws_cloudwatch_log_delivery_source.this`、`aws_cloudwatch_log_delivery_destination.this`、`aws_cloudwatch_log_delivery.this`（各自 `for_each`），另外每個 delivery 一個 `terraform_data.source_arn`（不碰 AWS，用途見〈行為〉，D35）。source 與 destination 的 tag 加 `Name = <name_prefix>-<key>`；delivery 只帶輸入的 `tags`（D35）。

**輸入**

```hcl
variable "name_prefix" {
  type        = string
  description = "Source and destination names are <name_prefix>-<key>."
}

variable "sources" {
  type = map(object({
    resource_arn = string
    log_type     = string                        # APPLICATION_LOGS | TRACES | USAGE_LOGS
  }))
  default = {}
}

variable "destinations" {
  type = map(object({
    type         = string                        # CWL | XRAY | S3
    resource_arn = optional(string)              # log group or bucket ARN; must be null for XRAY
  }))
  default = {}
}

variable "deliveries" {
  type = map(object({
    source      = string                         # key in sources
    destination = string                         # key in destinations
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 | 依據 |
|---|---|---|
| `log_type` | 只收 `APPLICATION_LOGS`、`TRACES`、`USAGE_LOGS` | project-a 用過前兩種；第三種照 AWS 文件，**未實測** |
| 目的地 | `type` 只收 `CWL`、`XRAY`、`S3`；`XRAY` 時 `resource_arn` 必須是 null；`CWL` 時必須是 log group ARN、`S3` 時必須是 bucket ARN | project-a 的 XRAY destination 只設 `delivery_destination_type`（`project-a/infra-v2/terraform/postdeploy/agentcore-tracing.tf:7-14`），CWL 只設 `destination_resource_arn`（`project-a/infra-v2/terraform/agent/logs.tf`） |
| 參照 | 每個 delivery 的 `source`、`destination` 都是存在的 key；同一個 source 不接兩次同一個 destination | — |
| 名稱長度 | `<name_prefix>-<key>` 最多 60 字 | 照 API 文件，**未實測** |

**行為**

- `XRAY` destination 設 `delivery_destination_type = "XRAY"`、不送 `delivery_destination_configuration`；`CWL`、`S3` 只送 `delivery_destination_configuration.destination_resource_arn`，跟 project-a 一致。
- **delivery 在 source 的 `resource_arn` 改變時跟著替換**：Runtime 或 Memory 重建、ARN 換了，source 會被替換；delivery 不跟著換的話，刪 source 時撞 `ConflictException`，apply 卡在半途（project-a 實際踩過，`project-a/infra-v2/terraform/postdeploy/agentcore-tracing.tf:34-40` 的註解）。只看 `resource_arn`，source 只改 tag 時不連帶重建 delivery。~~寫法是 `replace_triggered_by = [aws_cloudwatch_log_delivery_source.this[each.value.source].resource_arn]`~~ 已被 D35 取代：Terraform 1.15.8 的 `replace_triggered_by` 只能用 `each.key` 索引別的 resource，不能用 `each.value.source`。實作是每個 delivery 一個 `terraform_data.source_arn`（`input` 是那個 delivery 的 source 的 `resource_arn`），delivery 寫 `replace_triggered_by = [terraform_data.source_arn[each.key].output]`，效果相同。

**輸出**：`source_names`、`destination_arns`、`delivery_ids`（`map(string)`）。

**刻意不做**：log group 本身（`log-group` module）；跨帳號的 destination policy；`record_fields`、`field_delimiter`、S3 的 `s3_delivery_configuration`、destination 的 `output_format`（用預設；`record_fields`、`field_delimiter` 在 schema 是 optional 加 computed，不送時 plan 不會出現差異，D35）；IAM。CloudWatch Logs 目的地需要的 log group resource policy 由 CloudWatch 在建立 delivery 時自動加，前提是部署者有 `logs:PutResourcePolicy`，**未實測**（§7.3 第 19 項）。

### 4.30 `bedrock-knowledge-base`

**用途**：建一個 Bedrock Knowledge Base（`VECTOR` 型），向量存在專案自己的 Aurora PostgreSQL（pgvector），文件來源是 S3。向量儲存**只收 Aurora PostgreSQL**（決策 38）。

**為什麼只收 Aurora**：範本已經有 `rds` module 與 `data` stack，KB 跟應用程式用同一顆資料庫，不多一套向量資料庫的費用與維運。代價是三件 Terraform 做不到的事，要由專案的 migration 做：建 `vector` extension、建表與索引、建 KB 專用的資料庫帳號（SQL 見下，決策 53）。module 只負責接線，並在 plan 時擋掉名稱與欄位對應寫錯的輸入；**資料庫裡有沒有那張表，module 驗不到**。

**參考來源**：三個參考專案都沒有用過 Bedrock Knowledge Base。project-a 的知識庫是自建的 pgvector 加 Bedrock 嵌入模型，不經過 Bedrock KB（`project-a/docs/spec/knowledge-base.md`）。這個 module 的依據只有 schema 與 AWS 文件，所有行為都列在 §7.3 第 21 項待實測。

**資源**：`aws_bedrockagent_knowledge_base.this`（`knowledge_base_configuration.type = "VECTOR"`、`storage_configuration.type = "RDS"`）、`aws_bedrockagent_data_source.this`（`for_each = data_sources`，`data_source_configuration.type = "S3"`）。

**輸入**

```hcl
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z_-]{0,98}[0-9A-Za-z])?$", var.name))
    error_message = "name must be letters, digits, hyphens or underscores, at most 100 chars."
  }
}

variable "description" {
  type    = string
  default = null
}

variable "role_arn" {
  type = string                                  # Bedrock KB service role, created by iam-base; IAM role ARN, path allowed (D36)
}

variable "embedding_model_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+::foundation-model/.+$", var.embedding_model_arn))
    error_message = "embedding_model_arn must be a foundation-model ARN."
  }
}

variable "embedding_dimensions" {
  type        = number
  description = "Must equal the vector(N) size of the table's vector column."
  validation {
    condition     = var.embedding_dimensions > 0 && floor(var.embedding_dimensions) == var.embedding_dimensions
    error_message = "embedding_dimensions must be a positive whole number."
  }
}

variable "aurora" {
  type = object({
    cluster_arn            = string              # rds module output arn (deployment aurora or aurora_serverless)
    credentials_secret_arn = string              # Secrets Manager secret {"username","password"} of a dedicated KB database user
    database_name          = string
    table_name             = string              # schema.table, e.g. bedrock_integration.bedrock_kb
    field_mapping = optional(object({
      primary_key_field     = optional(string, "id")
      vector_field          = optional(string, "embedding")
      text_field            = optional(string, "chunks")
      metadata_field        = optional(string, "metadata")
      custom_metadata_field = optional(string)
    }), {})
  })
}

variable "data_sources" {
  type = map(object({                            # key: data source name, same rule as var.name
    bucket_arn              = string
    inclusion_prefixes      = optional(set(string), [])   # empty is sent as null (whole bucket)
    bucket_owner_account_id = string                         # 必填（決策 56）；目前帳號或 allowed_account_ids 裡的帳號
    data_deletion_policy    = optional(string, "RETAIN")   # RETAIN | DELETE
    chunking = optional(object({
      strategy           = optional(string, "FIXED_SIZE")  # FIXED_SIZE | NONE
      max_tokens         = optional(number, 300)
      overlap_percentage = optional(number, 20)
    }), {})
  }))
  default = {}
}

variable "allowed_account_ids" {
  type     = set(string)                         # 決策 56；目前帳號以外、可以擁有 data source bucket 的帳號
  default  = []
  nullable = false
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key for transient data during ingestion (data source server-side encryption)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

| validation | 內容 | 依據 |
|---|---|---|
| cluster | `aurora.cluster_arn` 必須是 `arn:aws…:rds:<region>:<account>:cluster:<id>`；DB instance ARN（`:db:`）被擋。`<id>` 是字母開頭的英數與 `-`，regex 收大寫（D36） | Bedrock KB 經 RDS Data API 連資料庫，Data API 只支援 Aurora cluster（§4.31） |
| secret | ~~`credentials_secret_arn` 是 Secrets Manager ARN~~ 已被決策 56 取代：必須是帶 6 字元後綴、不含 `*` 的完整 secret ARN | — |
| role | `role_arn` 是 IAM role ARN，**允許帶 path**（D36）；決策 56 起三個 module 用同一條 regex（`role(/<段>)*/<名稱>`，path 不能有空的一段），`agentcore-runtime`、`agentcore-gateway` 也允許 path | — |
| 同帳號（決策 56） | precondition：`aurora.cluster_arn`、`aurora.credentials_secret_arn` 的 region 與帳號必須是目前的（`aws_region`、`aws_caller_identity`）；每個 data source 的 `bucket_owner_account_id` 是 12 位數字，必須等於目前帳號或列在 `allowed_account_ids` | S3 ARN 不帶帳號，別的帳號搶到同名 bucket 也會比對成功；`bucket_owner_account_id` 讓 Bedrock 驗 bucket 的擁有者 |
| 模型與 key（決策 56） | `embedding_model_arn` 不准 `*`；`kms_key_arn` 只收 `key/<uuid>` 或多區域的 `key/mrk-<32 位>`，alias 與 `*` 都擋 | — |
| data source 名稱 | `data_sources` 的 key 就是 data source 名稱，規則同 KB 名稱（D36） | 照 API 文件，**未實測** |
| 名稱 | `database_name` 是小寫識別字；`table_name` 是 `<schema>.<table>` 或 `<table>`，每段 `^[a-z_][a-z0-9_]{0,62}$` | 只收小寫，避免 SQL 裡要加雙引號才對得上 |
| 欄位對應 | 5 個欄位名都是小寫識別字、彼此不重複 | 重複的欄位名，KB 寫入時會互相覆蓋（推論，**未實測**） |
| 維度 | `embedding_dimensions` 是正整數 | 跟 SQL 的 `vector(N)` 必須相同，module 驗不到資料庫，只能靠 README 與 guide 的對照 |
| chunking | `strategy` 只收 `FIXED_SIZE`、`NONE`；`max_tokens > 0`；`overlap_percentage` 1–99 | `overlap_percentage` 的 1–99：aws provider 6.69.0 在 plan 時也擋這個範圍以外的值（實作時發現，D36），module 先擋是為了讓錯誤指到 `data_sources`；其他照 API 文件，**未實測**；`HIERARCHICAL`、`SEMANTIC` 第一版不收 |
| data source | `bucket_arn` 是 S3 bucket ARN；`data_deletion_policy` 只收 `RETAIN`、`DELETE`；prefix 不以 `/` 開頭 | — |

**行為**

- `vector_knowledge_base_configuration.embedding_model_arn = var.embedding_model_arn`；`embedding_model_configuration.bedrock_embedding_model_configuration.dimensions = var.embedding_dimensions`。
- `storage_configuration.rds_configuration`：`resource_arn = aurora.cluster_arn`、`credentials_secret_arn`、`database_name`、`table_name`、`field_mapping` 照輸入；`custom_metadata_field = null` 時不送。
- module 不知道 `credentials_secret_arn` 是哪個資料庫帳號，也不擋 master secret（module 拿不到 master secret 的 ARN）。~~範本的 `agent` 只收專用帳號的 secret，並用 precondition 擋掉 master secret（決策 53，§5.3 增補）~~ 已被決策 55 取代：範本的 `agent` 不再收 secret ARN，自己替每個 KB 建 secret 並把那個 ARN 傳進來，master secret 在結構上就填不進來（測試 `kb_uses_the_secret_it_created` 鎖住）；README 與 description 寫明「不要給 master secret」。
- `data_deletion_policy` 預設 `RETAIN`：刪掉 data source 時不連帶清掉向量資料，避免一次錯誤的 apply 清空知識庫；要跟著刪的專案明寫 `DELETE`。
- `chunking.strategy = "NONE"` 時不送 `fixed_size_chunking_configuration`。
- `inclusion_prefixes` 是空集合時送 `null`（整個 bucket）。`inclusion_prefixes` 有沒有數量上限，**未查證**（§7.3 第 21 項）。
- `kms_key_arn` 有給時，套到每個 data source 的 `server_side_encryption_configuration`；KB 本身不帶 key。

**資料庫要先準備好的東西**（專案的 migration 負責，不在 Terraform 裡；`docs/guides/llm-agentcore.md` 會原樣收錄這段，Phase 15）

```sql
-- 1. extension（需要資料庫的 owner 或 rds_superuser）
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. schema 與表。vector(1024) 的 1024 必須等於 embedding_dimensions
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

CREATE TABLE IF NOT EXISTS bedrock_integration.bedrock_kb (
  id              uuid PRIMARY KEY,
  embedding       vector(1024),
  chunks          text,
  metadata        json,
  custom_metadata jsonb
);

-- 3. 索引：向量用 HNSW（cosine），全文與自訂 metadata 用 GIN
CREATE INDEX IF NOT EXISTS bedrock_kb_embedding_idx
  ON bedrock_integration.bedrock_kb USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS bedrock_kb_chunks_idx
  ON bedrock_integration.bedrock_kb USING gin (to_tsvector('simple', chunks));
CREATE INDEX IF NOT EXISTS bedrock_kb_custom_metadata_idx
  ON bedrock_integration.bedrock_kb USING gin (custom_metadata);

-- 4. KB 專用的資料庫帳號（決策 53）。只能讀寫上面那張表，不是 superuser、不能建資料庫與帳號、
--    不能在任何 schema 建物件。密碼不寫在 migration 裡，見下方〈帳號的密碼〉。
--    帳號名稱必須跟 agent 建的 secret 裡的 username 一致（決策 55：bedrock_kb_user）
--    database 名稱 app 換成 rds 的 database_name；表名換成 aurora.table_name
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bedrock_kb_user') THEN
    CREATE ROLE bedrock_kb_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE app TO bedrock_kb_user;
GRANT USAGE ON SCHEMA bedrock_integration TO bedrock_kb_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON bedrock_integration.bedrock_kb TO bedrock_kb_user;
```

| 對照 | SQL | module 輸入 |
|---|---|---|
| 表 | `bedrock_integration.bedrock_kb` | `aurora.table_name` |
| 主鍵 | `id uuid` | `field_mapping.primary_key_field`（預設 `id`） |
| 向量 | `embedding vector(1024)` | `field_mapping.vector_field`（預設 `embedding`）、`embedding_dimensions = 1024` |
| 文字 | `chunks text` | `field_mapping.text_field`（預設 `chunks`） |
| metadata | `metadata json` | `field_mapping.metadata_field`（預設 `metadata`） |
| 自訂 metadata | `custom_metadata jsonb` | `field_mapping.custom_metadata_field`（預設 null；有給才送，SQL 的這一欄與它的索引才需要） |
| 資料庫帳號 | `bedrock_kb_user` | `aurora.credentials_secret_arn` 指向的 secret 的 `username`（範本的 `agent` 傳入自己建的 `<project>-<env>-kb-<key>-db`，決策 55；~~從 `knowledge_bases[*].credentials_secret_arn` 傳入~~ 已被決策 55 取代） |

欄位名稱、型別與三個索引照 AWS 文件〈Prerequisites for Aurora PostgreSQL〉的範例，**沒有在我們的環境實測**；pgvector 要 0.5.0 以上才有 HNSW，Aurora PostgreSQL 各版本附的 pgvector 版本也**未查證**。migration 用 master 帳號執行（建 extension 與帳號需要它，§8.2）；**KB 連資料庫用的是第 4 步的專用帳號，不是 master**（決策 53，§8.8）。

**帳號權限比 AWS 文件的範例窄**：AWS 文件的範例對 KB 帳號給 `GRANT ALL ON SCHEMA bedrock_integration`，並用 KB 帳號建表（表的 owner 是 KB 帳號）。這裡表由 migration 建、owner 不是 KB 帳號，KB 帳號只有那張表的 `SELECT`、`INSERT`、`UPDATE`、`DELETE` 與 schema 的 `USAGE`，沒有 `CREATE`，也碰不到其他 schema 的表。Bedrock 在 ingestion 與查詢時是否需要更多權限（例如 `TRUNCATE`），**未實測**（§7.3 第 21 項）；實測不夠時，只在那張表上補缺的那一項，不改成 schema 層級的 `ALL`。PostgreSQL 14 以前 `PUBLIC` 預設對 `public` schema 有 `CREATE`，那是整顆資料庫的設定、不是這個帳號的權限，要不要 `REVOKE` 由專案決定，guide 寫明。

**帳號的密碼**（值由專案寫入，不在 Terraform 裡；secret 容器由範本的 `agent` 建，決策 55）：

~~原本的四步（專案自己建 secret → 跑 migration → `ALTER ROLE` → 把 secret ARN 寫進 `knowledge_bases[*].credentials_secret_arn`）~~ 已被決策 55 取代，改成兩段式：

| 步驟 | 誰做 | 做什麼 |
|---|---|---|
| 1 | 範本 | `agent` 的 `knowledge_bases` 加上這個 KB，`database_user_ready` 不寫（預設 `false`），Runtime 先不列它；apply `agent`：只建 secret `<project>-<env>-kb-<key>-db`（`foundation` 的專案 KMS key 加密，不含值）與語料 bucket，不建 KB。再 apply `iam-app`，KB role 拿到讀這個 secret 的權限 |
| 2 | 專案 | 寫入 secret 的值：`aws secretsmanager put-secret-value`，內容是 `{"username":"bedrock_kb_user","password":"<隨機產生>"}`（Bedrock 讀這兩個 key）。密碼用 `get-random-password` 產生、經檔案傳入、用完刪掉 |
| 3 | 專案 | 跑上面的 migration（第 1–4 步），再用 master 帳號執行 `ALTER ROLE bedrock_kb_user PASSWORD '<secret 裡的值>'`。密碼從 secret 讀出來直接送進 psql，不寫進 migration 檔、不進 shell history（guide 附指令） |
| 4 | 範本 | `database_user_ready = true`，要用它的 Runtime 在 `agent_runtimes[*].knowledge_bases` 列上；依序 apply `agent`（建 KB 與 data source）→ `iam-app` → `application` |

這個 secret 不由 RDS 管理，**沒有自動輪替**。換密碼時 `put-secret-value` 與 `ALTER ROLE` 要一起做，中間這段時間 ingestion 與查詢會認證失敗；KB 是每次連線都讀 secret、還是會快取，**未實測**（§7.3 第 21 項）。`agent` destroy 後 secret 會留在 7–30 天的復原期，期間重建同名 secret 會撞名。

**apply 順序**：`data`（Aurora 開 Data API，§4.31）→ `agent`（`database_user_ready = false`：secret 與語料 bucket）→ `iam-app` → **專案寫入 secret、跑 migration、設密碼**（上表第 2–3 步）→ `agent`（`database_user_ready = true`：建 KB）→ `iam-app` → `application`。KB 建立時 Bedrock 會不會檢查表、欄位與資料庫帳號，還是要到第一次 ingestion 才失敗，**未實測**（§7.3 第 21 項）；順序照「建立時就會檢查」排，比較保守。

**輸出**：`knowledge_base_id`、`knowledge_base_arn`、`data_source_ids`（`map(string)`）。

**刻意不做**：ingestion job（是執行期的動作，不是資源；文件上傳後由人或 CI 呼叫 `StartIngestionJob`，寫在 guide）；其他 7 種向量儲存（決策 38；S3 Vectors、OpenSearch Serverless 都不做，後者的向量索引 aws provider 也建不了）；`HIERARCHICAL`、`SEMANTIC` chunking 與 parsing、custom transformation；data source bucket 本身（module 不呼叫 module，§4.1；範本的 `agent` 用 `s3-bucket` 建，決策 51）；資料庫帳號與它的 secret（專案的 migration 與流程，決策 53；範本的 `agent` 建 secret 容器，決策 55）；IAM（KB role 的權限在 `iam-app`，§5.4 增補）。

### 4.31 `rds` 的 Data API 與兩個新輸出（MINOR，這一次發 `rds-v0.1.1`）

**用途**：兩件事一起發成 `rds-v0.1.1`（決策 39、52、54）。一是讓 Aurora cluster 開啟 RDS Data API（`aws_rds_cluster.enable_http_endpoint`）：Bedrock Knowledge Base 的 Aurora 向量儲存只能經 Data API 存取（§4.30），`rds` 目前沒有這個開關。二是補上 D21 記的兩個輸出 `deployment`、`database_name`，讓 `data` stack 發布 `database` JSON 時不用再從自己的 `var.db` 取這兩個值。

**介面**

```hcl
variable "data_api" {
  type        = bool
  default     = false
  description = "Enable the RDS Data API (enable_http_endpoint) on the Aurora cluster. Needed by Bedrock Knowledge Bases. Aurora only."
  validation {
    condition     = var.deployment != "rds" || !var.data_api
    error_message = "data_api needs deployment aurora or aurora_serverless; the Data API does not support RDS DB instances."
  }
}
```

- `aws_rds_cluster.this` 加 `enable_http_endpoint = var.data_api`；`aws_db_instance` 不動（它沒有這個屬性）。
- 變數名用 `data_api`，不用 `enable_http_endpoint`：AWS 的屬性名看不出它是 Data API。也不算 §4.1 禁止的 `enable_xxx` 開關：那條指的是「要不要建資源」，這是既有資源上的一個屬性，跟 `deletion_protection` 同類。
- **KB 不需要新的輸出**：KB 要的 cluster ARN 就是既有的 `arn`（Aurora 時是 cluster ARN，`modules/rds/outputs.tf`）。KB 不用 master secret（決策 53），`master_user_secret_arn` 跟 KB 無關。

**新輸出**（決策 52，D21）

```hcl
output "deployment" {
  description = "Deployment type as given: rds, aurora or aurora_serverless."
  value       = var.deployment
}

output "database_name" {
  description = "Name of the database created with the instance or cluster."
  value       = var.database_name
}
```

- 名稱照既有變數（`deployment`、`database_name`），不另取名。值直接取變數，不讀 resource 的屬性：兩者在三種型態都是原樣傳進 resource，取變數在 plan 時就是已知值，下游的 precondition 不會遇到 unknown。
- `data` stack 的 `database` JSON 改取這兩個輸出（`"deployment"`、`"name"`），JSON 的欄位與值都不變（Phase 14）。
- Data API 對 Aurora PostgreSQL 的版本要求（例如 13.12、14.9、15.4、16.1 以上）照 AWS 文件，**未查證**，不做成 validation，寫進 README 與 §7.3 第 21 項。

**版本判斷（§3.5）**：MINOR，照表應是 `rds-v0.1.0` → `rds-v0.2.0`；這一次照使用者決定發 `rds-v0.1.1`（決策 54），之後的版本照表。

| 檢查 | 結果 |
|---|---|
| 既有消費端換 `ref`、不改程式碼 | 新變數有預設值 `false`，不用改 |
| plan 會看到什麼 | `enable_http_endpoint` 在 schema 是 optional、非 computed，provider 對沒設的值當成 `false`；改成明寫 `false` 之後，既有 cluster 的 plan 應該零差異。**這是讀 schema 推論的，沒有 plan 可以證明**（本 repo 不跑 plan）；Phase 12 用「既有 5 個測試檔一行不改全部通過」加一個斷言 `enable_http_endpoint == false` 的 run 鎖住 |
| validation 有沒有收緊 | 沒有，新 validation 只作用在新變數 |
| 新輸出 | `deployment`、`database_name` 是新增的 output，不改任何資源；§3.5 的「新增 output」是 MINOR |
| 為什麼不是 PATCH | 新增能力（§3.5：新增有預設值、預設維持原行為的變數、新增 output 都是 MINOR） |

D21 裡 `rds` 的待辦（新增 `deployment` 與資料庫名稱兩個輸出）**併進這一版**（決策 52，取代原本「不併進」的寫法，§9.1 J64 附註已改）。

### 4.32 `s3-bucket` 的不過期選項（MINOR，這一次發 `s3-bucket-v0.1.1`）

**用途**：讓 bucket 可以不設過期規則，給 Knowledge Base 的語料 bucket 用（決策 51）。`s3-bucket-v0.1.0` 的 lifecycle 一律帶 `expiration`（1–3650 天），拿它放語料，文件到期會被 S3 刪掉，KB 下一次同步就跟著把向量清掉，而且整個過程不報錯。

**介面**

```hcl
variable "expiration_days" {
  type        = number
  default     = null
  description = "Days after which objects expire, 1-3650. null means 90. Must stay null when never_expire is true."

  validation {
    condition     = var.expiration_days == null ? true : (var.expiration_days >= 1 && var.expiration_days <= 3650)
    error_message = "expiration_days must be between 1 and 3650."
  }
}

variable "never_expire" {
  type        = bool
  default     = false
  nullable    = false
  description = "Keep objects until they are deleted explicitly: the lifecycle rule has no expiration. For content such as a knowledge base corpus; not for log buckets."

  validation {
    condition     = !(var.never_expire && var.expiration_days != null)
    error_message = "never_expire cannot be combined with expiration_days; leave expiration_days unset."
  }
}
```

`main.tf` 的改動：

```hcl
locals {
  expiration_days = var.never_expire ? null : coalesce(var.expiration_days, 90)
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # The id stays expire-objects for existing buckets, so switching to v0.1.1 is not a change.
    id     = var.never_expire ? "abort-incomplete-uploads" : "expire-objects"
    status = "Enabled"

    filter {}

    dynamic "expiration" {
      for_each = var.never_expire ? [] : [local.expiration_days]
      content {
        days = expiration.value
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

**設計取捨**

| 問題 | 做法 | 理由 |
|---|---|---|
| 為什麼不讓 `expiration_days = null` 直接代表不過期 | 不過期一律要明寫 `never_expire = true`；`expiration_days = null` 代表「用預設 90 天」 | 呼叫端常用 `optional(number)` 轉傳，沒給值時就是 null；如果 null 代表不過期，一個 log bucket 會在沒人注意時變成永久保存。明寫的布林值在 PR 審查看得到 |
| 為什麼 `expiration_days` 的預設從 `90` 改成 `null` | 預設 null、module 內 `coalesce` 成 90，效果不變 | 要讓「`never_expire = true` 又給了 `expiration_days`」被擋下，module 必須分得出呼叫端有沒有給天數；預設是 90 的話，給 90 跟沒給分不出來 |
| 互斥放在哪個變數 | `never_expire` 的 validation 引用 `expiration_days` | Terraform 1.9 起 validation 可以引用其他變數（本 repo `required_version >= 1.10`，`kms_key_arn` 的 validation 已經這樣用） |
| `expiration_days` 的 validation 為什麼寫成條件式 | `== null ? true : (...)` | `||` 在 `required_version` 涵蓋的所有版本是否都短路沒有查證；寫成條件式，null 時不會去比大小 |
| 不過期時 lifecycle 還留什麼 | 只留 `abort_incomplete_multipart_upload` 7 天，rule id 改成 `abort-incomplete-uploads` | 未完成的分段上傳不會變成物件，只會佔空間收錢，清掉它不影響語料；既有 bucket 的 rule id 維持 `expire-objects`，換版不會出現差異 |
| 算不算 §4.1 禁止的 `enable_xxx` | 不算 | 那條指的是「要不要建資源」，這是既有 lifecycle rule 裡的一個區塊（同 §4.31 對 `data_api` 的判斷） |

**刻意不做**：versioning（語料被誤刪救不回來；KB 的 `data_deletion_policy = "RETAIN"` 只在刪掉 data source 時保留向量，物件被刪之後的下一次同步仍會清掉對應的向量，§4.30。要不要做 versioning 是 `s3-bucket` 下一個 MINOR，等有專案需要）；event notification（上傳後自動觸發 ingestion 是應用程式的事）；允許其他 principal 寫入的 bucket policy（上傳的人或 CI 用自己的 IAM 權限，範本不給）。

**版本判斷（§3.5）**：MINOR，照表應是 `s3-bucket-v0.1.0` → `s3-bucket-v0.2.0`；這一次照使用者決定發 `s3-bucket-v0.1.1`（決策 54），之後的版本照表。

| 檢查 | 結果 |
|---|---|
| 既有消費端換 `ref`、不改程式碼 | `never_expire` 有預設值 `false`；`expiration_days` 沒給時仍是 90，給了數字時照舊 |
| plan 會看到什麼 | `never_expire = false` 時 rule id、`expiration.days`、`abort_incomplete_multipart_upload` 都跟 `v0.1.0` 相同，應該零差異；範本 `foundation` 的兩個 log bucket 明寫 `expiration_days = 90`，也不受影響。**這是讀程式推論的，沒有 plan 可以證明**；Phase 12 用「既有測試檔一行不改全部通過」鎖住 |
| validation 有沒有收緊 | 沒有。`expiration_days` 原本傳 null 會失敗，現在當成 90，是放寬；新的互斥 validation 只在新變數 `never_expire = true` 時才會擋。增補（決策 56）：`never_expire = true` 搭配非空的 `log_delivery` 也被擋（log bucket 一定要過期），同樣只影響新變數 |
| 為什麼不是 PATCH | 新增能力 |

**輸出**：不變（`bucket_name`、`arn`、`bucket_regional_domain_name`）。

## 5. 專案 infra 規範（給專案 app team）

### 5.1 資料夾結構

範本位置：`templates/project-infra/infra/`。專案 app team 把整個 `infra/` 複製到自己 repo 的根目錄。

```
infra/
├── README.md                       # stack 清單、apply 順序、SSM 合約表（每個 key 誰寫誰讀）、流量規格對照表
└── terraform/
    ├── foundation/
    ├── containerimage/
    ├── network/
    │   └── envs/
    │       ├── dev.tfvars、dev.tfbackend、prod.tfvars、prod.tfbackend
    │       └── examples/           # 流量規格範例（§5.11），不直接 apply
    │           ├── poc.tfvars
    │           ├── standard.tfvars
    │           └── high.tfvars
    ├── iam-base/
    ├── data/
    │   └── envs/examples/{poc,standard,high}.tfvars
    ├── agent/                      # 增補（決策 41）：guardrail、Runtime、Memory、Gateway、KB；預設什麼都不建
    ├── iam-app/
    ├── loadbalancer/
    │   └── envs/examples/{poc,standard,high}.tfvars
    └── application/
        ├── versions.tf             # required_version、required_providers、backend "s3" {}
        ├── providers.tf            # provider "aws"：allowed_account_ids、default_tags（含 Stack）、可選 assume_role
        ├── common.tf               # 所有 stack 一字不差：env、project、region、帳號 validation、name_prefix、ssm_prefix、common_tags
        ├── variables.tf            # 這個 stack 自己的變數
        ├── ssm-inputs.tf           # 讀上游 stack 的 SSM key（清單寫死在這裡）
        ├── ssm-outputs.tf          # module "ssm_publish"，發布給下游的 key
        ├── <resource>.tf           # 例：ecs.tf、alarms.tf；一個主題一個檔
        ├── adot-collector.yaml     # ADOT collector 設定，tracing.tf 用 file() 讀入；只有 iam-app 的 tracing 列了服務才會用到
        ├── outputs.tf              # 給人看的輸出（下游不讀 output，只讀 SSM）
        ├── tests/
        │   └── application.tftest.hcl   # mock_provider "aws" + override_data 餵 SSM 值
        ├── envs/
        │   ├── dev.tfvars          # 非機密值，進版控
        │   ├── dev.tfbackend       # bucket／key／region／use_lockfile，進版控
        │   ├── prod.tfvars
        │   ├── prod.tfbackend
        │   └── examples/{poc,standard,high}.tfvars   # log 告警與 X-Ray 抽樣的範例（§5.11）
        └── .terraform.lock.hcl     # 進版控
```

| 檔案 | 用途 | 規則 |
|---|---|---|
| `versions.tf` | `required_version = ">= 1.10"`、`aws ~> 6.0`、`backend "s3" {}` | backend 空殼，值一律從 `envs/<env>.tfbackend` 帶入 |
| `providers.tf` | provider 設定 | 每個 stack 只差 `Stack` tag 的值 |
| `common.tf` | 共通變數與 locals | **所有 stack 必須一字不差**，CI 用雜湊比對（§5.10） |
| `ssm-inputs.tf` | 上游值的唯一入口 | 讀 `insecure_value`，不讀 `value` |
| `ssm-outputs.tf` | 下游值的唯一出口 | 只能呼叫 `ssm-publish` module |
| `envs/<env>.tfvars` | 這個 stack 在這個環境的設定 | 不放任何 secret、不放其他 stack 的資源 id |
| `envs/<env>.tfbackend` | state 位置 | 一個環境一份；**客戶自管的 stack 在那個環境就不放這份檔**（§5.8） |
| `envs/examples/*.tfvars` | 流量規格範例 | 複製成 `envs/<env>.tfvars` 再改；本身不 apply，但 `validate.sh` 會拿它當測試輸入各跑一次 `terraform test`（§7.1），確保範例沒有壞掉 |

`.gitignore` 規則：忽略 `.terraform*/`、`*.tfstate*`、`crash.log`、`*.tfplan`；**不忽略** `*.tfvars` 與 `.terraform.lock.hcl`。

#### module 的 source：本 repo 內與複製出去之後

| 位置 | `source` 寫法 | 為什麼 |
|---|---|---|
| 本 repo 的 `templates/project-infra/infra/terraform/<stack>/` | 相對路徑 `../../../../../modules/<name>`（`<stack>` → `terraform` → `infra` → `project-infra` → `templates` → repo 根目錄，共 5 層） | tag 還不存在、repo 還沒上 GitHub 時，範本也能跑 `init -backend=false`、`validate`、`test`；CI 驗的是當下的 module 程式碼 |
| 專案 repo（複製出去之後） | `git::https://github.com/<org>/<repo>.git//modules/<name>?ref=<name>-v<semver>` | 釘版本；升版是一個改 `ref` 的 PR |
| 客戶 repo（FDE vendoring 之後） | 指向客戶 repo 內 vendored 目錄的相對路徑 | 客戶環境不一定連得到我們的 GitHub |

分工：

- **相對路徑 → `git::...?ref=`**：專案 app team 複製範本時手動改，一個 module 一行。改法與一次改完的指令寫在 `docs/guides/consuming-modules.md`。改完要跑 `terraform init -backend=false` 確認抓得到 tag。
- **`git::...?ref=` → vendored 相對路徑**：由 `scripts/vendor-modules.sh` 負責（§8.7）。這支腳本**只做這個方向**，不處理本 repo 範本的相對路徑；FDE 的輸入是一個已經釘好 tag 的專案 repo。

範本裡的 `git::` 範例（例如 §4.22）都是「複製出去之後」的樣子，文件出現時要標明。

### 5.2 state 拆分原則

一個 stack 一份 state。拆的依據只有兩個：

1. **擁有者**：誰有權改、誰要負責。客戶可能接手的（網路、資料庫、IAM）跟我們一定自己管的（服務）分開。
2. **變動頻率**：每週換版的東西不要跟一年動一次的 VPC 放在同一份 state，換版時 plan 才不會掃過網路、出錯時影響範圍才小。

依賴方向是單向的：上游不讀下游。apply 順序就是依賴順序。

### 5.3 預設 stack 清單

apply 順序：`foundation` → `containerimage` → `network` → `iam-base` → `data` → `iam-app` → `loadbalancer` → `application`；destroy 反序。（v1 原本的 8 個 stack；增補的 `agent` 插在 `data` 與 `iam-app` 之間，見下〈增補：`agent` stack〉。）

| 順序 | stack | 放什麼 | 用到的 module | 擁有者 | 變動頻率 | 讀（SSM，來源 stack） | 寫（SSM key） |
|---|---|---|---|---|---|---|---|
| 1 | `foundation` | 告警 SNS、專案共用 KMS key、Secrets Manager secret 容器（不含值）、flow log bucket、ALB access log bucket | `kms-key`、`sns-alarm-topic`、`s3-bucket` ×2、`ssm-publish`（另有一個原生 resource，見下） | 專案 app team；客戶自管時為客戶 | 低 | — | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| 2 | `containerimage` | 各服務的 ECR repository；**服務清單的單一決定點** | `ecr-repository`（`for_each` 服務）、`ssm-read`、`ssm-publish` | 同上 | 低（新增服務時才動） | `foundation` | `services`、`ecr_<service>_url`、`ecr_<service>_arn`、`mirrored_images`、`ecr_mirror_<name>_url`、`ecr_mirror_<name>_arn` |
| 3 | `network` | VPC（預設建立；模式 A 改登記既有）、interface endpoint、ALB／各服務／DB／Proxy 的 SG | `vpc`、`vpc-interface-endpoints`、`security-group`、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>`、`sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id`、`nat`、`interface_endpoints`、`alb_https`、`db_proxy`、`data_access` |
| 4 | `iam-base` | ECS execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | `iam-role` ×3、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | `rds`、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`network`、`iam-base` | `database`（JSON） |
| 6 | `iam-app` | Proxy role 讀 secret 的 policy、各服務 task role、ECS Exec 開關、追蹤開關（X-Ray 權限） | `iam-role-policy`、`iam-role`（`for_each` 服務）、`ssm-read`、`ssm-publish` | 同上 | 低～中（新增服務、調權限時） | `foundation`、`containerimage`、`network`、`iam-base`、`data` | `role_<service>_task_arn`、`ecs_exec_<service>`、`tracing` |
| 7 | `loadbalancer` | ALB、listener、ELB 5xx 告警、WAF 關聯 | `alb`、`ssm-read`、`ssm-publish` | 專案 app team | 低～中 | `foundation`、`network` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| 8 | `application` | ECS cluster、service、autoscaling、服務告警、dashboard、log 告警、X-Ray 抽樣、ADOT collector sidecar（照 `iam-app/tracing`） | `ecs-cluster`、`ecs-service`、`ecs-service-alarms`、`log-metric-alarm`、`xray`、`ssm-read` | 專案 app team | 高 | 前七個 | —（不需要時不發布） |

**`foundation` 的兩個 log bucket**：都用 `s3-bucket` module（§4.12）建，分成兩個是因為 bucket policy 不同。

| bucket | `s3-bucket` 的輸入 | 加密 | 其他 |
|---|---|---|---|
| flow log | `log_delivery = ["vpc_flow_logs"]` | SSE-S3（`kms_key_arn = null`） | lifecycle 90 天過期（預設值，專案依稽核需求調整） |
| ALB access log | `log_delivery = ["alb_access_logs"]` | **只能 SSE-S3**：ALB 的 log delivery 不支援 customer managed KMS，設了 log 會無聲遺失（`project-a/infra-v2/terraform/loadbalancer/access-logs.tf` 的註解）；`s3-bucket` 的 validation 會擋掉給 `kms_key_arn` 的寫法 | 同上 |

專案共用的 KMS key 用 `kms-key` module 建，`service_principals` 給 CloudWatch Logs、CloudWatch、SNS（§4.10）。

兩個 bucket 都由 `foundation` 建，即使該環境沒開 flow log 或 access log 也建（空 bucket 沒有費用），下游只靠 tfvars 的開關決定要不要用，SSM key 一律存在。

**`containerimage` 的寫法**（`ecr-repository` 用 `for_each` 對每個服務呼叫一次；下表的值是 module 的固定行為或範本給的輸入）：

| 項目 | 值 | 理由 |
|---|---|---|
| 服務清單 | `var.services`（`list(string)`），發布成 `services`（StringList） | 服務清單的單一決定點；`network`、`iam-app`、`application` 用 precondition 檢查自己的服務設定 key 跟它一致，少設定一個服務在 plan 就會停 |
| repository 名稱 | `<project>-<env>-<service>`（例如 `alpha-dev-api`） | 跟其他資源同一套命名 |
| `image_tag_mutability` | `IMMUTABLE` | 同一個 tag 不能被覆蓋，tfvars 裡的 tag 才真的對應到一個映像；搭配 `ecs-service` 拒收 `:latest` 的 validation，CI 要用 git SHA 之類不重複的值當 tag |
| `image_scanning_configuration.scan_on_push` | `true` | 推上去就掃描 |
| `force_delete` | `false` | repository 裡還有映像時 destroy 會失敗，不會連映像一起刪 |
| 加密 | KMS，用 `foundation` 發布的 `kms_key_arn` | 跟 SNS、log group 用同一把專案 CMK |
| lifecycle policy | 未加 tag 的映像 7 天後刪除；有 tag 的保留最近 50 個 | 預設值，專案依部署頻率與回退需求調整；回退要用的舊 tag 不能被清掉 |
| 外部映像副本 | `var.mirrored_images`（`set(string)`，預設空集合，沒有開關）；每個名稱建一個 repository `<project>-<env>-mirror-<name>`，設定（IMMUTABLE、掃描、KMS、lifecycle）與服務的 repository 相同，同一個 `ecr-repository` module 另一個 `for_each`（`module "ecr_mirror"`） | 沒有 NAT 的環境拉不到 ECR Public 上的映像（例如 ADOT collector），要先複製進自己的 ECR；複製動作是人或 CI 做的，不在 Terraform 裡。名稱檢查：格式同服務名稱；mirror 名稱不得等於服務名稱，`<project>-<env>-mirror-<name>` 也不得等於任何服務的 repository 名稱（服務 `mirror-adot` 與 mirror `adot` 會撞）。清單發布成 `mirrored_images`（String，JSON 陣列），不用 StringList，因為 `ssm-publish` 不收空清單而這份清單預設是空的 |

**`network` 的寫法**

`network` 預設呼叫 `vpc` module 建 VPC（模式 A 改成登記既有 VPC，見 §5.8），再呼叫 `security-group` module（§4.16）一次建 ALB、各服務、DB、Proxy 的 SG 與規則。stack 自己不寫任何 SG resource，只負責把一份服務清單在 locals 展開成 `security_groups` 與 `rules` 兩個 map 傳進 module。

`network` 在兩種模式下都呼叫 `vpc-interface-endpoints`（§4.21）：自建 VPC 時 `vpc_id`、`allowed_cidrs = [vpc_cidr]`、`subnet_ids` 來自 `vpc` 的輸出；模式 A 時來自 `existing` 與 `data "aws_vpc"`（`allowed_cidrs` 用 `data.aws_vpc.this.cidr_block_associations` 的全部 CIDR）。`subnet_tier` 必須存在而且不是 public，這條檢查從 `vpc` module 搬到 network stack 的 validation。`sg_vpce_id` 由 `vpc-interface-endpoints` 的 `security_group_id` 發布；`services` 是空集合時不發布（跟之前一樣，下游不讀這個 key）。

```hcl
variable "vpc" {
  description = "建立 VPC（預設）。與 existing 二選一。"
  type = object({
    cidr     = string
    azs      = list(string)
    subnets  = map(object({ type = string, newbits = optional(number), netnum_base = optional(number), cidrs = optional(map(string)) }))
    nat_mode = optional(string, "single")
    flow_log = optional(bool, false) # true 時送到 foundation 的 flow log bucket
  })
  default = null
}

variable "interface_endpoints" {
  description = "兩種模式都會建立。services 為空時不建任何 endpoint。"
  type = object({
    services    = optional(set(string), []) # 例：["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms"]
    subnet_tier = optional(string, "app")
  })
  default = {}
}

variable "existing" {
  description = "模式 A：登記客戶既有的 VPC。subnet_ids 的 key 必須包含 public、app、data。"
  type = object({
    vpc_id     = string
    subnet_ids = map(list(string)) # tier => 依 AZ 順序
  })
  default = null
}

variable "services" {
  description = "key 必須等於 containerimage 發布的 services。"
  type = map(object({
    port        = number
    from_alb    = optional(bool, false)        # ALB 轉進來
    callers     = optional(list(string), [])   # 哪些服務可以呼叫它
    data_access = optional(list(string), [])   # data_stores 的 key
  }))
}

variable "data_stores" {
  type = map(object({
    port  = number
    proxy = optional(bool, false) # 這裡是 Proxy 開關的單一決定點
  }))
  default = { db = { port = 5432 } }
}

variable "alb_ingress" {
  description = "誰可以連到 ALB。https = false 時不得包含 0.0.0.0/0。"
  type = object({
    https           = bool                       # 這裡是「ALB 有沒有憑證」的單一決定點
    cidrs           = optional(list(string), [])
    prefix_list_ids = optional(list(string), []) # 例：CloudFront 的 com.amazonaws.global.cloudfront.origin-facing
  })
}
```

| validation／precondition | 內容 |
|---|---|
| 二選一 | `vpc` 與 `existing` 恰好一個非 null |
| tier 名稱 | 建 VPC 時 `subnets` 必須包含 `public`、`app`、`data`；`existing.subnet_ids` 同樣 |
| 服務清單一致 | `keys(var.services)` 等於 `containerimage/services` |
| 呼叫關係 | `callers` 與 `data_access` 只能引用存在的服務與 data store |
| **沒有憑證時收窄** | `alb_ingress.https = false` 時，`cidrs` 不得包含 `0.0.0.0/0`（也不得包含 `::/0`），且 `cidrs` 與 `prefix_list_ids` 至少一個非空 |
| 至少一個來源 | `alb_ingress.https = true` 時，`cidrs` 與 `prefix_list_ids` 也至少一個非空（要開全網就明寫 `0.0.0.0/0`） |
| 模式 A 的 id 存在 | `data "aws_vpc"`、`data "aws_subnet"` 用 `for_each` 讀一次，id 不存在時 plan 失敗 |

規則表（由 locals 展開成 `security-group` 的 `rules`；module 裡一律用 `aws_vpc_security_group_ingress_rule`／`egress_rule` 搭配 `for_each`，來源用 `peer_group`（同一次呼叫裡的 SG，對應 `referenced_security_group_id`）、CIDR 或 prefix list，沒有 inline 規則）。SG 之間的每一條連線都展開成**兩條**規則：來源 SG 的 egress 加目的 SG 的 ingress。Terraform 建 SG 時會移除 AWS 預設的全部對外放行，只寫 ingress 的話來源端出不去。規則 key 是 `<來源>_out_<目的>` 與 `<目的>_in_<來源>`（SG key，例如 `api_out_db_proxy`、`db_proxy_in_api`），跟 §4.16 展開後的範例同一個做法：

| 從 | 到 | port | 條件 | 展開成 |
|---|---|---|---|---|
| `alb_ingress` 的 CIDR／prefix list | ALB SG | 443 與 80（80 只做轉址） | `https = true` | ALB SG 的 ingress，每個來源、每個 port 各一條（key `alb_in_<port>_<來源>`） |
| `alb_ingress` 的 CIDR／prefix list | ALB SG | 80 | `https = false` | 同上，只有 80 |
| ALB SG | 服務 SG | 該服務的 `port` | `from_alb = true` | ALB SG 的 egress ＋ 服務 SG 的 ingress |
| 呼叫端服務 SG | 被呼叫的服務 SG | 被呼叫端的 `port` | `callers` | 呼叫端的 egress ＋ 被呼叫端的 ingress |
| 服務 SG | `0.0.0.0/0` | 443 | 一律（經 NAT 或 VPC endpoint 呼叫 AWS API） | 服務 SG 的 egress 一條 |
| 服務 SG | Proxy SG | data store 的 `port` | `data_access` 且 `proxy = true` | 服務的 egress ＋ Proxy 的 ingress |
| 服務 SG | DB SG | data store 的 `port` | `data_access` 且 `proxy = false` | 服務的 egress ＋ DB 的 ingress |
| Proxy SG | DB SG | data store 的 `port` | `proxy = true` | Proxy 的 egress ＋ DB 的 ingress |
| `allowed_cidrs`（通常是 VPC CIDR） | VPC endpoint SG | 443 | 由 `vpc-interface-endpoints` module 建 | 不在 `rules` 裡 |

規則數等於上表展開後的數量，範本測試 `sg_rules_expand_from_services` 鎖住整個 key 集合。例：`alb_ingress = { https = true, cidrs = ["0.0.0.0/0"] }`、`api = { port = 8080, from_alb = true, data_access = ["db"] }`、`worker = { port = 9000, callers = ["api"] }`、`db` 不開 Proxy，展開成 10 條：ALB ingress 2、ALB→api 2、api→worker 2、兩個服務的 443 egress 2、api→db 2。

Proxy 的 SG 一律建立（沒有費用），`sg_db_proxy_id` 一律發布；`proxy = false` 時它沒有任何規則。ALB 的 egress 只開到各服務 SG 的服務 port，不開全網。

`network` 同時發布三個「單一決定點」的值，下游照著讀，不在下游再放一個變數：

| key | 內容 | 誰讀 | 下游怎麼用 |
|---|---|---|---|
| `alb_https` | `{"enabled":true}` | `loadbalancer` | precondition：`enabled == (var.certificate_arn != null)`，兩邊不一致就停 |
| `db_proxy` | `{"enabled":false}` | `data` | `enabled` 為 true 才把 `proxy` 物件傳進 `rds` |
| `data_access` | `{"db":["api","worker"]}` | `iam-app` | 名單上的服務，task role 才能讀 DB secret |

**觀測性 module 放在哪裡**：`log-metric-alarm` 與 `xray` 放在 `application`。告警的 log pattern、sampling rule 的 `service_name` 都跟服務綁在一起，跟服務同一個 stack 就不用跨 stack 傳名稱（跟服務告警放在 `application` 同一個理由）。範本的呼叫預設是空的：`var.log_alarms`（服務名稱 → `alarms` map）預設 `{}`、`var.xray_sampling_rules` 與 `var.xray_groups` 預設 `{}`，什麼都不建；範例值在 `application/envs/examples/`。`log-group` 範本預設不呼叫，留給專案加 Lambda 或自訂 log 時用。

**追蹤（ADOT collector 與 X-Ray）：範本已接好，預設關閉**（決策 36）。單一決定點是 `iam-app` 的 `var.tracing`（`set(string)`，預設空集合，必須是 `containerimage/services` 的子集合，用 `terraform_data` precondition 檢查），其他地方都不再放開關：

| stack | 做什麼 | 沒追蹤時 |
|---|---|---|
| `iam-app` | `tracing` 裡的服務，task role 加 `xray:PutTraceSegments`、`PutTelemetryRecords`、`GetSamplingRules`、`GetSamplingTargets` 四個動作（只支援 `Resource = "*"`）；發布 `tracing`（String，JSON 陣列，沒有時 `[]`，寫法比照 `mirrored_images`） | 沒有任何 `xray:` 動作，發布 `[]` |
| `application` | 讀 `iam-app/tracing`；被追蹤的服務加 ADOT collector sidecar（欄位逐項對照 `modules/ecs-service/examples/adot-sidecar/`：`essential = false`、`app_depends_on = "START"`、`/healthcheck`、`AOT_CONFIG_CONTENT`），主 container 加 `OTEL_EXPORTER_OTLP_ENDPOINT = http://localhost:4317` 與 `OTEL_SERVICE_NAME = <project>-<env>-<service>`（跟 `xray_sampling_rules` 的 `service_name` 同一個名稱）。collector 設定在 `application/adot-collector.yaml`，用 `file()` 讀入。映像由 `var.adot_collector = { tag, source }` 決定：`tag` 必須明確、不得 `latest`；`source = "public"` 取 ECR Public，`"mirror"` 取 `containerimage/ecr_mirror_adot_collector_url`（precondition：`containerimage/mirrored_images` 必須含 `adot-collector`）。有追蹤時 `adot_collector` 必填（precondition） | `sidecars = []`、環境變數不變，task definition 跟加這個功能之前一致；`network` 與 `containerimage` 的 mirror 都不讀（`ssm-read` 第二次呼叫的 key 清單是空的） |
| `network` | 新增發布 `interface_endpoints`（String，JSON 陣列，已排序，沒有時 `[]`） | 同左，永遠發布 |

沒有 NAT 的安全網放在 `application` 的 precondition：有服務被追蹤，而且 `network/nat` 的 `mode` 是 `none` 時，必須同時 `source = "mirror"`、`network/interface_endpoints` 含 `xray`、`ecr.api`、`ecr.dkr`。`mode = "external"`（客戶自管 VPC，模式 A）的 NAT 是客戶的責任，不擋，README 寫明；`single`、`per_az` 不檢查。S3 gateway endpoint（拉 ECR 映像的 layer 需要）：`modules/vpc` 的 `gateway_endpoints` 預設 `["s3"]`，自建 VPC 已經有；客戶自管 VPC 要自己確認，只寫在文件，不檢查。服務 SG 到 interface endpoint 不需要新規則：服務 SG 本來就有 `0.0.0.0/0` 的 443 egress，endpoint SG 對 VPC CIDR 開 443。xray 的 sampling rule 與 group 維持 `application` 的 `xray_sampling_rules`、`xray_groups`，不受追蹤開關影響。

#### 增補：`agent` stack（決策 41）

**結論**：範本新增第 9 個 stack `agent`，放 guardrail、inference profile、Memory、Runtime、Runtime 的 log 與 trace、Gateway、Knowledge Base。**預設關閉**：所有輸入預設是空的，`agent` 什麼都不建、只發布空的 JSON，其他 stack 的 plan 跟加這個功能之前一樣（比照決策 36 的追蹤）。

apply 順序（增補後）：`foundation` → `containerimage` → `network` → `iam-base` → `data` → **`agent`** → `iam-app` → `loadbalancer` → `application`；destroy 反序。上面那張 8 列的表是 v1 原本的清單，順序欄沒有重排；`agent` 這一列與既有 stack 的增補寫在下表。下表的順序欄照增補後的 9 個 stack 編號，跟範本 `infra/README.md` 一致：`foundation` 1、`containerimage` 2、`network` 3、`iam-base` 4、`data` 5、`agent` 6、`iam-app` 7、`loadbalancer` 8、`application` 9（~~原本寫成 `agent` 5a、`iam-app` 6、`application` 8~~，已被 D45 取代）。

| 順序 | stack | 放什麼（增補部分） | 用到的 module | 讀（SSM，來源 stack） | 寫（SSM key，增補部分） |
|---|---|---|---|---|---|
| 2 | `containerimage` | 每個 Runtime 一個 ECR repository；**Runtime 清單的單一決定點** `var.agent_runtimes` | `ecr-repository`（第三個 `for_each`，`module "ecr_agent"`） | 不變 | `agent_runtimes`、`ecr_agent_<rt>_url`、`ecr_agent_<rt>_arn` |
| 3 | `network` | 每個 Runtime 一個 SG（同一次 `security-group` 呼叫）；Runtime 連 DB 的規則；`interface_endpoints` 拒收 `bedrock-agentcore-control` | `security-group`（不變） | 多讀 `containerimage/agent_runtimes` | `sg_agent_<rt>_id`、`agent_data_access` |
| 4 | `iam-base` | 每個 Runtime 一個 execution role（trust、ECR 拉取、log）；KB 與 Gateway 的 service role（只有 trust） | `iam-role`（多兩個 `for_each`） | 多讀 `containerimage/agent_runtimes`、`ecr_agent_<rt>_arn` | `role_agent_<rt>_execution_arn`、`role_bedrock_kb_arn`、`role_agentcore_gateway_arn`、`agent_service_roles` |
| 5 | `data` | Aurora 可選開 Data API；`database` JSON 的 `deployment`、`name` 改取 `rds` 的新輸出（值不變，決策 52） | `rds`（`rds-v0.1.1`，§4.31） | 不變 | `database` 的 JSON 多兩個欄位（`cluster_arn`、`data_api`） |
| 6 | **`agent`（新）** | guardrail、inference profile、Memory、Runtime、Runtime 的 log group 與 vended log／trace、Gateway、KB 與它的語料 bucket、KB 資料庫帳號的 secret 容器（決策 55） | `bedrock-guardrail`、`bedrock-inference-profile`、`agentcore-memory`、`agentcore-runtime`、`log-group`、`log-delivery`、`agentcore-gateway`、`bedrock-knowledge-base`、`s3-bucket`（`s3-bucket-v0.1.1`，§4.32）、`ssm-read`、`ssm-publish` | ~~`foundation`、~~`containerimage`、`network`、`iam-base`、`data`（不讀 `foundation`：guardrail、Memory、語料 bucket 都不用專案 key，已被 D37 取代）；決策 55 起又讀 `foundation/kms_key_arn`，用來加密 KB 的 secret | 見下〈`agent` 發布的 key〉 |
| 7 | `iam-app` | Runtime execution role、KB role、Gateway role 的權限（確切 ARN；KB role 讀的是 KB 專用帳號的 secret，不是 master secret）；ECS task role 呼叫 Runtime、模型、guardrail、KB 的權限；**誰能呼叫什麼的單一決定點** `var.agent_access` | `iam-role-policy`（多兩個 `for_each`：每個 Runtime 一個、KB 與 Gateway role 共用一個）、`iam-role`（task role 多一份 inline policy `agent`） | 多讀 `containerimage/agent_runtimes`、`network/agent_data_access`、`agent` 的六個專案層 key；第二個 `ssm-read`（`in_agents`）讀每個 Runtime 的 `agent/agent_runtime_<rt>` 與 `iam-base/role_agent_<rt>_execution_arn`，有 KB 時讀 `role_bedrock_kb_arn`、Gateway 有 Lambda target 時讀 `role_agentcore_gateway_arn`（D40） | `agent_access` |
| 9 | `application` | 對 `agent_access` 有列的服務注入 Runtime ARN、模型 id、guardrail id、KB id；沒有 NAT 時的 endpoint 檢查 | 不變 | 多讀 `iam-app/agent_access`；`agent_access` 有列服務時，第二個 `ssm-read`（`in_agent`）讀 `agent/models`、`guardrails`、`knowledge_bases`、`bedrock_invoke`、`network/nat`、`interface_endpoints`，與有被引用的 `agent/agent_runtime_<rt>`（D40） | — |

`loadbalancer` 與 `foundation` 不變。stack 的擁有者是專案 app team，變動頻率「中」（換 Runtime 映像、調 guardrail 時動）。

**為什麼 `agent` 排在 `data` 之後、`iam-app` 之前**（決策 41）：Runtime 要 ECR（`containerimage`）、subnet 與 SG（`network`）、execution role（`iam-base`）、資料庫連線資訊（`data`）；KB 要資料庫已經開了 Data API、而且 migration 已經建好表。反過來，ECS task role 呼叫 Runtime、Runtime 的 execution role 呼叫 Memory 與 guardrail，這些權限要指向確切的 ARN，ARN 要等 `agent` 建好才有。這跟 RDS Proxy 是同一個兩段式（決策 20、28）：`iam-base` 先建只有基本權限的 role，`iam-app` 在 `agent` 之後用 `iam-role-policy` 附加指向確切 ARN 的權限。

這修掉 project-a 的兩個坑：

| project-a 的坑 | 為什麼是坑 | 範本怎麼做 | project-a 來源 |
|---|---|---|---|
| IAM 在 `agent` 之前 apply，所以 Runtime、Memory 用名稱前綴的萬用字元，guardrail 開到整個帳號 `guardrail/*` | 「哪個角色能用哪支 guardrail」只是約定，不是 IAM 邊界 | 兩段式 IAM，Resource 是確切 ARN | `project-a/infra-v2/terraform/iam/ssm-inputs.tf:45-59`、`project-a/docs/guide/guide-data-scientist.md:302` |
| `agent` 的 `ssm-outputs.tf` 整份註解掉，Runtime ARN 寫死在 `application` 的 tfvars | Runtime 重建後 tfvars 不改，呼叫打到舊的 Runtime 也不會報錯 | `agent` 一律發布，`application` 只從 SSM 讀 | `project-a/infra-v2/terraform/agent/ssm-outputs.tf:1-57`、`project-a/infra-v2/terraform/application/variables.tf:246`、`project-a/docs/runbook/runbook-agentcore.md:211` |

**第一次部署有 KB 時的順序**：~~`data`（`db.data_api = true`）→ 專案建 KB 帳號的 secret、跑 migration、設密碼（§4.30〈帳號的密碼〉）→ secret ARN 寫進 `agent` 的 tfvars → `agent` → `iam-app` → … 。~~ 已被決策 55 取代，`agent` 分兩段 apply：`data`（`db.data_api = true`）→ `agent`（`database_user_ready = false`：只建 secret `<project>-<env>-kb-<key>-db` 與語料 bucket）→ `iam-app`（KB role 拿到讀 secret 的權限）→ 專案 `put-secret-value`（`username = bedrock_kb_user`）、跑 migration、`ALTER ROLE` 設同一個密碼（§4.30〈帳號的密碼〉）→ `database_user_ready = true`，Runtime 列上這個 KB → `agent`（建 KB 與 data source）→ `iam-app` → `application`。沒有 KB 時不用這幾步。

**已部署環境的升級順序**（D45）：還沒有這些 key 的既有環境升到這一版時，也從 `containerimage` 開始照順序逐一 apply，不能跳過 `agent`。`iam-base`、`iam-app`、`application` 一律讀 `containerimage/agent_runtimes`、`network/agent_data_access`、`agent/*` 這些 key，上游還沒發布時 plan 會因為讀不到 SSM 參數而失敗。什麼都沒開時，這一輪只多出這些 SSM 參數，不建其他資源。範本 `infra/README.md` 寫了同樣的步驟。

##### 各 stack 的增補細節

**`containerimage`**

| 項目 | 值 | 理由 |
|---|---|---|
| Runtime 清單 | `var.agent_runtimes`（`set(string)`，預設空集合），發布成 `agent_runtimes`（String，JSON 陣列，已排序，沒有時 `[]`，寫法比照 `mirrored_images`） | Runtime 清單的單一決定點；`network`、`agent` 用 precondition 檢查自己的 Runtime 設定 key 跟它一致 |
| 名稱規則 | 同服務名稱（kebab-case）；不得等於任何服務或 mirror 名稱；`<project>-<env>-agent-<rt>` 不得等於任何服務 repository 名稱；`replace("<project>-<env>-<rt>", "-", "_")` 最多 48 字（Runtime 名稱上限，§4.26） | 名稱在 SG key、role 名稱、SSM key 裡跟服務共用同一個命名空間，撞名會互相蓋掉 |
| repository | `<project>-<env>-agent-<rt>`，設定與服務的 repository 相同（IMMUTABLE、掃描、KMS、lifecycle） | 同一個 `ecr-repository` module 的第三個 `for_each` |

**`network`**

```hcl
variable "agent_runtimes" {
  description = "key 必須等於 containerimage 發布的 agent_runtimes。預設空。"
  type = map(object({
    data_access = optional(list(string), []) # data_stores 的 key；Runtime 要直接連資料庫時才列
  }))
  default = {}
}
```

| 規則 | 內容 |
|---|---|
| SG | 每個 Runtime 一個 SG，key 是 `agent_<rt 的 - 換成 _>`，名稱 `<project>-<env>-agent-<rt>`，同一次 `security-group` 呼叫裡建；`agent_runtimes` 為空時不建（跟服務 SG 一樣，由清單決定，不是開關）。`network` 不知道 Runtime 的 `network_mode`，`PUBLIC` 的 Runtime 也有 SG 與 `sg_agent_<rt>_id`，只是 `agent` 不讀（D40） |
| 規則 | Runtime SG 對 `0.0.0.0/0` 的 443 egress 一條，規則 key `agent_<rt>_out_https`（經 NAT 或 interface endpoint 呼叫 AWS API）；增補（決策 56，`7a7593d`）：`nat.mode = "none"` 時這條改成只到 VPC CIDR（description `VPC interface endpoints`），沒有 NAT 時本來就只到得了 VPC 內的 endpoint；`mode = "none"` 只出現在範本自己建的 VPC，只有一個 CIDR。其他 mode（含客戶自管模式 A 回報的 `external`）維持 `0.0.0.0/0`；`data_access` 照服務的規則展開（有 Proxy 連 Proxy、沒有連 DB，egress ＋ ingress 兩條）。Runtime 沒有任何 ingress：呼叫 Runtime 走 AgentCore 的 API，不經過 SG |
| 不做 | Runtime 連 ECS 服務的規則（J60） |
| 發布 | `sg_agent_<rt>_id`；`agent_data_access`（String，JSON，`{"db":["assistant"]}`，只列至少有一個 Runtime 的 data store，沒有時 `{}`）。不併進既有的 `data_access`：那個 key 的名單是服務，`iam-app` 拿它對服務清單，混進 Runtime 名稱會讓既有的檢查失效 |
| validation | `keys(var.agent_runtimes)` 等於 `containerimage/agent_runtimes`（實作是 `guards.tf` 的 precondition，跟服務清單同一種寫法）；`data_access` 只能引用存在的 data store；SG key `agent_<rt>` 不得跟服務的 SG key 撞名（D40）；`interface_endpoints.services` 不得含 `bedrock-agentcore-control`（project-a 的規格明訂 VPC 內不得建控制面 endpoint，`project-a/docs/spec/agentcore-bedrock-integration.md:49`） |

Runtime 的 subnet 用哪個 tier 由 `agent` 決定（見下），`network` 已經發布每個 tier 的 `subnet_ids_<tier>`，不用新增 key。

**`iam-base`**：Runtime 清單讀 `containerimage/agent_runtimes`，`ecr_agent_<rt>_arn` 用 `module "in_agents"` 第二次讀（同 §5.6 每個服務一組的 key 的寫法）。KB 與 Gateway 的 role 要不要建，由 `iam-base` 自己的 `var.agent_service_roles` 決定（J55），`agent` 用 precondition 檢查。

```hcl
variable "agent_service_roles" {
  description = "要建立的 AgentCore／Bedrock 服務角色（只有 trust）。預設空。"
  type        = set(string)   # knowledge_base | gateway
  default     = []
}
```

| role | 名稱 | trust | 在 `iam-base` 的權限 | 在 `iam-app` 附加的權限 |
|---|---|---|---|---|
| Runtime execution（每個 Runtime 一個） | `<project>-<env>-agent-<rt>` | `bedrock-agentcore.amazonaws.com`，`aws:SourceAccount`；決策 56 起加 `aws:SourceArn = arn:aws:bedrock-agentcore:<region>:<account>:*` | 一份 inline policy `pull-and-log`：ECR 拉取限該 Runtime 的 repository；`ecr:GetAuthorizationToken`（`*`，既有例外）；~~`logs:CreateLogGroup`、`CreateLogStream`、`PutLogEvents`、`DescribeLogStreams` 限 `/aws/bedrock-agentcore/runtimes/<runtime 名稱>-*`~~ 已被 D40 取代：`logs:CreateLogGroup`、`DescribeLogStreams` 限 log group `/aws/bedrock-agentcore/runtimes/<runtime 名稱>-*`，`logs:CreateLogStream`、`PutLogEvents` 限同一個樣式的 `:log-stream:*`；`<runtime 名稱>` 是 `<project>_<env>_<rt>` | 見 §5.4 增補 |
| KB service role | `<project>-<env>-bedrock-kb` | `bedrock.amazonaws.com`，`aws:SourceAccount`；決策 56 起加 `aws:SourceArn = arn:aws:bedrock:<region>:<account>:knowledge-base/*` | 無 | 見 §5.4 增補 |
| Gateway role | `<project>-<env>-agentcore-gateway` | `bedrock-agentcore.amazonaws.com`，`aws:SourceAccount`；決策 56 起加 `aws:SourceArn = arn:aws:bedrock-agentcore:<region>:<account>:*` | 無 | 見 §5.4 增補 |

~~trust 只用 `aws:SourceAccount`：`iam-role` 目前不支援 `aws:SourceArn`（`modules/iam-role/variables.tf`），加這個能力是 `iam-role` 的 MINOR，這次不做（決策 47）。~~ 已被決策 56 取代：`iam-role-v0.1.1` 支援 `trust.source_arn`，三種服務角色都加上 `aws:SourceArn`（`c6bb164`）。條件用帳號與 region 的萬用字元，不需要等 `agent` 建好的確切 ARN，所以 stack 順序不變。這兩種 ARN 形狀**沒有用真的 AssumeRole 驗證過**（§7.3）；寫錯的症狀是 Runtime、KB、Gateway 建立或執行時拿不到 role。

發布 `role_agent_<rt>_execution_arn`；`role_bedrock_kb_arn`、`role_agentcore_gateway_arn` 只有在 `agent_service_roles` 含對應值時才存在；`agent_service_roles` 一律發布（String，JSON 陣列，已排序，沒有時 `[]`）。

**`data`**：`var.db` 新增 `data_api = optional(bool, false)`，傳給 `rds` 的 `data_api`（§4.31）。`database` JSON 既有的 `deployment`、`name` 改取 `module.db[0].deployment`、`module.db[0].database_name`（決策 52），值跟原本取 `var.db` 時相同，發布的參數不變。`database` 的 JSON 新增兩個欄位，照 §5.6「新增欄位是相容的」：

| 欄位 | 值 | 誰讀 |
|---|---|---|
| `cluster_arn` | `rds` 的 `arn`（Aurora 是 cluster ARN）；`deployment = "rds"` 時是 `null` | `agent`（KB 的 `aurora.cluster_arn`）、`iam-app`（KB role 的 Data API 權限） |
| `data_api` | `true`／`false` | `agent` 的 precondition |

**`agent`（新）**

輸入（tfvars 只放這個 stack 自己的設定；其他 stack 的 id 一律從 SSM 讀）：

```hcl
variable "agent_runtimes" {
  description = "key 必須等於 containerimage 發布的 agent_runtimes。預設空。"
  type = map(object({
    image_tag    = string                                  # 不得 latest
    network_mode = optional(string, "VPC")                 # VPC | PUBLIC（PUBLIC 要明寫，決策 42）
    subnet_tier  = optional(string, "app")                 # network 發布的 tier，不得是 public
    protocol     = optional(string, "HTTP")
    session_lifecycle = optional(object({
      idle_session_timeout = optional(number, 900)
      max_lifetime         = optional(number, 28800)
    }), {})
    models          = optional(list(string), [])           # var.models 的 key
    memories        = optional(list(string), [])           # var.memories 的 key
    guardrails      = optional(list(string), [])           # var.guardrails 的 key
    knowledge_bases = optional(list(string), [])           # var.knowledge_bases 的 key
    gateway         = optional(bool, false)                # 可以呼叫 var.agentcore_gateway
    tracing         = optional(bool, false)                # Runtime 追蹤的單一決定點（J56）
    workload_identity = optional(bool, false)              # 決策 56：AgentCore Identity 的單一決定點；true 時 iam-app 才給 GetWorkloadAccessToken*（未實測）
    environment     = optional(map(string), {})            # 專案自己的環境變數，不得跟範本產生的撞名；名稱像 secret 的會被 agentcore-runtime 擋（決策 56）
    log_retention_days = optional(number, 30)
  }))
  default = {}
}

variable "models" {
  description = "模型清單的單一決定點。key 是專案內的代號。"
  type = map(object({
    foundation_model_id      = string                      # 例：anthropic.claude-sonnet-4-5-20250929-v1:0
    inference_profile_prefix = optional(string)            # 例：apac、global；null = 直接用 foundation model（on-demand）
    tracked                  = optional(bool, false)       # true = 建 application inference profile，成本可依 tag 歸屬
  }))
  default = {}
}

variable "guardrails" {
  description = "每個 key 一支 guardrail，傳給 bedrock-guardrail（§4.24）。tier 預設 STANDARD。"
  type        = map(any) # 實作寫成與 bedrock-guardrail 輸入相同欄位的 object（agent/variables.tf），這裡省略
  default     = {}
}

variable "memories" {
  type = map(object({
    event_expiry_days = optional(number, 90)               # 7–365（agentcore-memory 的範圍，D33）
    strategies = optional(map(object({                     # key 是 strategy 名稱：字母開頭、只有字母數字底線（D33）
      type       = string
      namespaces = list(string)
    })), {})
  }))
  default = {}
}

variable "knowledge_bases" {
  type = map(object({
    embedding_model        = string                        # var.models 的 key，必須是 foundation model（沒有 prefix、不 tracked）
    embedding_dimensions   = number
    # credentials_secret_arn 已被決策 55 移除：secret 由 agent 自己建（<project>-<env>-kb-<key>-db），不再從 tfvars 收
    database_user_ready    = optional(bool, false)         # 決策 55：false 只建 secret 與語料 bucket；secret 有值、資料庫帳號設好同一個密碼之後才改 true，下一次 apply 建 KB
    table_name             = optional(string, "bedrock_integration.bedrock_kb")
    field_mapping = optional(object({                      # D37：實作是五個欄位的 object，不是 map(string)；預設同 bedrock-knowledge-base
      primary_key_field     = optional(string, "id")
      vector_field          = optional(string, "embedding")
      text_field            = optional(string, "chunks")
      metadata_field        = optional(string, "metadata")
      custom_metadata_field = optional(string)
    }), {})
    data_sources = map(object({                            # 都在這個 KB 的語料 bucket 裡（決策 51），只用 prefix 區分；key 是 data source 名稱，規則同 KB 名稱（D36）
      inclusion_prefixes = optional(set(string), [])
    }))
  }))
  default = {}
}

variable "agentcore_gateway" {
  description = "null = 不建 Gateway。target 只收 lambda 與 mcp_server（決策 40）。"
  type = object({
    targets = map(object({                                 # key 是 target 名稱：英數與單一 -（D34）
      type               = string
      lambda_arn         = optional(string)
      tool_schema_s3_uri = optional(string)
      endpoint           = optional(string)
    }))
  })
  default = null
}

variable "bedrock_invoke" {
  description = "跨帳號呼叫模型（只做 A 側，決策 44）。null = 同帳號。"
  type = object({
    role_arn        = string                               # B 帳號裡、由 B 帳號擁有者建立的 role
    session_seconds = optional(number, 3600)               # >= 900；0 不是「不限」
  })
  default = null
}
```

增補（D37）：上面多數的交叉檢查實作成變數 validation，不是 `terraform_data` precondition，錯誤在 plan 最前面就出現，而且測試的 `expect_failures` 指向變數。實作另外加了幾條：`models`、`guardrails`、`knowledge_bases` 的 key 必須是 kebab-case（它們會變成 `MODEL_ID_<KEY>` 這類環境變數與 bucket 名稱的一部分）；`memories` 的 key 是 kebab-case，而且 `<project>_<env>_<key>` 不超過 48 字；`foundation_model_id` 不得帶地區前綴（`^[a-z0-9-]+\.[A-Za-z0-9._:-]+$`）；`inference_profile_prefix` 只能是小寫字母；`memories` 的 `event_expiry_days` 必須是 7–365 的整數；`image_tag` 不得是 `latest`；`network_mode` 只收 `VPC`、`PUBLIC`。

`agent` 建什麼：

| 東西 | module | 名稱 | 條件 |
|---|---|---|---|
| guardrail | `bedrock-guardrail`（`for_each = var.guardrails`） | `<project>-<env>-<key>` | `guardrails` 非空 |
| application inference profile | `bedrock-inference-profile`（一次呼叫） | `<project>-<env>-<key>` | `models` 裡有 `tracked = true` 的；`copy_from` 在沒有 prefix 時是本 region 的 foundation model（`arn:aws:bedrock:<region>::foundation-model/<id>`），有 prefix 時是 system inference profile 的 ARN（D38） |
| Memory | `agentcore-memory`（`for_each = var.memories`） | `<project>_<env>_<key>`（`-` 換 `_`） | `memories` 非空 |
| Runtime | `agentcore-runtime`（`for_each = var.agent_runtimes`） | `<project>_<env>_<rt>` | `agent_runtimes` 非空 |
| Runtime 的 application log group | `log-group`（`for_each`） | `/agentcore/<project>-<env>-<rt>` | 每個 Runtime 一個；保留天數是 `log_retention_days`，不加密（不傳 `kms_key_arn`） |
| vended log 與 trace | `log-delivery`（`module "runtime_logs"`，有 Runtime 時一次呼叫） | source 與 delivery 是 `<project>-<env>-<rt>-logs`、`-traces`；destination 是 `<project>-<env>-<rt>`（CWL）與 `<project>-<env>-xray_traces`（D38） | 每個 Runtime：`APPLICATION_LOGS` → 上面的 log group；`tracing = true` 時另加 `TRACES` → `XRAY` |
| Gateway | `agentcore-gateway`（`for_each`，0 或 1 個，key 是 `this`） | `<project>-<env>-gateway` | `agentcore_gateway != null`；authorizer 固定 `AWS_IAM`（J58） |
| KB 資料庫帳號的 secret（決策 55） | 原生 `aws_secretsmanager_secret.kb_db`（`for_each = var.knowledge_bases`；S8 例外，見〈stack 裡的原生資源〉） | `<project>-<env>-kb-<key>-db` | 每個 KB 一個，不論 `database_user_ready`；`kms_key_id` 是 `foundation/kms_key_arn`；**不建 secret version**，值由專案寫入，不進 tfvars、SSM 與 state |
| KB 的語料 bucket | `s3-bucket`（`for_each = var.knowledge_bases`） | `<project>-<env>-kb-<key>-<account_id>`（同 `foundation` 的 log bucket 帶帳號 id，避免全域撞名） | 每個 KB 一個；`never_expire = true`、`kms_key_arn = null`（SSE-S3）、`log_delivery = []`、`force_destroy = false`（決策 51、J68） |
| KB | `bedrock-knowledge-base`（`for_each`，資料庫條件不成立時是空的，讓 precondition 成為唯一報出來的錯誤；決策 55 起 `database_user_ready = false` 的 KB 也不在裡面） | `<project>-<env>-<key>` | `knowledge_bases` 非空而且該 KB `database_user_ready = true`；每個 `data_sources` 的 `bucket_arn` 都是同一個 KB 的語料 bucket，`bucket_owner_account_id` 是 `var.expected_account_id`（決策 56）；`aurora.credentials_secret_arn` ~~是 `knowledge_bases[*].credentials_secret_arn`~~ 是上面那個 secret 的 ARN（決策 55）；`embedding_model_arn` 是本 region 的 foundation model ARN（`arn:aws:bedrock:<region>::foundation-model/<id>`，IAM 那側仍是 region `*`，D38） |

KMS：guardrail 與 Memory 的 `kms_key_arn` 範本先傳 `null`（AWS 管的 key），不用 `foundation` 的專案 key：那把 key 的 `service_principals` 要給 Bedrock 與 AgentCore 什麼條件，沒有實測（J59、§7.3 第 22 項）。

**Runtime 的環境變數由 `agent` 組，不收其他 stack 的 id**（修掉 project-a 把 Runtime ARN 寫在 tfvars 的坑）：

| 環境變數 | 值 | 條件 |
|---|---|---|
| `AWS_REGION` | `var.aws_region` | 一律 |
| `TRACELOOP_TRACE_CONTENT` | `"false"`，訊息內容不進 trace（決策 49） | 一律；`environment` 可以明寫 `"true"` 覆蓋，這是唯一能被覆蓋的範本變數 |
| `MODEL_ID_<KEY>` | `models` 的呼叫用 id（見下 `models`） | Runtime 的 `models` 有列 |
| `MEMORY_ID_<KEY>` | Memory id | Runtime 的 `memories` 有列 |
| `GUARDRAIL_ID_<KEY>`、`GUARDRAIL_VERSION` | guardrail id；版本固定 `DRAFT`（決策 46） | Runtime 的 `guardrails` 有列 |
| `KNOWLEDGE_BASE_ID_<KEY>` | KB id | Runtime 的 `knowledge_bases` 有列 |
| `AGENTCORE_GATEWAY_URL` | Gateway URL | `gateway = true` |
| `DB_HOST`、`DB_READER_HOST`、`DB_PORT`、`DB_NAME`、`DB_SECRET_ARN` | `data/database` 的 `app_endpoint` 等五個欄位，跟 ECS 服務同一組名稱（§4.22） | `database.enabled = true`，而且 Runtime 在 `network/agent_data_access` 的 `db` 名單上（範本的資料庫 data store key 是 `db`，D40） |
| `BEDROCK_INVOKE_ROLE_ARN`、`BEDROCK_INVOKE_SESSION_SECONDS` | `var.bedrock_invoke` | `bedrock_invoke != null` 且 Runtime 有列 `models` |
| `OTEL_*` | ~~照 `project-a/infra-v2/terraform/agent/runtime.tf:9-19` 的 OTEL 設定（exporter `otlp`、`http/protobuf`、traces endpoint 是 X-Ray 的 OTLP endpoint）~~ 已被 D38 取代，固定六個：`OTEL_SERVICE_NAME = <project>-<env>-<rt>`、`OTEL_TRACES_EXPORTER = otlp`、`OTEL_EXPORTER_OTLP_PROTOCOL = http/protobuf`、`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = https://xray.<region>.amazonaws.com/v1/traces`、`OTEL_METRICS_EXPORTER = none`、`OTEL_LOGS_EXPORTER = none` | `tracing = true` |

`<KEY>` 是 key 轉大寫、`-` 換 `_`。專案自己的 `environment` 不得使用上表的名稱（~~precondition~~ 實作是 `agent_runtimes` 的變數 validation，D37；`TRACELOOP_TRACE_CONTENT` 除外）。另外 `agentcore-runtime-v0.1.1` 擋名稱像 secret 的變數（決策 56，§4.23）；範本自己產生的 `DB_SECRET_ARN` 名稱以 `_ARN` 結尾、值是 ARN，照樣通過。擋的是固定名稱 `AWS_REGION`、`GUARDRAIL_VERSION`、`AGENTCORE_GATEWAY_URL`、五個 `DB_*`、兩個 `BEDROCK_INVOKE_*`，加上前綴 `MODEL_ID_`、`MEMORY_ID_`、`GUARDRAIL_ID_`、`KNOWLEDGE_BASE_ID_`、`OTEL_`（整個 `OTEL_` 前綴都保留給範本，不只上面六個）。

**`models` 的 `invoke_arns` 由一個 local 統一組**（決策 50）。只有這個 local 會產生模型的 IAM Resource，`iam-app` 照讀，不自己拼：

| 模型設定 | 呼叫用 id（`model_id`） | `invoke_arns` |
|---|---|---|
| 沒有 prefix | `<foundation_model_id>` | `arn:aws:bedrock:*::foundation-model/<foundation_model_id>` |
| 有 prefix | `<prefix>.<foundation_model_id>` | `arn:aws:bedrock:<region>:<account>:inference-profile/<prefix>.<foundation_model_id>`、`arn:aws:bedrock:*::foundation-model/<foundation_model_id>`；prefix 是 `global` 時再加 `arn:aws:bedrock:::foundation-model/<foundation_model_id>`（region 與帳號都空白） |
| `tracked = true` | application inference profile 的 ARN | 上一列（或第一列）再加 application inference profile 的 ARN |

foundation-model 那條的 region 一律是 `*`：system inference profile 會把請求路由到其他 region，`global.` 前綴還會對空 region 的 ARN 授權；寫死 region 會間歇失敗（`project-a/docs/runbook/runbook-cross-account-bedrock.md` 第 4 節的實測）。`global` 另加空 region 那一條是保守做法：`*` 能不能涵蓋空 region，project-a 只在跨帳號的 B 側間接看到，自己的批次評分角色仍保留這一條並註明未實測（`project-a/infra-v2/terraform/iam/judge-batch-role.tf:71-78`）。§7.3 第 23 項實測後可以拿掉，拿掉是範本的變更，不影響 module。

**precondition**（`terraform_data`，跟既有 stack 的 guard 同一種寫法）。增補（D37）：下表標「validation」的幾列實作成變數 validation；`guards.tf` 只放要讀 SSM 才判斷得了的那幾條：Runtime 清單一致、PUBLIC 模式、服務角色、KB 的資料庫、~~KB 不等於 master secret~~（決策 55 刪除）、沒有 NAT 的兩條

| 名稱 | 內容 |
|---|---|
| Runtime 清單一致 | `keys(var.agent_runtimes)` 等於 `containerimage/agent_runtimes` |
| 參照存在（validation） | 每個 Runtime 的 `models`、`memories`、`guardrails`、`knowledge_bases` 都是存在的 key；`gateway = true` 時 `agentcore_gateway != null`；KB 的 `embedding_model` 是沒有 prefix、沒有 tracked 的模型；決策 55 起 Runtime 的 `knowledge_bases` 只能列 `database_user_ready = true` 的 KB（KB 還沒建，`KNOWLEDGE_BASE_ID_<KEY>` 會是空的；測試 `runtime_with_knowledge_base_not_ready_rejected`） |
| `subnet_tier`（validation） | ~~存在於 `network` 發布的 tier，而且不是 `public`~~ 已被 D37 取代：validation 只檢查格式（`^[a-z][a-z0-9_]*$`）與不是 `public`；tier 存不存在，由第二個 `ssm-read` 讀 `network/subnet_ids_<tier>` 時讀不到而讓 plan 失敗（只讀 VPC 模式 Runtime 用到的 tier） |
| PUBLIC 模式 | `network_mode = "PUBLIC"` 的 Runtime 不得在 `network/agent_data_access` 上（PUBLIC 的 Runtime 不在 VPC 裡，連不到 isolated 的資料庫） |
| 服務角色 | `knowledge_bases` 非空時 `iam-base/agent_service_roles` 含 `knowledge_base`；`agentcore_gateway != null` 時含 `gateway` |
| KB 的資料庫 | `knowledge_bases` 非空時 `data/database` 是 `enabled = true`、`deployment != "rds"`、`data_api = true` |
| ~~KB 不用 master secret~~ 已被決策 55 取代 | 決策 55 起 `credentials_secret_arn` 這個輸入不存在，KB 用的一定是 `agent` 自己建的 secret（測試 `kb_uses_the_secret_it_created`），這條 validation 與 precondition 都刪掉了。以下是原本的內容：每個 KB 的 `credentials_secret_arn` 是單一 secret 的完整 ARN：`^arn:aws:secretsmanager:<region>:<account>:secret:[A-Za-z0-9/_+=.@!-]+-[A-Za-z0-9]{6}$`，region 等於 `var.aws_region`、帳號等於本帳號、以 6 字元後綴結尾、不得有 `*` 或 `?`（這些是 validation，D43；`!` 允許是因為 RDS 管理的 secret 名稱是 `rds!...`），而且**不等於 `data/database` 的 `secret_arn`**（precondition，決策 53）。只擋得到「把 master secret 的 ARN 原樣填進來」，secret 裡放的是不是 master 帳號的帳密，Terraform 看不到 |
| 語料 bucket 名稱（validation） | `<project>-<env>-kb-<key>-<account_id>` 不超過 63 字（`s3-bucket` 的 validation 也會擋，這條讓錯誤訊息指到 KB 的 key） |
| 跨帳號（validation） | `bedrock_invoke != null` 時 `role_arn` 是 IAM role ARN、不是本帳號、`session_seconds >= 900`；而且不得有 `tracked = true` 的模型（application inference profile 建在本帳號，B 帳號用不到）~~、KB 不得引用模型（KB 用本帳號的 KB role 呼叫嵌入模型）~~。刪除線那句已被 D37 取代：實作照 J66，`bedrock_invoke` 啟用時 KB 照常用本帳號的 KB role 呼叫本帳號的嵌入模型，不擋 |
| **沒有 NAT** | 有 `network_mode = "VPC"` 的 Runtime，而且 `network/nat` 的 `mode == "none"` 時，`network/interface_endpoints` 必須含 `bedrock-runtime`、`bedrock-agentcore`（決策 42）；另外依條件要求：`bedrock_invoke != null` 要 `sts`、有 VPC 模式的 Runtime `tracing = true` 要 `xray`、有 VPC 模式的 Runtime 列了 `knowledge_bases` 要 `bedrock-agent-runtime`、有 VPC 模式的 Runtime 在 `network/agent_data_access` 的 `db` 名單上要 `secretsmanager`（它用 execution role 讀 `DB_SECRET_ARN`；推論，**未實測**，D44）、有 Runtime 列了 `guardrails` 要 `bedrock-runtime`（已涵蓋）。`PUBLIC` 的 Runtime 不計入（D37）。`mode = "external"` 不檢查（客戶的責任，比照決策 36） |
| 沒有 NAT 時不准 Gateway | `nat.mode == "none"` 而且有 VPC 模式的 Runtime `gateway = true` 時擋下：Runtime 經 VPC 呼叫 Gateway 要哪個 endpoint 服務名稱，沒有查證（J57、§7.3 第 20 項） |

**`agent` 發布的 key**（全部是 String；沒有東西時也發布，值是空的 JSON）

| key | 內容 | 誰讀 |
|---|---|---|
| `agent_runtime_<rt>` | JSON：`{"arn":…,"id":…,"name":…,"execution_role_arn":…,"models":[…],"memories":[…],"guardrails":[…],"knowledge_bases":[…],"gateway":false,"tracing":false,"workload_identity":false}`，清單是 key（`workload_identity` 是決策 56 新增的欄位，`iam-app` 讀不到時當成 `false`）；key 名稱的 `<rt>` 是 Runtime 名稱的 `-` 換成 `_` | `iam-app`（execution role 的權限）、`application`（Runtime ARN） |
| `models` | JSON：`{"<key>":{"model_id":…,"invoke_arns":[…]}}`，沒有時 `{}`；**模型清單的單一決定點** | `iam-app`、`application` |
| `guardrails` | JSON：`{"<key>":{"id":…,"arn":…,"version":"DRAFT","profile_id":…}}`；`CLASSIC` 時 `profile_id` 是 `null` | `iam-app`、`application` |
| `agent_memories` | JSON：`{"<key>":{"id":…,"arn":…}}` | `iam-app` |
| `knowledge_bases` | JSON：`{"<key>":{"ready":…,"id":…,"arn":…,"embedding_model":"<models 的 key>","bucket_name":…,"bucket_arn":…,"inclusion_prefixes":{"<data source key>":[…]},"data_source_ids":{"<data source key>":"<data source id>"},"credentials_secret_arn":…}}`；tfvars 裡的每個 KB 都有一筆（決策 55）：`database_user_ready = false` 時 `ready = false`、`id` 與 `arn` 是 `null`、`data_source_ids` 是 `{}`；`bucket_*` 是 `agent` 建的語料 bucket（決策 51），`inclusion_prefixes` 每個 data source 一個已排序的清單（沒給 prefix 時是 `[]`），`data_source_ids` 給跑 `StartIngestionJob` 的人或 CI 查 data source id（D39），`credentials_secret_arn` ~~照 tfvars（決策 53）~~ 是 `agent` 建的 secret 的 ARN（決策 55），不是值 | `iam-app`（KB role 的 S3 與 secret 權限）、`application`；`data_source_ids` 沒有 stack 讀 |
| `agentcore_gateway` | `{"enabled":false}` 或 `{"enabled":true,"arn":…,"url":…,"lambda_arns":[…],"tool_schema_arns":[…]}`；`tool_schema_arns` 是 Lambda target 的 `tool_schema_s3_uri` 轉成的 S3 物件 ARN（`s3://<bucket>/<key>` → `arn:aws:s3:::<bucket>/<key>`，已排序，沒有時 `[]`，D42） | `iam-app` |
| `bedrock_invoke` | `{"enabled":false}` 或 `{"enabled":true,"role_arn":…,"session_seconds":3600}`；**跨帳號的單一決定點**（決策 44） | `iam-app`、`application` |

`ssm-publish` 的 String 上限是 4096 字（Standard tier）。每個 Runtime 一個 key 就是為了這個上限；`models` 一個模型約 300 字，十個以內放得下，超過時 `ssm-publish` 的 validation 在 plan 就會擋（J61）。

**`iam-app`**：見 §5.4 增補。新增 `var.agent_access`（**ECS 服務能呼叫什麼的單一決定點**）：

```hcl
variable "agent_access" {
  description = "服務 => 它可以呼叫的 AgentCore／Bedrock 資源（agent 發布的 key）。沒列的服務沒有任何 bedrock 權限。"
  type = map(object({
    runtimes        = optional(list(string), [])
    models          = optional(list(string), [])
    guardrails      = optional(list(string), [])
    knowledge_bases = optional(list(string), [])
  }))
  default = {}
}
```

precondition：key 是 `containerimage/services` 的子集合；每個清單的值都是 `agent` 發布的 key；決策 55 起 `knowledge_bases` 只能列 `ready = true` 的 KB（`ready = false` 的 id 與 ARN 是 `null`，服務會拿到 null 的 Resource 與空的 `KNOWLEDGE_BASE_ID`；`8b840ea`，測試 `agent_access_rejects_knowledge_base_not_ready`）。發布 `agent_access`（String，JSON，內容就是這個變數，沒有時 `{}`）。

**`application`**：讀 `iam-app/agent_access`；有列的服務，主 container 加環境變數 `AGENTCORE_RUNTIME_ARN_<RT>`、`MODEL_ID_<KEY>`、`GUARDRAIL_ID_<KEY>` 與 `GUARDRAIL_VERSION`、`KNOWLEDGE_BASE_ID_<KEY>`；`bedrock_invoke` 啟用且服務有列 `models` 時加 `BEDROCK_INVOKE_ROLE_ARN`、`BEDROCK_INVOKE_SESSION_SECONDS`。`agent_access` 是空的時，第二個 `ssm-read`（`module "in_agent"`）的 key 清單是空的，task definition 跟加這個功能之前一樣（迴歸要求，比照決策 36）。有列服務時它讀 `agent/models`、`guardrails`、`knowledge_bases`、`bedrock_invoke`、`network/nat`、`interface_endpoints`，以及至少被一個服務列到的 `agent/agent_runtime_<rt>`；`GUARDRAIL_VERSION` 只在服務列了 guardrail 時加（D40）。沒有 NAT 時的 precondition：有服務列了 `runtimes` 要 `bedrock-agentcore`、列了 `models` 或 `guardrails` 要 `bedrock-runtime`、列了 `knowledge_bases` 要 `bedrock-agent-runtime`、`bedrock_invoke` 啟用要 `sts`。

**interface endpoint 對照**（`network` 的 `interface_endpoints.services`，nat = `none` 時由上面的 precondition 強制）

| 服務 | 誰需要 | 依據 |
|---|---|---|
| `bedrock-runtime` | 呼叫模型（`InvokeModel`／`Converse`）、`ApplyGuardrail` | `project-a/infra-v2/terraform/network/vpc-endpoints.tf:2`；`ApplyGuardrail` 走這個 endpoint 是依 SDK 的 client 分類，**未實測**（project-a ADR-0016 也列為未查證） |
| `bedrock-agentcore` | ECS 服務 `InvokeAgentRuntime`、Runtime 讀寫 Memory | `project-a/infra-v2/terraform/network/vpc-endpoints.tf:2`、`project-a/docs/spec/agentcore-bedrock-integration.md` |
| `bedrock-agent-runtime` | 查 KB（`Retrieve`） | 照 AWS 文件，**未實測** |
| `secretsmanager` | VPC 模式、在 `agent_data_access` 的 `db` 名單上的 Runtime 讀 DB secret（D44） | 推論：沒有 NAT 時 Secrets Manager 公網端點連不到，**未實測** |
| `sts` | 跨帳號 assume role | 推論：沒有 NAT 時 STS 公網端點連不到，**未實測** |
| `xray` | Runtime 用 OTEL 直送 X-Ray | 推論，**未實測** |
| `bedrock` | 控制面（`ListGuardrails` 這類）；範本直接注入 guardrail id，不需要 | project-a 有建，範本不要求 |
| **不得建** `bedrock-agentcore-control` | — | `project-a/docs/spec/agentcore-bedrock-integration.md:49`；`network` validation 擋 |

Runtime 拉映像是 AgentCore 服務端做的、還是經由 VPC 裡的 ENI，**未實測**；schema 的 `require_service_s3_endpoint` 是 computed，暗示服務需要 S3 gateway endpoint（自建 VPC 時 `vpc` 預設已有 `s3`）。AgentCore 的 VPC 模式是否限定特定 AZ ID、每個 Runtime 用掉多少 ENI，也**未查證**（§7.3 第 17 項）。

**PUBLIC 模式的取捨**（決策 42）：Runtime 不在 VPC 裡，對外連線不經過 SG 與 interface endpoint，也連不到 isolated tier 的資料庫；好處是不佔 subnet 的 IP、不需要 NAT 或 endpoint。範本只在 `network_mode = "PUBLIC"` 明寫時才用，precondition 擋掉它跟 `agent_data_access` 同時出現。

**跨帳號（A 側）**（決策 44）：專案帳號（A）的 Runtime 與服務 assume B 帳號的 role 呼叫模型。範本只做 A 側：`bedrock_invoke` 是唯一的設定點，`iam-app` 照讀，把列了 `models` 的 Runtime 與服務的 `bedrock:InvokeModel*` 換成 `sts:AssumeRole`（Resource 恰為那個 role），`agent` 與 `application` 注入環境變數。B 側的 role、它的 trust（信任 A 帳號的哪些 role）、B 帳號的模型使用權，由 B 帳號擁有者處理，寫在 guide（`project-a/docs/runbook/runbook-cross-account-bedrock.md:9-11,78-85`）。project-a 把同一個設定放在兩個 stack（`project-a/docs/runbook/runbook-cross-account-bedrock.md:87-100`），這裡收成一個。

**範本會怎麼串**（`agent` 的主要呼叫，`source` 寫成複製出去之後的樣子，同 §4.22 的慣例）：

```hcl
module "runtime" {
  source   = "git::.../modules/agentcore-runtime?ref=agentcore-runtime-v0.1.1"
  for_each = var.agent_runtimes

  name          = replace("${local.name_prefix}-${each.key}", "-", "_")
  role_arn      = module.in_agents.strings["role_agent_${local.agent_key[each.key]}_execution_arn"]
  container_uri = "${module.in_agents.strings["ecr_agent_${local.agent_key[each.key]}_url"]}:${each.value.image_tag}"

  network = each.value.network_mode == "PUBLIC" ? { mode = "PUBLIC" } : {
    mode               = "VPC"
    subnet_ids         = module.in_tiers.lists["subnet_ids_${each.value.subnet_tier}"]
    security_group_ids = [module.in_agents.strings["sg_agent_${local.agent_key[each.key]}_id"]]
  }

  session_lifecycle     = each.value.session_lifecycle
  protocol              = each.value.protocol
  environment_variables = local.runtime_environment[each.key] # 上表，由本 stack 組
}

module "agent_logs" {
  source      = "git::.../modules/log-delivery?ref=log-delivery-v0.1.1"
  name_prefix = local.name_prefix
  sources     = local.delivery_sources      # 每個 Runtime 的 APPLICATION_LOGS；tracing 的再加 TRACES
  destinations = merge(
    { for rt, lg in module.runtime_log_group : rt => { type = "CWL", resource_arn = lg.arn } },
    local.any_tracing ? { xray_traces = { type = "XRAY" } } : {}, # Runtime keys are kebab-case, so no clash
  )
  deliveries = local.deliveries
}
```

增補（D38）：實作的 log delivery 是 `module "runtime_logs"`（`count`，有 Runtime 才呼叫），source、destination、delivery 的 key 都放在 `local.log_delivery` 一個 local；`network` 在 `PUBLIC` 時傳 `{ mode = "PUBLIC", subnet_ids = [], security_group_ids = [] }`。其他照上面的寫法。

#### stack 裡的原生資源（例外清單）

範本的 stack 原則上只呼叫 module。下表是唯一允許的原生 resource（SG 已改由 `security-group` module 建，不在清單上），`scripts/validate.sh` 依這張表檢查（§5.6 S8）；要加新的例外，先改這張表並寫理由。

| stack | 原生 resource | 理由 | 之後怎麼收 |
|---|---|---|---|
| `foundation` | `aws_secretsmanager_secret`（應用程式 secret 的容器，不含值） | 只有一個 resource、兩三個屬性，包成 module 省不到東西（已拍板，§9.2 決策 30） | 有輪替、跨帳號 policy 這類需求時再做 `secret` module，這一列刪掉 |
| `agent` | `aws_secretsmanager_secret`（每個 KB 一個資料庫帳號的 secret 容器 `<project>-<env>-kb-<key>-db`，專案 key 加密，不含值） | 同上一列的理由；容器由範本建，名稱、KMS key、`iam-app` 的 Resource 一定對得上（§9.2 決策 55）。`validate.sh` 的 `s8_allowed` 多 `agent:aws_secretsmanager_secret` | 同上一列 |

不算原生 resource、可以留在 stack 的：`data "aws_caller_identity"`、`data "aws_region"`、模式 A 的 `data "aws_vpc"`／`data "aws_subnet"`、`terraform_data` 這類不碰 AWS 的資源。`data "aws_ssm_parameter"` 不行，只能在 `ssm-read` 裡（§5.6 S3）。

**跟 project-a 的對照**（`project-a/docs/spec/infra.md`〈infra-v2 的 stack 之間怎麼傳值〉）：

| project-a stack | 範本 | 說明 |
|---|---|---|
| `foundation` | `foundation` | 加上兩個 log bucket |
| `containerimage` | `containerimage` | 加上服務清單 |
| `network` | `network` | 改用 `vpc` module；SG 規則由服務清單展開 |
| `database` | `data` | 改用 `rds` module；ElastiCache 不在第一版 |
| `iam` | `iam-base`、`iam-app` | 拆成兩個，讓 Proxy 的 role 能在資料庫建立前存在、讀 secret 的權限在資料庫建立後附加（§5.4） |
| `bridge` | 刪除 | 只有一棵 SSM 樹，不需要轉寫 |
| `loadbalancer` | `loadbalancer` | 改用 `alb` module；target group 改由 `ecs-service` 建 |
| `agent`、`operation` | 不在範本（增補：`agent` 收進範本，決策 41） | project-a 特有（AgentCore、Lambda、跳板機），專案自己加 stack。增補之後 `agent` 由範本提供，`operation` 仍不在範本 |
| `application` | `application` | 加上 autoscaling 與告警 |
| `postdeploy` | 刪除 | autoscaling 收進 `ecs-service`、服務告警收進 `application`、ALB 與資料庫告警收進 `alb`、`rds` module |

### 5.4 `iam-base` 與 `iam-app` 的寫法

**只有 `iam-role` 與 `iam-role-policy` 兩個 module 建 IAM**（已拍板，§9.2）。範本的 stack 也不直接寫 `aws_iam_*`，一律呼叫這兩個 module；其他 17 個 module 都不建 IAM，只收 ARN。IAM 集中在兩個 stack，原因：權限審查只要看兩個地方；客戶自管 IAM 時只要接這兩個 stack，而且在客戶的部署 role 不能改 IAM 的環境（例如 project-a prod b2c 的 deploy role 明確 Deny `iam:Put*`），module 自建 role 根本 apply 不過。

拆成兩個是因為依賴方向：RDS Proxy 建立時要給 role ARN（role 要在 `data` 之前存在），但 role 讀 secret 的權限要指到 master secret 的 ARN（secret 要等 `data` 建好才有）。

| stack | 時間點 | 建什麼 | 用哪個 module |
|---|---|---|---|
| `iam-base` | `data` 之前 | ECS execution role、RDS Proxy role（**只有 trust，沒有 policy**）、Enhanced Monitoring role | `iam-role` ×3 |
| `iam-app` | `data` 之後 | 對 Proxy role 附加讀 secret 的 policy；各服務的 task role；ECS Exec 開關 | `iam-role-policy`、`iam-role`（`for_each` 服務） |

**policy 一律用 `jsonencode()` 產生字串**，傳進 `iam-role` 的 `inline_policies` 或 `iam-role-policy` 的 `policies`。不用 `data "aws_iam_policy_document"`：mock provider 會把它的 `json` 填成隨機字串，測試就斷言不到 policy 內容。

#### `iam-base`

- **execution role**（一個專案一個）：
  - ECR 拉映像限定 `containerimage` 發布的 `ecr_<service>_arn` 與 `ecr_mirror_<name>_arn`（mirror 清單讀 `mirrored_images`，用 `module "in_mirrors"` 第二次讀；沒有 mirror 時 Resource 與原來完全相同）（`ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`、`ecr:BatchCheckLayerAvailability`）；`ecr:GetAuthorizationToken` 只支援 `Resource = "*"`，是例外並寫註解。
  - `logs:CreateLogStream`、`logs:PutLogEvents` 限定 `arn:aws:logs:<region>:<account>:log-group:/ecs/<name_prefix>-*:*`。log group 在 `application` 才建，所以用命名規則限定，這要求 log group 名稱照 `ecs-service` 的預設（`/ecs/<name>`）。
  - `secretsmanager:GetSecretValue` 限定 `foundation` 發布的 `app_secret_arn`；`kms:Decrypt` 限定 `foundation` 的 key。
  - **沒有 DB secret 的權限**（DB secret 由 task role 讀，§8.2）。
- **RDS Proxy role**：`iam-role` 只給 `trust`（`rds.amazonaws.com`，`source_account` 設本帳號），`inline_policies = {}`。
- **Enhanced Monitoring role**：trust `monitoring.rds.amazonaws.com`；inline policy 只給 `logs:CreateLogGroup`、`logs:PutRetentionPolicy`、`logs:CreateLogStream`、`logs:PutLogEvents`、`logs:DescribeLogStreams`、`logs:GetLogEvents`，Resource 限定 `RDSOSMetrics` log group 與其 log stream。project-a 掛的是 AWS managed policy `AmazonRDSEnhancedMonitoringRole`（`project-a/infra-v2/terraform/database/rds.tf`），這裡改成等價的 inline policy；**是否足夠未驗證**（§7.3）。
- 發布 `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn`。

**`data`** 從 SSM 讀 `role_rds_proxy_arn` 與 `role_rds_monitoring_arn`，傳進 `rds` 的 `proxy.role_arn` 與 `monitoring.role_arn`。

#### `iam-app`

- **Proxy role 的 policy**（`iam-role-policy`）：`role_arn` 是 `iam-base/role_rds_proxy_arn`；policy 是 `secretsmanager:GetSecretValue`，**Resource 恰為 `data/database` 的 `secret_arn`**；master secret 用 CMK 加密時（範本用 `foundation` 的 `kms_key_arn`），另加 `kms:Decrypt`，Resource 為該 key，條件 `kms:ViaService = secretsmanager.<region>.amazonaws.com`。project-a 的 `kms:Decrypt` 是 `Resource = "*"`（`project-a/infra-v2/terraform/database/rds-proxy.tf`），範本收窄到單一 key。`database` 是 `{"enabled":false}` 時不呼叫。不管 Proxy 有沒有開都附加（Proxy role 一定存在），這樣之後打開 Proxy 不用再跑 `iam-app`。
- **task role**（一個服務一個，服務清單讀 `containerimage/services`，`iam-role` 加 `for_each`）：預設沒有任何權限。
  - `network/data_access` 名單上的服務加 `secretsmanager:GetSecretValue`（Resource 恰為 DB secret ARN）與上述 `kms:Decrypt`。應用程式用 `DB_SECRET_ARN` 自己讀 secret（project-a 的做法），理由見 §8.2。
  - **ECS Exec**：`var.ecs_exec_services`（`list(string)`，預設 `[]`）裡的服務加 `ssmmessages:CreateControlChannel` 等 4 個 action（只支援 `Resource = "*"`，是另一個例外），同時對每個服務發布 `ecs_exec_<service>`，值是 `{"enabled":true}` 或 `{"enabled":false}`。`application` 讀同一個 key 傳給 `ecs-service` 的 `enable_execute_command`，自己沒有這個變數。
  - **追蹤**：`var.tracing`（`set(string)`，預設 `[]`，必須是 `containerimage/services` 的子集合）裡的服務加上面的 4 個 `xray:` action（`Resource = "*"`，第三個例外），沒列的服務一個 `xray:` 動作都沒有。`application` 讀同一份發布值決定要不要掛 collector，自己沒有開關。
- 發布 `role_<service>_task_arn`、`ecs_exec_<service>`、`tracing`。

#### Proxy 建立時的權限：未驗證

建立 RDS Proxy 時，如果它的 role 還沒有讀 secret 的權限，AWS 是讓建立失敗，還是建立成功、等 `iam-app` apply 之後才能連線，**目前沒有實測**，列在 §7.3。兩種結果的對策：

| 實測結果 | 對策 |
|---|---|
| 建立成功，`iam-app` apply 之後才連得上 | 照正常順序 apply。第一次部署時，`data` apply 完到 `iam-app` apply 完之間 Proxy 連不上，這段時間應用程式還沒部署，沒有影響 |
| 建立失敗 | 第一次部署先在 `network` 設 `data_stores.db.proxy = false`，照順序跑到 `iam-app`；再改成 `true`，依序 apply `network`、`data`。`iam-app` 的 policy 在第一輪就已經附加到 Proxy role 上，所以第二輪不用再跑 `iam-app`。這個兩段式步驟要寫進 `infra/README.md` |

#### 最小權限的測試分兩層

| 層 | 測試放哪裡 | 鎖住什麼 |
|---|---|---|
| module | `modules/iam-role/tests/`、`modules/iam-role-policy/tests/` | Allow statement 沒有 `*` 或 `service:*` 動作（validation 加 `expect_failures`）；沒有 managed policy；`iam-role` 的 trust 只給服務主體、`source_account` 有給時帶 `aws:SourceAccount` |
| 範本 | `iam-base/tests/`、`iam-app/tests/`（`mock_provider "aws"`，`ssm-read` 的 data source 用 `override_data`） | 見下表 |

| stack | run | 斷言 |
|---|---|---|
| 兩者 | `Resource = "*"` 只出現在允許清單 | 只有 `ecr:GetAuthorizationToken`、ECS Exec 的 4 個 `ssmmessages` action，以及專案開了追蹤時的 X-Ray 動作（`xray:PutTraceSegments`、`PutTelemetryRecords`、`GetSamplingRules`、`GetSamplingTargets`，§4.20）可以搭配 `*`；用反向驗證證明這條測得到（暫時加一個 `s3:GetObject` on `*`，測試要紅） |
| `iam-base` | trust 各自正確 | execution role 只信任 `ecs-tasks.amazonaws.com`、Proxy role 只信任 `rds.amazonaws.com`、monitoring role 只信任 `monitoring.rds.amazonaws.com` |
| `iam-base` | Proxy role 只有 trust | Proxy role 的 `inline_policies` 是空的 |
| `iam-base` | execution role 沒有 DB secret 權限 | execution role 的 policy 裡沒有任何指向 DB secret 的 Resource |
| `iam-base` | monitoring 只到 `RDSOSMetrics` | Resource 全部是 `RDSOSMetrics` 的 log group／stream |
| `iam-app` | Proxy 只讀那一個 secret | `iam-role-policy` 的 `role_arn` 等於 `role_rds_proxy_arn`；`secretsmanager:GetSecretValue` 的 Resource 恰為 `override_data` 餵進來的 `secret_arn`；`kms:Decrypt` 帶 `kms:ViaService` |
| `iam-app` | 只有 `data_access` 名單上的服務能讀 DB secret | 不在名單上的服務，task role 沒有 `secretsmanager` 權限 |
| `iam-app` | 沒有 DB 時不附加 | `database = {"enabled":false}` 時沒有 `iam-role-policy` 呼叫，任何 task role 都沒有 secret 權限 |
| `iam-app` | ECS Exec 一致 | `ecs_exec_services` 裡的服務有 `ssmmessages` 權限，且發布 `{"enabled":true}`；其他服務兩者都沒有 |
| `iam-app` | 追蹤一致 | `tracing` 裡的服務恰好有 4 個 `xray:` 動作且發布的 JSON 陣列含它；沒列的服務沒有任何 `xray:` 動作；預設發布 `[]`；`tracing` 含 `containerimage/services` 以外的名稱時 plan 失敗 |

#### 增補：AgentCore 與 Bedrock 的權限（決策 41、50）

同一個兩段式：`iam-base` 在 `agent` 之前建 role（Runtime execution role 只有 ECR 拉取與 log，KB 與 Gateway role 只有 trust，見 §5.3 增補），`iam-app` 在 `agent` 之後用 `iam-role-policy` 附加指向確切 ARN 的權限。Resource 一律從 `agent` 發布的 JSON 取，`iam-app` 不自己拼 ARN（`models.invoke_arns` 由 `agent` 的一個 local 組，決策 50）。

**Runtime execution role**（每個 Runtime 一個 `iam-role-policy` 呼叫，`role_arn` 是 `iam-base/role_agent_<rt>_execution_arn`，權限照 `agent/agent_runtime_<rt>` 的清單，policy 名稱 `agent`；~~下表一條都不適用的 Runtime 不呼叫，因為 `iam-role-policy` 不收空的 `policies`，D40~~ 決策 56 起每個 Runtime 至少有「metrics」那一條，所以每個 Runtime 都有這份 policy）

| statement | 動作 | Resource | 條件 |
|---|---|---|---|
| 模型 | `bedrock:InvokeModel`、`bedrock:InvokeModelWithResponseStream`（`Converse` 與 `ConverseStream` 用的也是這兩個動作） | Runtime 列的 `models` 的 `invoke_arns` 聯集 | Runtime 有列 `models`，且 `bedrock_invoke` 沒有啟用 |
| 跨帳號 | `sts:AssumeRole` | 恰為 `bedrock_invoke.role_arn` | Runtime 有列 `models`，且 `bedrock_invoke` 啟用（取代上一列） |
| Memory | `bedrock-agentcore:CreateEvent`、`ListEvents`、`GetEvent`、`RetrieveMemoryRecords` | 列的 Memory 的 ARN | 有列 `memories`；動作照 `project-a/infra-v2/terraform/iam/agentcore-role.tf:126-134` |
| guardrail | `bedrock:ApplyGuardrail` | 列的 guardrail 的 ARN，加上 `arn:aws:bedrock:*:<account>:guardrail-profile/<profile_id>`（`STANDARD` 的才有） | 有列 `guardrails` |
| KB | `bedrock:Retrieve`、`bedrock:RetrieveAndGenerate` | 列的 KB 的 ARN | 有列 `knowledge_bases`；`RetrieveAndGenerate` 還會呼叫模型，模型權限照上面「模型」那列另外給（**未實測**） |
| Gateway | `bedrock-agentcore:InvokeGateway` | Gateway ARN | `gateway = true` |
| DB secret | `secretsmanager:GetSecretValue`；`kms:Decrypt` 帶 `kms:ViaService` | 恰為 `database.secret_arn`；專案 key | `database.enabled = true`，而且 Runtime 在 `network/agent_data_access` 的 `db` 名單上；寫法同 task role（§5.4），共用同一組 statement |
| 追蹤 | `xray:PutTraceSegments`、`xray:PutTelemetryRecords`、`xray:PutSpans` | `*`（X-Ray 不支援 resource-level） | `tracing = true`；動作照 `project-a/infra-v2/terraform/iam/agentcore-role.tf`（`sid = "XRay"`） |
| metrics（決策 56） | `cloudwatch:PutMetricData`（`Sid = "PutAgentCoreMetrics"`） | `*`（`PutMetricData` 不支援 resource-level），條件 `StringEquals cloudwatch:namespace = bedrock-agentcore` | 一律（每個 Runtime） |
| workload identity（決策 56） | `bedrock-agentcore:GetWorkloadAccessToken`、`GetWorkloadAccessTokenForJWT`、`GetWorkloadAccessTokenForUserId`（`Sid = "GetWorkloadAccessTokens"`） | `arn:aws:bedrock-agentcore:<region>:<account>:workload-identity-directory/default` 與 `.../default/workload-identity/*` | `agent_runtimes[*].workload_identity = true`；舊的 `agent_runtime_<rt>` JSON 沒有這個欄位時當成 `false`。動作、Resource 與「Runtime 需不需要」都**未實測** |

**guardrail profile 的 ARN**：region 一律 `*`，profile id 一律是確切值、不得是 `*`。`STANDARD` 的 `ApplyGuardrail` 另外對 guardrail profile 授權，而 region 由 AWS 動態選（project-a 實際看到 `ap-south-1`），寫死 region 會變成間歇失敗（`project-a/docs/guide/guide-data-scientist.md:294-300`、`project-a/infra-v2/terraform/iam/ssm-inputs.tf:56-59`，決策 50）。

**KB service role**（`agent_service_roles` 含 `knowledge_base` 時，一個 `iam-role-policy` 呼叫涵蓋所有 KB）

| statement | 動作 | Resource |
|---|---|---|
| 嵌入模型 | `bedrock:InvokeModel` | 各 KB 的 `embedding_model` 的 `invoke_arns` |
| Data API | `rds-data:ExecuteStatement`、`rds-data:BatchExecuteStatement` | 恰為 `database.cluster_arn` |
| cluster 描述 | `rds:DescribeDBClusters` | 恰為 `database.cluster_arn` |
| KB 帳號的 secret | `secretsmanager:GetSecretValue`；`kms:Decrypt` 帶 `kms:ViaService = secretsmanager.<region>.amazonaws.com`，決策 56 起再加 `kms:EncryptionContext:SecretARN` 等於這些 secret 的 ARN（KB role 只能為自己的 secret 解密，`0641431`） | 恰為各 KB 的 `credentials_secret_arn`（`agent/knowledge_bases`；決策 55 起是 `agent` 建的 secret，`ready = false` 的 KB 也有，所以 KB 建立之前 KB role 就讀得到）；`foundation` 的專案 key（同 master secret 的寫法，J69）。**沒有** `database.secret_arn`（決策 53）。`iam-app` 的 `terraform_data.knowledge_base_secrets_are_exact` 在授權這一端用同一條 regex 重新檢查 `agent/knowledge_bases` 發布的 ARN（D43）：萬用字元的 ARN 會讓 KB role 讀得到 master secret |
| 文件來源 | `s3:ListBucket`（帶 `s3:prefix` 條件，只有給了 `inclusion_prefixes` 時）、`s3:GetObject`；決策 56 起兩條都帶 `aws:ResourceAccount = <本帳號>`（S3 ARN 不帶帳號，別的帳號搶到同名 bucket 也會比對成功） | 各 KB 的語料 bucket（`agent/knowledge_bases` 的 `bucket_arn`）、`<bucket ARN>/<prefix>*`（沒給 prefix 時是 `<bucket ARN>/*`）。增補（D40）：每個 KB 各一條 `ListBucket` 與一條 `GetObject`；`s3:prefix` 條件是 `StringLike`，值為 `<prefix>*`；同一個 KB 只要有一個 data source 沒給 prefix，那個 KB 就整個 bucket 都讀得到（prefix 條件與 `<prefix>*` 都拿掉），因為那個 data source 本來就會讀整個 bucket |

動作清單照 AWS 文件〈Create a service role for Knowledge Bases〉，**未實測**是否足夠（§7.3 第 21 項）。語料 bucket 由範本建、用 SSE-S3（決策 51、J68），KB role 讀物件不需要 KMS 權限。

所有 KB 共用一個 KB role，所以 KB role 讀得到每一個 KB 的 secret。各 KB 的資料庫帳號在資料庫裡只對自己的表有權限，但這個隔離在資料庫層，不在 IAM 層；要讓 KB 之間在 IAM 上也分開，得改成每個 KB 一個 role，第一版不做（J70）。

**Gateway role**（`agent_service_roles` 含 `gateway` 時，policy 名稱 `lambda-targets`；KB role 的 policy 名稱是 `knowledge-bases`）：`lambda:InvokeFunction`，Resource 是 Lambda target 的 ARN 與 `<arn>:*`（版本與別名，照 `project-b/infra/terraform/modules/agentcore/gateway.tf:34-50`）。沒有 Lambda target 時不附加（`iam-role-policy` 不收空的 `policies`）。增補（D42）：同一份 policy 另有 `Sid = "ReadToolSchemas"` 的 `s3:GetObject`，Resource 恰為 `agent/agentcore_gateway` 的 `tool_schema_arns`，只有不是空的時才加（決策 56 起帶 `aws:ResourceAccount = <本帳號>`）；在這之前 Gateway role 讀不到放在 S3 的工具定義，用 `tool_schema_s3_uri` 的 Lambda target 建不起來。

**ECS task role**（`agent_access` 有列的服務，加在既有 task role 的 inline policy 裡）

| statement | 動作 | Resource |
|---|---|---|
| Runtime | `bedrock-agentcore:InvokeAgentRuntime` | 列的 Runtime 的 ARN 與 `<ARN>/runtime-endpoint/*` |
| 模型 | 同 Runtime execution role 的「模型」或「跨帳號」那列 | 同左 |
| guardrail | 同 Runtime execution role | 同左 |
| KB | `bedrock:Retrieve` | 列的 KB 的 ARN |

沒列在 `agent_access` 的服務一個 `bedrock` 或 `bedrock-agentcore` 動作都沒有。project-a 的 task role 還有 `bedrock:ListGuardrails`（`Resource = "*"`，`project-a/infra-v2/terraform/iam/ecs-roles.tf:124-126`），因為程式用名稱查 guardrail；範本直接注入 guardrail id 與版本，不需要，所以 **`Resource = "*"` 的允許清單不因為 guardrail 而變長**。

**`Resource = "*"` 允許清單的變化**：只多一個動作 `xray:PutSpans`，而且只出現在 `tracing = true` 的 Runtime execution role 上（J56）。增補（決策 56）：再多 `cloudwatch:PutMetricData`，每個 Runtime execution role 都有，而且一定帶 `cloudwatch:namespace = bedrock-agentcore` 條件。§5.4〈最小權限的測試分兩層〉那張表的「兩者」那一列，Phase 14 照這個改；反向驗證：暫時給沒開追蹤的 Runtime 加 `xray:PutSpans`、或給任何 role 加 `bedrock:ListGuardrails` on `*`，測試要紅。

**Runtime 建立時的權限：未驗證**。`agent` apply 時，Runtime 的 execution role 只有 trust、ECR 拉取與 log，還沒有模型、Memory、guardrail 的權限。我們的推論是 `CreateAgentRuntime` 只檢查 role 能不能被 assume、映像拉不拉得到（這兩樣 `iam-base` 都已經給了），其餘權限在 invoke 時才評估；**這沒有實測**，project-a 的 IAM 一直是在 `agent` 之前用萬用字元給齊的，沒有反例也沒有正例（§7.3 第 16 項）。這也是 ECR 與 log 放在 `iam-base` 而不是 `iam-app` 的原因。如果實測證明建立時就要模型或 Memory 的權限，Proxy 那種「先關掉再打開」的兩輪 apply 在這裡行不通（Runtime 的權限清單要等 `agent` 發布才讀得到），要回頭改設計，屆時再找使用者決定。

**範本測試要鎖住的**（Phase 14，`iam-base/tests/`、`iam-app/tests/`）

| stack | run | 斷言 |
|---|---|---|
| `iam-base` | Runtime execution role 的 trust | 只信任 `bedrock-agentcore.amazonaws.com`，帶 `aws:SourceAccount`；決策 56 起另帶 `aws:SourceArn`，region 跟著 `aws_region`（`agent_role_source_arn_follows_region`） |
| `iam-base` | Runtime 只拉自己的映像 | ECR 拉取的 Resource 恰為 `ecr_agent_<rt>_arn` |
| `iam-base` | KB、Gateway role 只有 trust | `inline_policies` 是空的；`agent_service_roles = []` 時兩個 role 都不存在 |
| `iam-app` | KB role 不讀 master secret | KB role 的 `secretsmanager:GetSecretValue` 的 Resource 恰為 `override_data` 餵進來的各 KB `credentials_secret_arn`，**不含** `database.secret_arn`；`kms:Decrypt` 帶 `kms:ViaService`。反向驗證：暫時把 `database.secret_arn` 加進 Resource，測試要紅（決策 53） |
| `iam-app` | KB role 只讀自己的語料 bucket | S3 的 Resource 恰為 `agent/knowledge_bases` 的 `bucket_arn` 與它的 prefix，沒有其他 bucket |
| `iam-app` | Resource 恰為確切 ARN | 模型、Memory、guardrail、KB、Gateway、Runtime 的 Resource 都等於 `override_data` 餵進來的 ARN，沒有任何萬用字元（`*` 只出現在 `arn:aws:bedrock:*:` 與 `arn:aws:bedrock:*::foundation-model/` 的 region 欄） |
| `iam-app` | guardrail profile | Resource 含 `arn:aws:bedrock:*:<account>:guardrail-profile/<id>`，`<id>` 不是 `*`；`CLASSIC` 的 guardrail 沒有 profile 那條 |
| `iam-app` | 跨帳號 | `bedrock_invoke` 啟用時有 `sts:AssumeRole`、沒有 `bedrock:InvokeModel`；沒啟用時相反 |
| `iam-app` | 沒列的服務沒有權限 | `agent_access` 沒列的服務，task role 沒有任何 `bedrock*` 動作 |
| `iam-app` | 預設不變 | `agent_runtime_*` 不存在、`agent_access = {}` 時，既有 task role 的 policy 跟加這個功能之前完全相同 |
| 兩者 | `Resource = "*"` 允許清單 | 見上〈允許清單的變化〉 |

### 5.5 state 的 bucket 與 key

| 項目 | 規則 | 例 |
|---|---|---|
| bucket | 放 state 的帳號一個 bucket，不在專案 stack 裡建（由 platform team 或帳號開通時建好）；開 versioning、SSE、Block Public Access。名稱是佔位符（§9.3 待補資訊） | `<state-bucket>` |
| key | `<project>-<env>/<stack>/terraform.tfstate` | `alpha-dev/application/terraform.tfstate` |
| lock | `use_lockfile = true`（S3 原生 lock，不用 DynamoDB） | — |
| 加密 | `encrypt = true` | — |

`envs/dev.tfbackend` 範例：

```hcl
bucket       = "<state-bucket>"
key          = "alpha-dev/application/terraform.tfstate"
region       = "ap-northeast-1"
encrypt      = true
use_lockfile = true
```

project-a 踩過的坑：uat 與 prod 的 state 在同一個 bucket，只靠 key 前綴分開，key 寫錯會讀到別的環境（`project-a/infra-v2/terraform/application/envs/uat.tfbackend` 的註解）。範本的 `scripts/validate.sh` 會靜態檢查每份 `envs/<env>.tfbackend` 的 `key` 是不是剛好等於 `<project>-<env>/<stack>/terraform.tfstate`（`<stack>` 取目錄名、`<env>` 取檔名）。

### 5.6 SSM 合約

| 規則 | 內容 |
|---|---|
| 路徑 | `/<project>/<env>/<stack>/<key>`；只有一棵樹 |
| key 命名 | snake_case；ARN 結尾 `_arn`、id 結尾 `_id`、清單用複數或 `_ids`；服務名稱裡的 `-` 轉成 `_`（服務 `order-api` 的 SG key 是 `sg_order_api_id`） |
| 型別 | 純量用 `String`；清單用 `StringList`（逗號串接，元素不得含逗號）；多欄位或條件值用 `String` 裝 JSON |
| 條件值 | SSM 不收空字串，可有可無的值一律包 JSON：`{"enabled":false}`／`{"enabled":true,...}`，讀取端 `jsondecode()` |
| 單一決定點 | 兩個 stack 都要知道的開關，只由上游一個 stack 決定並發布，下游讀，不在兩邊各放一個變數。例：`network/alb_https`、`network/db_proxy`、`network/data_access`、`containerimage/services`、`containerimage/mirrored_images`、`iam-app/ecs_exec_<service>`、`iam-app/tracing`。增補：`containerimage/agent_runtimes`（Runtime 清單）、`network/agent_data_access`、`iam-base/agent_service_roles`、`data/database` 的 `data_api`、`agent/models`（模型清單）、`agent/bedrock_invoke`（跨帳號）、`agent/agent_runtime_<rt>` 的 `tracing`、`iam-app/agent_access`（服務能呼叫什麼） |
| secret | **不進 SSM**。SSM 只放 secret 的 ARN，值在 Secrets Manager |
| 寫入 | 只能透過 `ssm-publish`；其他地方不得宣告 `aws_ssm_parameter` |
| 讀取 | 只能透過 `ssm-read`（裡面是 `data "aws_ssm_parameter"` 加 `for_each`、只讀 `insecure_value`）；key 清單寫在 `ssm-inputs.tf` 的 module 呼叫裡 |
| 方向 | 只能讀 apply 順序更早的 stack 發布的 key |

**合約表**（範本 `infra/README.md` 放同一張表，客戶自管時照這張表發布）

| stack | key | 型別 | 內容 |
|---|---|---|---|
| `foundation` | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn` | String | ARN |
| `foundation` | `alb_log_bucket_name` | String | bucket 名稱（ALB 的 `access_logs.bucket` 收名稱，不收 ARN） |
| `containerimage` | `services` | StringList | 服務名稱 |
| `containerimage` | `ecr_<service>_url`、`ecr_<service>_arn` | String | — |
| `containerimage` | `mirrored_images` | String（JSON 陣列） | mirror 名稱，沒有時 `[]` |
| `containerimage` | `ecr_mirror_<name>_url`、`ecr_mirror_<name>_arn` | String | 外部映像副本的 repository，只有設了 `mirrored_images` 才存在 |
| `network` | `vpc_id`、`vpc_cidr` | String | — |
| `network` | `azs` | StringList | AZ 順序，所有 `subnet_*` 清單都照這個順序 |
| `network` | `subnet_ids_public`、`subnet_ids_app`、`subnet_ids_data` | StringList | 依 AZ 排序。新增其他 tier 時多發布 `subnet_ids_<tier>`，只有需要它的 stack 才去讀 |
| `network` | `subnet_cidrs_<tier>` | StringList | 同上 |
| `network` | `sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id` | String | `sg_vpce_id` 來自 `vpc-interface-endpoints` 的 `security_group_id`；沒有 interface endpoint 時不發布 |
| `network` | `nat` | String（JSON） | `{"mode":"per_az","ids":["nat-...","nat-..."]}`；`none` 時 `ids` 為 `[]`；客戶自管模式 A（登記既有 VPC）時是 `{"mode":"external","ids":[]}`，客戶 VPC 的 NAT 不由我們回報 |
| `network` | `interface_endpoints` | String（JSON 陣列） | 已建的 interface endpoint 服務名稱（已排序），沒有時 `[]`；`application` 在追蹤且沒有 NAT 時檢查它 |
| `network` | `alb_https`、`db_proxy` | String（JSON） | `{"enabled":true}` |
| `network` | `data_access` | String（JSON） | `{"db":["api"]}` |
| `iam-base` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` | String | — |
| `data` | `database` | String（JSON） | 見下 |
| `iam-app` | `role_<service>_task_arn` | String | — |
| `iam-app` | `ecs_exec_<service>` | String（JSON） | `{"enabled":false}` |
| `iam-app` | `tracing` | String（JSON 陣列） | 要追蹤的服務名稱（已排序），沒有時 `[]`；`application` 照它掛 collector sidecar |
| `loadbalancer` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` | String | `listener_arn` 有憑證時是 HTTPS listener，否則是 HTTP；`listener_protocol` 是 `HTTPS` 或 `HTTP` |
| `containerimage` | `agent_runtimes` | String（JSON 陣列） | 增補（決策 41）。Runtime 名稱，已排序，沒有時 `[]`；Runtime 清單的單一決定點 |
| `containerimage` | `ecr_agent_<rt>_url`、`ecr_agent_<rt>_arn` | String | 增補。Runtime 的 repository，只有設了 `agent_runtimes` 才存在 |
| `network` | `sg_agent_<rt>_id` | String | 增補。Runtime 的 SG；每個 Runtime 都發布，`PUBLIC` 的也是（`agent` 只讀 VPC 模式的）。`<rt>` 是 Runtime 名稱的 `-` 換成 `_`，本表其他 `<rt>` 同 |
| `network` | `agent_data_access` | String（JSON） | 增補。`{"db":["assistant"]}`，只列至少有一個 Runtime 的 data store，Runtime 名稱已排序，沒有時 `{}`；哪些 Runtime 有連 data store 的 SG 規則；`db` 名單上的 Runtime 才拿得到 `DB_*` 環境變數與讀 DB secret 的權限 |
| `iam-base` | `role_agent_<rt>_execution_arn` | String | 增補。Runtime execution role |
| `iam-base` | `role_bedrock_kb_arn`、`role_agentcore_gateway_arn` | String | 增補。只有 `agent_service_roles` 含 `knowledge_base`／`gateway` 才存在 |
| `iam-base` | `agent_service_roles` | String（JSON 陣列） | 增補。`["gateway","knowledge_base"]` 的子集合，已排序，沒有時 `[]` |
| `agent` | `agent_runtime_<rt>` | String（JSON） | 增補。Runtime 的 ARN、id、名稱、execution role ARN 與它能用的 `models`／`memories`／`guardrails`／`knowledge_bases`（key 清單）、`gateway`、`tracing`、`workload_identity`（決策 56 新增；讀的一方缺這個欄位時當成 `false`）（§5.3 增補） |
| `agent` | `models` | String（JSON） | 增補。`{"<key>":{"model_id":…,"invoke_arns":[…]}}`，沒有時 `{}`；模型清單的單一決定點，`invoke_arns` 是唯一的模型 IAM Resource 來源 |
| `agent` | `guardrails` | String（JSON） | 增補。`{"<key>":{"id":…,"arn":…,"version":"DRAFT","profile_id":…}}`，沒有時 `{}` |
| `agent` | ~~`agent_memories`、`knowledge_bases`~~ 已被 D39 拆成下面兩列 | — | — |
| `agent` | `agent_memories` | String（JSON） | 增補。`{"<key>":{"id":…,"arn":…}}`，沒有時 `{}` |
| `agent` | `knowledge_bases` | String（JSON） | 增補。`{"<key>":{"ready":…,"id":…,"arn":…,"embedding_model":…,"bucket_name":…,"bucket_arn":…,"inclusion_prefixes":{"<data source key>":[…]},"data_source_ids":{"<data source key>":"<id>"},"credentials_secret_arn":…}}`，沒有時 `{}`（決策 51、53、55，D39）。tfvars 裡的每個 KB 都有一筆；`ready` 是決策 55 新增的欄位，`database_user_ready = false` 時 `ready = false`、`id` 與 `arn` 是 `null`、`data_source_ids` 是 `{}`，`iam-app` 的 `agent_access` 不准列這種 KB。`inclusion_prefixes` 每個 data source 一個已排序清單，沒給時 `[]`；`data_source_ids` 給 `StartIngestionJob` 用，沒有 stack 讀；`credentials_secret_arn` 是 `agent` 建的 secret 的 ARN（決策 55），不是 secret 的值，符合上面「secret 不進 SSM」，而且必須是帶 6 字元後綴的完整 ARN（~~`agent` 的 validation 與~~ `iam-app` 的 precondition 檢查，D43；`agent` 那一道隨 tfvars 輸入一起在決策 55 刪除） |
| `agent` | ~~`agentcore_gateway`、`bedrock_invoke`~~ 已被 D42 拆成下面兩列 | — | — |
| `agent` | `agentcore_gateway` | String（JSON） | 增補。`{"enabled":false}` 或 `{"enabled":true,"arn":…,"url":…,"lambda_arns":[…],"tool_schema_arns":[…]}`；兩個清單都已排序、沒有時 `[]`；`tool_schema_arns` 是 Lambda target 工具定義的 S3 物件 ARN，`iam-app` 給 Gateway role 恰為這些 ARN 的 `s3:GetObject`（D42） |
| `agent` | `bedrock_invoke` | String（JSON） | 增補。`{"enabled":false}` 或 `{"enabled":true,"role_arn":…,"session_seconds":…}`；跨帳號的單一決定點 |
| `iam-app` | `agent_access` | String（JSON） | 增補。服務 → `{runtimes, models, guardrails, knowledge_bases}`，沒有時 `{}`；`application` 照它注入環境變數 |

**`database` 的 JSON**

有資料庫時：

```json
{
  "enabled": true,
  "deployment": "aurora",
  "port": 5432,
  "name": "app",
  "secret_arn": "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-...",
  "app_endpoint": "alpha-dev-db.proxy-xxxx.ap-northeast-1.rds.amazonaws.com",
  "app_reader_endpoint": "alpha-dev-db-ro.endpoint.proxy-xxxx.ap-northeast-1.rds.amazonaws.com",
  "writer_endpoint": "alpha-dev-db.cluster-xxxx.ap-northeast-1.rds.amazonaws.com",
  "reader_endpoint": "alpha-dev-db.cluster-ro-xxxx.ap-northeast-1.rds.amazonaws.com",
  "proxy_endpoint": "alpha-dev-db.proxy-xxxx.ap-northeast-1.rds.amazonaws.com",
  "has_reader": true
}
```

沒有資料庫時：`{"enabled":false}`。

增補（J64）：有資料庫時多兩個欄位，`"cluster_arn"`（Aurora 是 cluster ARN，`rds` 型態是 `null`）與 `"data_api"`（`true`／`false`），給 `agent` 的 Knowledge Base 與 `iam-app` 的 KB role 用（§5.3 增補）。既有的 `"deployment"`、`"name"` 改取 `rds-v0.1.1` 的 `deployment`、`database_name` 輸出（決策 52、54），欄位與值不變。`secret_arn` 仍是 master secret，KB 不讀它（決策 53）；`agent` 只拿它來擋「KB 填了 master secret」。

| 欄位 | 誰讀 | 說明 |
|---|---|---|
| `app_endpoint`、`app_reader_endpoint`、`port`、`name`、`secret_arn` | `application`、`iam-app` | **應用程式只讀這五個**。有沒有開 Proxy、是哪一種型態，由 `rds` 的輸出決定，應用程式不用知道 |
| `deployment`、`writer_endpoint`、`reader_endpoint`、`proxy_endpoint`、`has_reader` | 維運與除錯 | 例如直接連 writer 跑 migration；`proxy_endpoint` 沒開時是 `null` |

JSON 欄位的增減照 module 的 semver 想：新增欄位是相容的；刪除或改名欄位會讓下游 `jsondecode(...).xxx` 報錯，要當成破壞性變更，同時改所有讀取端。

**tier 與 AZ 調整時，下游怎麼不動**

| 調整 | 發布端的變化 | 下游要改什麼 |
|---|---|---|
| AZ 從 2 個加到 3 個 | `azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>` 清單變長，key 名稱不變 | 不用改程式碼。下游拿到的是清單，`ecs-service`、`rds`、`alb` 收的都是 `list(string)`；重新 apply 即可（ECS service 會滾動部署，資料庫的 subnet group 應該是就地更新，未實測） |
| 改 NAT 模式 | `nat` 的 JSON 內容變 | 不用改；沒有 stack 依賴 NAT 的 id 運作 |
| 新增一個 tier（例如 `batch`） | 多一個 `subnet_ids_batch`、`subnet_cidrs_batch` | 只有要用它的 stack 在 `ssm-inputs.tf` 加上讀取 |
| 改既有 tier 的 CIDR 大小 | 清單內容變，subnet 會重建 | 不用改程式碼，但這是**會重建 subnet 的變更**，上面的 ENI 要先清空；實務上用新增 tier 再遷移，不直接改 |
| 改 tier 名稱 | — | **不允許**。`public`、`app`、`data` 寫進合約，改名等於改合約 |

讀取寫法（`ssm-inputs.tf`，一律呼叫 `ssm-read`，§4.13）。key 清單先放進 local，再傳給 `module "in"`：`terraform test` 讀不到 module 的輸入值，測試要斷言「這個 stack 只讀這些 key」（範本測試的 `reads_only_listed_keys`）時只能斷言 local，所以 module 輸入一律先放 local。

```hcl
locals {
  ssm_input_strings = {
    alarm_topic_arn        = "foundation/alarm_topic_arn"
    vpc_id                 = "network/vpc_id"
    role_ecs_execution_arn = "iam-base/role_ecs_execution_arn"
    database               = "data/database"
  }
  ssm_input_lists = {
    subnet_ids_app = "network/subnet_ids_app"
  }
}

module "in" {
  source     = "../../../../../modules/ssm-read" # 複製出去後改成 git::...?ref=ssm-read-v<semver>
  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

locals {
  database = jsondecode(module.in.strings["database"]) # 條件值
}
```

**每個服務一組的 key 要第二個 `ssm-read`**。`iam-base` 要讀 `containerimage/ecr_<service>_arn`、`application` 要讀 `ecr_<service>_url`、`sg_<service>_id`、`role_<service>_task_arn`、`ecs_exec_<service>`，這些 key 的名稱取決於服務清單，而 `iam-base` 的服務清單本身是從 SSM（`containerimage/services`）讀來的。同一個 module 呼叫的輸入不能依賴它自己的輸出，所以這兩個 stack 多一個 `module "in_services"`，key 清單同樣先放 local（`ssm_service_strings`）：

```hcl
locals {
  service_key         = { for s in module.in.lists["services"] : s => replace(s, "-", "_") }
  ssm_service_strings = { for s, k in local.service_key : "ecr_${k}_arn" => "containerimage/ecr_${k}_arn" }
}

module "in_services" {
  source     = "../../../../../modules/ssm-read"
  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_service_strings
}
```

`application` 的服務清單取自自己的 `var.services`（precondition 檢查它等於 `containerimage/services`），同樣用 `module "in_services"` 讀每個服務的 key。

外部映像副本的 ARN 同理：`iam-base` 先讀 `containerimage/mirrored_images`（JSON 陣列，用 `jsondecode` 解開）得到 mirror 名稱，再用 `module "in_mirrors"` 讀每個 `ecr_mirror_<name>_arn`（`ssm_mirror_strings`）。沒有 mirror 時 `in_mirrors` 什麼都不讀。

增補（Phase 14，D40）：Runtime 一組的 key 也是同樣的寫法。`iam-base` 用 `module "in_agents"` 讀每個 `ecr_agent_<rt>_arn`；`agent` 用 `in_agents` 讀 `ecr_agent_<rt>_url`、`role_agent_<rt>_execution_arn`、VPC 模式 Runtime 的 `sg_agent_<rt>_id` 與它們用到的 `subnet_ids_<tier>`，有 KB 時讀 `role_bedrock_kb_arn`、有 Gateway 時讀 `role_agentcore_gateway_arn`（Runtime 清單取自自己的 `var.agent_runtimes`，precondition 檢查它等於 `containerimage/agent_runtimes`）；`iam-app` 用 `in_agents` 讀 `agent_runtime_<rt>` 與 `role_agent_<rt>_execution_arn`；`application` 用 `in_agent` 讀 `agent` 的值，只有 `agent_access` 有列服務時才讀。服務角色的 ARN 只有在 `iam-base` 建了那個 role 時才存在，所以一律放在第二個 `ssm-read`，用條件決定讀不讀。

下游引用 `module.in.strings["vpc_id"]`、`module.in.lists["subnet_ids_app"]`。本地名稱（map 的 key）通常跟 SSM key 同名；同一個 key 名稱在兩個 stack 都有時，本地名稱可以加前綴區分。測試時用 `override_data { target = module.in.data.aws_ssm_parameter.this["network/vpc_id"] ... }` 餵值。

為什麼用 SSM 不用 `terraform_remote_state`：客戶自管的資源不在我們的 state 裡，`remote_state` 讀不到；SSM 是我們跟客戶都能接的介面。project-a 沒有為這個決定寫 ADR，這個 repo 補 `docs/adr/0003-cross-stack-values-via-ssm-only.md`。

`scripts/validate.sh` 的靜態規則（編號沿用 implement-process，S3、S4 依這次的 module 改寫，S8 是新增），全部接進 CI。對客戶 repo 執行時（`delivering-to-customer.md`），`<repo>/vendor/modules/<module>/` 當作 `modules/<module>/`、`<repo>/infra/terraform/<stack>/` 當作範本的 stack，下表的規則對它們一視同仁；換算只在 `scripts/validate.sh` 的 `canon()` 一處：

| # | 規則 | 說明 |
|---|---|---|
| S1 | 每個 `*.tftest.hcl` 都宣告 `mock_provider "aws"` | 測試不得需要 AWS 憑證 |
| S2 | `resource "aws_ssm_parameter"` 只能出現在 `modules/ssm-publish/` | 只能透過 `ssm-publish` 寫入；範圍含 `modules/` 與 `templates/` |
| S3 | `data "aws_ssm_parameter"` 只能出現在 `modules/ssm-read/`；`modules/ssm-read/` 只讀 `insecure_value`，不得出現 `.value`（`each.value` 是例外：那是 `for_each` 的迭代變數，不是參數的值） | 範本 stack 改用 `ssm-read`，原本「`ssm-inputs.tf` 不讀 `.value`」改由這條涵蓋 |
| S4 | `resource "aws_iam_*"` 只能出現在 `modules/iam-role/` 與 `modules/iam-role-policy/`（後者只允許 `aws_iam_role_policy`），範本的 stack 也不例外；`resource "aws_security_group"`、`aws_vpc_security_group_ingress_rule`、`aws_vpc_security_group_egress_rule` 只能出現在 `modules/security-group/` 與 `modules/vpc-interface-endpoints/`，`modules/vpc/` 與範本的 stack 都不得出現；`resource "aws_default_security_group"` 只能出現在 `modules/vpc/`（§4.7） | 「只有兩個 IAM module 建 IAM」「SG 一律透過 module」的程式檢查（`d770756` 起由 `scripts/validate.sh` 執行） |
| S5 | 範本 ~~8 個~~ 9 個 stack（Phase 14 加 `agent`）的 `common.tf` 雜湊相同 | 修掉 project-a「common.tf 多版本漂移」 |
| S6 | 每份 `envs/<env>.tfbackend` 的 `key` 等於 `<project>-<env>/<stack>/terraform.tfstate`；`envs/examples/` 不得有 tfbackend | 修掉 project-a「key 寫錯讀到別的環境」 |
| S7 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數；`modules/` 底下不得出現 `random_password` | 密碼一律由 RDS 管理 |
| S8 | 範本 stack 裡的 `resource "<type>"` 只能是 §5.3 例外清單上的型別與 stack（~~目前只有 `foundation` 的 `aws_secretsmanager_secret`~~ 決策 55 起是 `foundation` 與 `agent` 的 `aws_secretsmanager_secret`） | 「stack 只呼叫 module」的程式檢查 |
| S9 | 增補（決策 46）：`resource "aws_bedrock_guardrail_version"` 不得出現在 `modules/` 與 `templates/` | 發佈過版本的 guardrail，之後的 apply 只改 `DRAFT`，實際生效的是舊版，plan 乾淨（`project-a/docs/guide/guide-data-scientist.md:268`）。本次只寫文件，`validate.sh` 在 Phase 12 實作 |

增補後其他規則不變：7 個新 module 不建 IAM 由 S4 涵蓋；~~`agent` stack 只呼叫 module，S8 的例外清單不用加~~（已被決策 55 取代：`agent` 多一個原生 `aws_secretsmanager_secret`，`s8_allowed` 加 `agent:aws_secretsmanager_secret`）；S5 的「8 個 stack」在 Phase 14 變成 9 個（`agent` 的 `common.tf` 也要一字不差）。Phase 14 已照這樣實作：`agent` 沒有原生 AWS resource，只有 `terraform_data` 的 guard，9 份 `common.tf` 一致（決策 55 之後 `agent` 多了 KB 的 secret 容器）。

project-a 的 `project-a/infra-v2/terraform/check-ssm-contract.sh` 還有第三條「讀的 key 必須是 apply 順序更早的 stack 有發布的」。**這條第一版不做，列為之後要補的檢查。** 理由：第一版範圍要小；而且這條要解析每個 stack 的 HCL（`ssm-outputs.tf` 的 `strings`／`lists` 與 `ssm-inputs.tf` 的 key 清單）再做跨 stack 比對，project-a 用 awk 硬解，格式一變就會誤判。第一版靠兩件事補位：各 stack 的測試鎖住它讀取的 key 清單；`infra/README.md` 的合約表寫明每個 key 誰寫誰讀，PR 審查時對照。上表「方向」那一條仍然是規則，只是還沒有自動檢查。

project-a 那支腳本沒有接進 CI，也沒列入 `bridge` 與 `postdeploy`，等於沒在跑；這裡的規則一定要接進 CI。

### 5.7 環境切換

手打 `terraform` 時，切換環境是**四個彼此獨立的選擇**，沒有任何東西把它們綁在一起：

| 選擇 | 怎麼指定 | 忘了換的後果 |
|---|---|---|
| AWS 身分 | `aws-vault exec <profile> --` | 打到錯的帳號（由 `allowed_account_ids` 擋下） |
| backend | `-backend-config=envs/<env>.tfbackend` | 讀寫到別的環境的 state |
| 變數 | `-var-file=envs/<env>.tfvars` | 用錯的設定規劃 |
| 工作目錄 | `TF_DATA_DIR=.terraform-<env>` | 沿用上一個環境的 backend 設定與 provider 快取 |

固定步驟：

```bash
cd infra/terraform/application
export TF_DATA_DIR=.terraform-dev
terraform init -reconfigure -backend-config=envs/dev.tfbackend
terraform plan -var-file=envs/dev.tfvars
```

- 換環境一律 `init -reconfigure`，不用 `-migrate-state`（後者會把 state 搬過去）。
- 帳號防線：`providers.tf` 寫 `allowed_account_ids = [var.expected_account_id]`；`common.tf` 用一張 `env → 帳號` 對照表 validation `expected_account_id`，表外的 env 一律拒絕。帳號錯的時候在 plan 前就停。
- 環境名稱**只有一層**：`env` 同時用在檔名（`envs/dev.tfvars`）、資源命名、SSM 路徑、state key。project-a 有 `devbox`／`box` 兩層命名，填反時檢查會比對到空集合然後「通過」，這裡不再重演。

`common.tf` 的帳號 validation：

```hcl
variable "env" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.env))
    error_message = "env must be 2-12 lowercase letters or digits, starting with a letter."
  }
}

variable "expected_account_id" {
  type = string
  validation {
    condition     = contains(lookup(local.accounts_by_env, var.env, []), var.expected_account_id)
    error_message = "expected_account_id is not registered for this env in common.tf."
  }
}

locals {
  # 專案複製範本後改這張表；新增環境要改所有 stack 的 common.tf（CI 會檢查一致）
  accounts_by_env = {
    dev  = ["111111111111"]
    prod = ["222222222222"]
  }
}
```

`expected_account_id` 不給預設值。project-a 的 `application` stack 預設指到 prod b2c 帳號（`project-a/infra-v2/terraform/application/providers.tf`），漏帶 tfvars 時要靠第二條 validation 才擋得住；沒有預設值的話，漏帶就直接報缺變數。

### 5.8 客戶自管資源模式

情境：客戶自己管一部分資源，我們只部署其餘部分。分成兩種模式：

| | 模式 A：客戶管 VPC、我們管 SG | 模式 B：network 整個由客戶管 |
|---|---|---|
| 適用 | 客戶有既有 VPC 規範，但讓我們開 SG | 客戶的網路團隊連 SG 都要自己管 |
| `network` stack | 照跑，`vpc = null`、改給 `existing = { vpc_id, subnet_ids }`；用 data source 驗證 id 存在後，發布**同一組 key**，SG 與 interface endpoint 仍由我們建（`vpc-interface-endpoints` 的 `allowed_cidrs` 用客戶 VPC 的全部 CIDR、`subnet_ids` 用 `existing.subnet_ids[subnet_tier]`）；用 `data "aws_vpc"` 檢查客戶 VPC 有開 `enable_dns_support` 與 `enable_dns_hostnames`，沒開時 `private_dns_enabled = true` 的 endpoint 無法解析；路由、IGW、NAT、gateway endpoint、default SG 一律不碰 | 該環境**不放** `network/envs/<env>.tfbackend` 與 tfvars，我們不跑 |
| 誰發布 `network/*` 的 key | `network` stack（我們） | 客戶，照 §5.6 合約表發布全部 key，包括 `sg_*`、`alb_https`、`db_proxy`、`data_access` 這些 JSON |
| 下游 | 不變 | 不變 |

其他 stack（`foundation`、`containerimage`、`iam-base`、`data`、`iam-app`）也可以照模式 B 交給客戶：該環境不放那個 stack 的 tfbackend 與 tfvars，客戶照合約發布同樣的 key。

共通做法：

1. 客戶照同一份 SSM 合約（`infra/README.md` 的合約表）在 `/<project>/<env>/<stack>/<key>` 發布 key。路徑裡的 `<stack>` 照寫（例如客戶發布 `/<project>/prod/network/vpc_id`），即使客戶那邊沒有叫 `network` 的東西。
2. 客戶自管的 stack 在那個環境**不放** `envs/<env>.tfbackend` 與 `envs/<env>.tfvars`。沒有檔案就無法 init，誤跑的機會從根本消失。
3. 建議客戶給我們的部署 role 明確 Deny `ssm:PutParameter`／`ssm:DeleteParameter` 於客戶擁有的路徑，作為第二道防線。
4. 跨帳號部署用 `providers.tf` 的可選 `assume_role`（`deploy_role_arn`，空字串代表用呼叫者身分），跟 project-a 相同。
5. 客戶的部署 role 不能改 IAM 時，`iam-base` 與 `iam-app` 一定要交給客戶（模式 B）。這也是「只有 `iam-role` 建 IAM、而且只在兩個 IAM stack 呼叫」的原因：其他 module 一旦自己建 role，這種環境就 apply 不過。
6. 客戶環境連不到我們的 GitHub 時，FDE 用 `scripts/vendor-modules.sh` 把專案 repo 裡已釘 tag 的 `git::` source 換成 vendored 相對路徑，provider 用 `terraform providers mirror` 鏡像（§8.7、`docs/guides/delivering-to-customer.md`）。

跟 project-a 的差別：project-a 有兩棵樹（`/project-a/<env_label>/<stack>/<key>` 與 `/shared/infra/<key>`），再用 `bridge` stack 在自管環境把樹 A 轉寫成樹 B。新專案從一開始就只有一棵樹，客戶發布的就是同一棵樹的 key，不需要 bridge。

### 5.9 命名與 tag

- 命名前綴 `local.name_prefix = "${var.project}-${var.env}"`，資源名稱 `<name_prefix>-<component>`（例如 `alpha-dev-api`、`alpha-dev-db`、`alpha-dev-alb`）。不提供 `name_prefix` 覆寫變數；project-a 的覆寫是為了收編既有資源，新專案不需要。module 不組命名，收完整的 `name`；客戶有自己的命名規範（例如 project-c 的 `[資源]-[應用]-[環境]-[區域]-[描述]-[序號]`）時，由專案在 root 組好名稱再傳進 module，module 不用改（已拍板，§9.2）。
- 長度限制要在 root 留意：ALB 名稱上限 32、target group 名稱上限 32（`ecs-service` 的 `name` 因此限 26）、RDS identifier 上限 63（`rds` 的 `name` 限 50，留給 `-final-<random>` 後綴）。`project` 與 `env` 的長度要讓這幾個名稱放得下。
- 服務名稱用 kebab-case（`order-api`），進 SSM key 時 `-` 轉 `_`（`sg_order_api_id`）。
- `default_tags`：`Project`、`Environment`、`Managed = "terraform"`、`Stack`，加上可選的 `Owner`。用 `Managed` 不用範例的 `ManagedBy`，跟 project-a 一致。
- 不在 tag 放 `timestamp()`。

### 5.10 沿用 project-a 的與修掉 project-a 的

**沿用**

| 做法 | project-a 來源 |
|---|---|
| 依擁有者與變動頻率拆 stack，一個 stack 一份 state，apply 順序單向 | `project-a/infra-v2/terraform/` |
| 跨 stack 只走 SSM，只能透過 `ssm-publish` 寫入 | `project-a/infra-v2/terraform/modules/ssm-publish/` |
| `backend "s3" {}` 空殼加 `envs/<env>.tfbackend` | `project-a/infra-v2/terraform/application/versions.tf`、`envs/` |
| `TF_DATA_DIR=.terraform-<env>`、換環境 `init -reconfigure` | `project-a/docs/runbook/runbook-terraform-state.md` §1 |
| `allowed_account_ids` 加 env→帳號 validation | `project-a/infra-v2/terraform/application/providers.tf` |
| `.terraform.lock.hcl` 進版控、`use_lockfile = true` | 各 stack |
| CI 自動找出所有 root 跑 `init -backend=false`、`validate`、`test` | `project-a/.github/workflows/` 的 `terraform-static` job |
| SG 規則用獨立的 `aws_vpc_security_group_*_rule` | `project-a/infra-v2/terraform/network/security-group-rules.tf`、`security-groups.tf` 的註解 |
| Aurora 的 `manage_master_user_password`、四個預設參數、final snapshot 的 `random_id` 後綴、Proxy 的連線池參數 | `project-a/infra-v2/terraform/database/rds.tf`、`rds-proxy.tf` |
| ALB access log bucket 用 SSE-S3 | `project-a/infra-v2/terraform/loadbalancer/access-logs.tf` |

**修掉的坑**

| project-a 的坑 | 為什麼是坑 | 範本怎麼做 | project-a 來源 |
|---|---|---|---|
| 兩棵 SSM 樹加 `bridge` | 多一個 stack、多一套 key 命名（snake_case 對 kebab-case），只為了接客戶的路徑 | 一棵樹；客戶照合約發布同一棵樹 | `bridge/providers.tf`、`docs/spec/infra.md` |
| 跨 stack 的 id 寫死在 tfvars | 上游換資源，下游 tfvars 不改，plan 不會提醒 | 一律從 SSM 讀；tfvars 只放這個 stack 自己的設定 | `postdeploy/envs/devbox.tfvars`、`application` 的 `target_group_arn` |
| uat／prod 的 tfvars 只在持有人本機 | 換人就不能部署，拿舊檔 apply 會退版 | 非機密 tfvars 全部進版控；secret 不進 tfvars | `project-a/.gitignore` 第 31–43 行 |
| **secret 值寫在 tfvars** | `loadbalancer/envs/{uat,prod}.tfvars` 有明文的 `chat_origin_lock_header_value`；這兩個檔沒進版控，但值就躺在持有人本機的檔案裡，而且會進 state | 範本不得照抄。origin lock 這類共享密值放 Secrets Manager，Terraform 只引用 ARN（WAF 規則需要明文比對時，值也只從 Secrets Manager 讀，不進 tfvars） | `loadbalancer/envs/uat.tfvars`、`prod.tfvars`（未進版控） |
| 開關預設全關 | `postdeploy` 5 個 `*_enabled` 預設 `false`，tfvars 不完整時 plan 會規劃刪除已存在的資源（簡報記為 27 個，本次未重算） | module 沒有開關；必要的輸入沒給就在 plan 前報錯 | `postdeploy/variables.tf` |
| 告警與 autoscaling 放在獨立的 `postdeploy` | 需要前面 stack 的名稱與 ARN，只能寫死在 tfvars | 服務告警收進 `application`、ALB 與資料庫告警收進 `alb`、`rds` module | `postdeploy/` |
| 第三個 AZ 的 subnet 會靜默重疊 | `ecs_app` 與 `agent_app` 用不同 `newbits` 從同一個 CIDR 切，只放得下兩個 AZ，靠一條寫死的 precondition 擋 | `vpc` module 把所有 subnet 換成整數區間兩兩比對 | `network/subnets-app.tf` |
| public route table 用 inline `route {}` | 對整張表有權威性，客戶加的 peering 路由每次 apply 都被刪 | 一律用 `aws_route` 獨立資源 | `network/nat.tf`、`docs/reports/2026-09-04-customer-owned-network-and-terraform.md` |
| Enhanced Monitoring 掛 AWS managed policy、Proxy 的 `kms:Decrypt` 是 `Resource = "*"` | 測試斷言不到內容；權限比需要的寬 | inline policy、Resource 收窄到 `RDSOSMetrics` 與單一 key | `database/rds.tf`、`rds-proxy.tf` |
| `stacks.sh` 失效 | `ORDER` 沒有 `bridge` 與 `postdeploy`，也不支援 devbox／uat | 不提供一鍵跑全部的腳本；apply 順序寫在 `infra/README.md`，靠人照順序跑 | `stacks.sh` |
| `common.tf` 多版本漂移 | `check-ssm-contract.sh` 要求一字不差，實際 11 個 stack 有 5 種版本，因為那支腳本沒接進 CI | `validate.sh` 比對雜湊，接進 CI | 各 stack 的 `common.tf`、`check-ssm-contract.sh` |
| 雙層環境命名（`devbox`／`box`） | 填反不報錯，檢查比對到空集合後「通過」 | 只有一層 `env` | `scripts/lib/env-guard.sh` |
| `expected_account_id` 預設指 prod 帳號 | 漏帶 tfvars 時預設就是正式站 | 不給預設值 | `application/providers.tf` |

### 5.11 依流量調整規格

規格不放進 module（module 沒有 `size = "small"` 這種 preset），而是放在範本的範例 tfvars：`network/envs/examples/{poc,standard,high}.tfvars`，以及 `data`、`loadbalancer` 對應的範例檔；`infra/README.md` 附下面這張對照表。理由見 §9.1 J11。

| | PoC | 一般正式 | 大流量 |
|---|---|---|---|
| VPC CIDR | /20：public /26、app /24、data /27 | /19～/16，app /22 起跳 | /16，app /20 起跳 |
| AZ | 2 | 2 | 3 |
| NAT | `single`（沒有對外流量時可用 `none`） | `per_az` | `per_az` |
| interface endpoint（`vpc-interface-endpoints` 的 `services`；S3 gateway 是 `vpc` 的 `gateway_endpoints`） | 無（只開 S3 gateway） | `ecr.api`、`ecr.dkr`、`logs`、`secretsmanager`、`kms` | 上一欄再加 `ssm`、`ssmmessages`、`xray`；需要時加 `bedrock-runtime` |
| flow log | 關 | 開（S3） | 開（S3） |
| RDS | `rds`、`db.t4g.micro`／`small`、單一 AZ；或 `aurora_serverless` 0.5～4 ACU | `aurora_serverless` 2～16 ACU 加 1 個 reader；或 `aurora` `db.r7g.large` 加 1 個 reader；或 `rds` 加 `multi_az` | `aurora` `db.r7g.xlarge` 以上、2 個以上 reader、開 Proxy |
| 備份／刪除保護 | 1～7 天、`false` | 7～14 天、`true` | 14 天以上、`true` |
| ALB | 可以只開 HTTP（SG 要收窄）、idle 60、不開 access log、不掛 WAF | HTTPS、access log、WAF | 同一般正式；SSE 這類長連線服務 idle 設 300 |
| RDS Proxy（`network` 的 `data_stores.db.proxy`） | 不開 | 開 | 開 |
| 追蹤抽樣（`xray` 的 sampling rule，或 SDK 端的 `traceidratio`） | 100％（project-b dev 用 `fixed_rate = 1.0` 的全抽樣規則，`project-b/infra/terraform/deploy/dev/main.tf`；project-a 範本預設 `otel_traces_sampler_arg = 1.0`，`project-a/infra-v2/terraform/envs/_template/application.tfvars.example`） | 每秒 1 筆加 5％（等於 AWS 帳號預設的 `Default` 規則；project-b 非 dev 環境就是沿用它，`project-b/infra/terraform/modules/agentcore/variables.tf` 的說明）。**無實測依據**：沒有專案在正式流量下量過這個比例的成本與可用度 | 每秒 1 筆加 1～5％，health check 規則設 0。**無實測依據** |
| log 告警（`log-metric-alarm`） | 不開 | 開。project-a 的正式站開了 audit 寫入失敗、rate limit fail-open 這類事件告警（`project-a/infra-v2/terraform/postdeploy/alarms-persistence.tf`、`envs/prod.tfvars` 的 `alarms_enabled = true`） | 開，同一般正式 |

**依據**

| 項目 | 實際設定或實測 | 來源 |
|---|---|---|
| project-c VPC 大小 | uat `/22`、prod `/21`，每個 AZ 一個 `ingress`／`ecs`／`db`／`egress` subnet | `project-c-infra/environments/{uat,prod}/network/terraform.tfvars` |
| project-c NAT | uat 關閉，註解寫省約 USD 66／月（CE-1149，TGW 未接、沒有流量）；prod 每個 AZ 一顆 | 同上、`project-c-infra/environments/uat/network/routes.tf` |
| project-c interface endpoint | `kms`、`secretsmanager`、`ssm`、`ssmmessages`、`ecr.api`、`ecr.dkr`、`logs`、`xray`；另有 `bedrock-runtime`、`bedrock` | `project-c-infra/environments/uat/platform/terraform.tfvars`（`vpce_interface_config`、`ai_vpce_config`） |
| project-c Serverless 規格 | sit、uat 0.5～4 ACU；prod 2～16 ACU；備份 uat 7 天、prod 14 天 | `project-c-app/environments/{sit,uat,prod}/project-c/platform/terraform.tfvars`（prod 那份的註解仍寫 0.5～4，實際值是 2～16） |
| project-a 資料庫 | uat `db.r7g.large` 加 1 個 reader；devbox `db.t4g.medium` 加 1 個 reader | `project-a/infra-v2/terraform/database/envs/uat.tfvars`（未進版控，只在持有人本機）、`devbox.tfvars` |
| project-a ECS 規模 | prod autoscaling min 10／max 40 | `project-a/docs/reports/2026-09-17-prod-load-test-150qps/README.md` |
| project-a 目標流量 | 150 則／秒（9,000 RPM）推算約需 12.2 個 task，且落在已驗證區間之外 | `project-a/docs/reports/2026-09-19-first-turn-ttft-cold-provisioning/README.md` |
| project-a Proxy | 正式站 48 小時內零錯誤、零逾時；7 天內 26 次 session pinning。同一份報告的流量最高小時是 238 輪對話，**這是低流量下的結果，不能當成 Proxy 在高 QPS 下的證據** | `project-a/docs/reports/2026-09-18-prod-latency-breakdown.md` |
| project-a ALB 連線數 | 8 QPS 時 `ActiveConnectionCount` 逐分鐘峰值 87 | `project-a/docs/reports/2026-09-18-devbox-full-chain-load-test/README.md` |

**Proxy 的預設**：dev（PoC）不開，prod（一般正式、大流量）開。開關在 `network` 的 `data_stores.db.proxy`（單一決定點，§5.3），`data` 照 `network/db_proxy` 決定要不要傳 `proxy` 給 `rds`。第一次部署 prod 時，如果 §7.3 的實測證實「Proxy role 還沒有讀 secret 的權限就無法建立 Proxy」，就先設成不開，照順序 apply 到 `iam-app`，再改成開、依序 apply `network` 與 `data`，跟 §5.4 的對策相同。實測結果出來之前，`infra/README.md` 的第一次部署步驟兩種都要寫。

**沒有實測依據的部分**：大流量那一欄的 RDS 規格沒有任何專案實測過；`rds` 型態（一般 RDS）也沒有任何專案用過。兩者都只是起點，第一個用到的專案要自己量。

**IP 規劃公式**

一個 Fargate task 用 1 個 IP（awsvpc）。每個 subnet 有 5 個 IP 被 AWS 保留。

```
app tier 每個 AZ 需要的 IP ≥ ceil(max_task 數 × 2 ÷ AZ 數)    # 部署時 max 200%，新舊 task 同時存在
                           + interface endpoint 數（放在 app tier 時，每個 endpoint 每個 AZ 1 個）
                           + 預留（建議再加 50%）
                           + 5（AWS 保留）
public tier 每個 AZ ≥ ALB 節點用量（AWS 要求 subnet 至少 /27、至少 8 個可用 IP）+ NAT（每顆 1 個）+ 5
data tier 每個 AZ ≥ DB instance 數 + Proxy 的 ENI + 5
```

例：一般正式，max 40 task、2 個 AZ、5 個 interface endpoint → `ceil(40 × 2 ÷ 2) + 5 = 45`，加 50％ 約 68，加 5 約 73，`/25`（123 個可用）就夠；表上建議 `/22`，是留給服務數量成長，不是單一服務需要。project-a 的 app subnet 切到 `/19`（`ecs_app` 與 `agent_app` 都是），主要是為了 AgentCore 的 ENI；ECS 本身用不到那麼大（`project-a/infra-v2/terraform/network/subnets-app.tf`）。Proxy 每個 subnet 會用掉幾個 IP，AWS 沒有固定數字，**未驗證**。

增補：VPC 模式的 AgentCore Runtime 也在 `agent_runtimes[*].subnet_tier` 指定的 tier 裡用 ENI，每個 Runtime 用掉幾個 IP、會不會隨 session 數增加，**未查證**（§7.3 第 17 項）。在量到之前，用到 Runtime 的專案照 project-a 的做法把那個 tier 切大（project-a 用 `/19`），或另開一個 `agent` tier 專給 Runtime。

## 6. 四個團隊在這個 repo 的責任

### 6.1 責任

| 團隊 | 擁有 | 負責 | 不負責 |
|---|---|---|---|
| platform team | `modules/`、`.github/`、`scripts/`、`docs/adr/`、`release-please-*` | module 介面與 semver、CI、發版、安全基線、審查範本變更 | 各專案的 tfvars 與 apply |
| core app team | 本 repo 暫無 | 未來 AP 層共用元件比照本 repo 的發版模式另開 repo；需要 infra 支援時對 platform team 開 issue | infra module |
| 專案 app team | 自己 repo 裡的 `infra/` | 複製範本、釘版本、升版、自己的 tfvars 與 apply、回報 module 的 bug 或需求 | module 內部實作 |
| 專案 FDE team | 自己的交付 repo | vendoring、providers mirror、與客戶約定 SSM 合約、回報客戶環境差異 | 決定差異要不要收進 module |

### 6.2 交接點

| 交接 | 從 → 到 | 形式 |
|---|---|---|
| module 新需求或 bug | 專案 app team／FDE → platform team | GitHub issue，附消費端的呼叫方式與期望行為 |
| 新版發布 | platform team → 所有消費端 | release-please 產生的 tag 與 CHANGELOG；MAJOR 版另外通知 |
| 範本改版 | platform team ↔ 專案代表 | PR，需要雙方核准 |
| 客戶環境差異 | FDE → platform team | issue，platform team 決定收進 module（MINOR）或留在專案 |
| 交付給客戶 | FDE → 客戶 | vendored module＋SSM 合約表＋`docs/guides/delivering-to-customer.md` |

### 6.3 CODEOWNERS

`<org>` 與 team slug 都是佔位符，團隊成立後填入（§9.3 待補資訊）。

```
# 預設：platform team
*                                         @<org>/platform-team

/modules/                                 @<org>/platform-team
/.github/                                 @<org>/platform-team
/scripts/                                 @<org>/platform-team
/docs/adr/                                @<org>/platform-team
/release-please-config.json               @<org>/platform-team
/.release-please-manifest.json            @<org>/platform-team

# 範本：platform team 加專案代表
/templates/                               @<org>/platform-team @<org>/project-app-reps
/docs/guides/project-infra-standard.md    @<org>/platform-team @<org>/project-app-reps
/docs/guides/consuming-modules.md         @<org>/platform-team @<org>/project-app-reps

# 交付：platform team 加 FDE
/scripts/vendor-modules.sh                @<org>/platform-team @<org>/fde-team
/docs/guides/delivering-to-customer.md    @<org>/platform-team @<org>/fde-team

# 團隊分工：四方都要看
/docs/guides/team-roles.md                @<org>/platform-team @<org>/core-app-team @<org>/project-app-reps @<org>/fde-team
```

新增的 `vpc`、`alb`、`rds` 都在 `/modules/` 底下，範本新增的 stack 都在 `/templates/` 底下，這份 CODEOWNERS 不用因為三層架構而改。

規則：CODEOWNERS 要搭配分支保護的「Require review from Code Owners」才有效；GitHub 對同一路徑取最後一條符合的規則，所以具體路徑寫在後面。

## 7. 驗證策略

### 7.1 沒有 AWS 環境時驗得到的

| 層級 | 指令 | 驗到什麼 | 需要網路 | 需要 AWS 憑證 |
|---|---|---|---|---|
| 格式 | `terraform fmt -check -recursive` | 格式 | 否 | 否 |
| lint | `tflint`，第一版只用內建的 terraform ruleset（`recommended` preset） | 未使用的變數、缺型別、命名慣例之類 | 否（內建 ruleset 不用下載 plugin） | 否 |
| 語法與型別 | `terraform init -backend=false`、`terraform validate` | HCL 語法、型別、引用、validation 的寫法本身 | 下載 provider | 否 |
| 行為 | `terraform test`，全部 `mock_provider "aws"` | 資源有沒有建、數量、命名、條件建立、validation 會不會擋下錯誤輸入（`expect_failures`） | 下載 provider | 否 |
| 靜態規則 | `scripts/validate.sh` | §5.6 的 S1–S8（增補 S9，Phase 12）：每個 test 都用 `mock_provider`、SSM 寫入只在 `ssm-publish`、SSM 讀取只在 `ssm-read`、IAM 只在 `iam-role`、`common.tf` 一致、tfbackend key 格式、`rds` 沒有 password 變數、範本 stack 只有例外清單上的原生 resource | 否 | 否 |

每個 module 的 `tests/` 至少要有：

- 預設輸入的 plan（資源數量、預設值，例如 `cpu_architecture == "ARM64"`）。
- 每個條件建立的開與關（例如 `load_balancer = null` 時 target group 數量為 0）。
- 每條 validation 一個 `expect_failures`，而且要有一個「合法邊界值會通過」的對照 run（只測會失敗的一邊，validation 寫錯成永遠失敗也會通過）。

`vpc`、`alb`、`rds` 的測試清單：

| module | run（plan，除非另註） | `expect_failures` |
|---|---|---|
| `vpc` | 2 AZ 與 3 AZ 的自動切；明確 `cidrs`；`nat_mode` 三種各一（`single` 只有 1 顆 NAT、`per_az` 每個 AZ 一顆且 private route 指向同 AZ、`none` 沒有 NAT 也沒有 `0.0.0.0/0` 路由）；isolated tier 沒有任何 `0.0.0.0/0` 路由；gateway endpoint 關聯所有 private／isolated 路由表；default SG 沒有任何規則；不再有 interface endpoint 與任何 `aws_security_group`；`flow_log = null` 時 0 個；subnet key 是 `"<tier>/<az>"`；沒有任何 inline `route`／`ingress` | CIDR 不是 /16～/24 或不是網路位址；AZ 少於 2、多於 4 或重複；tier 同時給 `newbits` 與 `cidrs`；兩個 public tier；`cidrs` 少一個 AZ；**兩個 tier 重疊**（含「第三個 AZ 才重疊」這個 project-a 案例）；subnet 超出 VPC；`nat_mode != "none"` 卻沒有 public tier；gateway endpoint 給 `ec2` |
| `vpc-interface-endpoints` | 每個 `services` 一個 `Interface` endpoint，`private_dns_enabled` 預設 `true`，`subnet_ids` 與 `security_group_ids` 照輸入；每個 `allowed_cidrs` 一條 443/tcp 的 ingress rule，沒有 egress、沒有 inline 規則；`services = []` 時三種資源都是 0 個且 `security_group_id = null`；`private_dns_enabled = false` 照輸入 | 服務名稱帶 `com.amazonaws.` 前綴；`allowed_cidrs` 為空、含 `0.0.0.0/0` 或不是 CIDR；`subnet_ids` 少於 2；`vpc_id` 格式錯 |
| `alb` | 有憑證：HTTPS listener 用 `ELBSecurityPolicy-TLS13-1-2-2021-06`、預設 404，HTTP listener 預設 301；沒有憑證：只有 HTTP listener、預設 404，`listener_protocol = "HTTP"`；`drop_invalid_header_fields = true`；`access_logs`、`web_acl_arn` 為 null 時對應資源 0 個；ELB 5xx 告警的 `alarm_actions`、`ok_actions` 都是 `sns_topic_arns` | 名稱超過 32 字或以 `internal-` 開頭；subnet 少於 2；`idle_timeout` 0 或 4001；`certificate_arn` 不是 ACM ARN；有 `additional_certificate_arns` 卻沒有 `certificate_arn`；`sns_topic_arns` 為空 |
| `rds` | 三種型態各自的 basic；`{rds, aurora, serverless} × {proxy_off, proxy_on}` 共 6 個；`aurora_proxy_ro`（Aurora 有 reader 時有 read-only endpoint）；`rds_proxy_no_ro`（一般 RDS 沒有）；`proxy_role_passed_through`（`aws_db_proxy.role_arn` 等於輸入）；`no_password_all_modes`（`manage_master_user_password == true`，`password`、`password_wo` 都是 null）；`final_snapshot`（名稱帶 `random_id` 後綴）；`alarms_per_deployment`（rds 沒有 replica lag 告警、Aurora 有 reader 才有、Proxy 開才有兩條 Proxy 告警）；三種型態的輸出格式一致（`app_endpoint`、`identifier_type` 等） | 型態物件不符；`aurora` 用 `db.serverless`；ACU 超出 0～256、min > max 或不是 0.5 的倍數；`reader_count = 16`；`rds` 填了 `cluster_parameters`；proxy 缺 `role_arn` 或格式錯；`rds`／`aurora` 沒給 `connections_threshold`；`sns_topic_arns` 為空 |

`rds` 的 mock 要用 `mock_resource` 給 `aws_db_instance` 與 `aws_rds_cluster` 的 `master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x", kms_key_id = "k", secret_status = "active" }]`，以及 `address`、`endpoint`、`reader_endpoint`、`port` 的預設值。不給的話 nested list 是空的，取 `[0]` 會失敗。

`kms-key`、`ecr-repository`、`s3-bucket`、`ssm-read`、`iam-role`、`iam-role-policy`、`security-group`、`log-group`、`log-metric-alarm`、`xray` 的測試清單，以及 `ecs-service` 的 `sidecars` 迴歸要求：

| module | run（plan，除非另註） | `expect_failures` |
|---|---|---|
| `kms-key` | `enable_key_rotation = true`；alias 是 `alias/<name>`；key policy 第一段是帳號 root；每個 `service_principals` 一段 statement、條件照輸入；`administrator_arns` 有給時多一段 | `deletion_window_in_days` 6 或 31；`name` 以 `aws/` 開頭；service principal 是 `*` 或不以 `.amazonaws.com` 結尾；service 動作給 `*` 或 `kms:*`；`administrator_arns` 含 `*` |
| `ecr-repository` | `IMMUTABLE`、`scan_on_push = true`、`force_delete = false`；`kms_key_arn = null` 時 `AES256`、有給時 `KMS`；lifecycle policy 的兩條規則與預設值（7 天、50 個）；覆寫後的值 | 名稱含大寫或空白；`untagged_expire_days = 0`；`keep_count = 0` |
| `s3-bucket` | 封鎖公開存取四項全開；`BucketOwnerEnforced`；bucket policy 一定有 `aws:SecureTransport = false` 的 Deny；`log_delivery = []` 時只有那一段 Deny；`alb_access_logs` 有 ELB 服務帳號與服務主體兩段（`data.aws_elb_service_account` 用 `override_data`）；`vpc_flow_logs` 有 PutObject 與 GetBucketAcl，帶 `aws:SourceAccount`；`kms_key_arn` 有給時是 `aws:kms` | 名稱含 `.` 或大寫；`expiration_days = 0`；`log_delivery` 給 `cloudtrail`；**`alb_access_logs` 搭配 `kms_key_arn`** |
| `ssm-read` | `strings` 的輸出等於 `override_data` 給的 `insecure_value`；`lists` 以逗號切開；同一個 `<stack>/<key>` 出現在兩個本地名稱時只讀一次；兩個 map 都空時沒有 data source | `ssm_prefix` 缺開頭斜線或多結尾斜線；值不是 `<stack>/<key>`（例如 `network/VPC_ID`、`/network/vpc_id`） |
| `iam-role` | trust 只有給的服務主體；`source_account` 有給時帶 `aws:SourceAccount`；每個 `inline_policies` 一個 `aws_iam_role_policy`；`permissions_boundary` 照輸入 | trust 為空或給 `*`；`source_account` 不是 12 位數；inline policy 不是 JSON；Allow statement 的 Action 是 `*` 或 `s3:*`（字串與清單兩種寫法、沒寫 `Effect` 的都要測）；`Statement` 寫成單一物件（`statement_object_rejected`）；`Statement` 是空清單（`empty_statement_list_rejected`）；Allow 用 `NotAction`，字串、清單、沒寫 `Effect` 三種（`allow_notaction_*_rejected`）；反向：`s3:Get*` 這種前綴萬用要通過（`allow_prefix_wildcard_passes`）、Deny 用 `*` 要通過（`deny_wildcard_is_allowed`）、Deny 搭配 `NotAction` 要通過（`deny_notaction_is_allowed`）；Allow 用 `NotResource`，字串、清單、沒寫 `Effect` 三種（`allow_notresource_rejected`、`allow_notresource_list_rejected`、`allow_notresource_without_effect_rejected`）；反向：Deny 搭配 `NotResource` 要通過（`deny_notresource_is_allowed`） |
| `iam-role-policy` | 每個 `policies` 一個 `aws_iam_role_policy`；`role` 等於從 `role_arn` 取出的名稱 | `role_arn` 帶 path 或不是 role ARN；`policies` 為空；policy 不是 JSON；以及跟 `iam-role` 相同的 policy 檢查：Action 是 `*` 或 `secretsmanager:*`、單一物件 `Statement`、空 `Statement`、Allow 用 `NotAction`（三種寫法）、Allow 用 `NotResource`（三種寫法，`allow_notresource_*`）；反向：前綴萬用、Deny 用 `*`、Deny 搭配 `NotAction`、Deny 搭配 `NotResource`（`deny_notresource_is_allowed`）都要通過。兩個 module 的這組 run 名稱相同 |
| `security-group` | 每個 `security_groups` 一個 SG；規則依 `type` 分到 ingress／egress 兩種資源；`peer_group` 轉成同一次呼叫裡 SG 的 id（`referenced_security_group_id`）；`to_port` 預設等於 `from_port`；`ip_protocol = "-1"` 時沒有 port；沒有 inline 規則 | 規則指向不存在的 SG key；同一條規則給了兩個 peer 或沒有 peer；`type = "both"`；tcp 規則沒有 `from_port`；**ingress 對 `0.0.0.0/0` 沒寫 `allow_internet = true`**；egress 對 `0.0.0.0/0` 不需要 `allow_internet` 要**通過**（反向） |
| `log-group` | `retention_in_days` 等於輸入、預設 30；`kms_key_arn` 有給時帶上；`subscription = null` 時沒有 subscription filter；給 Lambda 目的地時不給 `role_arn` 也能通過（`lambda_subscription_without_role`；只驗「不報錯」，`role_arn` 是 null 這件事測不到，因為 provider 的 `role_arn` 是 optional 加 computed，mock 會填假值）；給 Firehose 目的地時帶 `role_arn` | `retention_days = 0` 或 `2`；名稱以 `aws/` 開頭；`destination_arn` 是 S3 ARN；Kinesis／Firehose 目的地沒給 `role_arn` |
| `log-metric-alarm` | 每個 `alarms` 項目一個 metric filter 與一個 alarm，名稱 `<name_prefix>-<key 的 _ 換成 ->`；filter 的 `metric_transformation` 是 `value = "1"`、`default_value = 0`；alarm 的預設是 `Sum`、60 秒、1 期、`>= 1`、`notBreaching`；**每個 alarm 的 `alarm_actions` 與 `ok_actions` 都等於 `sns_topic_arns`**（反向驗證：拿掉一個的 `ok_actions` 測試要紅）；`alarms = {}` 時兩種資源都是 0 個 | `sns_topic_arns = []`；key 不是 snake_case；`pattern` 或 `description` 是空字串；`statistic = "p99"`；`period = 45`；`datapoints_to_alarm` 大於 `evaluation_periods`；`namespace` 以 `AWS/` 開頭 |
| `xray` | 每個 `sampling_rules` 一個 rule，名稱 `<name_prefix>-<key>`、沒給的欄位是 `*`；每個 `groups` 一個 group，`insights_configuration` 照輸入；兩個 map 都空時什麼都不建 | 名稱超過 32 字；`priority = 0` 或 `10000`；`fixed_rate = 1.5`；兩條 rule 的 `priority` 相同；group 的 `filter_expression` 空字串；`notifications_enabled = true` 但 `insights_enabled = false` |
| `ecs-service` 的 `sidecars` | **迴歸要求：`sidecars = []` 時，`aws_ecs_task_definition.this.container_definitions` 跟加這個變數之前完全相同**：`jsondecode` 後長度是 1、主 container 沒有 `dependsOn` 欄位，而且既有的 `ecs-service` 測試檔一行都不改就全部通過。另外：一個 sidecar 時長度是 2、順序是 `app` 在前；sidecar 的 `logConfiguration` 用同一個 log group、`awslogs-stream-prefix` 是 sidecar 名稱（或 `log_stream_prefix`）；有 `app_depends_on = "START"` 時主 container 才有 `dependsOn = [{ containerName = <sidecar>, condition = "START" }]`；sidecar 的 `secrets` 轉成 `valueFrom` | sidecar 名稱是 `app` 或重複；sidecar 映像用 `:latest`；`app_depends_on = "READY"`；`app_depends_on = "HEALTHY"` 卻沒有 `health_check`；sidecar 的 port 跟主 container 撞號；secret 不是 ARN |

`modules/vpc/tests/endpoints.tftest.hcl` 拆分後的去向：

| run | 去向 | 說明 |
|---|---|---|
| `s3_gateway_by_default`、`gateway_endpoint_ec2_fails`、`gateway_endpoint_s3_and_dynamodb_pass` | 留在 `vpc` | gateway endpoint 留在 `vpc` |
| `no_flow_log_by_default`、`flow_log_to_s3`、`flow_log_cloudwatch_arn_fails`、`flow_log_bad_traffic_type_fails`、`flow_log_accept_passes` | 留在 `vpc` | flow log 留在 `vpc` |
| `no_interface_endpoints_by_default` | 搬到 `vpc-interface-endpoints`，改寫 | 改成 `services = []` 時不建任何資源、`security_group_id = null`；原本斷言的 `output.vpce_security_group_id` 已經不存在 |
| `interface_endpoints_in_tier` | 搬到 `vpc-interface-endpoints`，改寫 | subnet 改由 `subnet_ids` 直接給，斷言改成「endpoint 的 subnet 等於輸入」；443 規則的 CIDR 改成來自 `allowed_cidrs` |
| `interface_service_with_region_prefix_fails`、`interface_service_short_name_passes` | 搬到 `vpc-interface-endpoints` | `expect_failures` 從 `var.interface_endpoints` 改成 `var.services` |
| `interface_tier_missing_fails`、`interface_tier_public_fails`、`interface_tier_isolated_passes` | 從 `vpc` 刪除 | module 不再有 tier 的概念（呼叫端直接給 subnet）。同樣的檢查搬到範本 network stack 的測試：`interface_endpoints.subnet_tier` 不存在或是 public 時被擋、是 isolated 時通過 |

`vpc` 另外要拿掉 `main.tf` 裡 `interface_endpoints.subnet_tier` 的 precondition、`variables.tf` 的 `interface_endpoints`、`outputs.tf` 的 `vpce_security_group_id`，`endpoints.tf` 只留 gateway endpoint。

範本 stack 的測試要用 `override_data` 餵 `ssm-read` 裡的 `data.aws_ssm_parameter`（target 寫成 `module.in.data.aws_ssm_parameter.this["<stack>/<key>"]`），否則 mock 產生的隨機字串會被下游的 ARN validation 擋掉。IAM 的最小權限測試分兩層：`iam-role`、`iam-role-policy` module 鎖「沒有萬用動作、沒有 managed policy」；範本的 `iam-base`、`iam-app` 鎖「Resource 恰為該給的 ARN、execution role 沒有 DB secret 權限」（§5.4）。「只有兩個 IAM module 建 IAM」「SG 只在 `security-group` 與 `vpc`」由 S4 保證，因為 `terraform test` 無法列舉資源型別。範本另外要測：`network` 在 `alb_ingress.https = false` 且 `cidrs` 含 `0.0.0.0/0` 時被擋；`vpc` 與 `existing` 同時給時被擋；`loadbalancer` 在 `alb_https` 與 `certificate_arn` 不一致時被擋；`data` 在 `db_proxy` 為 false 時不傳 `proxy`。

範例 tfvars 的驗證方式：`scripts/validate.sh` 對有 `envs/examples/` 的 stack（~~`network`、`data`、`loadbalancer`~~ 現況是 `network`、`data`、`agent`、`loadbalancer`、`application`，`agent` 是 Phase 14 加的，D41），除了一般的 `terraform test`，再對每個範例檔各跑一次 `terraform test -var-file=envs/examples/<x>.tfvars`。這類測試放在 `tests/examples/`（dev、prod 的 tfvars 放在 `tests/tfvars/`），用 `-test-directory` 指定，一般的 `terraform test` 不會跑到它們（Phase 0 已實測：子目錄不會被預設的 `terraform test` 掃到）。測試直接吃範例檔的值，不在 `tests/*.tftest.hcl` 裡再複製一份 `variables {}`：複製一份的話，範例檔改了測試不會跟著變，等於沒驗到範例。這要求這幾個 stack 的測試檔不在 `variables {}` 寫死會蓋掉範例值的變數（`-var-file` 的值會被測試檔的 `variables {}` 覆蓋），斷言也要寫成對任何合法輸入都成立的形式（例如「`nat_mode = per_az` 時 NAT 數等於 AZ 數」，而不是「NAT 數等於 2」）。

**增補：7 個新 module 與 `rds` Data API 的測試清單**（決策 37 起；Phase 13 照這張表做，每條 validation 都要有「合法邊界值通過」的對照 run）

| module | run（plan，除非另註） | `expect_failures`（反向：通過的那一側寫在括號裡） |
|---|---|---|
| `bedrock-guardrail` | 預設 tier 是 `STANDARD`，`content_policy_config` 與 `topic_policy_config` 兩塊都有 `tier_config = [{ tier_name = "STANDARD" }]`；`cross_region_config.guardrail_profile_identifier` 等於由 `override_data` 的 partition、region、account 組成的 ARN；明寫 `CLASSIC` 時兩塊的 tier 都是 `CLASSIC`、沒有 `cross_region_config`；只有 `words` 時只有 `word_policy_config`，其他 policy 區塊都不存在；`denied_topics` 為空時沒有 `topic_policy_config`；`version` 輸出是 `DRAFT`；`PROMPT_ATTACK` 的 `output_strength = "NONE"` 照輸入 | 名稱 51 字或含空白（50 字通過）；`STANDARD` 沒給 profile（給了通過）；`CLASSIC` 給了 profile（null 通過）；profile id 格式錯（`apac.guardrail.v1:0` 通過）；31 個 topic（30 個通過）；全部 policy 都空（只有一個 word、只有一個 managed word list、只有 grounding 各自通過；`expect_failures` 指向 `aws_bedrock_guardrail.this` 的 precondition，D30）；managed word list 給 `PROFANITY` 以外的值；`contextual_grounding` 兩個門檻都是 null（D30）；strength 給 `EXTREME`；content filter key 給 `SPAM`；`PROMPT_ATTACK` 的 `output_strength = "HIGH"`；PII action 給 `MASK`；grounding 門檻 1.0（0.99 通過）；tier 給 `PREMIUM` |
| `bedrock-inference-profile` | 每個 `profiles` 一個 profile，名稱 `<name_prefix>-<key>`、`model_source.copy_from` 照輸入；`profiles = {}` 時 0 個；`foundation-model` 與 `inference-profile` 兩種 ARN 都通過 | `copy_from` 不是 ARN、是 `provisioned-model` 或 application inference profile 的 ARN；名稱 65 字（64 字通過）；名稱含不允許的字元或連續兩個 `-`（D31） |
| `agentcore-runtime` | `network_mode = "VPC"`，subnet 與 SG 照輸入；`mode = "PUBLIC"` 時沒有 `network_mode_config`；`lifecycle_configuration` 兩欄都有、預設 900／28800；**只覆寫 `idle_session_timeout` 時 `max_lifetime` 仍是 28800**（這條是 project-a 那個 PUT 坑的迴歸測試）；`jwt_authorizer = null` 時沒有 `authorizer_configuration`；`request_header_allowlist` 為空時沒有那個區塊；`container_uri` 照輸入、沒有 `ignore_changes`（grep，不是 run） | 名稱含 `-`（底線通過）、49 字（48 字通過）、數字開頭；`:latest`（明確 tag 與 digest 都通過）；不是 ECR 的 URI；`idle_session_timeout` 59 或 1209601（60、1209600 通過）；`idle > max_lifetime`；`role_arn` 帶 path 或不是 role；`VPC` 只給 1 個 subnet 或 subnet 重複（2 個通過）；`VPC` 沒給 SG、6 個 SG（5 個通過）；`PUBLIC` 卻給了 subnet；`mode = "PRIVATE"`；`protocol = "GRPC"`；JWT 的 `discovery_url` 是 http 或少了 well-known 結尾；JWT 的 audience 與 clients 都是空的 |
| `agentcore-memory` | `event_expiry_duration` 照輸入、預設 90；`strategies = {}` 時 0 個 strategy；每個 strategy 的 `memory_id` 等於 Memory 的 id、`name` 等於 key、`type` 照輸入、`namespace_templates` 等於輸入的 `namespaces`（D33）、沒有 `configuration` | ~~`event_expiry_days` 2 或 366（3、365 通過）、2.5~~ 已被 D33 取代：`event_expiry_days` 2、3、6 或 366（7、365 通過）、2.5、範圍內的小數；strategy 型別給 `CUSTOM`；`namespaces` 為空或不以 `/` 開頭；名稱含 `-`；strategy 的 key 含 `-` 或 49 字（48 字通過） |
| `agentcore-gateway` | `protocol_type = "MCP"`；`AWS_IAM` 時沒有 `authorizer_configuration`；`CUSTOM_JWT` 時有 `discovery_url` 與 audience；Lambda target 的 `lambda_arn` 照輸入、有 `credential_provider_configuration.gateway_iam_role`；`tools` 寫法產生 `inline_payload`，每個 property 一個 `property` block；`tool_schema_s3_uri` 寫法產生 `tool_schema.s3.uri`、沒有 `inline_payload`；MCP server target 的 `endpoint` 照輸入、沒有 credential 區塊；`targets = {}` 時 0 個 target；`mcp.search_type = null` 時不送 | `authorizer.type = "NONE"`；`CUSTOM_JWT` 沒有 `discovery_url`；`AWS_IAM` 給了 `discovery_url`；target 型別 `open_api`；Lambda target 沒給 `lambda_arn`；Lambda target 同時給 `tools` 與 `tool_schema_s3_uri`、或兩個都沒給（各給一個都通過）；MCP server target 給了 `lambda_arn`；`endpoint` 是 http；`tool_schema_s3_uri` 不是 `s3://` 或沒有 key；property 型別給 `date`；同一個 target 兩個工具同名（不同 target 同名通過）；另外 D34 補的：gateway 名稱或 target key 含 `--`、101 字（100 字通過）；`lambda_arn` 不是 function ARN；Lambda target 給了 `endpoint`；`tools = []`；工具 `description` 是空字串；`role_arn` 帶 path |
| `log-delivery` | 每個 source／destination／delivery 一個資源；XRAY destination 的 `delivery_destination_type = "XRAY"` 且沒有 `delivery_destination_configuration`；CWL destination 只有 `destination_resource_arn`；delivery 的 `delivery_source_name` 與 `delivery_destination_arn` 對到正確的 key；三個 map 都空時什麼都不建；`replace_triggered_by` 存在（grep，不是 run；實作指向 `terraform_data.source_arn[each.key].output`，D35）；source 與 destination 的 tag 帶 `Name` | delivery 指向不存在的 source 或 destination；XRAY 給了 `resource_arn`；CWL 沒給或給了 S3 ARN；`log_type = "ACCESS_LOGS"`；destination `type = "FIREHOSE"`；名稱 61 字（60 字通過） |
| `bedrock-knowledge-base` | `knowledge_base_configuration.type = "VECTOR"`、`storage_configuration.type = "RDS"`；`rds_configuration` 的五個欄位照輸入；`field_mapping` 沒給時是 `id`／`embedding`／`chunks`／`metadata`、沒有 `custom_metadata_field`；`dimensions` 照輸入；每個 `data_sources` 一個 data source，`type = "S3"`、`bucket_arn`、`inclusion_prefixes` 照輸入、`data_deletion_policy` 預設 `RETAIN`；`chunking.strategy = "NONE"` 時沒有 `fixed_size_chunking_configuration`；`kms_key_arn` 有給時每個 data source 都有 `server_side_encryption_configuration`（D36） | `cluster_arn` 是 `:db:` 的 instance ARN（`:cluster:` 通過）；`table_name` 含大寫、雙引號或三段；兩個欄位同名；欄位名含 `-`；`embedding_dimensions` 0 或 1.5；`embedding_model_arn` 是 inference profile；`overlap_percentage` 0 或 100（1、99 通過）；`max_tokens = 0`；`strategy = "SEMANTIC"`；`data_deletion_policy = "PURGE"`；prefix 以 `/` 開頭；另外 D36 補的：`role_arn` 不是 role；data source 的 key 不符合名稱規則；`bucket_arn` 帶物件路徑；`database_name` 含大寫；`credentials_secret_arn` 不是 secret ARN |
| `rds`（Data API） | **既有 5 個測試檔一行不改全部通過**；新檔 `tests/data-api.tftest.hcl`：預設時 `aws_rds_cluster.this[0].enable_http_endpoint == false`（`aurora` 與 `aurora_serverless` 各一）；`data_api = true` 時是 `true` | `deployment = "rds"` 配 `data_api = true`（`aurora` 配 `true` 通過） |
| `rds`（新輸出，決策 52） | 新檔 `tests/deployment-outputs.tftest.hcl`：三種型態各一個 run，`output.deployment` 等於輸入的 `deployment`、`output.database_name` 等於輸入的 `database_name`；改一個非預設的 `database_name`（例如 `kb`）時輸出跟著變（不能只測預設值，否則寫死也會過） | 沒有新 validation |
| `s3-bucket`（不過期，決策 51） | **既有 `tests/s3-bucket.tftest.hcl` 一行不改全部通過**（含 `lifecycle_defaults` 的 90 天與 `expiration_*` 的四個邊界）；新檔 `tests/never-expire.tftest.hcl`：`never_expire = true` 時 rule 沒有 `expiration` 區塊、`abort_incomplete_multipart_upload` 仍是 7 天、rule id 是 `abort-incomplete-uploads`、`status = "Enabled"`；預設時 rule id 是 `expire-objects`、`expiration.days == 90`；明寫 `expiration_days = null` 時是 90（不是不過期）；`never_expire = null` 時當成 `false`（`nullable = false`），`expiration.days == 90`；`never_expire = false` 配 `expiration_days = 30` 時是 30 | `never_expire = true` 配 `expiration_days = 30` 被擋（`expect_failures = [var.never_expire]`；`never_expire = true` 不給天數通過、`never_expire = false` 配 30 通過）；`expiration_days = 0` 仍被擋（既有 run 涵蓋） |

這 7 個 module 不得有任何 `aws_iam_*`（S4），整個 repo 不得有 `aws_bedrock_guardrail_version`（S9），這兩條由 `validate.sh` 擋，不寫成 run。

`s3-bucket` 的反向驗證：暫時讓 `never_expire = true` 也送 `expiration`，不過期的 run 要紅；暫時拿掉互斥 validation，`never_expire_rejects_expiration_days` 要紅；暫時把 `coalesce` 拿掉（null 直接傳給 `days`），明寫 null 的 run 要紅。`rds` 的反向驗證：暫時把 `deployment` 輸出寫死 `"aurora"`，`rds` 型態的 run 要紅。

**增補：範本 Phase 14 的測試**（已實作，D41；下表是各 stack 這次新增的 run，名稱照程式碼。implement-process Phase 14 計畫裡的單一 run 多半拆成「被擋」與「通過」兩個 run，下表以實作為準）

| stack | 新增的 run | 鎖住什麼 |
|---|---|---|
| `containerimage` | `agent_runtimes_default_empty`、`agent_runtime_repository_is_created`、`agent_runtime_name_clash_with_service`、`agent_runtime_name_clash_with_mirror`、`agent_runtime_repository_clash_with_service`、`agent_runtime_without_clash_passes`、`agent_runtime_name_not_kebab_case_rejected`、`agent_runtime_name_too_long`、`agent_runtime_name_at_limit_passes`；`tests/tfvars/` 的 `tfvars_create_one_repository_per_runtime` | 預設不建、發布 `[]`；撞名三種與 48 字上限的兩個方向 |
| `network` | `agent_runtimes_default_empty`、`agent_sg_rules_expand`、`agent_data_access_through_proxy`、`publishes_agent_data_access`、`agent_runtimes_must_match_containerimage_extra_rejected`、`agent_runtimes_must_match_containerimage_missing_rejected`、`agent_runtimes_matching_containerimage_passes`、`agent_data_access_unknown_store_rejected`、`agent_sg_key_clash_with_service_rejected`、`control_plane_endpoint_rejected`、`data_plane_endpoint_passes` | 443 egress 與 `data_access` 展開後的規則 key（有 Proxy 時連 Proxy）；清單一致；拒收 `bedrock-agentcore-control` |
| `iam-base` | `agent_roles_absent_by_default`、`agent_runtime_execution_role`、`agent_service_roles_trust_only`、`agent_service_role_only_listed`、`agent_service_role_unknown_rejected`、`publishes_agent_role_arns`；`tests/tfvars/` 的 `tfvars_agent_service_roles_are_known`；既有的 `wildcard_resource_allowlist` 涵蓋 Runtime role 的 `ecr:GetAuthorizationToken` | §5.4 增補表的 `iam-base` 三列 |
| `data` | `data_api_off_by_default`、`data_api_passed_and_published`、`database_json_from_rds_outputs`、`cluster_arn_null_for_rds`；`tests/tfvars/` 的 `tfvars_publish_the_data_api_switch` | `data_api` 傳給 `rds` 並發布；`deployment`、`name` 取 module 輸出（決策 52）；`rds` 型態的 `cluster_arn` 是 `null` |
| `agent`（新，86 個加 tfvars 1 個、examples 4 個） | 讀取與發布：`reads_only_listed_keys`、`reads_runtime_keys`、`publishes_under_stack_path`、`nothing_by_default`、`publishes_agent_keys`、`runtime_json_shape`、`guardrails_json`、`memory_named_and_published`、`gateway_wiring_and_json`、`publishes_kb_bucket_and_secret`。Runtime：`runtime_wired_from_upstream`、`public_runtime_is_explicit`、`runtime_defaults_to_vpc`、`runtime_image_tag_latest_rejected`、`runtime_network_mode_unknown_rejected`、`runtime_public_tier_rejected`、`runtime_other_tier_passes`、`runtimes_must_match_containerimage_extra_rejected`、`runtimes_must_match_containerimage_missing_rejected`、`runtime_references_unknown_model_rejected`、`runtime_gateway_without_gateway_rejected`、`runtime_env_only_from_ssm_and_stack`、`runtime_env_without_data_access_has_no_db`、`runtime_env_trace_content_override`、`runtime_env_template_name_rejected`、`runtime_env_db_name_rejected`、`runtime_tracing_env_and_delivery`、`runtime_untraced_has_logs_only`。模型與 guardrail、Memory：`invoke_arns_shapes`、`tracked_on_demand_model_copies_the_foundation_model`、`model_id_with_region_prefix_rejected`、`model_key_not_kebab_case_rejected`、`model_prefix_invalid_rejected`、`guardrail_defaults_standard`、`guardrail_key_not_kebab_case_rejected`、`memory_expiry_below_seven_rejected`、`memory_expiry_above_365_rejected`、`memory_expiry_at_365_passes`、`memory_name_too_long_rejected`。沒有 NAT：`nat_none_requires_bedrock_runtime`、`nat_none_requires_bedrock_agentcore`、`nat_none_with_endpoints_passes`、`nat_external_is_not_checked`、`nat_none_public_runtime_is_not_checked`、`nat_none_tracing_requires_xray`、`nat_none_cross_account_requires_sts`、`nat_none_knowledge_base_requires_agent_runtime_endpoint`、`nat_none_db_runtime_requires_secretsmanager`、`nat_none_db_runtime_with_secretsmanager_passes`、`nat_none_blocks_gateway`、`gateway_with_nat_passes`、`gateway_needs_its_service_role`。KB：`kb_corpus_bucket`、`kb_corpus_bucket_name_too_long`、`kb_corpus_bucket_name_at_limit_passes`、`kb_requires_aurora_data_api_rds_rejected`、`kb_requires_aurora_data_api_off_rejected`、`kb_requires_a_database`、`kb_requires_the_service_role`、`kb_ready_passes`、`kb_embedding_model_with_prefix_rejected`、~~`kb_secret_not_master`、`kb_secret_not_a_secret_rejected`、`kb_secret_other_region_rejected`、`kb_secret_other_account_rejected`、`kb_secret_wildcard_rejected`、`kb_secret_without_suffix_rejected`、`kb_dedicated_secret_passed_as_is`~~（決策 55 刪除，見下〈決策 55、56 的測試〉）、`knowledge_base_key_not_kebab_case_rejected`。其他：`public_runtime_without_db`、`vpc_runtime_with_db_passes`、`cross_account_session_899_rejected`、`cross_account_session_900_passes`、`cross_account_with_tracked_model_rejected`、`cross_account_role_in_this_account_rejected`，以及每個 stack 都有的 `common.tf`／`providers.tf` 檢查（`env_format_*`、`project_format_rejected`、`account_*`、`deploy_role_*`）。`tests/tfvars/` 的 `tfvars_create_what_they_list`；`tests/examples/` 的 `example_creates_the_runtimes`、`example_keeps_message_content_out_of_traces`、`example_models_never_pin_the_foundation_model_region`、`example_corpus_buckets_never_expire` | §5.3〈增補：`agent` stack〉的每一條 precondition 與 validation 兩個方向；環境變數只來自 SSM 與本 stack；`invoke_arns` 的三種形狀；預設什麼都不建、只發布空的 JSON |
| `iam-app` | `agent_default_no_change`、`runtime_execution_permissions_exact`、`guardrail_profile_region_star`、~~`runtime_without_permissions_gets_no_policy`~~（決策 56 改成 `runtime_without_permissions_gets_only_metrics`）、`untraced_runtime_has_no_xray`、`cross_account_assumes_role_instead_of_invoking`、`same_account_invokes_models`、`kb_role_does_not_read_master_secret`、`kb_role_reads_only_own_corpus_bucket`、`gateway_role_invokes_lambda_targets`（含 `ReadToolSchemas`）、`kb_secret_wildcard_from_ssm_rejected`、`gateway_without_lambda_gets_no_policy`、`service_agent_permissions`、`agent_access_unknown_service_rejected`、`agent_access_unknown_runtime_rejected`、`agent_access_unknown_model_rejected`、`agent_access_known_passes`；`tests/tfvars/` 的 `tfvars_agent_access_names_known_services`；既有的 `wildcard_resource_allowlist` 改成允許 `xray:PutSpans` 只出現在開了追蹤的 Runtime | §5.4 增補表的 `iam-app` 各列 |
| `application` | `no_agent_access_no_change`、`agent_env_injected`、`agent_env_cross_account`、`nat_none_runtime_requires_bedrock_agentcore`、`nat_none_model_requires_bedrock_runtime`、`nat_none_guardrail_requires_bedrock_runtime`、`nat_none_knowledge_base_requires_agent_runtime_endpoint`、`nat_none_cross_account_requires_sts`、`nat_none_with_agent_endpoints_passes`、`nat_external_agent_endpoints_not_checked` | `agent_access = {}` 時 task definition 不變；有列的服務才注入；沒有 NAT 時的 endpoint 要求 |

**增補：決策 55、56 的測試**（`59f647b`～`8b840ea`，名稱照程式碼；module 這一輪共新增 111 個 run，逐條見各 module 的 `tests/`）

| 對象 | 新增或改名的 run | 鎖住什麼 |
|---|---|---|
| `agent` | `kb_secret_created_per_knowledge_base`、`kb_database_user_not_ready_creates_only_the_secret`、`kb_uses_the_secret_it_created`、`kb_secret_has_no_value`、`runtime_with_knowledge_base_not_ready_rejected`、`runtime_with_knowledge_base_ready_gets_its_id`、`runtime_workload_identity_published`；`publishes_kb_bucket_and_secret` 改成斷言 `ready` 與 `null` 的 id。總數仍是 86 個（刪 7 個 `kb_secret_*`，加 7 個） | 每個 KB 一個 secret、用專案 key、沒有 secret version；`database_user_ready = false` 只建 secret 與 bucket；KB 用的就是自己建的 secret（master secret 結構上填不進來）；Runtime 不能用還沒 ready 的 KB |
| `iam-app` | `agent_access_rejects_knowledge_base_not_ready`、`workload_identity_grants_access_token`、`workload_identity_false_grants_no_access_token`、`runtime_without_permissions_gets_only_metrics`；既有 KB role 的 run 加斷言 `kms:EncryptionContext:SecretARN` 與 `aws:ResourceAccount` | `agent_access` 不能列 `ready = false` 的 KB；workload identity 兩個方向；每個 Runtime 都有帶 namespace 條件的 `PutMetricData` |
| `iam-base` | `agent_role_source_arn_follows_region` | 三種服務角色的 `aws:SourceArn` 形狀跟著 region |
| `network` | `agent_egress_vpc_only_without_nat`、`agent_egress_internet_in_existing_mode` | `nat.mode = "none"` 時 Runtime 的 443 只到 VPC CIDR；模式 A 仍是 `0.0.0.0/0` |
| 9 個 module（`iam-role` 5、`s3-bucket` 4、`agentcore-gateway` 19、`agentcore-runtime` 35、`log-delivery` 11、`bedrock-knowledge-base` 20、`bedrock-inference-profile` 6、`bedrock-guardrail` 7、`agentcore-memory` 4） | 新檔 `tests/security.tftest.hcl`（gateway、runtime、log-delivery）、`modules/s3-bucket/tests/never-expire.tftest.hcl` 加 run，其餘加在既有檔 | §4.23〈安全補強〉表的每一條，兩個方向；`allowed_account_ids` 列了別的帳號就放行；`iam-role` 的 `source_account_only_policy_unchanged` 固定沒給 `source_arn` 時的整段 trust JSON |

反向驗證（mutation）：主 agent 對每一條 MEDIUM 以上的修正做過「暫時拿掉檢查、對應 run 要紅」；LOW 的項目（L1–L5）照使用者決定沒有做（implement-process Phase 17）。

`run` 的 `command`：預設用 `plan`。**只有在宣告了 `mock_provider "aws"` 的測試檔裡，才可以用 `command = apply`**（mock 下的 apply 不碰 AWS，用來讓 `arn`、`id` 這類 computed 值有假值可以斷言）。`scripts/validate.sh` 已經檢查每個測試檔都有 `mock_provider "aws"`，所以這條由同一個檢查保證。

tflint 的 aws ruleset（`tflint-ruleset-aws`，能抓到不存在的 instance type 這類錯）要 `tflint --init` 從 GitHub 下載 plugin，第一版不用，列為下一版。

本機工具：terraform 1.15.8、tflint 0.64.0。本機沒有 terraform-docs、pre-commit、release-please、trivy、checkov；這些只提供設定檔，驗收不依賴它們，README 的輸入／輸出表先手寫。

### 7.2 驗不到的

| 驗不到 | 為什麼 | 實際風險 |
|---|---|---|
| IAM 實際權限 | mock 不評估 policy | execution role 少一條權限，task 起不來或拉不到 secret |
| AWS API 的參數檢查 | mock 不呼叫 API | 例如 Fargate 某些 CPU／記憶體組合在特定 region 不支援、listener rule priority 撞號 |
| 資源配額 | 同上 | ECS service、target group、告警數量的帳號上限 |
| apply 的順序與時序 | 只有真的 apply 才會遇到 | target group 要先掛上 listener 才能給 ECS service 用；`create_before_destroy` 在 target group 改 port 時是否如預期 |
| CloudWatch 指標維度 | mock 不檢查指標名稱與維度 | 告警建得起來，但永遠沒有資料（例如 service 層 Container Insights 指標的維度不對） |
| SNS＋KMS＋CloudWatch 的組合 | 需要真的發布一則訊息 | 告警觸發了，訊息因為 key policy 被丟掉 |
| `ignore_changes` 與 autoscaling 的互動 | 要真的擴縮 | — |
| RDS 型態互換 | mock 不模擬 replace 的實際行為 | `aurora` ↔ `aurora_serverless` 預期就地修改、`rds` ↔ Aurora 預期 destroy＋create，都要實測 |
| Proxy 建立時的權限 | mock 不呼叫 RDS API | 建立失敗或建立成功但連不上（§5.4） |
| KMS key policy 的服務條件 | mock 不評估 key policy | 某個服務不支援範本給的條件 key，加密或解密失敗 |
| VPC endpoint 的 private DNS、NAT 路由 | 要真的有網路流量 | task 拉不到映像、呼叫不到 Secrets Manager |

### 7.3 之後有 AWS 環境時要補的

本 repo 是範例，不部署到 AWS（2026-10-15 決定）。下面這份清單不會在本 repo 執行，留給照這個範例建立、實際部署的 repo 當驗證清單。

1. 在沙箱帳號用範本 PoC 規格跑完 ~~八個~~ 九個 stack（Phase 14 加 `agent`，預設什麼都不建）的 apply，再 destroy（反序；`deletion_protection` 要先關）。
2. **Proxy 建立時的權限**：在 `iam-app` 還沒附加 policy 前建立 Proxy，記錄是建立失敗，還是建立成功但連線失敗；依結果選 §5.4 表裡的對策，寫進 `infra/README.md`。
3. **RDS 型態互換**：`aurora` ↔ `aurora_serverless` 確認 plan 只有就地修改、實際停機多久；`rds` → `aurora` 確認 plan 是 replace 且被 `deletion_protection` 擋下。
4. **Serverless v2 的 0 ACU**：`min_capacity = 0` 在範本選的 engine 版本能不能 apply、閒置多久會暫停、恢復要多久、恢復期間應用程式看到什麼錯誤。
5. 對 `ecs-service` 跑真實請求，確認：task 用 task role 能讀到 DB secret、經 Proxy 與不經 Proxy 都連得上、log 有進 log group、ECS Exec 在開的服務能進去、私有 subnet 經 NAT 或 VPC endpoint 拉得到映像。
6. Enhanced Monitoring 的 inline policy 是否足夠（`RDSOSMetrics` 有資料）。
7. ALB：沒有憑證時 SG 只對指定來源開 80，其他來源連不上；有憑證時 80 回 301；access log 確實寫進 SSE-S3 bucket；flow log 寫進 S3。
8. 手動把一個告警設成 ALARM（`aws cloudwatch set-alarm-state`），確認 email 收得到，包括 KMS 加密的 topic。
9. 確認 `ecs-service-alarms`、`alb`、`rds` 每個告警在 CloudWatch 上有資料點（不是 INSUFFICIENT_DATA）。
10. 改 `container_port` 跑一次，確認 target group 的 `create_before_destroy` 換得過去。
11. AZ 從 2 個加到 3 個，確認下游 stack 只要重新 apply、程式碼不用改（§5.6）。
12. **KMS key policy**：CloudWatch Logs、CloudWatch 告警發布到加密的 SNS、ECR、Secrets Manager 用 `kms-key` 建的 key 都正常；`s3-bucket` 的 ALB access log 在舊 region（`ap-northeast-1`）寫得進去。
13. **X-Ray 抽樣**：用 ADOT sidecar（或 X-Ray SDK）的 remote sampling 確認 `xray` 建的 sampling rule 真的生效（health check 不再進 trace、`fixed_rate` 接近設定值）；確認 SDK 端固定比例抽樣（project-a 的做法）不受 rule 影響；確認 `log-metric-alarm` 的告警在印出事件後一分鐘內轉 ALARM、且 email 收得到；確認範本接好的 collector（`application/adot-collector.yaml`、`/healthcheck` 與 `health_check` extension、`essential = false`）在真實 task 裡 healthy 且 X-Ray console 看得到 trace；沒有 NAT 的 VPC 用 mirror 映像加 `ecr.api`、`ecr.dkr`、`xray` endpoint 與 S3 gateway endpoint 真的拉得到映像、送得出 trace；`v0.43.1` 這個 tag 在 ECR Public 上存在。
14. 把 module 版本從 v0.x 升到 v1.0.0（見 §3.5）。

增補（決策 37 起）。下面每一項都對應到文中某個標了「未實測」或「未驗證」的地方；同樣只留給實際部署的 repo：

15. **guardrail**：`STANDARD` 加 `cross_region_config` 對中文輸入真的會擋、`CLASSIC` 不擋（重現 project-a 的實測）；寫錯的 profile id 在 apply 時成功、第一次 `ApplyGuardrail` 才失敗；`ApplyGuardrail` 在沒有 NAT 時走 `bedrock-runtime` endpoint 呼叫得到；guardrail profile 的 IAM 用 region `*` 時不會間歇失敗；module 的名稱、profile id、PII action、grounding 門檻、「至少一種 policy」這幾條 validation 跟 API 的實際規則一致。
16. **Runtime 建立時的權限**：execution role 只有 trust、ECR、log 時 `CreateAgentRuntime` 是否成功；`iam-app` apply 之後第一次 invoke 是否就能呼叫模型、Memory、guardrail（§5.4 增補）。
17. **AgentCore 的 VPC 模式**：Runtime 拉映像走服務端還是 VPC 裡的 ENI；沒有 NAT 時只靠 S3 gateway endpoint、`bedrock-runtime`、`bedrock-agentcore` endpoint 能不能拉到映像、呼叫到模型與 Memory；VPC 模式是否限定特定 AZ ID；每個 Runtime 用掉多少 ENI 與 IP（project-a 為此把 app subnet 切到 `/19`，§5.11），把結果補進 §5.11 的 IP 規劃公式。
18. **名稱與列舉值**：Runtime、Memory、Gateway、target、KB、log delivery 的名稱規則與長度；Runtime 的 `protocol`、Memory strategy 的 `type`、log delivery 的 `log_type` 允許值；Runtime 的 `idle_session_timeout <= max_lifetime`；inference profile 名稱的字元規則（D31）；Gateway `mcp.search_type` 的允許值（module 不檢查，D34）；Runtime 的 `environment_variables` 送 `{}` 時讀回來是不是 null、會不會每次 plan 都有差異（module 目前改送 null，這是推測，D32）。Memory 保留天數的下限已由 provider 6.69.0 確定是 7（D33），不用再測。module 的 validation 比 AWS 寬時會在 apply 才失敗，比 AWS 窄時會擋掉合法的輸入，兩種都要在第一次部署時記下來改。
19. **log-delivery**：CWL 目的地的 log group resource policy 由 CloudWatch 自動加（部署者有 `logs:PutResourcePolicy` 時）；Runtime 的 `APPLICATION_LOGS` 與 `TRACES` 真的進 log group 與 X-Ray；Runtime 重建時 `replace_triggered_by` 讓 delivery 一起替換、沒有 `ConflictException`；trace 需要帳號層的 Transaction Search（`aws/spans` log group），被清掉時 span 全部遺失且不報錯（`project-a/docs/runbook/runbook-agentcore.md:276`），guide 要寫檢查方式；範本給 Runtime 的六個 `OTEL_*` 環境變數（D38，traces 直送 `https://xray.<region>.amazonaws.com/v1/traces`、metrics 與 logs exporter 是 `none`）真的送得出 trace；Runtime execution role 的 log 權限（`CreateLogGroup`、`DescribeLogStreams` 在 log group，`CreateLogStream`、`PutLogEvents` 在 log stream，D40）是否足夠。
20. **Gateway**：Lambda target 用 `gateway_iam_role` 呼叫 Lambda（project-b 沒有實際用過）；**MCP server target 不帶 credential provider 時 AWS 收不收**；扁平的 `tools` 產生的 inline schema 被 Gateway 接受，包括 `properties` 是空 map 時只送 `input_schema { type = "object" }`、`type = "array"`／`"object"` 的屬性不帶 `items`／`properties`（D34）；Runtime 在 VPC 裡呼叫 Gateway 需要哪個 interface endpoint 服務名稱（查證之前 `agent` 在沒有 NAT 時擋下 Gateway，J57）；Gateway role 只有 `tool_schema_arns` 的 `s3:GetObject` 時，用 `tool_schema_s3_uri` 的 Lambda target 建得起來（D42）。
21. **Knowledge Base**：Aurora PostgreSQL 的哪些版本支援 Data API、附的 pgvector 是否 0.5.0 以上；§4.30 的 SQL（欄位型別、三個索引）是否就是 Bedrock 要的；KB 建立時是否檢查表與欄位（決定 apply 順序是否真的要先跑 migration）；KB role 的動作清單是否足夠（Data API、`DescribeDBClusters`、secret 與它的 `kms:Decrypt`、S3、嵌入模型）；**KB 專用帳號只有那張表的 `SELECT`／`INSERT`／`UPDATE`／`DELETE` 與 schema 的 `USAGE` 時，ingestion、重新同步（含刪除文件後的清除）、`Retrieve` 是否都成功**，不夠時記下錯誤訊息與缺的權限（§4.30，決策 53）；KB 的 secret 改密碼後，KB 是每次連線都讀新值還是會快取、認證失敗會持續多久；`StartIngestionJob` 用 `agent/knowledge_bases` 的 `data_source_ids` 跑完向量確實寫進表；KB role 的 `s3:ListBucket` 帶 `s3:prefix` `StringLike <prefix>*` 條件時 ingestion 列得到物件（D40）；`inclusion_prefixes` 有沒有數量上限（module 不擋，D36）；沒有 NAT 時 VPC 模式的 Runtime 經 `secretsmanager` endpoint 讀得到 DB secret（D44）；`rds` 對既有 Aurora cluster 換成 `rds-v0.2.0`、`data_api = false` 時 plan 零差異。增補（決策 55）：KB 建立時 Bedrock 會不會檢查資料庫帳號（決定 `database_user_ready` 的兩段式是否必要）；`agent` 建的 secret 沒有值時 `iam-app` 照樣能附加權限；KB role 的 `kms:Decrypt` 帶 `kms:EncryptionContext:SecretARN` 時解得開專案 key 加密的 secret（決策 56）；`agent` destroy 後重建同名 secret 撞名的實際錯誤與處理（`restore-secret` 或 `--force-delete-without-recovery`）。
22. **KMS**：guardrail、Memory、KB data source 改用 `foundation` 的專案 key 時，key policy 要給哪些 service principal 與條件（範本目前傳 `null`，J59）。
23. **跨帳號（A 側）**：A 帳號的 Runtime 與 ECS 服務用 `sts:AssumeRole` 取得 B 帳號 role、呼叫 B 帳號的模型；沒有 NAT 時 `sts` endpoint 是否足夠；`models.invoke_arns` 的 foundation-model region `*` 對 `global.` 前綴與地區前綴都成立（project-a 的實測在 B 側，A 側沒有）；`*` 是否涵蓋空 region，涵蓋的話 `global` 那條空 region 的 ARN 可以拿掉。
24. **Memory strategy**：`SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE` 不給 `memory_execution_role_arn` 能不能建、能不能產生長期記憶（三個參考專案都沒用過 strategy）。
25. **`s3-bucket-v0.1.1`**（決策 51、54）：既有的 log bucket 換成 `s3-bucket-v0.1.1`、不給 `never_expire` 時 plan 零差異；`never_expire = true` 時 lifecycle 只有 `abort_incomplete_multipart_upload` 一條、`filter {}` 的 rule AWS 接受；KB 的 data source 讀 SSE-S3 的語料 bucket 不需要額外的 bucket policy。

26. **服務角色的 `aws:SourceArn`**（決策 56）：Runtime execution role、Gateway role 用 `arn:aws:bedrock-agentcore:<region>:<account>:*`、KB role 用 `arn:aws:bedrock:<region>:<account>:knowledge-base/*`，AgentCore 與 Bedrock 實際 AssumeRole 時帶的 `aws:SourceArn` 是否落在這兩個形狀內；不符的症狀是 Runtime、Gateway、KB 建立或執行時拿不到 role。`iam-role-v0.1.1` 對沒給 `source_arn` 的既有 role plan 零差異。
27. **Runtime 的 metrics 與 workload identity**（決策 56，原 §8.8 的 L5）：`cloudwatch:PutMetricData` 帶 `cloudwatch:namespace = bedrock-agentcore` 條件時 Runtime 的指標寫得進去（namespace 名稱照 AWS 文件，**未實測**）；`workload_identity = true` 的三個 `GetWorkloadAccessToken*` 動作與 `workload-identity-directory/default` 的 Resource 是否就是 AgentCore Identity 要的；不開時 Runtime 是否照常運作。
28. **沒有 NAT 時 Runtime 的 egress 只到 VPC CIDR**（決策 56）：Runtime 經 interface endpoint 呼叫模型、Memory、X-Ray、Secrets Manager 都成功；S3 gateway endpoint 走的是 prefix list 不是 VPC CIDR，Runtime 拉映像如果走 VPC 裡的 ENI（第 17 項）會被這條擋下，要確認。

## 8. 安全考量

### 8.1 IAM 最小權限

- execution role 與 task role 分開，而且每個服務一個 task role。
- 不掛 `AmazonECSTaskExecutionRolePolicy` 這類 Resource 是 `*` 的 managed policy。只有 AWS 不支援 resource-level 的 action 例外（`ecr:GetAuthorizationToken`、ECS Exec 的 `ssmmessages:*`），寫在 policy 旁邊的註解。
- 只有 `iam-role` 與 `iam-role-policy` 兩個 module 建 IAM，兩者都不收 AWS managed policy、都會擋掉 Allow statement 裡的 `*` 與 `service:*` 動作；範本只在 `iam-base`、`iam-app` 兩個 stack 呼叫它們，權限集中審查（§5.4）。
- RDS Proxy role 在 `iam-base` 只有 trust；讀 secret 的權限由 `iam-app` 用 `iam-role-policy` 附加，Resource 恰為那一個 secret ARN，`kms:Decrypt` 收窄到單一 key 並帶 `kms:ViaService`；Enhanced Monitoring role 用 inline policy，只到 `RDSOSMetrics`。
- KMS key policy 不能對 `*` principal 開放（`kms-key` 的 validation 擋）；帳號 root 那一段是 AWS 的預設寫法，讓 IAM policy 可以授權這把 key。
- ECS Exec 預設關閉。project-c 一律開（`project-c-app/modules/app-service/ecs-standard.tf`），等於每個服務都能被有權限的人進 shell。

### 8.2 secret

- secret 的值不進 tfvars、不進 SSM `String`、不進 state。`foundation` 只建 Secrets Manager 的 secret 容器，值由人或輪替流程寫入。
- 不在 Terraform 用 `random_password` 產生 secret（值會留在 state）。
- 一般的 secret（`foundation` 的 `app_secret_arn`）用 ECS 的 `secrets`（`valueFrom`）注入，權限在 execution role。
- **DB 的 master secret 例外，由應用程式用 task role 自己讀**（project-a 的做法：`DB_SECRET_ARN` 當環境變數，程式去 Secrets Manager 取）。原因有兩個：execution role 是整個專案共用的，放進去等於每個服務都能拿到 DB 密碼；RDS 管理的 master 密碼會自動輪替，`valueFrom` 只在 task 啟動時讀一次，輪替後舊 task 會用舊密碼連線失敗，程式自己讀才能在認證失敗時重讀。
- **第一版讓應用程式直接用 master secret，這是已知風險。** master 帳號權限最大（可以改 schema、建帳號），應用程式的 SQL injection 或憑證外洩，影響的是整個資料庫。緩解：只有 `network` 的 `data_access` 名單上的服務能讀（§5.4）；開 Proxy 時應用程式拿到的密碼只用來連 Proxy。之後要補：另建應用程式專用帳號（只給需要的 schema 權限，密碼放另一個 secret），或改用 Proxy 的 IAM 認證，讓應用程式完全不碰密碼。Knowledge Base 不在這個風險裡：它一開始就用專用帳號（決策 53，§8.8）。
- `rds` module 沒有任何 password 變數，`manage_master_user_password = true` 固定；`scripts/validate.sh` 擋 `modules/rds/variables.tf` 出現名稱含 `password` 的變數與整個 `modules/` 出現 `random_password`。
- `ssm-publish` 寫的是 `insecure_value`，值會出現在 plan 輸出與 CI log，所以 SSM 只放非機密值。

### 8.3 加密

- `sns-alarm-topic` 可選 `kms_master_key_id`。用 CMK 時 key policy 要允許 `cloudwatch.amazonaws.com` 使用（`kms:Decrypt`、`kms:GenerateDataKey*`），否則告警發布會失敗；AWS managed key `alias/aws/sns` 不能用，validation 擋掉。
- `ecs-cluster`、`ecs-service` 的 log group 可選 `log_kms_key_arn`；key policy 要允許 `logs.<region>.amazonaws.com`。
- 範本的 `foundation` 建一把專案共用 CMK，key policy 同時給 CloudWatch 與 CloudWatch Logs。
- `rds` 的 storage 一律加密（`storage_encrypted = true`），可選 CMK；master secret 可選另一把 CMK（`master_user_secret_kms_key_arn`），範本用 `foundation` 的 key。
- **ALB access log 的 bucket 只能用 SSE-S3**，不能用 CMK：ALB 的 log delivery 不支援 customer managed KMS，設了 log 會無聲遺失（`project-a/infra-v2/terraform/loadbalancer/access-logs.tf`）。flow log 的 bucket 第一版也用 SSE-S3。兩個 bucket 都開 Block Public Access，bucket policy 只允許對應的 log delivery principal，條件帶本帳號。

### 8.4 網路入口

- ALB 有憑證時開 443，80 一律 301 轉到 HTTPS，TLS policy 固定 `ELBSecurityPolicy-TLS13-1-2-2021-06`。
- **ALB 沒有憑證時允許只開 HTTP，但 SG 要收窄**：`network` 的 validation 不准 `alb_ingress.cidrs` 含 `0.0.0.0/0`，只能開給 CloudFront 的 managed prefix list（`com.amazonaws.global.cloudfront.origin-facing`）或指定的 CIDR。明文 HTTP 對全網開放，等於讓任何人能在路上看到或改掉請求內容。`loadbalancer` 再用 precondition 確認 `alb_https` 跟 `certificate_arn` 一致，避免 SG 以為有 HTTPS、ALB 實際只開 HTTP。
- `drop_invalid_header_fields = true`；預設 action 回 404，只有 `ecs-service` 建的 listener rule 會轉發。
- DB 與 Proxy 只接受指定服務 SG 的連線（§5.3 規則表），`publicly_accessible = false` 固定；`data` tier 預設是 isolated，沒有對外路由。
- VPC 的 default security group 由 `vpc` module 清空規則，避免資源誤用。

### 8.5 帳號防線

- 每個 stack 的 provider 都有 `allowed_account_ids = [var.expected_account_id]`，`expected_account_id` 不給預設值，並用 `env → 帳號` 對照表 validation（§5.7）。
- 客戶自管的 stack 在該環境不放 tfbackend（§5.8）。

### 8.6 CI

- CI 不需要、也不得持有 AWS 憑證：workflow `permissions: contents: read`，不給 `id-token: write`，不用 `aws-actions/configure-aws-credentials`，不引用任何 AWS 相關 secret。
- `validate.sh` 檢查每個 `tests/*.tftest.hcl` 都宣告 `mock_provider "aws"`，避免有人寫出需要真實憑證的測試。
- 第三方 action 用 commit SHA 釘版（project-a 的 workflow 已經這樣做）。
- `release.yml` 需要 `contents: write` 打 tag，跟 `ci.yml` 分開，權限只給 release job。

### 8.7 `vendor-modules.sh` 的輸入驗證

這支腳本由 FDE 在本機執行，會寫入客戶 repo，輸入要當成不可信：

| 輸入 | 檢查 |
|---|---|
| module 名稱 | 符合 `^[a-z][a-z0-9-]*$`，且在指定 tag 的 `modules/` 底下存在 |
| tag | 符合 `^<module>-v[0-9]+\.[0-9]+\.[0-9]+$`，而且 tag 前綴跟 module 名稱一致；`git rev-parse --verify "refs/tags/<tag>^{commit}"` 要成功 |
| 目標 repo | 必須是 git repo 且工作目錄乾淨（沒有未提交變更），否則拒絕執行，避免覆蓋使用者的檔案 |
| 目的路徑 | 固定為目標 repo 的 `vendor/modules/<name>/`，不收任意路徑；寫入前確認正規化後仍在目標 repo 根目錄內 |
| 取檔方式 | 用 `git archive <tag> modules/<name>` 取出，不 checkout、不執行 module 裡的任何東西；拒絕含 symlink 的內容 |
| 改寫 source | 只改寫完全符合 `git::https://github.com/<org>/<repo>.git//modules/<name>?ref=<tag>` 的那一行，改成指向 `vendor/modules/<name>` 的相對路徑，其他不動 |
| 可追溯 | 寫 `vendor/modules/VERSIONS`，每個 module 一行：名稱、tag、commit SHA |

這支腳本只負責「`git::...?ref=<tag>` → vendored 相對路徑」這個方向（§5.1）。本 repo 範本的相對路徑改成 `git::` 是專案 app team 複製範本時的手動步驟，寫在 `docs/guides/consuming-modules.md`，不歸這支腳本。

腳本一律 `set -euo pipefail`，所有變數加引號，不用 `eval`。

### 8.8 增補：LLM 與 AgentCore（決策 37 起）

- **IAM 指向確切 ARN**：模型、Memory、guardrail、KB、Gateway、Runtime 的權限都在 `iam-app` 用 `agent` 發布的 ARN 附加，不用名稱萬用字元（§5.4 增補）。例外只有兩種 region 欄的 `*`：foundation-model（system inference profile 會跨 region 路由）與 guardrail profile（AWS 動態選 region），兩者的 id 都是確切值。`Resource = "*"` 的允許清單只多 `xray:PutSpans`，而且只給開了追蹤的 Runtime。
- **沒列的就沒有**：ECS 服務只有列在 `iam-app` 的 `agent_access` 才有任何 `bedrock`／`bedrock-agentcore` 動作；Runtime 只有它在 `agent_runtimes` 裡列的模型、Memory、guardrail、KB。
- **guardrail 預設 `STANDARD`**：`CLASSIC` 只評估英文，非英文產品等於沒有護欄，而且看起來一切正常（`status: READY`、plan 乾淨）。module 不建 guardrail 版本，S9 擋整個 repo；實際生效的永遠是 `DRAFT`，apply 的改動就是線上的政策。
- **資源與 IAM 就位不等於功能生效**：guardrail 建好、權限給了，應用程式沒有呼叫 `ApplyGuardrail` 就沒有效果（project-a 的輸出護欄就是這樣，`project-a/docs/guide/guide-data-scientist.md:262-264`）。guide 要寫「怎麼確認真的有在擋」。
- **trace 不含訊息內容**：Runtime 預設 `TRACELOOP_TRACE_CONTENT=false`（決策 49），對話內容不進 X-Ray；要開必須在 tfvars 明寫，PR 審查看得到。
- **Gateway 一定要認證**：`agentcore-gateway` 不收 `authorizer_type = "NONE"`；範本固定 `AWS_IAM`，只有列了 `gateway = true` 的 Runtime 的 execution role 能呼叫。
- **PUBLIC 模式**：Runtime 的對外連線不經過 SG 與 interface endpoint，範本只在明寫時使用，而且不能同時連資料庫（決策 42）。
- **Knowledge Base 用專用的資料庫帳號**（決策 53）：KB 經 Data API 連資料庫用的是專案 migration 建的 `bedrock_kb_user`，不是 master。它只有 KB 那張表的 `SELECT`、`INSERT`、`UPDATE`、`DELETE` 與 schema 的 `USAGE`，不是 superuser、不能建帳號與資料庫、不能在任何 schema 建物件（§4.30）。KB role 的 `secretsmanager:GetSecretValue` 只到各 KB 的 `credentials_secret_arn`，讀不到 master secret（`iam-app` 的測試鎖住）；~~`agent` 的 precondition 擋掉把 master secret 的 ARN 填進來~~ 決策 55 起 secret 由 `agent` 自己建，KB 一定用那個 secret，master secret 在結構上填不進來（測試 `kb_uses_the_secret_it_created`）。原本「KB role 拿得到最大權限的資料庫帳號、影響整個資料庫」的風險不再適用；應用程式用 master secret 的風險（§8.2）不受影響，仍然存在。
  - `rds-data:ExecuteStatement` 本身不限資料庫帳號，KB role 能跑哪些 SQL 完全由它拿得到的那個帳號決定，所以**資料庫的 GRANT 是唯一的邊界**。migration 改權限時要當成安全變更審查，不能為了排除 ingestion 錯誤改成 schema 層級的 `ALL`。
  - 剩下的風險：secret 不由 RDS 管理、沒有自動輪替，換密碼要專案自己把 `put-secret-value` 與 `ALTER ROLE` 一起做；所有 KB 共用一個 KB role，KB 之間的隔離只在資料庫層（J70）；~~secret 的容器在範本外，建立時用哪把 key、誰有權限寫入，範本管不到（§9.5 Q1）~~ 決策 55 起容器由 `agent` 建、用專案 key，剩下的是「誰有權限 `put-secret-value`」，那是部署者與專案自己的 IAM，範本不給任何 principal 寫入權限。
- **語料 bucket 不過期**（決策 51）：KB 的語料 bucket 用 `s3-bucket` 的 `never_expire = true`，文件不會被 lifecycle 刪掉。沒有 versioning，誤刪的物件救不回來，下一次同步會連帶清掉對應的向量（`data_deletion_policy = "RETAIN"` 只管刪掉 data source 的情況）。bucket 封鎖公開存取、只允許 TLS，範本不給任何 principal 寫入權限，上傳由人或 CI 用自己的權限做。
- **環境變數不是 secret 的地方**：Runtime 的環境變數在 console、API 與 state 裡都看得到。範本只放 id、ARN、URL；DB 密碼一律是 `DB_SECRET_ARN`，由 Runtime 用 execution role 自己讀。~~module 不做「值看起來像 secret」的檢查（J62）~~ 已被決策 56 取代：`agentcore-runtime` 擋名稱像 secret 的變數（以 `_ARN` 結尾、值是 ARN 的放行）；看的是名稱不是值，取個無害的名稱照樣擋不住，審查仍是主要防線。
- **控制面 endpoint 不建**：`network` 拒收 `bedrock-agentcore-control`，VPC 內的程式碼不該能改 AgentCore 的設定（project-a 的規格同樣明訂）。
- **KB secret 一定是確切 ARN**（D43）：`credentials_secret_arn` 必須是帶 6 字元後綴的完整 ARN，不准萬用字元。~~`agent` 用 validation 擋，~~`iam-app` 在授權前用同一條 regex 再擋一次（`agent` 那一道隨 tfvars 輸入在決策 55 刪除，ARN 現在是 `agent` 自己建的 resource 輸出）；少了這道，`...:secret:*` 這種值會讓 KB role 讀得到 master secret。
- **同帳號**（決策 56）：Gateway 的 Lambda target、Runtime 的 ECR 映像、log-delivery 的 source 與 `CWL` 目的地、KB 的語料 bucket 擁有者，預設都必須是目前帳號，跨帳號要在 module 的 `allowed_account_ids` 明列；KB 的 cluster 與 secret 一律同帳號同 region。範本不傳 `allowed_account_ids`。KB role 與 Gateway role 讀 S3 時帶 `aws:ResourceAccount`。
- **Runtime 的請求標頭**（決策 56）：`request_header_allowlist` 不准轉 `Cookie`、`Proxy-Authorization`、`Host`、`X-Amz-Security-Token`、`X-Amz-Date`；`Authorization` 只在有 `jwt_authorizer`（AgentCore 已經驗過 token）時可以轉進容器。
- **guardrail 的修改權限**（決策 56，L1）：`DRAFT` 改了立刻生效（決策 46 不變）。建議用 SCP 或 permission boundary 把 `bedrock:UpdateGuardrail`、`bedrock:DeleteGuardrail` 限給部署用的 role；module 與範本都不建這條限制，由帳號的擁有者做。

**已知風險，這一輪不修**（Phase 14 之後的安全審查，D46）。增補（決策 56）：這張表在 Phase 17 逐項處理完，最後一欄是結果；前三欄保留原文。

| # | 風險 | 現況 | 之後怎麼收 | 決策 56 的結果 |
|---|---|---|---|---|
| M1 | 新的服務角色（Runtime execution、KB、Gateway）的 trust 只有 `aws:SourceAccount`，沒有 `aws:SourceArn` | 同帳號內任何 Bedrock 或 AgentCore 資源都能用這些 role（confused deputy 只擋到帳號邊界） | `iam-role` 支援 `aws:SourceArn` 是 MINOR，決策 47 已延後；做了之後 `iam-base` 要等 `agent` 的 ARN，順序得重想 | **已修**（`59f647b`、`c6bb164`）：`iam-role-v0.1.1` 的 `trust.source_arn`；三種角色用帳號加 region 的萬用字元 ARN，不必等 `agent`，順序不變。ARN 形狀**未實測**（§7.3 第 26 項） |
| M4 | KB role 的 `kms:Decrypt` 沒有 `kms:EncryptionContext:SecretARN` 條件；S3 statement 沒有 `aws:ResourceAccount` | 只靠 `kms:ViaService` 與確切的 bucket ARN；縱深防禦少一層 | 加上兩個條件，Resource 不變 | **已修**（`0641431`）：`kms:Decrypt` 加 `kms:EncryptionContext:SecretARN`；語料 bucket 與工具定義的 S3 statement 加 `aws:ResourceAccount` |
| L1 | guardrail 一律用 `DRAFT`，內容可以被改 | apply 的改動立刻是線上政策，沒有版本可回退（決策 46 的取捨） | 有版本需求時另做發佈流程，S9 要一起改 | **決定維持**：仍用 `DRAFT`（決策 46 不變）；`bedrock-guardrail` 的 README 建議用 SCP 或 permission boundary 把 `UpdateGuardrail`、`DeleteGuardrail` 限給部署用的 role（`de5499a`） |
| L2 | Runtime 的 `environment` 擋不住有人把 secret 寫進去 | 值會進 state、console 與 API（J62 不做猜測式檢查） | 靠審查；guide 寫明只放 id、ARN、URL | **已修**（`0ed7943`）：`agentcore-runtime` 擋名稱像 secret 的環境變數（取代 J62）；只看名稱，審查仍要做 |
| L3 | Gateway 的 `lambda_arn` 沒有限定本帳號 | 可以指到別的帳號的 Lambda，Gateway role 就有權呼叫它 | 在 `agent` 加 validation 比對帳號 | **已修**（`f7420dd`）：改在 module 做，`agentcore-gateway` 的 precondition 要求 Lambda target 在目前帳號或 `allowed_account_ids` |
| L4 | Runtime SG 對 `0.0.0.0/0` 開 443 egress | 跟 ECS 服務的 SG 相同；資料外送只靠應用程式本身 | 沒有 NAT 的環境本來就只到 endpoint；需要時改成 prefix list 或 endpoint SG | **已修**（`7a7593d`）：`nat.mode = "none"` 時改成只到 VPC CIDR；有 NAT 與模式 A 維持 `0.0.0.0/0`（§7.3 第 28 項） |
| L5 | Runtime execution role 沒有 `bedrock-agentcore:GetWorkloadAccessToken*` 與 CloudWatch metrics 權限 | 範本不支援 AgentCore Identity；Runtime 要不要這些權限才能正常運作，**未實測** | §7.3 第 16 項實測時一起確認，需要再加 | **已加，未實測**（`0641431`、`22191ed`）：每個 Runtime 有帶 namespace 條件的 `cloudwatch:PutMetricData`；`GetWorkloadAccessToken*` 只給 `workload_identity = true` 的 Runtime（§7.3 第 27 項） |

## 9. 決策與待補事項

### 9.1 我已判斷（附理由，不同意請提出）

| # | 事項 | 判斷 | 理由 |
|---|---|---|---|
| J1 | `sns-alarm-topic` 一次一個 topic 還是一個 map | 一次一個 | 介面小；多群組用 root 的 `for_each` |
| J2 | `autoscaling = null` 時要不要建 scalable target | 建，`min = max = desired_count` | service 忽略 `desired_count`，不建的話改 `desired_count` 不會生效（project-c 的做法） |
| J3 | target group 命名 | `<name>-<container_port>`，`name` 上限 26 字元 | 改 port 時新舊名稱不同，`create_before_destroy` 才成立；名稱看得出是哪個服務 |
| J4 | 告警放在哪個 module | 每個服務的告警在 `ecs-service-alarms`；ALB 整體的 ELB 5xx 告警在 `alb`（一個 ALB 只建一份）；資料庫的 CPU、FreeableMemory、DatabaseConnections，Aurora 的 ReplicaLag，以及有 Proxy 時的兩條 Proxy 告警在 `rds`。門檻取 project-c 與 project-a，三個 module 的 `sns_topic_arns` 都必填 | ELB 5xx 只有 `LoadBalancer` 維度，放在服務的告警裡會重複；資料庫告警跟資料庫同一個 module，型態切換時告警跟著變 |
| J5 | SSM key 命名 | snake_case；服務名稱的 `-` 轉 `_` | 跟 project-a 樹 A 與 `ssm-publish` 既有測試一致；`ssm-publish` 的 key validation 只收 snake_case |
| J6 | tfvars 要不要拆共用檔 | 不拆，每個 stack 一份完整 tfvars | 少一個 `-var-file`；帳號不一致時 `allowed_account_ids` 會擋 |
| J7 | `common.tf` 怎麼保持一致 | 每個 stack 放實體檔，CI 比對雜湊 | symlink 在 vendoring、Windows、`git archive` 都可能出問題 |
| J8 | ECS Exec 預設 | 關 | 最小權限；要用的服務明確打開 |
| J9 | `vendor-modules.sh` 的方向 | 只做 `git::` → vendored 相對路徑 | 範本相對路徑 → `git::` 是複製範本時一次性的手動步驟，寫進 `consuming-modules.md` 就夠，不值得多一條腳本路徑 |
| J10 | `rds` 的型態變數名稱 | `deployment`，值為 `rds`、`aurora`、`aurora_serverless`；型態專屬物件 `rds`、`aurora`、`serverless`，選了哪個就必須給那個，其他兩個必須是 null | 不用 `engine_mode`：AWS 有同名屬性，而 Serverless v2 的 `engine_mode` 其實是 `provisioned`，會混淆 |
| J11 | 流量規格 preset 放哪裡 | 不放進 module；放在範本的 `envs/examples/{poc,standard,high}.tfvars`，README 附對照表（§5.11） | preset 放進 module，升版時會無聲改變網路；每個專案的 CIDR 一定不同；module 直接暴露真正的參數（HashiCorp Module Composition） |
| J12 | 一般 RDS 的 reader 端點 | `reader_endpoint` 等於 writer，另外輸出 `has_reader = false` | 下游不用為型態寫分支 |
| J13 | `rds` 第一版不做的 | 一般 RDS 的 read replica、RDS Multi-AZ DB cluster、同一個 cluster 混用 provisioned 與 serverless instance | 範圍控制；目前沒有專案需要 |
| J14 | 應用程式的 DB 帳號 | 第一版用 master secret，風險寫在 §8.2，之後補應用程式專用帳號或 Proxy IAM 認證 | 先讓三層架構跑起來；另建帳號需要在資料庫裡執行 SQL，Terraform 的 AWS provider 做不到，要另一套機制 |
| J15 | WAF | 只收 `web_acl_arn` 做關聯，Web ACL 由專案自己建 | 規則每個專案不同 |
| J16 | log bucket | ALB access log 與 flow log 各一個 bucket，都建在 `foundation`；ALB 那個只能 SSE-S3 | 兩者的 bucket policy 不同；ALB 不支援 CMK，用了 log 會無聲遺失（project-a `loadbalancer/access-logs.tf`） |
| J17 | SG 的規則怎麼寫 | 規則由 `services`、`data_stores`、`alb_ingress` 在 network stack 的 locals 展開，交給 `security-group` module（決策 29）；一律獨立規則資源、來源用同一次呼叫裡的 SG、CIDR 或 prefix list；ALB egress 只到各服務的 port；DB 與 Proxy 的 SG 都在 `network`（app → proxy → db，沒開 Proxy 時 app → db）；VPC endpoint 的 SG 由 `vpc-interface-endpoints` module 建、只對 `allowed_cidrs` 開 443 | inline 規則會洗掉客戶加的規則（project-a 客戶自管網路報告）；SG 跟服務拓樸綁在一起，所以展開邏輯留在 stack、建立交給 module |
| J18 | 客戶自管模式 | 模式 A（客戶管 VPC、我們管 SG，`existing` 與 `vpc` 二選一）與模式 B（`network` 整個由客戶管，照合約發布全部 key）（§5.8） | 兩種情況都遇過；下游不用改 |
| J19 | 網路第一版不做的 | IPv6、private NAT、Transit Gateway、VPC peering | 範圍控制 |
| J20 | 補一條靜態檢查 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數；整個 `modules/` 不得出現 `random_password` | 讓「密碼不進 Terraform」由程式擋，不靠審查 |
| J21 | 「單一決定點」的範圍 | 除了 ECS Exec，再加四個：`containerimage/services`（服務清單）、`network/alb_https`（有沒有憑證）、`network/db_proxy`（開不開 Proxy）、`network/data_access`（哪些服務能讀 DB secret）。下游用 precondition 檢查自己的設定跟上游一致 | 這四件事都同時影響兩個以上的 stack（例如 Proxy 開關同時決定 SG 規則與 `rds` 的 `proxy`），各放一個變數就會出現「SG 開了、Proxy 沒建」這類不一致 |
| J22 | DB secret 怎麼給應用程式 | task role 讀（`DB_SECRET_ARN`），不經 execution role 的 `valueFrom` | execution role 全專案共用；master 密碼會自動輪替，`valueFrom` 只在啟動時讀一次（§8.2）。不同時支援 `valueFrom`，避免兩條路徑 |
| J23 | `rds` 的 DatabaseConnections 門檻 | `aurora_serverless` 沒給時用 project-c 的公式從 `max_capacity` 推算；`rds`、`aurora` 必填 | provisioned 的 `max_connections` 取決於 instance class 的記憶體，離線算不出來；不給門檻就不建告警等於又多一個隱形開關 |
| J24 | Proxy 的 SG 與兩個 log bucket | 一律建立、一律發布 key，即使沒用到 | SSM 不收空字串，「有時存在的 key」會讓下游的讀取清單變成條件式；這三樣資源沒有費用 |
| J25 | `vpc` 的 route table | 一個 subnet 一張表；default SG 清空規則 | `per_az` NAT 需要每個 AZ 有自己的表，統一一 subnet 一表最單純；清空 default SG 避免誤用 |
| J26 | Enhanced Monitoring role 的 policy | inline policy，action 照 AWS managed policy `AmazonRDSEnhancedMonitoringRole` 的內容整理，Resource 限 `RDSOSMetrics` | 不掛 AWS managed policy 的原則；**是否足夠未驗證**（§7.3） |
| J27 | 範本 stack 只呼叫 module 的例外 | 只留一個：`foundation` 的 secret 容器（決策 30）（決策 55 起多一個：`agent` 的 KB secret 容器）；data source 不算例外（`aws_ssm_parameter` 除外）；新增靜態規則 S8 依例外清單檢查 | 例外要是程式擋得住的清單，不然「只呼叫 module」會慢慢失守（§5.3、§5.6） |
| J28 | `kms-key` 的 key policy | 第一段固定給帳號 root `kms:*`；服務 principal 由 `service_principals` 給動作與條件；`administrator_arns` 可選 | 少了 root 那段，IAM policy 無法授權這把 key，可能變成沒人管得了（AWS 預設寫法，project-c 也是）。每個服務支援的條件 key 不同，交給呼叫端給，**範本的條件清單未驗證** |
| J29 | `s3-bucket` 的 log delivery 介面 | `log_delivery = set(string)`，值只有 `alb_access_logs`、`vpc_flow_logs`；`alb_access_logs` 同時給 ELB 服務帳號與服務主體；搭配 `kms_key_arn` 時 validation 擋 | 舊 region 只給服務主體會 Access Denied（project-a `loadbalancer/access-logs.tf`）；把「ALB log bucket 只能 SSE-S3」變成程式擋 |
| J30 | `s3-bucket` 另外固定的兩項 | `BucketOwnerEnforced`、拒絕非 TLS 的 Deny statement | log bucket 不需要 ACL；Deny 不違反「不對 `*` 開放」（那條指 Allow） |
| J31 | `ecr-repository` 的 lifecycle | 規則 1 刪未加 tag 的舊映像，規則 2 用 `tagStatus = "any"` 保留最近 N 個 | ECR 的 `tagged` 規則必須搭配 tag 前綴或樣式，用 `any` 加優先序最單純 |
| J32 | `ssm-read` 的介面 | 輸入是「本地名稱 → `<stack>/<key>`」，輸出 `strings`、`lists`；不幫忙 `jsondecode`；缺 key 直接讓 plan 失敗 | module 不猜哪些值是 JSON；缺 key 代表上游沒 apply 或客戶沒發布，應該停 |
| J33 | `iam-role` 的 `arn` 輸出 | `depends_on` inline policy | 下游拿到 ARN 時權限已經附加（範例 `core` module 的寫法） |
| J35 | `security-group` 一次呼叫管一組 SG | 不做成「一次一個 SG」；整組 SG 與規則在同一次呼叫，規則用 SG 的 key 互相指 | 規則鏈是雙向引用（ALB egress → app、app ingress ← ALB），一次一個的話 stack 只能對同一個 module block 用 `for_each`，引數引用自己會形成自我引用（§4.16） |
| J36 | 「沒有憑證時 ALB SG 不准對 0.0.0.0/0 開 80」放哪裡 | 放在 network stack 的 `alb_ingress` validation；`security-group` module 只負責通用底線「ingress 對 `0.0.0.0/0` 必須明寫 `allow_internet = true`」 | 這條要知道「哪個 SG 是 ALB」與「有沒有憑證」，兩者都是專案語意；通用 module 不該知道，放進去就得加一個專屬旗標（§4.16） |
| J37 | `iam-role-policy` 收 `role_arn` 而不是 `role_name` | 從 ARN 最後一段取名稱；validation 不准帶 path | SSM 合約發布的是 ARN，下游不用多一個 key；範本的 role 都不加 path |
| J38 | 既有 module 要不要改成呼叫 `log-group`／`log-metric-alarm` | 不改，維持平坦組合；`log-group` 給 Lambda、應用程式自訂 log、範本 stack 用 | HashiCorp Module Composition：module 不巢狀呼叫 module。巢狀之後版本耦合，改 `log-group` 會連帶讓 `ecs-service` 換版 |
| J39 | `log-metric-alarm` 一次呼叫的範圍 | 一個 log group、多組 filter 加 alarm；`alarms` 可以是空 map | 照 project-a 的寫法（一張事件表對一個 log group）；空 map 讓範本可以預設呼叫但什麼都不建，不需要開關 |
| J40 | `log-metric-alarm` 用 `default_value = 0`，不支援 `dimensions` | 照 project-a | 兩者在 CloudWatch 不能同時用；有 `default_value` 時沒有事件的期間指標是 0，告警判斷比較穩定 |
| J41 | 觀測性 module 放在哪個 stack | `log-metric-alarm`、`xray` 放 `application`；`log-group` 範本預設不呼叫 | 告警的 pattern 與 sampling rule 的 `service_name` 都跟服務綁在一起，跟服務同一個 stack 才不用跨 stack 傳名稱（跟決策 6 同一個理由）。sampling rule 雖然是帳號層級的資源，但名稱帶專案前綴，不會跟別的專案撞 |
| J42 | `sidecars` 的欄位 | name、image、essential、command、cpu、memory_reservation、environment、secrets、port_mappings、health_check、`app_depends_on`、`log_stream_prefix`；log 走同一個 log group、只換 stream 前綴 | ADOT 需要 command／health check／資源保留，`app_depends_on` 讓主 container 等 collector；不收 volume、`dependsOn` 任意組合、`firelensConfiguration`，等真的有專案需要再加（MINOR） |
| J43 | ADOT 範例放哪裡 | `modules/ecs-service/examples/adot-sidecar/`（CI 會驗）加 `docs/guides/observability.md`（整套做法）；範本 stack 預設不放（**已被決策 36 推翻**：範本已接好，預設關閉） | 原本的理由：範本預設不開追蹤，放進範本會讓每個專案背一個關著的 sidecar；guide 才寫得下跨三個 stack 的做法。這會在 `docs/guides/` 多一份檔案（§1.1） |
| J44 | ADOT collector 的設定怎麼帶 | 用 `environment` 的 `AOT_CONFIG_CONTENT`，不學 project-c 存成 SSM parameter | 設定不是機密；範本規定 `aws_ssm_parameter` 只能由 `ssm-publish` 建（S2） |
| J45 | `vpc-interface-endpoints` 收 `allowed_cidrs` 還是 `vpc_cidr` | `allowed_cidrs = list(string)`，範本給 `[vpc_cidr]`；不准 `0.0.0.0/0` | 客戶 VPC 可能有 secondary CIDR、或要讓 peering 網段使用；收清單不增加呼叫端負擔，也不用之後改介面 |
| J46 | `services` 為空時 | 不建任何資源，`security_group_id = null` | 範本預設的 PoC 規格沒有 interface endpoint，stack 不需要為了它加 `count` |
| J47 | `aws_default_security_group` 算不算 S4 的範圍 | 不算「新建 SG」，留在 `vpc`；S4 另外寫一條：它只准出現在 `modules/vpc/` | 它接管 VPC 本來就有的 default SG 並清空規則，跟 VPC 生命週期綁在一起；只准在 `vpc`，模式 A 就不會碰到客戶的 default SG |
| J48 | interface endpoint 的 tier 檢查放哪裡 | 從 `vpc` 的 precondition 搬到 network stack 的 validation | module 改收 subnet id，已經不知道 tier；tier 是範本的語意 |
| J49 | private DNS 的前提由誰檢查 | network stack 在模式 A 用 `data "aws_vpc"` 檢查客戶 VPC 有開 `enable_dns_support`、`enable_dns_hostnames`；module 不檢查 | module 拿不到 VPC 屬性；自建 VPC 時 `vpc` 已經固定開啟 |
| J50 | ~~Knowledge Base 的文件來源 bucket 誰建~~ **已被決策 51 取代**：範本的 `agent` 用 `s3-bucket-v0.2.0`（版本號已被決策 54 取代：改發 `s3-bucket-v0.1.1`）（`never_expire = true`）為每個 KB 建語料 bucket，`data_sources` 不再收 `bucket_arn`。以下是原本的判斷 | 範本不建；`agent` 的 `knowledge_bases[*].data_sources[*].bucket_arn` 由專案在 tfvars 給（跟 `loadbalancer` 的 `certificate_arn` 一樣是外部輸入），KB role 的 S3 權限只到這些 bucket 與 prefix | `s3-bucket` 一律帶 lifecycle 到期（`expiration_days` 1–3650，沒有「不過期」），拿它建語料 bucket，文件會被自動刪掉、KB 下一次同步就跟著清空。讓 `s3-bucket` 支援不過期是它的 MINOR，等第一個專案真的需要時再做 |
| J51 | ~~KB 連資料庫用哪個帳號~~ **已被決策 53 取代**：一開始就用 KB 專用的資料庫帳號，`knowledge_bases[*].credentials_secret_arn` 必填。以下是原本的判斷 | 第一版用 `data` 的 master secret，風險寫在 §8.8 | 範本第一版只有 master 帳號（J14）；另建帳號要在資料庫執行 SQL 並多一個 secret，範本目前沒有放它的地方。之後補可選的 `credentials_secret_arn` 覆蓋（MINOR） |
| J52 | `agentcore-memory` 第一版的範圍與預設 | 只收內建的 `SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE` strategy，不收 `CUSTOM` 與 self-managed；`event_expiry_days` 預設 90 | `CUSTOM` 要自訂模型、`append_to_prompt` 與 Memory execution role，範本就得多一個 role 與權限；三個參考專案都沒用過 strategy。保留天數越長、留存的個資越多，預設取中間值；project-a 用 365 是它自己的取捨 |
| J53 | `agentcore-runtime` 要不要建 endpoint | 不建，只用 AWS 自帶的 `DEFAULT` | project-a 只用 `DEFAULT`；多 endpoint（例如藍綠）沒有專案需要，之後加是 MINOR |
| J54 | Lambda target 的工具定義怎麼收 | `tool_schema_s3_uri`（完整定義放 S3）或扁平的 `tools`（每個工具一層屬性），兩者恰好一個 | schema 的 inline 工具定義是多層 block，不是 JSON 字串，Terraform 寫不出任意深度（§9.4 D23）；project-b 的寫法是一層 |
| J55 | KB 與 Gateway 的 service role 由誰決定要不要建 | `iam-base` 的 `agent_service_roles`（`set(string)`，預設空），`agent` 用 precondition 檢查一致 | role 要在 `agent` 之前存在，只有更早的 stack 能決定；照「上游決定、下游檢查」的單一決定點寫法（J21）。不一律建立：決策 41 要求沒有輸入就什麼都不建 |
| J56 | Runtime 的追蹤開關放哪裡 | `agent` 的 `agent_runtimes[*].tracing`，發布在 `agent_runtime_<rt>`；`iam-app` 照讀給 execution role 三個 X-Ray 動作（多一個 `xray:PutSpans`），不併進 `iam-app/tracing` | `agent` 在 `iam-app` 之前，它要知道開不開才能建 `TRACES` delivery 與設 OTEL 環境變數；`iam-app/tracing` 的名單是 ECS 服務（collector sidecar 用），兩者機制不同。`xray:PutSpans` 是 OTEL 直送 X-Ray 需要的動作（`project-a/infra-v2/terraform/iam/agentcore-role.tf`），所以允許清單多一個動作 |
| J57 | 沒有 NAT 時能不能用 Gateway | 擋下（`agent` 的 precondition） | Runtime 經 VPC 呼叫 Gateway 要哪個 interface endpoint 服務名稱沒有查證；放行的話症狀是工具呼叫逾時，看起來像 Gateway 或 Lambda 的問題。§7.3 第 20 項查證後改成檢查那個 endpoint |
| J58 | 範本的 Gateway 認證 | 固定 `AWS_IAM`，module 另外支援 `CUSTOM_JWT` | 範本裡呼叫 Gateway 的只有自己的 Runtime，用 execution role 簽 SigV4 最單純；JWT 要 IdP，範本沒有 |
| J59 | guardrail 與 Memory 的 KMS | 範本傳 `null`（AWS 管的 key）；module 收 `kms_key_arn` | `foundation` 的專案 key 要給 Bedrock 與 AgentCore 哪些 service principal 與條件沒有實測（§7.3 第 22 項）；給錯的症狀是建立或讀寫失敗 |
| J60 | Runtime 連 ECS 服務的 SG 規則 | 第一版不做；Runtime SG 只有 443 egress 與 `data_access` | project-a 的 Runtime 只連資料庫與外部 API；需要時在 `network` 的 `agent_runtimes` 加 `calls`，展開方式同服務的 `callers` |
| J61 | `agent` 發布的 JSON 太大怎麼辦 | 每個 Runtime 一個 key；project 層級的 `models` 等放在一個 key；超過 4096 字時 `ssm-publish` 的 validation 在 plan 擋下 | `ssm-publish` 寫死 Standard tier（上限 4096 字）；改 Advanced tier 有費用，等真的有專案超過再說 |
| J62 | 要不要檢查環境變數「看起來像 secret」（**已被決策 56 取代**：`agentcore-runtime` 擋名稱像 secret 的變數，`*_ARN` 且值是 ARN 的放行；以下是原本的判斷） | 不做 | 只能靠猜（名稱含 `PASSWORD`、值像金鑰），會漏也會誤擋，還會讓人以為有防線；規則改成文件與審查：環境變數只放 id、ARN、URL |
| J63 | `models` 的介面 | `foundation_model_id` 加可選的 `inference_profile_prefix`，不從一個字串解析 | foundation model id 與 system inference profile id 都是點分隔，`anthropic.x` 與 `apac.anthropic.x` 只能靠猜哪一段是地區前綴；分成兩個欄位，`invoke_arns` 的組法就沒有歧義 |
| J64 | `data` 發布的 `database` 要加什麼 | 加 `cluster_arn`、`data_api` 兩個欄位 | KB 與 KB role 需要 cluster ARN；照 §5.6「新增欄位是相容的」。附註：~~D21 的 `rds` 新增輸出（`deployment`、資料庫名稱）不併進 `rds-v0.2.0`，要併由使用者決定~~ 使用者決定併進：`rds-v0.2.0` 新增 `deployment`、`database_name` 兩個輸出，`data` 改取這兩個輸出發布（決策 52）（版本號已被決策 54 取代：改發 `rds-v0.1.1`） |
| J65 | `agent` 的 lock 檔怎麼產生 | 照 Phase 8〈lock 檔的產生方式〉原文，硬性限制第 9 條的例外延伸到 Phase 14 的 `agent` 一個 stack | 新 stack 是 root，要提交全平台雜湊的 lock 檔；跟其他 8 個 stack 同一個 aws 版本（6.69.0），新 module 的下限 `>= 6.69` 也剛好滿足 |
| J66 | 跨帳號與其他設定的關係 | `bedrock_invoke` 啟用時：所有列了 `models` 的 Runtime 與服務都改成 `sts:AssumeRole`；不准有 `tracked` 模型；KB 不受影響（KB 用本帳號的 KB role 呼叫本帳號的嵌入模型） | 一個專案的模型不是全在本帳號、就是全在 B 帳號，最單純；application inference profile 建在本帳號，B 帳號的 role 用不到 |
| J67 | `s3-bucket` 不過期選項的介面 | 新增 `never_expire`（`bool`，預設 `false`，`nullable = false`）；`expiration_days` 預設改成 `null`、module 內當成 90；兩者互斥（`never_expire = true` 時給了 `expiration_days` 就擋）；不過期時 lifecycle 只留未完成分段上傳的清除，rule id 改成 `abort-incomplete-uploads` | 不讓 `expiration_days = null` 直接代表不過期：`optional(number)` 轉傳時沒給值就是 null，log bucket 會在沒人注意時變成永久保存。細節見 §4.32 |
| J68 | KB 語料 bucket 的設定 | 每個 KB 一個 bucket，名稱 `<project>-<env>-kb-<key>-<account_id>`；SSE-S3（`kms_key_arn = null`）、`force_destroy = false`、不給任何 log delivery；`data_sources` 只用 prefix 區分 | 一個 KB 一個 bucket，KB role 的 S3 權限就是「這個 KB 的 bucket」，不用跨 KB 比對 prefix。SSE-S3 是因為 Bedrock 讀 SSE-KMS bucket 時 key policy 要給什麼沒有實測（同 J59 的理由），用 SSE-S3 的話 KB role 不需要 bucket 的 KMS 權限。不用 versioning：`s3-bucket` 沒有這個能力（§4.32） |
| J69 | KB 帳號的 secret 用哪把 KMS key | guide 要求用 `foundation` 的專案 key 建；`iam-app` 給 KB role 那把 key 的 `kms:Decrypt`，帶 `kms:ViaService = secretsmanager.<region>.amazonaws.com` | 跟 v1 對 master secret 的做法一樣（`data` 傳 `master_user_secret_kms_key_arn`、`iam-app` 的 Proxy role 與 task role 都是這個 statement，§5.4）。專案改用 AWS 管的 `aws/secretsmanager` 也能用（那把 key 的 policy 允許帳號內經 Secrets Manager 解密），這條 statement 只是用不到；改用其他 CMK 則 KB 讀不到 secret。`agent` 不檢查 secret 用哪把 key：要用 `data "aws_secretsmanager_secret"` 讀，等於讓 `agent` 在 plan 時多一個 AWS 呼叫，換到的只是提早一點看到錯誤 |
| J70 | 多個 KB 時 secret 與 role 怎麼對應 | 每個 KB 自己一個 `credentials_secret_arn`（可以各自是不同的資料庫帳號、只對自己的表有權限）；KB role 仍然只有一個，讀得到所有 KB 的 secret | KB role 由 `iam-base` 的 `agent_service_roles` 決定、只有一個（J55）。改成每個 KB 一個 role，`iam-base` 就得知道 KB 清單，而 KB 清單在 `agent`，順序在 `iam-base` 之後。第一版 KB 之間的隔離只在資料庫層，寫在 §8.8 |

### 9.2 已拍板決策

| # | 決策 | 理由 | 影響的章節 |
|---|---|---|---|
| 1 | ~~module 一律不建 IAM~~ → 由決策 25、28 修改：**只有 `iam-role` 與 `iam-role-policy` 建 IAM**。`ecs-service`、`rds` 等其他 module 只收 role ARN；role 在範本的 `iam-base`／`iam-app` 透過這兩個 module 建好，ARN 經 SSM 傳到使用端 | 集中審查；客戶自管 IAM 時接得上（例如 project-a prod b2c 的 deploy role 不能改 IAM）。policy 用 `jsonencode()` 寫，mock 下測得到內容 | §4.1、§4.2、§4.3、§4.14、§4.15、§5.4、§7.1、§8.1 |
| 2 | 範本在本 repo 內用相對路徑引用 module（`../../../../../modules/<name>`）；複製到專案 repo 時改成 `git::...?ref=<module>-v<semver>`，改法寫在 `consuming-modules.md`；`vendor-modules.sh` 只負責 `git::` → vendored 相對路徑 | 本 repo 在 tag 不存在、repo 未上 GitHub 時也要能跑 `init -backend=false`、`validate`、`test`（與 implement-process U3 一致） | §1.1、§4.22、§5.1、§5.8、§8.7 |
| 3 | 新增 `containerimage` stack（ECR），排在 `foundation` 之後 | ECR 的擁有者與變動頻率跟 SNS／KMS 不同，客戶自管時也常分開；execution role 要用 ECR 的 ARN 限縮權限 | §5.1、§5.3、§5.4、§5.8 |
| 4 | 每個 Phase 一個 commit；含多個 module 的 Phase 改成一個 module 一個 commit；直接 commit 在 `main`，不 push；author `<author-email>`；Conventional Commits | 使用者決定。一個 commit 只動一個 module 目錄，release-please 依路徑歸屬才不會互相污染 CHANGELOG | 實作流程見 `implement-process.md` |
| 5 | 起始版本 `v0.1.0` | 還沒在真實 AWS apply 過；§7.3 驗完再升 `v1.0.0` | §3.5 |
| 6 | 服務告警放在 `application` stack | 告警直接吃 service 與 target group 的輸出，避免 project-a `postdeploy` 在 tfvars 寫死 id；代價是調門檻也要動高頻變動的 stack | §4.22、§5.3 |
| 7 | ~~SG 由 `network` stack 建；`network` 不建 VPC，只登記既有 VPC／subnet 的 id~~ | **已作廢，由決策 18 取代。** SG 仍由 `network` 建；VPC 改成預設建立 | — |
| 8 | 資料層 stack 命名為 `data` | 涵蓋資料庫與快取 | §5.3 |
| 9 | 不提供 `stacks.sh` | project-a 的那支已經失效；八個 stack 照 `infra/README.md` 的順序手動跑，比一支沒人維護的腳本可靠 | §5.10 |
| 10 | 命名：範本用 `<project>-<env>-<component>`，module 收完整的 `name` | module 不管命名，project-c 那種客戶規範也接得上 | §4.1、§5.9 |
| 11 | module 不提交 `.terraform.lock.hcl`，範本 stack 提交 | Terraform 只採用 root module 的 lock；module 的 lock 對消費端沒有作用 | §4.1、§5.1 |
| 12 | tflint 第一版只用內建 terraform ruleset | 不用下載 plugin、CI 不用帶 token；aws ruleset 列為下一版 | §7.1 |
| 13 | `terraform test` 的 run 只有在有 `mock_provider "aws"` 的測試檔裡才可以用 `command = apply` | mock 下的 apply 不碰 AWS，讓 computed 值可以斷言（與 implement-process U5 一致） | §7.1 |
| 14 | SSM 合約的靜態檢查第一版只做兩條（只有 `ssm-publish` 可宣告 `aws_ssm_parameter`；`data "aws_ssm_parameter"` 只能出現在 `ssm-read`，且只讀 `insecure_value`）；「讀的 key 必須是更早的 stack 發布的」之後再補 | 第一版範圍要小；第三條要解析 HCL 做跨 stack 比對 | §5.6、§7.1 |
| 15 | ECR 預設 `IMMUTABLE`、`scan_on_push = true`、`force_delete = false` | 同一個 tag 不能被覆蓋，部署才可追溯；推上去就掃描；有映像時 destroy 會失敗，不會誤刪 | §5.3 |
| 16 | ECS Exec 的開關由 IAM stack（現在是 `iam-app`）發布到 SSM，`application` 讀同一個 key | 只有一個地方決定，不會出現 exec 開了卻沒有權限 | §5.4、§5.6 |
| 17 | 第一版 module 從 5 個變成 8 個，新增 `vpc`、`rds`、`alb`，做出最小三層架構（ALB 在 public，AP 與 DB 在 private） | 使用者決定：沒有網路與資料庫，範本示範不了完整的專案 | §1、§4.7–§4.22 |
| 18 | `network` stack 預設用 `vpc` module 建立 VPC；客戶自管時改為登記既有 VPC（模式 A）或整個交給客戶（模式 B）。取代決策 7 | 使用者決定；subnet 調整時 SSM key 名稱不變（§5.6） | §5.3、§5.6、§5.8 |
| 19 | `rds` 支援一般 RDS、Aurora、Aurora Serverless v2 三種型態，由一個變數選擇；RDS Proxy 是 module 內的選項 | 使用者決定 | §4.9 |
| 20 | `iam` 拆成 `iam-base` 與 `iam-app`，範本從 7 個 stack 變 8 個，順序 `foundation` → `containerimage` → `network` → `iam-base` → `data` → `iam-app` → `loadbalancer` → `application`。`iam-base` 建 execution role、Proxy role（只有 trust）、Enhanced Monitoring role；`data` 把 role ARN 傳進 `rds`；`iam-app` 讀 `database.secret_arn`，用 `iam-role-policy` 對 Proxy role 附加讀 secret 的 policy（決策 28），並建 task role | Proxy 建立時要 role，role 的權限又要等 secret 存在。Proxy 在 role 尚無權限時能不能建立**未驗證**，兩種結果的對策見 §5.4 | §5.3、§5.4、§7.3 |
| 21 | flow log 送 S3，bucket 建在 `foundation`，不需要 IAM role；範本範例只在正式環境開啟 | 使用者決定 | §4.7、§5.3、§5.11 |
| 22 | NAT 支援 `none`、`single`、`per_az`；範本範例正式環境 `per_az`、PoC `single` | 使用者決定；project-c uat 關 NAT、prod 每個 AZ 一顆（§5.11 依據） | §4.7、§5.11 |
| 23 | ALB 沒有憑證時允許只開 HTTP，但 `network` 的 validation 不准 ALB SG 對 `0.0.0.0/0` 開 80，只能開給 CloudFront managed prefix list 或指定 CIDR；有憑證時開 443、80 一律 301、TLS policy 固定 `ELBSecurityPolicy-TLS13-1-2-2021-06` | 使用者決定；明文 HTTP 不能對全網開放 | §4.8、§5.3、§8.4 |
| 24 | 第一版再加 5 個 module，從 8 個變 13 個（決策 28、29 之後再加 2 個，共 15 個）：`kms-key`（CMK、key policy、alias、自動輪替，`foundation` 呼叫）、`ecr-repository`（一個 repository 一次呼叫，`containerimage` 用 `for_each`）、`s3-bucket`（log bucket，`foundation` 建 flow log 與 ALB access log 兩個）、`ssm-read`（跟 `ssm-publish` 配對，`ssm-inputs.tf` 改呼叫它）、`iam-role`（trust 加 inline policy） | 使用者決定：每個 AWS 服務一個 module，stack 只負責呼叫 module | §1、§4.10–§4.14、§5.3、§5.6 |
| 25 | 「module 不建任何 IAM」改成「只有 `iam-role` module 建 IAM」（決策 28 再放寬為 `iam-role` 與 `iam-role-policy`）；其他 module 仍不建 IAM，範本 stack 也一律透過 IAM module | 使用者決定 | §4.1、§4.14、§5.4、§5.6 S4、§8.1 |
| 26 | `modules/` 底下的 `.tf` 與 `.tftest.hcl`，所有註解、`description`、`error_message` 一律只用英文，不可中英混雜，禁止任何 icon／emoji；註解只寫程式碼看不出來的原因。`README.md`、`CHANGELOG.md` 不受限制 | 使用者決定 | §4.1、§4.10–§4.14 的介面範例 |
| 27 | 第一個版本 tag `<module>-v0.1.0` 由人手動打（19 個），manifest 維持登記 `0.1.0`；之後的版本交給 release-please | 使用者決定 | §3.5、`docs/guides/releasing-modules.md` |
| 28 | 新增 `iam-role-policy` module（只建 `aws_iam_role_policy`，附加到既有 role），維持 RDS Proxy 的兩段式：`iam-base` 用 `iam-role` 建只有 trust 的 Proxy role，`iam-app` 在 secret 存在後用 `iam-role-policy` 附加讀 secret 的 policy，Resource 恰為那個 secret ARN。IAM 規則改成「只有 `iam-role` 與 `iam-role-policy` 建 IAM」；`iam-role-policy` 同樣擋掉 `*` 與 `:*` 動作。不採用命名樣式加 tag 條件的寫法（原 P1 選項 c） | 使用者決定（原待拍板 P1）。Resource 是確切的 ARN，權限最精確；代價是恢復「role 沒權限時能否建立 Proxy」這個未驗證項目，對策見 §5.4 | §4.14、§4.15、§5.4、§5.6 S4、§5.11、§7.3、§8.1 |
| 29 | SG 做成 `security-group` module，一次呼叫建一組互相引用的 SG 與規則；`network` stack 改成呼叫它，例外清單拿掉 SG。規則一律用獨立的 `aws_vpc_security_group_*_rule` 加 `for_each`，不准 inline。「沒有憑證時 ALB SG 不准對 0.0.0.0/0 開 80」放在 network stack，module 只負責通用的「ingress 對全網開放必須明寫 `allow_internet`」 | 使用者決定（原待拍板 P2）。放置位置的理由見 §4.16 | §4.16、§5.3、§5.6 S4、§8.4 |
| 30 | `foundation` 的 secret 容器不做成 module，留在例外清單 | 使用者採納建議（原待拍板 P3）：只有一個 resource，包成 module 省不到東西 | §5.3 |
| 31 | 再加 3 個觀測性 module，從 15 個變 18 個：`log-group`（保留天數只收 AWS 允許的值、可選 KMS、可選 subscription filter，目的地以 ARN 傳入）、`log-metric-alarm`（metric filter 加 alarm，一次呼叫多組，`sns_topic_arns` 必填，`alarm_actions`、`ok_actions` 都接）、`xray`（sampling rule 與 group，控制追蹤成本） | 使用者決定（Phase 7E） | §1、§4.17–§4.19、§5.3、§7.1 |
| 32 | `ecs-service` 新增通用的 `sidecars`（MINOR），不寫死 ADOT；`sidecars = []` 時結果跟現在完全一致，列為迴歸測試要求。ADOT、collector 設定、task role 的 X-Ray／CloudWatch 權限由專案在 `application` 與 `iam-app` 自己決定 | 使用者決定（Phase 7E） | §4.20、§7.1 |
| 33 | 這 3 個新 module 都不建 IAM；既有的 `ecs-service`、`rds`、`ecs-service-alarms` 不改成呼叫 `log-group` 或 `log-metric-alarm` | 主 agent 判斷，見 §9.1 J38 | §4.17、§4.18 |
| 34 | interface endpoint 從 `vpc` 拆出來，成為 `vpc-interface-endpoints` module（interface endpoint 加 endpoint 專用的 SG，SG 只允許指定 CIDR 連 443，規則用獨立 rule 資源）；module 總數 19 個。`vpc` 移除 `interface_endpoints` 變數、endpoint SG 與 `vpce_security_group_id` 輸出；subnet、route table、IGW、NAT、gateway endpoint、flow log 留在 `vpc`。名稱用 `vpc-interface-endpoints` 不用 `vpc-endpoints`，避免誤會 gateway endpoint 也在裡面。`vpc` 還沒打過 tag，這項併進 `v0.1.0`，不算破壞性變更 | 使用者決定。IGW、NAT、gateway endpoint 都是路由，要跟 `vpc` 建的 route table 在一起，拆開的話 `per_az` NAT 對錯表不會報錯、加 AZ 要改兩個 module；客戶自管 VPC 時路由歸客戶，我們不該碰（project-a 2026-09-04 報告）。interface endpoint 不碰路由，拆出來之後 network stack 在自建與客戶既有 VPC 兩種模式都能呼叫 | §1、§4.7、§4.21、§5.3、§5.6 S4、§5.8、§5.11、§7.1 |
| 35 | `iam-role` 與 `iam-role-policy` 新增第四條 validation：Allow statement 不准搭配 `NotResource`（沒寫 `Effect` 視為 Allow，Deny 搭配 `NotResource` 照樣放行），兩個 module 一字不差 | 使用者同意比照 `NotAction`：`Allow` 加 `NotResource` 的效果接近 `Resource = "*"`，原本三條都擋不到 | §4.14、§4.15、§7.1 |
| 36 | 範本把 X-Ray 追蹤完整接好，預設關閉：`iam-app` 新增 `tracing`（單一決定點，task role 的 X-Ray 四個動作、發布 `tracing`），`application` 照它掛 ADOT collector sidecar 並設 OTEL 環境變數（映像由 `adot_collector = { tag, source }` 決定），`network` 新增發布 `interface_endpoints`，沒有 NAT 時 `application` 用 precondition 要求 mirror 映像與 `xray`、`ecr.api`、`ecr.dkr` endpoint。範本預設不開追蹤，只有 `tracing` 列了服務才會建立任何東西。**推翻決策 32 的後半句**（「ADOT、collector 設定、task role 的 X-Ray 權限由專案在 `application` 與 `iam-app` 自己決定」）以及 §4.20 原本「範本的 stack 預設不開追蹤；放進範本會讓每個專案都背一個預設關閉的 sidecar」的理由：`ecs-service` 的 `sidecars` 仍然通用、不寫死 ADOT，只是範本不再留空；單一決定點從 `iam-app/tracing_<service>` 改成一個 `iam-app/tracing` 清單 | 使用者決定：「第一版就讓 X-Ray 能完整用起來」 | §4.20、§5.3、§5.4、§5.6 |
| 37 | **LLM 增補**：新增 7 個 module：`bedrock-guardrail`、`bedrock-inference-profile`、`agentcore-runtime`、`agentcore-memory`、`agentcore-gateway`、`log-delivery`、`bedrock-knowledge-base`，各自從 `<module>-v0.1.0` 開始（版本號已被決策 54 取代：改發 `<module>-v0.1.1`）；既有 19 個 `v0.1.0` tag 不動；不做 `s3-vectors`。寫進 v1 當增補（決策 37 起、Phase 11–16），不開 v2 | 使用者決定 | §1、§3.2、§3.5、§4.23–§4.30 |
| 38 | Knowledge Base 的向量儲存只收 Aurora PostgreSQL pgvector（`rds_configuration`）。`vector` extension、表與索引由專案的 migration 建，Terraform 不碰；module 只接線並驗名稱與欄位對應；guide 附可照抄的 SQL；apply 順序 `data` → migration → `agent`。data source 只收 S3 | 使用者決定 | §4.30、§5.3 |
| 39 | `rds` 新增 `data_api`（`enable_http_endpoint`，預設 `false`，只限 Aurora），既有消費端 plan 零差異，屬於 MINOR，發 `rds-v0.2.0`（版本號已被決策 54 取代：改發 `rds-v0.1.1`） | 使用者決定；Bedrock KB 的 Aurora 儲存只能經 Data API。semver 判斷見 §4.31 | §4.31、§5.3 |
| 40 | Gateway 的 target 只收 Lambda 與 MCP server；不做 credential provider、OpenAPI、Smithy、VPC Lattice | 使用者決定；唯一的參考（project-b）OpenAPI 經 VPC Lattice 跨帳號走不通，credential provider 牽涉 secret | §4.28 |
| 41 | 範本新增 `agent` stack，預設關閉（沒有輸入就什麼都不建）；順序 `foundation` → `containerimage` → `network` → `iam-base` → `data` → `agent` → `iam-app` → `loadbalancer` → `application`；`iam-base` 建只有基本權限的 role，`iam-app` 在 `agent` 之後附加確切 ARN 的權限（同決策 20、28 的 Proxy 兩段式）；單一決定點清單與 §5.6 合約表照增補更新 | 使用者決定；修掉 project-a 的名稱萬用字元與 tfvars 寫死 Runtime ARN | §5.3、§5.4、§5.6 |
| 42 | Runtime 的網路模式預設 `VPC`，`PUBLIC` 只在明寫時允許（validation 加文件寫取捨）；沒有 NAT 時用 precondition 要求 `bedrock-runtime`、`bedrock-agentcore` endpoint（比照決策 36 對 X-Ray 的做法）；永遠不建 `bedrock-agentcore-control` endpoint | 使用者決定 | §4.26、§5.3、§8.8 |
| 43 | 新 module 的 aws provider 是 `>= 6.69, < 7.0`，記為 §4.1 的例外 | 使用者採納建議：6.0 沒有 `aws_bedrockagentcore_*`，寫 `>= 6.0` 是做不到的承諾；6.69.0 是唯一查過 schema 的版本 | §4.1、§4.23 |
| 44 | 跨帳號呼叫模型只做 A 側，設定只有一個地方（`agent` 的 `bedrock_invoke`），`iam-app`、`application` 照讀 | 使用者採納建議；project-a 把同一個值放在兩個 stack。B 側 role 由 B 帳號擁有者負責 | §5.3、§5.4 |
| 45 | Runtime 的映像 tag 由 Terraform 擁有：不用 `ignore_changes`，不准 `:latest` | 使用者採納建議；跟 `ecs-service` 一致，繞過 Terraform 換版會被下一次 apply 退版 | §4.26 |
| 46 | guardrail 的 tier 預設 `STANDARD`，`STANDARD` 必須給 cross-region profile id；不建 guardrail 版本，新增靜態規則 S9（`aws_bedrock_guardrail_version` 不得出現在 `modules/` 與 `templates/`；本次只寫文件，`validate.sh` 在 Phase 12 實作） | 使用者採納建議；`CLASSIC` 只評估英文，發佈版本之後 apply 對執行中的版本無效，兩者都不報錯 | §4.24、§5.6、§8.8 |
| 47 | Bedrock 告警不在這次範圍；`iam-role` 支援 `aws:SourceArn` 延後 | 使用者採納建議；告警的指標維度要先實測，`SourceArn` 只有 KB 與 Gateway 的 trust 用得到 | §5.3 |
| 48 | Runtime 的 `idle_session_timeout` 與 `max_lifetime` 一律一起送，預設 900／28800 | 使用者採納建議；底層 API 是 PUT，少送一個會靜默回到 AWS 預設 | §4.26 |
| 49 | 範本的 Runtime 預設 `TRACELOOP_TRACE_CONTENT=false` | 使用者採納建議；對話內容不進 trace | §5.3、§8.8 |
| 50 | guardrail profile 的 IAM ARN region 用 `*`；`models.invoke_arns` 由 `agent` 的一個 local 組，foundation-model 的 region 用 `*` | 使用者採納建議；兩者的 region 都由 AWS 動態決定，寫死會間歇失敗 | §5.3、§5.4 |
| 51 | KB 的語料 bucket 由範本建：`s3-bucket` 新增不過期的選項（`never_expire`，預設 `false`；`expiration_days` 沒給時仍是 90），既有消費端 plan 零差異，屬於 MINOR，發 `s3-bucket-v0.2.0`（版本號已被決策 54 取代：改發 `s3-bucket-v0.1.1`）；範本的 `agent` 為每個 KB 用 `s3-bucket` 建一個不過期的語料 bucket，`knowledge_bases[*].data_sources` 不再收 `bucket_arn`。取代 J50 | 使用者決定。介面細節是主 agent 的判斷（J67、J68） | §1、§3.5、§4.12、§4.23、§4.30、§4.32、§5.3、§5.4、§5.6、§7.1、§7.3、§8.8 |
| 52 | `rds-v0.2.0`（版本號已被決策 54 取代：改發 `rds-v0.1.1`） 同時包含 `data_api` 與 D21 記的兩個新輸出 `deployment`、`database_name`；`data` 發布 `database` JSON 時改取這兩個輸出，欄位與值不變 | 使用者決定；兩者都是 MINOR，一起發可以少一個版本 | §4.31、§5.3、§5.6、§7.1、§9.1 J64、§9.4 D21 |
| 53 | KB 一開始就用專用的資料庫帳號，不用 master secret。專案的 migration 建只能讀寫 KB 那張表的帳號（不是 superuser、不能在 schema 建物件），帳密由專案放進自己建的 Secrets Manager secret（不在本 repo 的 module 裡）；`agent` 從 tfvars 收 `knowledge_bases[*].credentials_secret_arn` 傳給 `bedrock-knowledge-base`，precondition 擋掉 master secret；`iam-app` 給 KB role 的 `secretsmanager:GetSecretValue` 恰為那些 ARN，加上專案 key 的 `kms:Decrypt`（帶 `kms:ViaService`）。取代 J51 | 使用者決定。secret 容器要不要改由範本建，列為待決（§9.5 Q1） | §4.30、§5.3、§5.4、§5.6、§7.1、§7.3、§8.8 |
| 54 | 增補動到的 9 個 module（決策 56 起是 10 個，加 `iam-role`）一律發 `<module>-v0.1.1`：7 個新 module（`bedrock-guardrail`、`bedrock-inference-profile`、`agentcore-runtime`、`agentcore-memory`、`agentcore-gateway`、`log-delivery`、`bedrock-knowledge-base`）加上 `rds`、`s3-bucket`。7 個新 module 不打 `v0.1.0`；其他 17 個 module 只有 `v0.1.0`；19 個既有的 `v0.1.0` tag 留在 `28a8647`，不移動。`.release-please-manifest.json` 在 Phase 16 把這 9 個都登記成 `0.1.1`。取代決策 37、39、51、52 與 J50、J64、D28 裡寫的版本號，那些列的其餘內容不變 | 使用者決定（2026-10-15）。照 §3.5 的表，`rds`、`s3-bucket` 的變更是 MINOR，應該發 `0.2.0`；這一次刻意用 `0.1.1`，只限這一次，之後的版本照 §3.5 的表。附註（2026-10-16）：Phase 16 在 `81ac4d3` 打的 9 個 `v0.1.1` tag 只在本機、從未推送；Phase 17 的補強改了其中 8 個 module 並把 `iam-role` 加進來（決策 56），所以把那 9 個 tag 刪掉，在新的 release commit `54f2837` 重打 10 個（annotated，照 `releasing-modules.md` 的補打迴圈、從 manifest 讀版本）。19 個 `v0.1.0` 仍在 `28a8647`，不動 | §1、§3.5、§4.12、§4.23、§4.31、§4.32、§5.3、§5.6、§7.3、implement-process Phase 12、16、17 |
| 55 | §9.5 Q1 定案：KB 資料庫帳號的 Secrets Manager secret 由範本的 `agent` 建，每個 KB 一個 `<project>-<env>-kb-<key>-db`，用 `foundation` 的專案 KMS key 加密，Terraform 不寫值（不建 secret version）。tfvars 的 `knowledge_bases[*].credentials_secret_arn` 移除。KB 分兩段：`database_user_ready`（預設 `false`）為 `false` 時只建 secret 與語料 bucket；專案用 `put-secret-value` 寫入 `{"username":"bedrock_kb_user","password":…}`、跑 migration 的 `ALTER ROLE` 設同一個密碼，改成 `true` 後依序 apply `agent` → `iam-app` → `application`。S8 的例外清單加 `agent:aws_secretsmanager_secret`。Runtime 不能列還沒 ready 的 KB（`agent` 的 validation），`iam-app` 的 `agent_access` 也不能（precondition，`8b840ea`）。`agent/knowledge_bases` 多 `ready` 欄位，ready 之前 `id`、`arn` 是 `null`。取代決策 53 的「專案自己建 secret、`agent` 收 ARN」與原本「precondition 擋 master secret」那條：現在 KB 用的就是 `agent` 建的 secret，結構上填不進 master secret（測試 `kb_uses_the_secret_it_created`） | 使用者決定（2026-10-16）。KMS key、名稱、`iam-app` 的 Resource 一定對得上，`agent` 不必再檢查 ARN 的帳號與 region；代價是 S8 多一個例外，以及 `agent` destroy 後同名 secret 在 7–30 天的復原期內會撞名。KB 建立時會不會檢查資料庫帳號沒有實測，所以照「會檢查」排成兩段 | §4.30、§5.3、§5.4、§5.6、§7.1、§7.3、§8.8、§9.5 |
| 56 | 模組安全審查加上 Phase 14 審查留下的項目，一起補強：同帳號檢查加 `allowed_account_ids`（Gateway 的 Lambda target、Runtime 的 ECR 映像、log-delivery 的 source 與 CWL 目的地、KB 的 cluster／secret／語料 bucket 擁有者，`bucket_owner_account_id` 改必填）；三個 module 統一 `role_arn` regex、允許 IAM path（解掉 D36）；inference profile 加 `Name` tag（解掉 D31）；KMS key ARN validation 收多區域的 `mrk-` key；guardrail 的 PII 類型白名單；JWT 的空白項目擋掉；Runtime 的請求標頭黑名單，`Authorization` 只在有 JWT authorizer 時可以轉；Runtime 擋名稱像 secret 的環境變數，以 `_ARN` 結尾而且值是 ARN 的放行（取代 J62）；`s3-bucket` 的 `never_expire` 不准配 `log_delivery`；`iam-role` 的 `trust.source_arn`，用在三種 agent 服務角色（M1，ARN 形狀未實測）；KB role 的 `kms:EncryptionContext:SecretARN` 與 S3 的 `aws:ResourceAccount`（M4）；沒有 NAT 時 Runtime SG 的 egress 只到 VPC CIDR（L4）；每個 Runtime 都有帶 `bedrock-agentcore` namespace 條件的 `cloudwatch:PutMetricData`（所以每個 Runtime 都有 policy），`GetWorkloadAccessToken*` 只給 `workload_identity = true` 的 Runtime（L5，未實測）；guardrail 維持 `DRAFT`（決策 46 不變），建議用 SCP 或 permission boundary 把 `bedrock:UpdateGuardrail`、`DeleteGuardrail` 限給部署用的 role（L1）。L2、L3 由環境變數檢查與 Lambda 同帳號檢查涵蓋。`iam-role` 因此加入 `v0.1.1`（共 10 個） | 使用者決定（2026-10-16）。tag 都還沒推，併進同一批 `v0.1.1` 比多發一版單純；跨帳號是少數情況，預設擋、要用的人明列 | §1、§3.5、§4.14、§4.23、§4.30、§4.32、§5.3、§5.4、§5.6、§7.1、§7.3、§8.8、implement-process Phase 17 |

### 9.3 待補資訊（不需要拍板，名稱定了填入即可）

| 項目 | 目前的佔位符 | 出現在 |
|---|---|---|
| GitHub org | `<org>` | §3.3、§3.6、§4.22、§5.1、§8.7 的 source 範例 |
| repo 名稱 | `<repo>` | 同上 |
| CODEOWNERS 的 team slug | `@<org>/platform-team`、`@<org>/core-app-team`、`@<org>/project-app-reps`、`@<org>/fde-team` | §6.3 |
| state bucket 命名，以及由誰建立 | `<state-bucket>` | §5.5 |

### 9.4 核對第一手來源時發現跟規劃簡報不一致的地方

| # | 簡報寫的 | 實際 | 影響 |
|---|---|---|---|
| D1 | project-c 的告警在 `project-c-infra` 或 app module | 在 `project-c-app/modules/app-platform/cloudwatch-alarms.tf`（不是 `app-service`）；檔頭編號列 19 項（含 EventBridge 與 Bedrock），檔內實際是 22 個 alarm 資源 | 只影響引用路徑，本文已用正確路徑 |
| D2 | project-c AWS provider 釘死 6.44 | sit、prod 釘 `6.44`，uat 是 `~> 6.0` | 可以當成「版本不一致」的現況證據（§2.1） |
| D3 | project-c step scaling「冷卻註解寫 60 秒但 locals 是 180 秒」 | `project-c-app/modules/app-service/ecs-autoscaling.tf` 的 locals 是 180 秒，註解寫「3 min」，一致；60 只出現在指標週期 | 簡報這點未能證實，本文沒有引用 |
| D4 | project-c cluster 的 FARGATE 預設策略 | `base = 1`（`project-c-infra/modules/infra-platform/ecs.tf`）；project-a 是 `base = 0` | 本文預設 `base = 0`，可由變數調整 |
| D5 | project-a `application` 讀「樹 B」 | 確認：`application/common.tf` 的 `ssm_prefix = "/shared/infra"`，`foundation` 等是 `/project-a/<env_label>` | 與簡報一致；另外確認 `common.tf` 在 11 個 stack 間有 5 種版本，`check-ssm-contract.sh` 沒有被 CI、Makefile 或 `scripts/` 呼叫 |
| D6 | 範本 stack 清單（簡報 4.2） | project-a 有 `containerimage`（ECR），範本沒有對應的 stack | 已拍板新增 `containerimage`（§9.2 決策 3）；之後再加上 `iam` 拆分，範本為 8 個 stack（決策 20） |
| D7 | `postdeploy` 預設全關會規劃刪 27 個資源 | 確認 5 個 `*_enabled` 預設 `false`；27 這個數字本次沒有重算 | 本文引用時標註「簡報記為 27 個，本次未重算」 |
| D8 | 範例 `core` module | 除了 cluster 還建 execution role 並掛 `AmazonECSTaskExecutionRolePolicy` | 本設計不沿用（§4.2、§8.1） |
| D9 | （三層架構研究）project-a 的 ALB 有 HTTPS listener | `project-a/docs/spec/infra.md`〈入口負載平衡器與 WAF 防護〉寫 `chat_domain_name` 非空時 MUST 啟用 HTTPS:443 與 TLS 1.3 policy，但 `project-a/infra-v2/terraform/loadbalancer/alb.tf` 只有 `aws_lb_listener.chat_http`（HTTP:80），預設 action 回 403 | spec 與實作不一致，屬於 project-a 的問題；本設計的 `alb` 照 spec 的行為寫（有憑證才開 443），不照 project-a 的實作 |
| D10 | project-a 的 loadbalancer tfvars | `loadbalancer/envs/{uat,prod}.tfvars` 含明文的 `chat_origin_lock_header_value`；這兩個檔沒進版控 | 範本不得照抄，記在 §5.10 的「修掉的坑」 |
| D11 | 參數群組的 family | Aurora 的 cluster 與 instance 參數群組 family 都是 `aurora-postgresql<major>`（project-a `database/rds.tf` 用 `aurora-postgresql16`）；只有一般 RDS 是 `postgres<major>` | `rds` module 照這個對應（§4.9） |
| D12 | 三層架構增補文件：project-c Serverless「備份 14 天」 | 只有 prod 是 14 天；uat 是 7 天。prod 的 tfvars 註解寫 0.5～4 ACU，實際值是 2～16（`project-c-app/environments/{uat,prod}/project-c/platform/terraform.tfvars`） | §5.11 依據表照原始碼寫 |
| D13 | 三層架構增補文件：project-a「Proxy 在約 100 QPS 下零錯誤」 | 報告寫的是 48 小時零錯誤、零逾時，報告裡流量最高的小時是 238 輪對話，沒有 100 QPS 的數字（`project-a/docs/reports/2026-09-18-prod-latency-breakdown.md`） | §5.11 依據表改寫，並標明是低流量下的結果 |
| D14 | 三層架構增補文件：project-c VPC 大小與 NAT 的來源 | VPC CIDR、subnet、NAT 設定在 `project-c-infra/environments/{uat,prod}/network/terraform.tfvars`；CE-1149 的註解在同一份檔與 `uat/network/routes.tf`。interface endpoint 清單確實在 `uat/platform/terraform.tfvars` | 只影響引用路徑 |
| D15 | 三層架構增補文件：「9,000 RPM 約需 12.2 個 task」 | 報告寫的是「目標 150 則／秒對應 12.2 個 task，落在已驗證的區間之外」，是外推值（`project-a/docs/reports/2026-09-19-first-turn-ttft-cold-provisioning/README.md`） | §5.11 依據表標明是推算 |
| D16 | 三層架構增補文件：「J7 是 ELB 5xx 那條」 | 本文件原本的編號就是 J4，增補文件寫 J7 是筆誤 | 本次改寫 J4 |
| D17 | （第二輪增補）8 個 module 實作與 design 的差異 | 已回寫到各 module 章節：vpc 移除中間 AZ 時 CIDR 位移、多兩條檢查；rds 的 `[0]` 位址、`<name>-writer`／`<name>-reader-N`、random provider、`pending-reboot` 只用在 `shared_preload_libraries`、validation 較多、`sns_topic_arns` 的 regex 結尾 `.+` 較寬；ecs-service 的 `step[...]`／`scaling[...]` 位址與 key、`service_arn` 取 `.id`、region 從 `cluster_arn` 拆、log driver 多兩個固定選項；ecs-service-alarms 告警集中在 `this[<key>]`；alb ELB 5xx 用 `GreaterThanOrEqualToThreshold`、404 本文 `Not Found`。另外：examples 目錄不是 `basic`（alb 是 `http-only`、`https`，rds 是 `rds`、`aurora-serverless-proxy`），測試依主題拆多檔，§4.1 已放寬；alb 的 listener 與告警、ecs-service-alarms 的告警只帶 `var.tags`、沒有加 `Name`，rds 的告警有加，**各 module 不一致** | 以程式碼為準。兩項列為**待統一**，這次不改程式碼：(1) 會建告警與 listener 的 module 一律在 tags 加 `Name`；(2) `sns_topic_arns` 的 ARN regex 統一成同一條（建議 alb／ecs-service-alarms 的 `[A-Za-z0-9_-]+$` 結尾）。之後一起以 PATCH 版發布 |
| D18 | （Phase 7 A–D）7 個新 module 的實作與 design 的差異 | 已回寫：`iam-role`、`iam-role-policy` 的 validation 改成三條（`Statement[0]` 要求非空清單、迴圈用 `try(..., [])` 讓非 JSON 能被 `expect_failures` 接到、Allow 不准 `NotAction`），兩個 module 一字不差；`kms-key` 的 `administrator_arns` regex 結尾 `[^*]+$` 擋 `role/*`，管理者 statement 的動作清單與服務 statement 的 Sid 規則寫進 §4.10；`s3-bucket` 在 SSE-KMS 時 `bucket_key_enabled = true`；`security-group` 的 `ip_protocol` 只收 `tcp`／`udp`／`-1`、`vpc_id` 有格式 validation、規則的 `Name` tag 是規則的 key，另記兩個已知限制（主機位元、兩個 `/1` 繞過 `allow_internet`）。`ecr-repository`、`ssm-read` 核對後與 design 一致 | 以程式碼為準 |
| D19 | （Phase 7 完成）實作與 design 的差異 | 已回寫：`iam-role`、`iam-role-policy` 新增第四條「Allow 不准 `NotResource`」（決策 35）；`log-group` 的 subscription filter 名稱用 `var.name`，`role_arn` 是 provider 的 optional 加 computed，Lambda 目的地時為 null 只能靠程式碼保證；`log-metric-alarm` 的 `default_value` 在 module 內 `tostring()`，metric filter 不帶 tag；`xray` 的 `version = 1`、`resource_arn = "*"` 寫死；ADOT 範例的 sidecar 改成 `essential = false`；`vpc-interface-endpoints` 的 ingress rule 加 `Name` tag。另外：`allowed_cidrs` 有多個時，每條 ingress rule 的 `Name` 都是同一個 `<name>-vpce-https`，不影響運作，只是在 console 分不出哪一條對應哪個 CIDR | 以程式碼為準；`Name` 相同這點建議下一個 PATCH 版改成帶 CIDR，列為待統一 |
| D20 | （Phase 8 完成，`e71db48`）範本 8 個 stack 的實作與 design 的差異 | 已回寫：`network/nat` 在客戶自管模式 A 發布 `{"mode":"external","ids":[]}`（§5.6 合約表）；`ssm-inputs.tf` 一律先把 key 清單放進 local 再傳給 `module "in"`，因為 `terraform test` 讀不到 module 的輸入值；`iam-base` 與 `application` 多一個 `module "in_services"` 讀每個服務一組的 key（§5.6 讀取寫法）；SG 之間的每條連線展開成「來源 egress ＋ 目的 ingress」兩條，規則數等於展開後的數量（§5.3 規則表）。另外：規則 key 實作是 `alb_in_<port>_<來源>`、`<來源>_out_<目的>`、`<目的>_in_<來源>`，跟 §4.16 範例的 `alb_in_https`、`api_out_proxy`、`db_in_proxy` 寫法不同（範例的規則 key 把 `db_proxy` 簡寫成 `proxy`，實作一律用完整的 SG key，例如 `api_out_db_proxy`、`db_in_db_proxy`）；測試的寫法差異記在 implement-process 的 Phase 8 節與風險表 R15、R16 | 以程式碼為準；§4.16 的範例只示意展開方式，規則 key 不改 |
| D21 | （Phase 8 發現）三個 module 的小問題，之後發版處理 | `ecs-service` 的 `cpu`、`memory`、`cpu_architecture`、`desired_count` 有預設值但沒有 `nullable = false`，呼叫端傳 `null` 時不會套預設（`cpu_architecture` 會直接被 validation 擋下），範本在 `application` 的 `optional(..., 預設)` 補上同樣的值；`rds` 的輸出沒有 `deployment` 與資料庫名稱，`data` stack 發布 `database` JSON 時只能取自己的 `var.db`；`vpc-interface-endpoints` 在 `services = []`、什麼都不建時仍然要求至少 2 個 subnet；範本兩種模式的 app tier 都至少有 2 個 subnet，目前不受影響，但其他呼叫端不建 endpoint 也得給 subnet | 列為待辦，等級照 §3.5：`ecs-service` 補 `nullable = false` 是 PATCH（修正傳 `null` 時沒套預設的行為）；`rds` 新增輸出、`vpc-interface-endpoints` 在 `services` 為空時不檢查 subnet 是 MINOR（向下相容的新功能與放寬 validation）。修之前範本的寫法不用改。增補：`rds` 那一項併進 `rds-v0.2.0`（版本號已被決策 54 取代：改發 `rds-v0.1.1`），輸出名稱是 `deployment`、`database_name`（決策 52，§4.31）；其他兩項仍是待辦 |
| D22 | （LLM 增補規劃稿）「19 個 `v0.1.0` tag 在 `3a15b26`」 | 2026-10-15 改寫 git 歷史之後，19 個 tag 在 `28a8647`（`git tag --points-at 28a8647` 是 19 個） | implement-process Phase 11–16 的驗收指令改用 `git rev-parse <module>-v0.1.0^{commit}`，不寫死 hash |
| D23 | （規劃稿）Lambda target 的工具定義收 `tool_schema_json` 字串 | aws 6.69.0 的 schema：`target_configuration.mcp.lambda.tool_schema.inline_payload` 是多層 block（`input_schema` → `property` → `items` …，第三層之後才有 `properties_json`／`items_json` 字串），不是 JSON 字串；`tool_schema.s3.uri` 對 Lambda 是 optional、對 MCP server 是必填；MCP server 的 inline payload 才是字串 | `agentcore-gateway` 改收 `tool_schema_s3_uri` 或扁平的 `tools`（J54） |
| D24 | （規劃稿）Memory 的自訂 strategy「各要 `model_id`」 | schema 的 `configuration.extraction`／`consolidation`／`reflection` 除了 `model_id` 還必填 `append_to_prompt`，`reflection` 另外必填 `namespace_templates` | 第一版不收自訂 strategy（J52），不影響介面 |
| D25 | （規劃稿）KB 的 `rds_configuration.field_mapping` 有四個欄位 | schema 有五個：`primary_key_field`、`vector_field`、`text_field`、`metadata_field` 必填，另有 optional 的 `custom_metadata_field` | `bedrock-knowledge-base` 收五個，第五個預設 null（§4.30） |
| D26 | （規劃稿）省略 `tier_config` 就是 `CLASSIC` | 確認，而且 schema 裡 `tier_config` 是 optional 加 **computed**：省略之後 AWS 回填 `CLASSIC`，之後的 plan 不會出現差異，事後也看不出來 | module 一律明寫（§4.24） |
| D27 | （規劃稿）Gateway 的參考 project-b「OpenAPI 經 VPC Lattice 失敗」引用 `gateway.tf:105-110` | 註解在第 109–113 行；另外檔頭寫明 Lambda target 是「legacy, currently unused」，所以 Lambda target 也沒有部署過的證據 | §4.28 照實寫「沒有部署過的證據」 |
| D28 | （規劃稿）`rds` 要為 KB 新增 cluster ARN 輸出 | 不用：既有的 `arn` 輸出在 Aurora 時就是 cluster ARN | `rds-v0.2.0`（版本號已被決策 54 取代：改發 `rds-v0.1.1`） 不為 KB 加 cluster ARN 輸出；後來另外併進 D21 的 `deployment`、`database_name` 兩個輸出（決策 52，§4.31），跟 KB 無關 |
| D29 | （規劃稿）`global.` 前綴的模型另外列一條空 region 的 foundation-model ARN | 保留。project-a 的跨帳號 runbook 寫「foundation-model 那條的 region 必須是 `*`」，但同一個專案的批次評分角色仍列了空 region 那一條，註解寫「`*` 能不能涵蓋空 region，沒有在這個角色上實測過」（`project-a/infra-v2/terraform/iam/judge-batch-role.tf:71-78`） | `invoke_arns` 對 `global` 前綴多一條空 region 的 ARN，標未實測（§5.3 增補、§7.3 第 23 項） |
| D30 | （Phase 13，`ea0a365`）`bedrock-guardrail` 的實作與 design 的差異 | 已回寫 §4.24、§7.1：`tier_config` 在 provider 6.69.0 是 list 型別的屬性，寫成 `tier_config = [{ tier_name = var.tier }]`，不是 block；region 取 `data.aws_region.current.region`（`.name` 已 deprecated）；topic 的 `type = "DENY"` 寫死；多兩條 validation：`contextual_grounding` 給了就至少要有一個門檻、`managed_word_lists` 只收 `PROFANITY`；「至少一種 policy」是 resource 的 lifecycle precondition，不是變數 validation；多一個 `examples/zh-tw-standard`（implement-process 原本就列了，§4.24 補上） | 以程式碼為準 |
| D31 | （Phase 13，`71e7550`）`bedrock-inference-profile` 的實作與 design 的差異 | 已回寫 §4.23、§4.25、§7.1、§7.3 第 18 項：名稱字元規則（`^([0-9a-zA-Z:.][ _-]?)+$`，照 AWS 文件）寫成第二條 validation，仍**未實測**；`copy_from` 給 application inference profile 的 ARN 會被擋，有測試鎖住；64 字上限 provider 自己也會擋。另外（實作者沒有回報，核對程式碼時發現）：profile 的 `tags = var.tags`，**沒有加 `Name`**，跟 §4.1 的約定不同，README 與 CHANGELOG 都沒有說明理由 | 以程式碼為準；`Name` 這點跟 D17 同類，列為待統一，要補的話是 MINOR（只改 tag，不 replace）（決策 56 已補：`Name = <name_prefix>-<key>`，`e39b772`） |
| D32 | （Phase 13，`1948aba`）`agentcore-runtime` 的實作與 design 的差異 | 已回寫 §4.26、§7.1、§7.3 第 18 項：`security_group_ids` 也要不重複；`jwt_authorizer` 的 `allowed_audience`、`allowed_clients` 空集合時送 `null`；`environment_variables` 空 map 時送 `null`，理由是「空 map 讀回來是 null、送 `{}` 會永遠有差異」，這是**未實測的推測**；`network`、`protocol`、`environment_variables`、`request_header_allowlist` 也加了 `nullable = false`（design 原本只有 `session_lifecycle` 有）；不建 endpoint 資源（已是 J53，不是新差異） | 以程式碼為準 |
| D33 | （Phase 13，`8708820`）`agentcore-memory` 的實作與 design 的差異 | 已回寫 §4.27、§5.3〈增補：`agent` stack〉的 `memories`、§7.1、§7.3 第 18 項：`event_expiry_days` 的下限是 **7**，不是 3。aws provider 6.69.0 在 plan 階段就擋 7 以下的值（`value must be between 7 and 365, got: 3`，主 agent 實測確認），API 文件與 project-a 寫的 3 用這個 provider 版本送不出去；strategy 的 `namespaces` 輸入送進 provider 的 `namespace_templates`（provider 把 `namespaces` 標成 deprecated），輸入名稱不變；strategy 名稱就是 `strategies` 的 key，規則同 Memory 名稱；`event_expiry_days`、`strategies` 是 `nullable = false` | 以程式碼為準。收緊下限在 v0.1.0 之前，不涉及版本規則；範本 `agent` 的 `memories` 預設 90，不受影響 |
| D34 | （Phase 13，`4048dbf`）`agentcore-gateway` 的實作與 design 的差異 | 已回寫 §4.28、§5.3 的 `agentcore_gateway`、§7.1、§7.3 第 18、20 項：gateway 名稱與 target key 不得有連續的 `--`；`tool_schema_s3_uri` 必須是 `s3://<bucket>/<key>`；`lambda_arn` 必須是 Lambda function ARN（可帶 alias 或版本）；`authorizer`、`targets` 是 `nullable = false`；target 名稱就是 `targets` 的 key；`properties` 是空 map 時仍送 `input_schema { type = "object" }`（**未實測**）；`mcp.search_type` 沒有 validation。新的未實測項目併進 §7.3 第 20 項（不帶 outbound 認證的 MCP server target 原本就在第 20 項，沒有另開）：空 `properties`、`array`／`object` 屬性不帶 `items` | 以程式碼為準 |
| D35 | （Phase 13，`0c79364`）`log-delivery` 的實作與 design 的差異 | 已回寫 §4.23、§4.29、§7.1：design 寫的 `replace_triggered_by = [aws_cloudwatch_log_delivery_source.this[each.value.source].resource_arn]` 在 Terraform 1.15.8 不成立（`replace_triggered_by` 只能用 `each.key` 索引別的 resource）。實作改成每個 delivery 一個 `terraform_data.source_arn`（`input` 是對應 source 的 `resource_arn`），delivery 寫 `replace_triggered_by = [terraform_data.source_arn[each.key].output]`，意圖相同（只看 ARN，source 只改 tag 時不重建 delivery）；delivery 只帶輸入的 `tags`，沒有 `Name`；`record_fields`、`field_delimiter` 在 schema 是 optional 加 computed，module 不送 | 以程式碼為準；delivery 的 `Name` 列為待統一（同 D17）。§7.3 第 19 項「Runtime 重建時 delivery 一起替換」的實測仍要做，寫法換了不影響要驗的事 |
| D36 | （Phase 13，`36d6ee5`）`bedrock-knowledge-base` 的實作與 design 的差異 | 已回寫 §4.30、§5.3 的 `knowledge_bases`、§7.1、§7.3 第 21 項：`role_arn` 有格式 validation，而且**允許帶 path**（`agentcore-runtime`、`agentcore-gateway` 不允許）；data source 名稱就是 `data_sources` 的 key，規則同 KB 名稱；`inclusion_prefixes` 空集合時送 `null`；`kms_key_arn` 套到每個 data source 的 `server_side_encryption_configuration`；`cluster_arn` 的 cluster id 收大寫；provider 6.69.0 自己也在 plan 時擋 `overlap_percentage` 1–99 以外的值，原本標「未實測」的這個範圍由 provider 確認（實作者回報，module README 有記載）。新的未查證項目：`inclusion_prefixes` 有沒有數量上限（§7.3 第 21 項） | 以程式碼為準。`role_arn` 是否帶 path 三個 module 不一致，列為待統一（決策 56 已統一：三個都允許 path，同一條 regex） |
| D37 | （Phase 14）`agent` stack 的輸入檢查與 design 的差異 | 已回寫 §5.3〈增補：`agent` stack〉：design 的 precondition 表多數實作成變數 validation（參照存在、`subnet_tier`、語料 bucket 名稱、跨帳號、KB secret 的格式／region／帳號、保留的環境變數名稱），只有要讀 SSM 才判斷得了的留在 `guards.tf`；`subnet_tier` 存不存在不另寫檢查，由讀 `network/subnet_ids_<tier>` 時讀不到讓 plan 失敗；`knowledge_bases[*].field_mapping` 是五個欄位的 object，不是 `map(string)`；`guardrails` 寫成與 `bedrock-guardrail` 相同欄位的 object；另外多了 key 必須是 kebab-case（`models`、`guardrails`、`memories`、`knowledge_bases`）、Memory 名稱 48 字、`foundation_model_id` 不帶地區前綴、`inference_profile_prefix` 只收小寫字母；保留的環境變數連 `OTEL_` 整個前綴都擋；沒有 NAT 的條件式 endpoint（`xray`、`bedrock-agent-runtime`）與 Gateway 的阻擋只看 VPC 模式的 Runtime；`agent` 不讀 `foundation`。design 原本寫的「`bedrock_invoke` 啟用時 KB 不得引用模型」跟 J66 矛盾，實作照 J66 不擋 | 以程式碼為準。刪掉那一句是修正 design 自己的矛盾，不是新的決定 |
| D38 | （Phase 14）`agent` 建的資源與環境變數 | 已回寫 §5.3：Runtime 的 `OTEL_*` 固定六個（`OTEL_SERVICE_NAME = <project>-<env>-<rt>`、`OTEL_TRACES_EXPORTER = otlp`、`OTEL_EXPORTER_OTLP_PROTOCOL = http/protobuf`、`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = https://xray.<region>.amazonaws.com/v1/traces`、`OTEL_METRICS_EXPORTER = none`、`OTEL_LOGS_EXPORTER = none`），不再指向 project-a 的檔案；KB 的 `embedding_model_arn` 與 tracked 模型在沒有 prefix 時的 `copy_from` 是本 region 的 foundation model ARN（IAM 的 `invoke_arns` 仍是 region `*`）；log delivery 是 `module "runtime_logs"`（`count`），CWL destination 名稱是 `<project>-<env>-<rt>`、X-Ray destination 是 `<project>-<env>-xray_traces`；Gateway 的 `for_each` key 是 `this`；KB 在資料庫條件不成立時不建，讓 precondition 成為唯一的錯誤；Runtime 的 log group 不加密。`agent` 另有 `outputs.tf`：`runtime_arns`、`corpus_bucket_names` | 以程式碼為準。§7.3 第 19 項加上 OTEL 變數送不送得出 trace 的實測 |
| D39 | （Phase 14）`agent/knowledge_bases` 多一個欄位 | 已回寫 §5.3〈`agent` 發布的 key〉與 §5.6 合約表：每個 KB 多 `data_source_ids`（data source 的 key → data source id），給跑 `StartIngestionJob` 的人或 CI 用，沒有 stack 讀；`inclusion_prefixes` 的形狀寫明是「data source key → 已排序的清單」；§5.6 原本合併的 `agent_memories`、`knowledge_bases` 一列拆成兩列。照 §5.6「新增欄位是相容的」 | 以程式碼為準。範本 `infra/README.md` 的合約表已補上 `data_source_ids` |
| D40 | （Phase 14）既有 6 個 stack 的接線與 design 的差異 | 已回寫 §5.3、§5.4、§5.6：`network` 為每個 Runtime 都建 SG 並發布 `sg_agent_<rt>_id`（它不知道 `network_mode`，`PUBLIC` 的也建），egress 規則 key 是 `agent_<rt>_out_https`，`agent_data_access` 只列至少有一個 Runtime 的 data store，另擋 SG key `agent_<rt>` 跟服務撞名；`iam-base` 的 Runtime execution role 的 log 權限拆成兩條（log group 上 `CreateLogGroup`、`DescribeLogStreams`；log stream 上 `CreateLogStream`、`PutLogEvents`），policy 名稱 `pull-and-log`；`iam-app` 多讀 `containerimage/agent_runtimes`、`network/agent_data_access`，Gateway role 的 ARN 只在有 Lambda target 時讀，沒有任何權限的 Runtime 不呼叫 `iam-role-policy`，Runtime 讀 DB secret 與 `agent` 注入 `DB_*` 都只看 `agent_data_access` 的 `db` 名單，KB role 的 S3 權限每個 KB 各一組、只要有一個 data source 沒給 prefix 就整個 bucket；`application` 的第二個 `ssm-read`（`in_agent`）只在 `agent_access` 有列服務時讀 `agent` 與 `network/nat`、`interface_endpoints` | 以程式碼為準。只看 `db` 這點跟範本的資料庫 data store key 綁在一起，專案另加 data store 時要記得 |
| D41 | （Phase 14）測試與範例 | 已回寫 §7.1：新增「範本 Phase 14 的測試」表，run 名稱照程式碼；implement-process 計畫裡的單一 run 多半拆成「被擋」與「通過」兩個。`agent` 跟 `network`、`data`、`loadbalancer`、`application` 一樣有 `envs/examples/{poc,standard,high}.tfvars` 與 `tests/examples/`；§7.1 原本只列 `network`、`data`、`loadbalancer`，連 Phase 9 補充之後的 `application` 也漏了，一併改。run 區塊數：`agent` 91、`application` 67、`containerimage` 48、`data` 33、`foundation` 22、`iam-app` 53、`iam-base` 32、`loadbalancer` 27、`network` 89，共 462（Phase 14 之前 310；含安全審查後補的 5 個，見 D42–D44） | 以程式碼為準。run 區塊數不等於 `validate.sh` 回報的 `n passed`：`tests/tfvars/` 對 dev、prod 各跑一次，`tests/examples/` 對每個範例各跑一次 |
| D42 | （Phase 14 安全審查）Gateway role 讀不到 S3 上的工具定義 | 已回寫 §5.3〈`agent` 發布的 key〉、§5.4 的 Gateway role、§5.6、§7.3 第 20 項：`agent/agentcore_gateway` 多發布 `tool_schema_arns`（只取 Lambda target 的 `tool_schema_s3_uri`，轉成確切的 S3 物件 ARN）；`iam-app` 的 Gateway role policy 多一條 `Sid = "ReadToolSchemas"` 的 `s3:GetObject`，Resource 恰為這些 ARN，清單是空的時不加。design 原本的 Gateway role 只有 `lambda:InvokeFunction` | 以程式碼為準。新增欄位，照 §5.6「新增欄位是相容的」 |
| D43 | （Phase 14 安全審查）KB secret ARN 必須是確切值 | 已回寫 §5.3 的 `knowledge_bases` 與 precondition 表、§5.4 的 KB role、§5.6、§8.8：`credentials_secret_arn` 的 validation 改成 `^arn:aws:secretsmanager:<region>:<account>:secret:[A-Za-z0-9/_+=.@!-]+-[A-Za-z0-9]{6}$`（完整 ARN、6 字元後綴、不准萬用字元；`!` 是為了 RDS 管理的 `rds!...` 名稱）；`iam-app` 新增 `terraform_data.knowledge_base_secrets_are_exact`，在授權這一端對 `agent/knowledge_bases` 發布的值用同一條 regex 再檢查一次。原本只檢查「是 Secrets Manager ARN、region 與帳號相符、不等於 master」，`...:secret:*` 會通過，KB role 因此讀得到 master secret | 以程式碼為準 |
| D44 | （Phase 14 安全審查）沒有 NAT 時讀 DB secret 的 endpoint | 已回寫 §5.3 的「沒有 NAT」precondition 與 interface endpoint 對照表、§7.3 第 21 項：`nat.mode = "none"` 而且有 VPC 模式的 Runtime 在 `network/agent_data_access` 的 `db` 名單上時，另外要求 `secretsmanager` endpoint（Runtime 用 execution role 讀 `DB_SECRET_ARN`） | 以程式碼為準。這是推論，**未實測** |
| D45 | （Phase 14）已部署環境的升級順序與 stack 編號 | 已回寫 §5.3〈增補：`agent` stack〉：既有環境升級時也從 `containerimage` 照順序逐一 apply、不能跳過 `agent`（`iam-base`、`iam-app`、`application` 無條件讀新的 key），什麼都沒開時只多出 SSM 參數；增補表的順序欄原本是 `agent` 5a、`iam-app` 6、`application` 8，改成跟範本 `infra/README.md` 一樣的 1–9（`agent` 6、`iam-app` 7、`loadbalancer` 8、`application` 9） | 以程式碼與範本 README 為準 |
| D46 | （Phase 14 安全審查）記錄但這一輪不修的風險 | 寫進 §8.8〈已知風險，這一輪不修〉：M1 新服務角色的 trust 沒有 `aws:SourceArn`；M4 KB role 的 `kms:Decrypt` 沒有 `kms:EncryptionContext:SecretARN`、S3 statement 沒有 `aws:ResourceAccount`；L1 guardrail `DRAFT` 可變；L2 Runtime `environment` 擋不住 secret（會進 state）；L3 Gateway `lambda_arn` 沒有限定本帳號；L4 Runtime SG 的 443 egress 對 `0.0.0.0/0`；L5 Runtime execution role 沒有 `GetWorkloadAccessToken*` 與 CloudWatch metrics 權限（不支援 AgentCore Identity，未實測） | 沒有改程式碼。M1 屬於決策 47 已延後的範圍（決策 56 逐項處理，結果寫在 §8.8 那張表的最後一欄） |

### 9.5 待決事項（需要使用者決定）

| # | 問題 | 現在的寫法 | 另一個選項 | 主 agent 的看法 |
|---|---|---|---|---|
| ~~Q1~~（已由決策 55 定案：範本的 `agent` 建） | KB 帳號的 Secrets Manager secret 容器由誰建 | 照使用者的決定（決策 53）：專案在範本外自己建，`agent` 只收 ARN | 範本建容器、不含值（比照 `foundation` 的 `aws_secretsmanager_secret.app`，決策 30）：例如 `agent` 依 `knowledge_bases` 的 key 建 `<project>-<env>-kb-<key>-db`，用專案 key 加密，發布 ARN；值仍由專案寫入 | 範本建的好處是 KMS key、名稱、tag 一致，`agent` 不必再檢查 ARN 的帳號與 region，`iam-app` 的 Resource 也一定對得上；代價是 §5.3 的原生 resource 例外清單多一列（S8 跟著改），而且 secret 刪除有 7–30 天的復原期，`agent` destroy 後重建同名 secret 會撞名。這是取捨，不是對錯，沒有替使用者決定 |
