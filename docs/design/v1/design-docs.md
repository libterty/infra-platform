# infra-platform v1 設計文件

> 狀態：使用者已拍板（§9.2），可以進入實作；實作步驟見 [`implement-process.md`](./implement-process.md)
> 範圍：第一版（ECS 試行，加上 VPC、RDS、ALB 組成的最小三層架構）
> 文中路徑若沒有特別說明，都相對於 `<workspace>/`。

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
│   └── ssm-publish/
│       （每個都有 main.tf variables.tf outputs.tf versions.tf README.md CHANGELOG.md examples/<情境>/ tests/*.tftest.hcl）
├── templates/
│   └── project-infra/
│       └── infra/terraform/<stack>/...   # §5；8 個 stack，用相對路徑引用 ../../../../../modules/<name>
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
    │   └── observability.md              # ADOT sidecar、X-Ray 權限與抽樣的整套做法（§4.20）
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
- `scripts/vendor-modules.sh` 與 CI 用 `^(vpc|vpc-interface-endpoints|alb|rds|kms-key|ecr-repository|s3-bucket|iam-role|iam-role-policy|security-group|log-group|log-metric-alarm|xray|ssm-read|ecs-cluster|ecs-service|ecs-service-alarms|sns-alarm-topic|ssm-publish)-v[0-9]+\.[0-9]+\.[0-9]+$` 檢查 tag；module 名稱清單從 `modules/` 目錄讀，不手寫。

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
| `versions.tf` | `required_version = ">= 1.10"`；`aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }`；**module 裡不寫 `provider` 與 `backend`** |
| 版本範圍 | module 用範圍（`>= 6.0, < 7.0`），root 用 `~> 6.x` 加 `.terraform.lock.hcl` 釘死實際版本 |
| lock 檔 | **module 不提交 `.terraform.lock.hcl`**（Terraform 只採用 root module 的 lock，module 的 lock 對消費端沒有作用）；範本的每個 stack 是 root，要提交 |
| 依賴 | 一律從外部傳入（cluster ARN、role ARN、subnet、SG、topic ARN），module 之間不互相呼叫，平坦組合 |
| IAM | **只有 `iam-role` 與 `iam-role-policy` 兩個 module 建 IAM**（`aws_iam_role`、`aws_iam_role_policy`）。其他 17 個 module 不建任何 `aws_iam_*`，需要 role 的地方（ECS execution／task role、RDS Proxy role、Enhanced Monitoring role）一律收 ARN；範本的 stack 也一律透過這兩個 module（§5.4）。由 `scripts/validate.sh` 靜態檢查（§5.6 S4） |
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

**用途**：讓一個 task 裡除了主 container `app` 之外，再放 sidecar（例如 ADOT collector、log router）。介面通用，**不寫死 ADOT**；要不要用 ADOT、collector 怎麼設定、task role 給哪些權限，都由專案在 `application` 與 `iam-app` stack 自己決定。

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
| `docs/guides/observability.md`（新增） | 整套做法：collector 設定檔範例（參考 project-c 的 `otel-collector-config.yaml`：OTLP receiver、batch、memory_limiter、濾掉 health check、`awsxray` exporter）、`iam-app` 要給 task role 的 X-Ray 與 CloudWatch 權限（`xray:PutTraceSegments`、`PutTelemetryRecords`、`GetSamplingRules`、`GetSamplingTargets`，只支援 `Resource = "*"`）、`iam-base` 要給 execution role 拉 ADOT 映像的權限、`xray` module 的 sampling rule 怎麼配、「要不要追蹤」用 `iam-app` 發布 `tracing_<service>` 當單一決定點 | 牽涉三個 stack，範本的 stack 預設不開追蹤；放進範本會讓每個專案都背一個預設關閉的 sidecar。guide 不會被 CI 驗證，所以 HCL 片段要跟 module example 對照 |

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

apply 順序：`foundation` → `containerimage` → `network` → `iam-base` → `data` → `iam-app` → `loadbalancer` → `application`；destroy 反序。

| 順序 | stack | 放什麼 | 用到的 module | 擁有者 | 變動頻率 | 讀（SSM，來源 stack） | 寫（SSM key） |
|---|---|---|---|---|---|---|---|
| 1 | `foundation` | 告警 SNS、專案共用 KMS key、Secrets Manager secret 容器（不含值）、flow log bucket、ALB access log bucket | `kms-key`、`sns-alarm-topic`、`s3-bucket` ×2、`ssm-publish`（另有一個原生 resource，見下） | 專案 app team；客戶自管時為客戶 | 低 | — | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| 2 | `containerimage` | 各服務的 ECR repository；**服務清單的單一決定點** | `ecr-repository`（`for_each` 服務）、`ssm-read`、`ssm-publish` | 同上 | 低（新增服務時才動） | `foundation` | `services`、`ecr_<service>_url`、`ecr_<service>_arn` |
| 3 | `network` | VPC（預設建立；模式 A 改登記既有）、interface endpoint、ALB／各服務／DB／Proxy 的 SG | `vpc`、`vpc-interface-endpoints`、`security-group`、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>`、`sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id`、`nat`、`alb_https`、`db_proxy`、`data_access` |
| 4 | `iam-base` | ECS execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | `iam-role` ×3、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | `rds`、`ssm-read`、`ssm-publish` | 同上 | 低 | `foundation`、`network`、`iam-base` | `database`（JSON） |
| 6 | `iam-app` | Proxy role 讀 secret 的 policy、各服務 task role、ECS Exec 開關 | `iam-role-policy`、`iam-role`（`for_each` 服務）、`ssm-read`、`ssm-publish` | 同上 | 低～中（新增服務、調權限時） | `foundation`、`containerimage`、`network`、`iam-base`、`data` | `role_<service>_task_arn`、`ecs_exec_<service>` |
| 7 | `loadbalancer` | ALB、listener、ELB 5xx 告警、WAF 關聯 | `alb`、`ssm-read`、`ssm-publish` | 專案 app team | 低～中 | `foundation`、`network` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| 8 | `application` | ECS cluster、service、autoscaling、服務告警、dashboard、log 告警、X-Ray 抽樣 | `ecs-cluster`、`ecs-service`、`ecs-service-alarms`、`log-metric-alarm`、`xray`、`ssm-read` | 專案 app team | 高 | 前七個 | —（不需要時不發布） |

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

#### stack 裡的原生資源（例外清單）

範本的 stack 原則上只呼叫 module。下表是唯一允許的原生 resource（SG 已改由 `security-group` module 建，不在清單上），`scripts/validate.sh` 依這張表檢查（§5.6 S8）；要加新的例外，先改這張表並寫理由。

| stack | 原生 resource | 理由 | 之後怎麼收 |
|---|---|---|---|
| `foundation` | `aws_secretsmanager_secret`（應用程式 secret 的容器，不含值） | 只有一個 resource、兩三個屬性，包成 module 省不到東西（已拍板，§9.2 決策 30） | 有輪替、跨帳號 policy 這類需求時再做 `secret` module，這一列刪掉 |

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
| `agent`、`operation` | 不在範本 | project-a 特有（AgentCore、Lambda、跳板機），專案自己加 stack |
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
  - ECR 拉映像限定 `containerimage` 發布的 `ecr_<service>_arn`（`ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`、`ecr:BatchCheckLayerAvailability`）；`ecr:GetAuthorizationToken` 只支援 `Resource = "*"`，是例外並寫註解。
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
- 發布 `role_<service>_task_arn`、`ecs_exec_<service>`。

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
| 單一決定點 | 兩個 stack 都要知道的開關，只由上游一個 stack 決定並發布，下游讀，不在兩邊各放一個變數。例：`network/alb_https`、`network/db_proxy`、`network/data_access`、`containerimage/services`、`iam-app/ecs_exec_<service>` |
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
| `network` | `vpc_id`、`vpc_cidr` | String | — |
| `network` | `azs` | StringList | AZ 順序，所有 `subnet_*` 清單都照這個順序 |
| `network` | `subnet_ids_public`、`subnet_ids_app`、`subnet_ids_data` | StringList | 依 AZ 排序。新增其他 tier 時多發布 `subnet_ids_<tier>`，只有需要它的 stack 才去讀 |
| `network` | `subnet_cidrs_<tier>` | StringList | 同上 |
| `network` | `sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id` | String | `sg_vpce_id` 來自 `vpc-interface-endpoints` 的 `security_group_id`；沒有 interface endpoint 時不發布 |
| `network` | `nat` | String（JSON） | `{"mode":"per_az","ids":["nat-...","nat-..."]}`；`none` 時 `ids` 為 `[]`；客戶自管模式 A（登記既有 VPC）時是 `{"mode":"external","ids":[]}`，客戶 VPC 的 NAT 不由我們回報 |
| `network` | `alb_https`、`db_proxy` | String（JSON） | `{"enabled":true}` |
| `network` | `data_access` | String（JSON） | `{"db":["api"]}` |
| `iam-base` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` | String | — |
| `data` | `database` | String（JSON） | 見下 |
| `iam-app` | `role_<service>_task_arn` | String | — |
| `iam-app` | `ecs_exec_<service>` | String（JSON） | `{"enabled":false}` |
| `loadbalancer` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` | String | `listener_arn` 有憑證時是 HTTPS listener，否則是 HTTP；`listener_protocol` 是 `HTTPS` 或 `HTTP` |

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

下游引用 `module.in.strings["vpc_id"]`、`module.in.lists["subnet_ids_app"]`。本地名稱（map 的 key）通常跟 SSM key 同名；同一個 key 名稱在兩個 stack 都有時，本地名稱可以加前綴區分。測試時用 `override_data { target = module.in.data.aws_ssm_parameter.this["network/vpc_id"] ... }` 餵值。

為什麼用 SSM 不用 `terraform_remote_state`：客戶自管的資源不在我們的 state 裡，`remote_state` 讀不到；SSM 是我們跟客戶都能接的介面。project-a 沒有為這個決定寫 ADR，這個 repo 補 `docs/adr/0003-cross-stack-values-via-ssm-only.md`。

`scripts/validate.sh` 的靜態規則（編號沿用 implement-process，S3、S4 依這次的 module 改寫，S8 是新增），全部接進 CI：

| # | 規則 | 說明 |
|---|---|---|
| S1 | 每個 `*.tftest.hcl` 都宣告 `mock_provider "aws"` | 測試不得需要 AWS 憑證 |
| S2 | `resource "aws_ssm_parameter"` 只能出現在 `modules/ssm-publish/` | 只能透過 `ssm-publish` 寫入；範圍含 `modules/` 與 `templates/` |
| S3 | `data "aws_ssm_parameter"` 只能出現在 `modules/ssm-read/`；`modules/ssm-read/` 只讀 `insecure_value`，不得出現 `.value`（`each.value` 是例外：那是 `for_each` 的迭代變數，不是參數的值） | 範本 stack 改用 `ssm-read`，原本「`ssm-inputs.tf` 不讀 `.value`」改由這條涵蓋 |
| S4 | `resource "aws_iam_*"` 只能出現在 `modules/iam-role/` 與 `modules/iam-role-policy/`（後者只允許 `aws_iam_role_policy`），範本的 stack 也不例外；`resource "aws_security_group"`、`aws_vpc_security_group_ingress_rule`、`aws_vpc_security_group_egress_rule` 只能出現在 `modules/security-group/` 與 `modules/vpc-interface-endpoints/`，`modules/vpc/` 與範本的 stack 都不得出現；`resource "aws_default_security_group"` 只能出現在 `modules/vpc/`（§4.7） | 「只有兩個 IAM module 建 IAM」「SG 一律透過 module」的程式檢查（`30f1b38` 起由 `scripts/validate.sh` 執行） |
| S5 | 範本 8 個 stack 的 `common.tf` 雜湊相同 | 修掉 project-a「common.tf 多版本漂移」 |
| S6 | 每份 `envs/<env>.tfbackend` 的 `key` 等於 `<project>-<env>/<stack>/terraform.tfstate`；`envs/examples/` 不得有 tfbackend | 修掉 project-a「key 寫錯讀到別的環境」 |
| S7 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數；`modules/` 底下不得出現 `random_password` | 密碼一律由 RDS 管理 |
| S8 | 範本 stack 裡的 `resource "<type>"` 只能是 §5.3 例外清單上的型別與 stack（目前只有 `foundation` 的 `aws_secretsmanager_secret`） | 「stack 只呼叫 module」的程式檢查 |

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
| 靜態規則 | `scripts/validate.sh` | §5.6 的 S1–S8：每個 test 都用 `mock_provider`、SSM 寫入只在 `ssm-publish`、SSM 讀取只在 `ssm-read`、IAM 只在 `iam-role`、`common.tf` 一致、tfbackend key 格式、`rds` 沒有 password 變數、範本 stack 只有例外清單上的原生 resource | 否 | 否 |

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

範例 tfvars 的驗證方式：`scripts/validate.sh` 對有 `envs/examples/` 的 stack（`network`、`data`、`loadbalancer`），除了一般的 `terraform test`，再對每個範例檔各跑一次 `terraform test -var-file=envs/examples/<x>.tfvars`。這類測試放在 `tests/examples/`（dev、prod 的 tfvars 放在 `tests/tfvars/`），用 `-test-directory` 指定，一般的 `terraform test` 不會跑到它們（Phase 0 已實測：子目錄不會被預設的 `terraform test` 掃到）。測試直接吃範例檔的值，不在 `tests/*.tftest.hcl` 裡再複製一份 `variables {}`：複製一份的話，範例檔改了測試不會跟著變，等於沒驗到範例。這要求這幾個 stack 的測試檔不在 `variables {}` 寫死會蓋掉範例值的變數（`-var-file` 的值會被測試檔的 `variables {}` 覆蓋），斷言也要寫成對任何合法輸入都成立的形式（例如「`nat_mode = per_az` 時 NAT 數等於 AZ 數」，而不是「NAT 數等於 2」）。

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

1. 在沙箱帳號用範本 PoC 規格跑完八個 stack 的 apply，再 destroy（反序；`deletion_protection` 要先關）。
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
13. **X-Ray 抽樣**：用 ADOT sidecar（或 X-Ray SDK）的 remote sampling 確認 `xray` 建的 sampling rule 真的生效（health check 不再進 trace、`fixed_rate` 接近設定值）；確認 SDK 端固定比例抽樣（project-a 的做法）不受 rule 影響；確認 `log-metric-alarm` 的告警在印出事件後一分鐘內轉 ALARM、且 email 收得到。
14. 把 module 版本從 v0.x 升到 v1.0.0（見 §3.5）。

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
- **第一版讓應用程式直接用 master secret，這是已知風險。** master 帳號權限最大（可以改 schema、建帳號），應用程式的 SQL injection 或憑證外洩，影響的是整個資料庫。緩解：只有 `network` 的 `data_access` 名單上的服務能讀（§5.4）；開 Proxy 時應用程式拿到的密碼只用來連 Proxy。之後要補：另建應用程式專用帳號（只給需要的 schema 權限，密碼放另一個 secret），或改用 Proxy 的 IAM 認證，讓應用程式完全不碰密碼。
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
| J27 | 範本 stack 只呼叫 module 的例外 | 只留一個：`foundation` 的 secret 容器（決策 30）；data source 不算例外（`aws_ssm_parameter` 除外）；新增靜態規則 S8 依例外清單檢查 | 例外要是程式擋得住的清單，不然「只呼叫 module」會慢慢失守（§5.3、§5.6） |
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
| J43 | ADOT 範例放哪裡 | `modules/ecs-service/examples/adot-sidecar/`（CI 會驗）加 `docs/guides/observability.md`（整套做法）；範本 stack 預設不放 | 範本預設不開追蹤，放進範本會讓每個專案背一個關著的 sidecar；guide 才寫得下跨三個 stack 的做法。這會在 `docs/guides/` 多一份檔案（§1.1） |
| J44 | ADOT collector 的設定怎麼帶 | 用 `environment` 的 `AOT_CONFIG_CONTENT`，不學 project-c 存成 SSM parameter | 設定不是機密；範本規定 `aws_ssm_parameter` 只能由 `ssm-publish` 建（S2） |
| J45 | `vpc-interface-endpoints` 收 `allowed_cidrs` 還是 `vpc_cidr` | `allowed_cidrs = list(string)`，範本給 `[vpc_cidr]`；不准 `0.0.0.0/0` | 客戶 VPC 可能有 secondary CIDR、或要讓 peering 網段使用；收清單不增加呼叫端負擔，也不用之後改介面 |
| J46 | `services` 為空時 | 不建任何資源，`security_group_id = null` | 範本預設的 PoC 規格沒有 interface endpoint，stack 不需要為了它加 `count` |
| J47 | `aws_default_security_group` 算不算 S4 的範圍 | 不算「新建 SG」，留在 `vpc`；S4 另外寫一條：它只准出現在 `modules/vpc/` | 它接管 VPC 本來就有的 default SG 並清空規則，跟 VPC 生命週期綁在一起；只准在 `vpc`，模式 A 就不會碰到客戶的 default SG |
| J48 | interface endpoint 的 tier 檢查放哪裡 | 從 `vpc` 的 precondition 搬到 network stack 的 validation | module 改收 subnet id，已經不知道 tier；tier 是範本的語意 |
| J49 | private DNS 的前提由誰檢查 | network stack 在模式 A 用 `data "aws_vpc"` 檢查客戶 VPC 有開 `enable_dns_support`、`enable_dns_hostnames`；module 不檢查 | module 拿不到 VPC 屬性；自建 VPC 時 `vpc` 已經固定開啟 |

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
| D20 | （Phase 8 完成，`5858bf4`）範本 8 個 stack 的實作與 design 的差異 | 已回寫：`network/nat` 在客戶自管模式 A 發布 `{"mode":"external","ids":[]}`（§5.6 合約表）；`ssm-inputs.tf` 一律先把 key 清單放進 local 再傳給 `module "in"`，因為 `terraform test` 讀不到 module 的輸入值；`iam-base` 與 `application` 多一個 `module "in_services"` 讀每個服務一組的 key（§5.6 讀取寫法）；SG 之間的每條連線展開成「來源 egress ＋ 目的 ingress」兩條，規則數等於展開後的數量（§5.3 規則表）。另外：規則 key 實作是 `alb_in_<port>_<來源>`、`<來源>_out_<目的>`、`<目的>_in_<來源>`，跟 §4.16 範例的 `alb_in_https`、`api_out_proxy`、`db_in_proxy` 寫法不同（範例的規則 key 把 `db_proxy` 簡寫成 `proxy`，實作一律用完整的 SG key，例如 `api_out_db_proxy`、`db_in_db_proxy`）；測試的寫法差異記在 implement-process 的 Phase 8 節與風險表 R15、R16 | 以程式碼為準；§4.16 的範例只示意展開方式，規則 key 不改 |
| D21 | （Phase 8 發現）三個 module 的小問題，之後發版處理 | `ecs-service` 的 `cpu`、`memory`、`cpu_architecture`、`desired_count` 有預設值但沒有 `nullable = false`，呼叫端傳 `null` 時不會套預設（`cpu_architecture` 會直接被 validation 擋下），範本在 `application` 的 `optional(..., 預設)` 補上同樣的值；`rds` 的輸出沒有 `deployment` 與資料庫名稱，`data` stack 發布 `database` JSON 時只能取自己的 `var.db`；`vpc-interface-endpoints` 在 `services = []`、什麼都不建時仍然要求至少 2 個 subnet；範本兩種模式的 app tier 都至少有 2 個 subnet，目前不受影響，但其他呼叫端不建 endpoint 也得給 subnet | 列為待辦，等級照 §3.5：`ecs-service` 補 `nullable = false` 是 PATCH（修正傳 `null` 時沒套預設的行為）；`rds` 新增輸出、`vpc-interface-endpoints` 在 `services` 為空時不檢查 subnet 是 MINOR（向下相容的新功能與放寬 validation）。修之前範本的寫法不用改 |
