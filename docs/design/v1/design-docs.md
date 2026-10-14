# infra-platform v1 設計文件

> 狀態：使用者已拍板（§9.2），可以進入實作；實作步驟見 [`implement-process.md`](./implement-process.md)
> 範圍：第一版（ECS 試行，加上 VPC、RDS、ALB 組成的最小三層架構）
> 文中路徑若沒有特別說明，都相對於 `<workspace>/`。

## 1. 結論

infra-platform 是Terraform private registry 的範例 repo。它用「Git tag 版本化的 monorepo」發布共用 module，讓各專案用 `?ref=<module>-v<semver>` 釘版本引用，不再每個專案各寫一套 VPC、資料庫、ECS、告警、跨 stack 傳值的程式碼。

第一版做出一個最小的三層架構：ALB 放 public subnet，ECS 服務（AP 層）與資料庫（DB 層）放 private subnet。內容是：

- 8 個 module，起始版本都是 `v0.1.0`：`vpc`、`alb`、`rds`、`ecs-cluster`、`ecs-service`、`ecs-service-alarms`、`sns-alarm-topic`、`ssm-publish`。`rds` 一個 module 支援一般 RDS、Aurora、Aurora Serverless v2 三種型態，RDS Proxy 是選項。
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
│   ├── alb/
│   ├── rds/
│   ├── ecs-cluster/
│   ├── ecs-service/
│   ├── ecs-service-alarms/
│   ├── sns-alarm-topic/
│   └── ssm-publish/
│       （每個都有 main.tf variables.tf outputs.tf versions.tf README.md CHANGELOG.md examples/basic/ tests/<name>.tftest.hcl）
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
    │   └── team-roles.md
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

簡報（`infra-platform/docs/slides/terraform-split/v7/07-infra-core-framework.pptx`）的敘事是「先從 ECS 開始、先試行」。第一版以 ECS 為主，再補上 VPC、ALB、RDS 三個 module，湊成最小三層架構，用一個專案範本證明「引用 → 升版 → 交付」整條路走得通。四個團隊還沒拆，這個 repo 先用 CODEOWNERS 與文件把邊界畫出來；團隊成立時，邊界不用重畫，只要把 team slug 填進去。

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
- `scripts/vendor-modules.sh` 與 CI 用 `^(vpc|alb|rds|ecs-cluster|ecs-service|ecs-service-alarms|sns-alarm-topic|ssm-publish)-v[0-9]+\.[0-9]+\.[0-9]+$` 檢查 tag；module 名稱清單從 `modules/` 目錄讀，不手寫。

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
- **起始版本**：8 個 module 都從 `v0.1.0` 開始（已拍板，§9.2），因為還沒在真實 AWS apply 過。0.x 期間 MINOR 可以有破壞性變更，CHANGELOG 要寫清楚。§7.3 的實環境驗證做完才升 `v1.0.0`。
- **第一個 tag 由人手動打**：`.release-please-manifest.json` 把 8 個 module 都登記為 `0.1.0`，release-please 會把它當成已經發過，不會產生 `<module>-v0.1.0`。所以第一次發版前，由 platform team 在 Phase 8 驗收過的 commit 上手動打 8 個 `<module>-v0.1.0` tag；之後的版本才交給 release-please。

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
| 目錄 | `main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`CHANGELOG.md`、`examples/basic/`、`tests/<name>.tftest.hcl` |
| `versions.tf` | `required_version = ">= 1.10"`；`aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }`；**module 裡不寫 `provider` 與 `backend`** |
| 版本範圍 | module 用範圍（`>= 6.0, < 7.0`），root 用 `~> 6.x` 加 `.terraform.lock.hcl` 釘死實際版本 |
| lock 檔 | **module 不提交 `.terraform.lock.hcl`**（Terraform 只採用 root module 的 lock，module 的 lock 對消費端沒有作用）；範本的每個 stack 是 root，要提交 |
| 依賴 | 一律從外部傳入（cluster ARN、role ARN、subnet、SG、topic ARN），module 之間不互相呼叫，平坦組合 |
| IAM | **module 不建任何 IAM 資源，沒有例外**（包括 `rds` 需要的 Proxy role 與 Enhanced Monitoring role）。role 在範本的 `iam-base`／`iam-app` stack 建，module 只收 ARN（§5.4） |
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
| `aws_appautoscaling_policy.step_*` 與 4 個 scaling 用 `aws_cloudwatch_metric_alarm` | `autoscaling.policy = "step"`（CPU、記憶體各一組 scale-out／scale-in） |
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

**輸出**：`service_name`、`service_arn`、`cluster_name`（從 ARN 拆出）、`task_definition_arn`、`task_definition_family`、`container_name`（固定 `app`）、`log_group_name`、`log_group_arn`、`target_group_arn`（模式一回傳傳入值、模式二回傳建立的、沒有 LB 時 `null`）、`target_group_arn_suffix`（從 ARN 拆出，給告警用）、`autoscaling_resource_id`（`service/<cluster>/<service>`）。

**刻意不做**

- 不建 security group。服務的 SG 由 `network` stack 建好，經 SSM 傳到 `application`，從 `network.security_group_ids` 傳入（見上方 `network` 變數）。
- 不建任何 IAM 資源（role、policy、attachment 都不建），只收 `execution_role_arn` 與 `task_role_arn`。execution role 在範本的 `iam-base` stack、task role 在 `iam-app` stack 建好，ARN 經 SSM 傳到 `application` stack 再傳進來（project-a 的做法）。範例的 `ecs-web-service` 在 module 裡建一個沒有任何 policy 的 task role，專案要加權限只能在 module 外另掛，反而分散。客戶自管 IAM 時（例如 project-a prod b2c 的 deploy role 被明確 Deny 改 IAM），module 自建 role 會直接 apply 失敗；收 ARN 就接得上。最小權限的測試因此放在範本的 `iam-base`／`iam-app` stack（§5.4、§7.1），不在這個 module。
- SG 放在 `network` stack 是 project-a 的做法（`project-a/infra-v2/terraform/network/security-groups.tf`），這樣 ALB SG 與服務 SG 的規則在同一個地方看得到。
- 不支援多 container／sidecar（project-c 的 ADOT sidecar）。等第二個專案需要時再加，屆時是 MINOR。
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
- 不提供讀取用的 module。讀取就是一個 `data "aws_ssm_parameter"` 加 `for_each`，包一層 module 反而看不出讀了什麼（寫法見 §5.6）。

### 4.7 `vpc`

**用途**：建一個 VPC 與它的 subnet、IGW、NAT、route table、VPC endpoint、flow log。tier 的數量與切法由呼叫端決定，module 不寫死「三層」。

**參考來源**

- subnet 依 tier 分、`cidrsubnet` 自動切：`project-a/infra-v2/terraform/network/vpc.tf`、`subnets-app.tf`
- 三種 tier 的路由（public 走 IGW、private 走 NAT、db 只有 local）、S3 gateway endpoint 關聯全部私有路由表：`project-a/docs/spec/infra.md`〈網路網段與子網配置模型〉、`project-a/infra-v2/terraform/network/nat.tf`、`vpc-endpoints.tf`
- 明確指定每個 subnet 的 CIDR、tier 名稱：`project-c-infra/environments/{uat,prod}/network/terraform.tfvars`（`ingress`／`ecs`／`db`／`egress` 四個 tier）
- interface endpoint 清單：`project-c-infra/environments/uat/platform/terraform.tfvars`（`vpce_interface_config`）

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
| `aws_security_group.vpce`、`aws_vpc_security_group_ingress_rule.vpce_https` | `interface_endpoints != null` | 只對 VPC CIDR 開 443 |
| `aws_vpc_endpoint.interface` | `for_each = interface_endpoints.services` | `private_dns_enabled = true`，放在 `interface_endpoints.subnet_tier` 的每個 AZ |
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

variable "interface_endpoints" {
  type = object({
    services    = set(string) # 例：["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms"]
    subnet_tier = string
  })
  default = null
  validation {
    condition     = var.interface_endpoints == null ? true : alltrue([for s in var.interface_endpoints.services : can(regex("^[a-z0-9][a-z0-9.-]*$", s))])
    error_message = "Service names are the part after com.amazonaws.<region>., e.g. ecr.api."
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
| `interface_endpoints.subnet_tier` 必須存在，且不是 public | endpoint 放錯 tier |
| 所有 subnet 都在 VPC CIDR 內 | 切出界 |
| 所有 subnet 的 CIDR 兩兩不重疊 | 把每個 CIDR 換成 `[起始整數, 結束整數]`（IP 四段乘 256 的冪次相加；結束 = 起始 + 2^(32−prefix) − 1），對每一對檢查 `end_a < start_b || end_b < start_a` |

**自動切的建議切法**：每個 tier 預留 4 個 AZ 的槽位（`netnum_base` 以 4 為間隔），之後從 2 個 AZ 加到 3、4 個時，既有 subnet 不用動。範本的範例（§5.11）照這個切。

**輸出**

| 輸出 | 型別 | 說明 |
|---|---|---|
| `vpc_id`、`vpc_cidr` | `string` | — |
| `azs` | `list(string)` | 原樣回傳，下游依這個順序對應清單 |
| `subnet_ids` | `map(list(string))` | tier => 依 `azs` 順序的 subnet id |
| `subnet_cidrs` | `map(list(string))` | 同上，CIDR |
| `route_table_ids` | `map(list(string))` | 同上，route table id |
| `nat_gateway_ids` | `list(string)` | 依 AZ 順序；`none` 時為 `[]`，`single` 時只有 1 個 |
| `vpce_security_group_id` | `string` | 沒有 interface endpoint 時為 `null` |

**範本固定的三個 tier 名稱**：`public`（type `public`）、`app`（type `private`）、`data`（type `isolated`；DB 需要對外連線時改 `private`）。這三個名稱寫進 SSM 合約（§5.6），不可更改；要加 tier 可以，名稱不能跟這三個衝突。

**刻意不做**：IPv6、private NAT、Transit Gateway 與 VPC peering 的路由（§1）；NACL（用 SG 就夠，NACL 是無狀態的，調錯很難查）；flow log 送 CloudWatch Logs（要多一個 IAM role，與「module 不建 IAM」衝突）；流量規格 preset（放範本的範例 tfvars，§5.11）。

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
| `aws_lb_listener.http` | 一律；有憑證時預設 action 為 301 轉到 HTTPS，沒有憑證時預設 action 回 404 |
| `aws_wafv2_web_acl_association.this` | `web_acl_arn != null` |
| `aws_cloudwatch_metric_alarm.elb_5xx` | 一律 |

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
| `aws_db_instance.this` | ✓ | | |
| `aws_rds_cluster_parameter_group.this`（family `aurora-postgresql<major>`） | | ✓ | ✓ |
| `aws_db_parameter_group.aurora_instance`（family `aurora-postgresql<major>`；`instance_parameters` 非空才建） | | 選用 | 選用 |
| `aws_rds_cluster.this` | | ✓ | ✓（加 `dynamic "serverlessv2_scaling_configuration"`） |
| `aws_rds_cluster_instance.this`（`count = 1 + reader_count`，index 0 是 writer） | | 指定的 class | `db.serverless` |
| `aws_cloudwatch_log_group.postgresql` | `/aws/rds/instance/<name>/postgresql` | `/aws/rds/cluster/<name>/postgresql` | 同 aurora |
| `random_id.final_snapshot` | ✓ | ✓ | ✓ |
| Proxy 一組（見下） | `proxy != null` | `proxy != null` | `proxy != null` |
| 告警（見下） | ✓ | ✓ | ✓ |

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

### 4.10 module 怎麼串：完整三層

下面依 apply 順序列出四個 stack 裡的 module 呼叫，示範一個 module 的輸出怎麼變成下一個 module 的輸入。同一個 stack 內直接引用 module 輸出；跨 stack 一律經過 SSM（`local.in` 是 `ssm-inputs.tf` 讀出來的純量，`local.in_lists` 是清單，寫法見 §5.6）。

**注意：這段的 `source` 是範本「複製到專案 repo 之後」的樣子。** 在本 repo 裡，範本用相對路徑引用 module（例如 `source = "../../../../../modules/vpc"`），這樣本 repo 才能在 tag 還不存在、repo 還沒上 GitHub 的時候跑 `init -backend=false`、`validate`、`test`。怎麼改見 §5.1〈module 的 source〉。

```hcl
# ── network stack ────────────────────────────────────────────
module "vpc" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpc?ref=vpc-v0.1.0"

  name     = local.name_prefix
  cidr     = var.vpc.cidr
  azs      = var.vpc.azs
  nat_mode = var.vpc.nat_mode
  subnets  = var.vpc.subnets # 範例 tfvars 見 §5.11；tier 名稱 public／app／data 固定
  interface_endpoints = var.vpc.interface_endpoints
  flow_log            = var.vpc.flow_log ? { destination_arn = local.in["flow_log_bucket_arn"] } : null
}
# 之後用 aws_security_group + aws_vpc_security_group_*_rule 建 ALB、各服務、DB、Proxy 的 SG（§5.3），
# 再用 ssm-publish 發布 vpc_id、subnet_ids_<tier>、sg_* 等 key（§5.6）。

# ── data stack ───────────────────────────────────────────────
module "db" {
  source = "git::https://github.com/<org>/<repo>.git//modules/rds?ref=rds-v0.1.0"

  name               = "${local.name_prefix}-db"
  deployment         = var.db.deployment
  engine_version     = var.db.engine_version
  database_name      = var.db.database_name
  rds                = var.db.rds
  aurora             = var.db.aurora
  serverless         = var.db.serverless
  subnet_ids         = local.in_lists["subnet_ids_data"]
  security_group_ids = [local.in["sg_db_id"]]
  kms_key_arn        = local.in["kms_key_arn"]

  # 有沒有 Proxy 由 network stack 決定（SG 規則在那裡），這裡照著讀
  proxy = jsondecode(local.in["db_proxy"]).enabled ? {
    security_group_ids = [local.in["sg_db_proxy_id"]]
    role_arn           = local.in["role_rds_proxy_arn"]
  } : null

  monitoring     = { role_arn = local.in["role_rds_monitoring_arn"] }
  sns_topic_arns = [local.in["alarm_topic_arn"]]
}
# ssm-publish 發布 database = jsonencode({ enabled = true, app_endpoint = module.db.app_endpoint, ... })

# ── loadbalancer stack ───────────────────────────────────────
module "alb" {
  source = "git::https://github.com/<org>/<repo>.git//modules/alb?ref=alb-v0.1.0"

  name               = "${local.name_prefix}-alb"
  subnet_ids         = local.in_lists["subnet_ids_public"]
  security_group_ids = [local.in["sg_alb_id"]]
  certificate_arn    = var.certificate_arn
  access_logs        = var.access_logs_enabled ? { bucket = local.in["alb_log_bucket_name"], prefix = local.name_prefix } : null
  sns_topic_arns     = [local.in["alarm_topic_arn"]]
}

# ── application stack ────────────────────────────────────────
locals {
  database = jsondecode(local.in["database"])
}

module "cluster" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-cluster?ref=ecs-cluster-v0.1.0"

  name = "${local.name_prefix}-app"
}

module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service?ref=ecs-service-v0.1.0"

  name               = "${local.name_prefix}-api"
  cluster_arn        = module.cluster.cluster_arn
  image              = "${local.in["ecr_api_url"]}:${var.api_image_tag}"
  container_port     = 8080
  execution_role_arn = local.in["role_ecs_execution_arn"]
  task_role_arn      = local.in["role_api_task_arn"]

  # 開關由 iam-app 決定，跟 task role 的 ssmmessages 權限同一個來源（§5.4）
  enable_execute_command = jsondecode(local.in["ecs_exec_api"]).enabled

  network = {
    subnet_ids         = local.in_lists["subnet_ids_app"]
    security_group_ids = [local.in["sg_api_id"]]
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
    listener_arn   = local.in["listener_arn"]
    vpc_id         = local.in["vpc_id"]
    priority       = 100
    path_patterns  = ["/api/*"]
    alb_arn_suffix = local.in["alb_arn_suffix"]
  }

  desired_count = var.api_desired_count
  autoscaling = {
    min_capacity    = var.api_desired_count
    max_capacity    = var.api_max_capacity
    target_tracking = { requests_per_target = 300 }
  }
}

module "api_alarms" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecs-service-alarms?ref=ecs-service-alarms-v0.1.0"

  name           = module.api.service_name
  cluster_name   = module.cluster.cluster_name
  service_name   = module.api.service_name
  sns_topic_arns = [local.in["alarm_topic_arn"]]
  max_capacity   = var.api_max_capacity

  load_balancer = {
    alb_arn_suffix          = local.in["alb_arn_suffix"]
    target_group_arn_suffix = module.api.target_group_arn_suffix
  }

  dashboard_name = "${local.name_prefix}-api"
}
```

告警分在三個地方，各自只建一份：ALB 整體（ELB 5xx）在 `alb`、資料庫在 `rds`、每個服務在 `ecs-service-alarms`。服務的告警直接吃 `module.api` 的輸出，同一次 apply 建立。project-a 的告警放在 `postdeploy` stack，cluster 名稱、service 名稱、target group suffix 都寫在 tfvars（`project-a/infra-v2/terraform/postdeploy/envs/devbox.tfvars`），前面的 stack 換了資源，這份 tfvars 不改，plan 也不會提醒。

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
        │   └── prod.tfbackend
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

範本裡的 `git::` 範例（例如 §4.10）都是「複製出去之後」的樣子，文件出現時要標明。

### 5.2 state 拆分原則

一個 stack 一份 state。拆的依據只有兩個：

1. **擁有者**：誰有權改、誰要負責。客戶可能接手的（網路、資料庫、IAM）跟我們一定自己管的（服務）分開。
2. **變動頻率**：每週換版的東西不要跟一年動一次的 VPC 放在同一份 state，換版時 plan 才不會掃過網路、出錯時影響範圍才小。

依賴方向是單向的：上游不讀下游。apply 順序就是依賴順序。

### 5.3 預設 stack 清單

apply 順序：`foundation` → `containerimage` → `network` → `iam-base` → `data` → `iam-app` → `loadbalancer` → `application`；destroy 反序。

| 順序 | stack | 放什麼 | 用到的 module | 擁有者 | 變動頻率 | 讀（SSM，來源 stack） | 寫（SSM key） |
|---|---|---|---|---|---|---|---|
| 1 | `foundation` | 告警 SNS、專案共用 KMS key、Secrets Manager secret 容器（不含值）、flow log bucket、ALB access log bucket | `sns-alarm-topic`、`ssm-publish` | 專案 app team；客戶自管時為客戶 | 低 | — | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| 2 | `containerimage` | 各服務的 ECR repository；**服務清單的單一決定點** | `ssm-publish` | 同上 | 低（新增服務時才動） | `foundation` | `services`、`ecr_<service>_url`、`ecr_<service>_arn` |
| 3 | `network` | VPC（預設建立；模式 A 改登記既有）、ALB／各服務／DB／Proxy 的 SG | `vpc`、`ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>`、`sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id`、`nat`、`alb_https`、`db_proxy`、`data_access` |
| 4 | `iam-base` | ECS execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | `ssm-publish` | 同上 | 低 | `foundation`、`containerimage` | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | `rds`、`ssm-publish` | 同上 | 低 | `foundation`、`network`、`iam-base` | `database`（JSON） |
| 6 | `iam-app` | Proxy role 讀 secret 的 policy、各服務 task role、ECS Exec 開關 | `ssm-publish` | 同上 | 低～中（新增服務、調權限時） | `foundation`、`containerimage`、`network`、`iam-base`、`data` | `role_<service>_task_arn`、`ecs_exec_<service>` |
| 7 | `loadbalancer` | ALB、listener、ELB 5xx 告警、WAF 關聯 | `alb`、`ssm-publish` | 專案 app team | 低～中 | `foundation`、`network` | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| 8 | `application` | ECS cluster、service、autoscaling、服務告警、dashboard | `ecs-cluster`、`ecs-service`、`ecs-service-alarms` | 專案 app team | 高 | 前七個 | —（不需要時不發布） |

**`foundation` 的兩個 log bucket**：分成兩個是因為 bucket policy 不同。

| bucket | 加密 | bucket policy 允許 | 其他 |
|---|---|---|---|
| flow log | SSE-S3 | `delivery.logs.amazonaws.com` 寫入，條件 `aws:SourceAccount` 為本帳號 | Block Public Access、lifecycle 90 天過期（預設值，專案依稽核需求調整） |
| ALB access log | **只能 SSE-S3**：ALB 的 log delivery 不支援 customer managed KMS，設了 log 會無聲遺失（`project-a/infra-v2/terraform/loadbalancer/access-logs.tf` 的註解） | 該 region 的 ELB log delivery 寫入（寫法照 project-a `access-logs.tf`） | 同上 |

兩個 bucket 都由 `foundation` 建，即使該環境沒開 flow log 或 access log 也建（空 bucket 沒有費用），下游只靠 tfvars 的開關決定要不要用，SSM key 一律存在。

**`containerimage` 的寫法**（原生資源，沒有 module）：

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

`network` 預設呼叫 `vpc` module 建 VPC（模式 A 改成登記既有 VPC，見 §5.8），再用原生資源建 SG。SG 不做成 module：規則跟專案的服務拓樸綁在一起，用一份服務清單在 locals 展開成規則表，比一個通用 SG module 好讀。

```hcl
variable "vpc" {
  description = "建立 VPC（預設）。與 existing 二選一。"
  type = object({
    cidr     = string
    azs      = list(string)
    subnets  = map(object({ type = string, newbits = optional(number), netnum_base = optional(number), cidrs = optional(map(string)) }))
    nat_mode = optional(string, "single")
    interface_endpoints = optional(object({
      services    = set(string)
      subnet_tier = optional(string, "app")
    }))
    flow_log = optional(bool, false) # true 時送到 foundation 的 flow log bucket
  })
  default = null
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

規則表（全部用 `aws_vpc_security_group_ingress_rule`／`egress_rule` 搭配 `for_each`，來源用 `referenced_security_group_id`，不寫 inline 規則）：

| 從 | 到 | port | 條件 |
|---|---|---|---|
| `alb_ingress` 的 CIDR／prefix list | ALB SG | 443 與 80（80 只做轉址） | `https = true` |
| `alb_ingress` 的 CIDR／prefix list | ALB SG | 80 | `https = false` |
| ALB SG（egress） | 服務 SG | 該服務的 `port` | `from_alb = true` |
| 呼叫端服務 SG | 被呼叫的服務 SG | 被呼叫端的 `port` | `callers` |
| 服務 SG（egress） | `0.0.0.0/0` | 443 | 一律（經 NAT 或 VPC endpoint 呼叫 AWS API） |
| 服務 SG | Proxy SG | data store 的 `port` | `data_access` 且 `proxy = true` |
| 服務 SG | DB SG | data store 的 `port` | `data_access` 且 `proxy = false` |
| Proxy SG | DB SG | data store 的 `port` | `proxy = true` |
| VPC CIDR | VPC endpoint SG | 443 | 由 `vpc` module 建 |

Proxy 的 SG 一律建立（沒有費用），`sg_db_proxy_id` 一律發布；`proxy = false` 時它沒有任何規則。ALB 的 egress 只開到各服務 SG 的服務 port，不開全網。

`network` 同時發布三個「單一決定點」的值，下游照著讀，不在下游再放一個變數：

| key | 內容 | 誰讀 | 下游怎麼用 |
|---|---|---|---|
| `alb_https` | `{"enabled":true}` | `loadbalancer` | precondition：`enabled == (var.certificate_arn != null)`，兩邊不一致就停 |
| `db_proxy` | `{"enabled":false}` | `data` | `enabled` 為 true 才把 `proxy` 物件傳進 `rds` |
| `data_access` | `{"db":["api","worker"]}` | `iam-app` | 名單上的服務，task role 才能讀 DB secret |

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

module 一律不建 IAM（已拍板，§9.2）。角色集中在兩個 IAM stack，原因：權限審查只要看兩個地方；客戶自管 IAM 時只要接這兩個 stack，而且在客戶的部署 role 不能改 IAM 的環境（例如 project-a prod b2c 的 deploy role 明確 Deny `iam:Put*`），module 自建 role 根本 apply 不過。

拆成兩個是因為依賴方向：RDS Proxy 建立時要給 role ARN（role 要在 `data` 之前存在），但 role 讀 secret 的權限要指到 master secret 的 ARN（secret 要等 `data` 建好才有）。一個 stack 做不到，只好拆開：

| stack | 時間點 | 建什麼 |
|---|---|---|
| `iam-base` | `data` 之前 | ECS execution role、RDS Proxy role（**只有 trust，沒有 policy**）、Enhanced Monitoring role |
| `iam-app` | `data` 之後 | 對 Proxy role 附加讀 secret 的 inline policy；各服務 task role；ECS Exec 開關 |

**`iam-base`**

- **execution role**（一個專案一個）：ECR 拉映像限定 `containerimage` 發布的 repo ARN（`ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`、`ecr:BatchCheckLayerAvailability`）；`ecr:GetAuthorizationToken` 只支援 `Resource = "*"`，是例外並寫註解；`logs:CreateLogStream`、`logs:PutLogEvents` 限定 `arn:aws:logs:<region>:<account>:log-group:/ecs/<name_prefix>-*:*`；`secretsmanager:GetSecretValue` 限定 `foundation` 發布的 `app_secret_arn`；有 CMK 時加 `kms:Decrypt` 限定該 key。**不掛 `AmazonECSTaskExecutionRolePolicy`**（它的 Resource 是 `*`）。log group 在 `application` 才建，所以 log 權限用命名規則限定，這要求 log group 名稱照 `ecs-service` 的預設（`/ecs/<name>`）。
- **RDS Proxy role**：trust `rds.amazonaws.com`，加 `aws:SourceAccount` 條件；**沒有任何 policy**，policy 由 `iam-app` 附加。
- **Enhanced Monitoring role**：trust `monitoring.rds.amazonaws.com`；inline policy 只給 `logs:CreateLogGroup`、`logs:PutRetentionPolicy`、`logs:CreateLogStream`、`logs:PutLogEvents`、`logs:DescribeLogStreams`、`logs:GetLogEvents`，Resource 限定 `RDSOSMetrics` log group（`arn:aws:logs:<region>:<account>:log-group:RDSOSMetrics` 與其 `:log-stream:*`）。**不掛 AWS managed policy**：project-a 掛的是 `AmazonRDSEnhancedMonitoringRole`（`project-a/infra-v2/terraform/database/rds.tf`），範本改寫成等價的 inline policy，讓測試斷言得到內容。這份 action 清單是照 AWS managed policy 的內容整理的，**實際權限是否足夠未驗證**（§7.3）。
- 發布 `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn`。

**`data`** 從 SSM 讀 `role_rds_proxy_arn` 與 `role_rds_monitoring_arn`，傳進 `rds` 的 `proxy.role_arn` 與 `monitoring.role_arn`。module 本身不碰 IAM。

**`iam-app`**

- **Proxy role 的 policy**：讀 `data/database` 的 `secret_arn`，對 `iam-base` 建的 Proxy role 附加 inline policy：`secretsmanager:GetSecretValue`，Resource 恰為該 secret ARN；master secret 用 CMK 加密時（範本用 `foundation` 的 `kms_key_arn`），另加 `kms:Decrypt`，Resource 為該 key，條件 `kms:ViaService = secretsmanager.<region>.amazonaws.com`。project-a 的寫法 `kms:Decrypt` 的 Resource 是 `*`（`project-a/infra-v2/terraform/database/rds-proxy.tf`），範本收窄到單一 key。role 名稱從 ARN 最後一段取得，所以 `iam-base` 的 role 不加 path。`database` 是 `{"enabled":false}` 時不附加。
- **task role**（一個服務一個，服務清單讀 `containerimage/services`）：預設沒有任何權限。`network/data_access` 名單上的服務加 `secretsmanager:GetSecretValue`（Resource 恰為 DB secret ARN）與上述 `kms:Decrypt`。應用程式用 `DB_SECRET_ARN` 自己讀 secret（project-a 的做法），不經 execution role 的 `valueFrom`，理由見 §8.2。
- **ECS Exec**：`var.ecs_exec_services`（`list(string)`，預設 `[]`）決定哪些服務的 task role 加上 `ssmmessages:CreateControlChannel` 等 4 個 action（只支援 `Resource = "*"`，是另一個例外），同時對每個服務發布 `ecs_exec_<service>`，值是 `{"enabled":true}` 或 `{"enabled":false}`。`application` 讀同一個 key 傳給 `ecs-service` 的 `enable_execute_command`，自己沒有這個變數，兩邊永遠一致。
- trust policy 的 principal 只有 `ecs-tasks.amazonaws.com`，加 `aws:SourceAccount` 條件。
- 發布 `role_<service>_task_arn`、`ecs_exec_<service>`。

**Proxy 建立時的權限：未驗證**

建立 RDS Proxy 時，如果它的 role 還沒有讀 secret 的權限，AWS 是讓建立失敗，還是建立成功、等 `iam-app` apply 之後才能連線，**目前沒有實測**，列在 §7.3。兩種結果的對策：

| 實測結果 | 對策 |
|---|---|
| 建立成功，`iam-app` apply 之後才連得上 | 照正常順序 apply。第一次部署時，`data` apply 完到 `iam-app` apply 完之間 Proxy 連不上，這段時間應用程式還沒部署，沒有影響 |
| 建立失敗 | 第一次部署先在 `network` 設 `data_stores.db.proxy = false`，照順序跑到 `iam-app`；再改成 `true`，依序 apply `network`、`data`。`iam-app` 的 policy 在第一輪就已經附加到 Proxy role 上（不管 Proxy 開不開都附加），所以第二輪不用再跑 `iam-app`。這個兩段式步驟要寫進 `infra/README.md` |

**policy 一律用 `jsonencode()` 寫，不用 `data "aws_iam_policy_document"`。** mock provider 會把 data source 的 `json` 填成隨機字串，測試就斷言不到 policy 內容。

最小權限測試（`iam-base/tests/`、`iam-app/tests/`，`mock_provider "aws"`）至少要有：

| stack | run | 斷言 |
|---|---|---|
| 兩者 | 沒有萬用 action | 每份 policy 的 Action 都不是 `*`、不以 `:*` 結尾 |
| 兩者 | `Resource = "*"` 只出現在允許清單 | 只有 `ecr:GetAuthorizationToken` 與 ECS Exec 的 4 個 `ssmmessages` action 可以搭配 `*`；用反向驗證證明這條測得到（暫時加一個 `s3:GetObject` on `*`，測試要紅） |
| 兩者 | 沒有 AWS managed policy | 沒有任何 `aws_iam_role_policy_attachment` 指到 `arn:aws:iam::aws:policy/` |
| `iam-base` | trust 各自正確 | execution role 只信任 `ecs-tasks.amazonaws.com`、Proxy role 只信任 `rds.amazonaws.com`、monitoring role 只信任 `monitoring.rds.amazonaws.com` |
| `iam-base` | Proxy role 沒有 policy | 沒有任何 `aws_iam_role_policy` 掛在 Proxy role 上 |
| `iam-base` | monitoring 只到 `RDSOSMetrics` | Resource 全部是 `RDSOSMetrics` 的 log group／stream |
| `iam-app` | Proxy 只讀那一個 secret | Resource 恰為 `override_data` 餵進來的 secret ARN；`kms:Decrypt` 帶 `kms:ViaService` 條件 |
| `iam-app` | 只有 `data_access` 名單上的服務能讀 DB secret | 不在名單上的服務，task role 沒有 `secretsmanager` 權限 |
| `iam-app` | 沒有 DB 時不附加 | `database = {"enabled":false}` 時 Proxy policy 與 task role 的 secret 權限都是 0 個 |
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
| 讀取 | `data "aws_ssm_parameter"` 加 `for_each`，讀 `insecure_value`；key 清單寫在 `ssm-inputs.tf` |
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
| `network` | `sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id` | String | 沒有 interface endpoint 時 `sg_vpce_id` 不發布 |
| `network` | `nat` | String（JSON） | `{"mode":"per_az","ids":["nat-...","nat-..."]}`；`none` 時 `ids` 為 `[]` |
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

讀取寫法：

```hcl
locals {
  ssm_inputs = {
    strings = ["foundation/alarm_topic_arn", "network/vpc_id", "iam-base/role_ecs_execution_arn", "data/database"]
    lists   = ["network/subnet_ids_app"]
  }
}

data "aws_ssm_parameter" "in" {
  for_each = toset(concat(local.ssm_inputs.strings, local.ssm_inputs.lists))
  name     = "${local.ssm_prefix}/${each.key}"
}

locals {
  in       = { for k in local.ssm_inputs.strings : basename(k) => data.aws_ssm_parameter.in[k].insecure_value }
  in_lists = { for k in local.ssm_inputs.lists : basename(k) => split(",", data.aws_ssm_parameter.in[k].insecure_value) }
  database = jsondecode(local.in["database"]) # 條件值
}
```

為什麼用 SSM 不用 `terraform_remote_state`：客戶自管的資源不在我們的 state 裡，`remote_state` 讀不到；SSM 是我們跟客戶都能接的介面。project-a 沒有為這個決定寫 ADR，這個 repo 補 `docs/adr/0003-cross-stack-values-via-ssm-only.md`。

`scripts/validate.sh` 第一版只靜態檢查其中兩條，並接進 CI：

1. 只有 `modules/ssm-publish/` 可以宣告 `resource "aws_ssm_parameter"`。
2. 讀取端（`ssm-inputs.tf`）不得讀 `.value`，只能讀 `insecure_value`。

project-a 的 `project-a/infra-v2/terraform/check-ssm-contract.sh` 還有第三條「讀的 key 必須是 apply 順序更早的 stack 有發布的」。**這條第一版不做，列為之後要補的檢查。** 理由：第一版範圍要小；而且這條要解析每個 stack 的 HCL（`ssm-outputs.tf` 的 `strings`／`lists` 與 `ssm-inputs.tf` 的 key 清單）再做跨 stack 比對，project-a 用 awk 硬解，格式一變就會誤判。第一版靠兩件事補位：各 stack 的測試鎖住它讀取的 key 清單；`infra/README.md` 的合約表寫明每個 key 誰寫誰讀，PR 審查時對照。上表「方向」那一條仍然是規則，只是還沒有自動檢查。

project-a 那支腳本沒有接進 CI，也沒列入 `bridge` 與 `postdeploy`，等於沒在跑；這裡做的兩條一定要接進 CI。

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
| `network` stack | 照跑，`vpc = null`、改給 `existing = { vpc_id, subnet_ids }`；用 data source 驗證 id 存在後，發布**同一組 key**，SG 仍由我們建 | 該環境**不放** `network/envs/<env>.tfbackend` 與 tfvars，我們不跑 |
| 誰發布 `network/*` 的 key | `network` stack（我們） | 客戶，照 §5.6 合約表發布全部 key，包括 `sg_*`、`alb_https`、`db_proxy`、`data_access` 這些 JSON |
| 下游 | 不變 | 不變 |

其他 stack（`foundation`、`containerimage`、`iam-base`、`data`、`iam-app`）也可以照模式 B 交給客戶：該環境不放那個 stack 的 tfbackend 與 tfvars，客戶照合約發布同樣的 key。

共通做法：

1. 客戶照同一份 SSM 合約（`infra/README.md` 的合約表）在 `/<project>/<env>/<stack>/<key>` 發布 key。路徑裡的 `<stack>` 照寫（例如客戶發布 `/<project>/prod/network/vpc_id`），即使客戶那邊沒有叫 `network` 的東西。
2. 客戶自管的 stack 在那個環境**不放** `envs/<env>.tfbackend` 與 `envs/<env>.tfvars`。沒有檔案就無法 init，誤跑的機會從根本消失。
3. 建議客戶給我們的部署 role 明確 Deny `ssm:PutParameter`／`ssm:DeleteParameter` 於客戶擁有的路徑，作為第二道防線。
4. 跨帳號部署用 `providers.tf` 的可選 `assume_role`（`deploy_role_arn`，空字串代表用呼叫者身分），跟 project-a 相同。
5. 客戶的部署 role 不能改 IAM 時，`iam-base` 與 `iam-app` 一定要交給客戶（模式 B）。這也是「module 不建 IAM」的原因：module 一旦自己建 role，這種環境就 apply 不過。
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
| interface endpoint | 無（只開 S3 gateway） | `ecr.api`、`ecr.dkr`、`logs`、`secretsmanager`、`kms` | 上一欄再加 `ssm`、`ssmmessages`、`xray`；需要時加 `bedrock-runtime` |
| flow log | 關 | 開（S3） | 開（S3） |
| RDS | `rds`、`db.t4g.micro`／`small`、單一 AZ；或 `aurora_serverless` 0.5～4 ACU | `aurora_serverless` 2～16 ACU 加 1 個 reader；或 `aurora` `db.r7g.large` 加 1 個 reader；或 `rds` 加 `multi_az` | `aurora` `db.r7g.xlarge` 以上、2 個以上 reader、開 Proxy |
| 備份／刪除保護 | 1～7 天、`false` | 7～14 天、`true` | 14 天以上、`true` |
| ALB | 可以只開 HTTP（SG 要收窄）、idle 60、不開 access log、不掛 WAF | HTTPS、access log、WAF | 同一般正式；SSE 這類長連線服務 idle 設 300 |
| RDS Proxy（`network` 的 `data_stores.db.proxy`） | 不開 | 開 | 開 |

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
| 靜態規則 | `scripts/validate.sh` | `common.tf` 一致、SSM 合約兩條規則（§5.6）、tfbackend key 格式、每個 test 都用 `mock_provider`、`modules/rds/variables.tf` 沒有名稱含 `password` 的變數、整個 `modules/` 沒有 `random_password` | 否 | 否 |

每個 module 的 `tests/` 至少要有：

- 預設輸入的 plan（資源數量、預設值，例如 `cpu_architecture == "ARM64"`）。
- 每個條件建立的開與關（例如 `load_balancer = null` 時 target group 數量為 0）。
- 每條 validation 一個 `expect_failures`，而且要有一個「合法邊界值會通過」的對照 run（只測會失敗的一邊，validation 寫錯成永遠失敗也會通過）。

三個新 module 的測試清單：

| module | run（plan，除非另註） | `expect_failures` |
|---|---|---|
| `vpc` | 2 AZ 與 3 AZ 的自動切；明確 `cidrs`；`nat_mode` 三種各一（`single` 只有 1 顆 NAT、`per_az` 每個 AZ 一顆且 private route 指向同 AZ、`none` 沒有 NAT 也沒有 `0.0.0.0/0` 路由）；isolated tier 沒有任何 `0.0.0.0/0` 路由；gateway endpoint 關聯所有 private／isolated 路由表；interface endpoint 與它的 SG 只對 VPC CIDR 開 443；`flow_log = null` 時 0 個；subnet key 是 `"<tier>/<az>"`；沒有任何 inline `route`／`ingress` | CIDR 不是 /16～/24 或不是網路位址；AZ 少於 2、多於 4 或重複；tier 同時給 `newbits` 與 `cidrs`；兩個 public tier；`cidrs` 少一個 AZ；**兩個 tier 重疊**（含「第三個 AZ 才重疊」這個 project-a 案例）；subnet 超出 VPC；`nat_mode != "none"` 卻沒有 public tier；gateway endpoint 給 `ec2` |
| `alb` | 有憑證：HTTPS listener 用 `ELBSecurityPolicy-TLS13-1-2-2021-06`、預設 404，HTTP listener 預設 301；沒有憑證：只有 HTTP listener、預設 404，`listener_protocol = "HTTP"`；`drop_invalid_header_fields = true`；`access_logs`、`web_acl_arn` 為 null 時對應資源 0 個；ELB 5xx 告警的 `alarm_actions`、`ok_actions` 都是 `sns_topic_arns` | 名稱超過 32 字或以 `internal-` 開頭；subnet 少於 2；`idle_timeout` 0 或 4001；`certificate_arn` 不是 ACM ARN；有 `additional_certificate_arns` 卻沒有 `certificate_arn`；`sns_topic_arns` 為空 |
| `rds` | 三種型態各自的 basic；`{rds, aurora, serverless} × {proxy_off, proxy_on}` 共 6 個；`aurora_proxy_ro`（Aurora 有 reader 時有 read-only endpoint）；`rds_proxy_no_ro`（一般 RDS 沒有）；`proxy_role_passed_through`（`aws_db_proxy.role_arn` 等於輸入）；`no_password_all_modes`（`manage_master_user_password == true`，`password`、`password_wo` 都是 null）；`final_snapshot`（名稱帶 `random_id` 後綴）；`alarms_per_deployment`（rds 沒有 replica lag 告警、Aurora 有 reader 才有、Proxy 開才有兩條 Proxy 告警）；三種型態的輸出格式一致（`app_endpoint`、`identifier_type` 等） | 型態物件不符；`aurora` 用 `db.serverless`；ACU 超出 0～256、min > max 或不是 0.5 的倍數；`reader_count = 16`；`rds` 填了 `cluster_parameters`；proxy 缺 `role_arn` 或格式錯；`rds`／`aurora` 沒給 `connections_threshold`；`sns_topic_arns` 為空 |

`rds` 的 mock 要用 `mock_resource` 給 `aws_db_instance` 與 `aws_rds_cluster` 的 `master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x", kms_key_id = "k", secret_status = "active" }]`，以及 `address`、`endpoint`、`reader_endpoint`、`port` 的預設值。不給的話 nested list 是空的，取 `[0]` 會失敗。

範本 stack 的測試要用 `override_data` 餵 `aws_ssm_parameter` 的 `insecure_value`，否則 mock 產生的隨機字串會被下游的 ARN validation 擋掉。IAM 的最小權限測試放在範本的 `iam-base`、`iam-app` stack（§5.4），module 不建 IAM 所以沒有這類測試；「module 不建 IAM」本身由 `validate.sh` 的靜態檢查保證（`modules/` 底下不得宣告 `aws_iam_*`），因為 `terraform test` 無法列舉資源型別。範本另外要測：`network` 在 `alb_ingress.https = false` 且 `cidrs` 含 `0.0.0.0/0` 時被擋；`vpc` 與 `existing` 同時給時被擋；`loadbalancer` 在 `alb_https` 與 `certificate_arn` 不一致時被擋；`data` 在 `db_proxy` 為 false 時不傳 `proxy`。

範例 tfvars 的驗證方式：`scripts/validate.sh` 對有 `envs/examples/` 的 stack（`network`、`data`、`loadbalancer`），除了一般的 `terraform test`，再對每個範例檔各跑一次 `terraform test -var-file=envs/examples/<x>.tfvars`。這類測試放在 `tests/examples/`（dev、prod 的 tfvars 放在 `tests/tfvars/`），用 `-test-directory` 指定，一般的 `terraform test` 不會跑到它們（子目錄不被預設掃描這點未驗證，Phase 6 先實測）。測試直接吃範例檔的值，不在 `tests/*.tftest.hcl` 裡再複製一份 `variables {}`：複製一份的話，範例檔改了測試不會跟著變，等於沒驗到範例。這要求這幾個 stack 的測試檔不在 `variables {}` 寫死會蓋掉範例值的變數（`-var-file` 的值會被測試檔的 `variables {}` 覆蓋），斷言也要寫成對任何合法輸入都成立的形式（例如「`nat_mode = per_az` 時 NAT 數等於 AZ 數」，而不是「NAT 數等於 2」）。

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
12. 把 module 版本從 v0.x 升到 v1.0.0（見 §3.5）。

## 8. 安全考量

### 8.1 IAM 最小權限

- execution role 與 task role 分開，而且每個服務一個 task role。
- 不掛 `AmazonECSTaskExecutionRolePolicy` 這類 Resource 是 `*` 的 managed policy。只有 AWS 不支援 resource-level 的 action 例外（`ecr:GetAuthorizationToken`、ECS Exec 的 `ssmmessages:*`），寫在 policy 旁邊的註解。
- module 不建 IAM，沒有例外；權限集中在 `iam-base`、`iam-app` 兩個 stack 審查（§5.4）。RDS Proxy role 的讀 secret 權限只到單一 secret ARN，`kms:Decrypt` 收窄到單一 key 並帶 `kms:ViaService`；Enhanced Monitoring role 用 inline policy，只到 `RDSOSMetrics`。
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
| J17 | SG 放在哪裡、怎麼寫 | 留在 `network` stack，用原生資源，不做 `security-group` module；規則由 `services`、`data_stores` 清單在 locals 展開；一律獨立規則資源、來源用 `referenced_security_group_id`；ALB egress 只到各服務的 port；DB 與 Proxy 的 SG 都在 `network`（app → proxy → db，沒開 Proxy 時 app → db）；VPC endpoint 的 SG 由 `vpc` module 建、只對 VPC CIDR 開 443 | inline 規則會洗掉客戶加的規則（project-a 客戶自管網路報告）；SG 跟服務拓樸綁在一起，通用 module 反而難讀 |
| J18 | 客戶自管模式 | 模式 A（客戶管 VPC、我們管 SG，`existing` 與 `vpc` 二選一）與模式 B（`network` 整個由客戶管，照合約發布全部 key）（§5.8） | 兩種情況都遇過；下游不用改 |
| J19 | 網路第一版不做的 | IPv6、private NAT、Transit Gateway、VPC peering | 範圍控制 |
| J20 | 補一條靜態檢查 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數；整個 `modules/` 不得出現 `random_password` | 讓「密碼不進 Terraform」由程式擋，不靠審查 |
| J21 | 「單一決定點」的範圍 | 除了 ECS Exec，再加四個：`containerimage/services`（服務清單）、`network/alb_https`（有沒有憑證）、`network/db_proxy`（開不開 Proxy）、`network/data_access`（哪些服務能讀 DB secret）。下游用 precondition 檢查自己的設定跟上游一致 | 這四件事都同時影響兩個以上的 stack（例如 Proxy 開關同時決定 SG 規則與 `rds` 的 `proxy`），各放一個變數就會出現「SG 開了、Proxy 沒建」這類不一致 |
| J22 | DB secret 怎麼給應用程式 | task role 讀（`DB_SECRET_ARN`），不經 execution role 的 `valueFrom` | execution role 全專案共用；master 密碼會自動輪替，`valueFrom` 只在啟動時讀一次（§8.2）。不同時支援 `valueFrom`，避免兩條路徑 |
| J23 | `rds` 的 DatabaseConnections 門檻 | `aurora_serverless` 沒給時用 project-c 的公式從 `max_capacity` 推算；`rds`、`aurora` 必填 | provisioned 的 `max_connections` 取決於 instance class 的記憶體，離線算不出來；不給門檻就不建告警等於又多一個隱形開關 |
| J24 | Proxy 的 SG 與兩個 log bucket | 一律建立、一律發布 key，即使沒用到 | SSM 不收空字串，「有時存在的 key」會讓下游的讀取清單變成條件式；這三樣資源沒有費用 |
| J25 | `vpc` 的 route table | 一個 subnet 一張表；default SG 清空規則 | `per_az` NAT 需要每個 AZ 有自己的表，統一一 subnet 一表最單純；清空 default SG 避免誤用 |
| J26 | Enhanced Monitoring role 的 policy | inline policy，action 照 AWS managed policy `AmazonRDSEnhancedMonitoringRole` 的內容整理，Resource 限 `RDSOSMetrics` | 不掛 AWS managed policy 的原則；**是否足夠未驗證**（§7.3） |

### 9.2 已拍板決策

| # | 決策 | 理由 | 影響的章節 |
|---|---|---|---|
| 1 | module 一律不建 IAM；`ecs-service` 只收 `execution_role_arn` 與 `task_role_arn`；role 在範本的 IAM stack 建好，ARN 經 SSM 傳到使用端（決策 20 之後拆成 `iam-base`、`iam-app`） | 集中審查；客戶自管 IAM 時接得上（例如 project-a prod b2c 的 deploy role 不能改 IAM）。最小權限測試放在範本的 IAM stack，policy 用 `jsonencode()` 寫，mock 下測得到內容 | §4.1、§4.2、§4.3、§5.4、§7.1、§8.1 |
| 2 | 範本在本 repo 內用相對路徑引用 module（`../../../../../modules/<name>`）；複製到專案 repo 時改成 `git::...?ref=<module>-v<semver>`，改法寫在 `consuming-modules.md`；`vendor-modules.sh` 只負責 `git::` → vendored 相對路徑 | 本 repo 在 tag 不存在、repo 未上 GitHub 時也要能跑 `init -backend=false`、`validate`、`test`（與 implement-process U3 一致） | §1.1、§4.10、§5.1、§5.8、§8.7 |
| 3 | 新增 `containerimage` stack（ECR），排在 `foundation` 之後 | ECR 的擁有者與變動頻率跟 SNS／KMS 不同，客戶自管時也常分開；execution role 要用 ECR 的 ARN 限縮權限 | §5.1、§5.3、§5.4、§5.8 |
| 4 | 每個 Phase 一個 commit；含多個 module 的 Phase 改成一個 module 一個 commit；直接 commit 在 `main`，不 push；author `<author-email>`；Conventional Commits | 使用者決定。一個 commit 只動一個 module 目錄，release-please 依路徑歸屬才不會互相污染 CHANGELOG | 實作流程見 `implement-process.md` |
| 5 | 起始版本 `v0.1.0` | 還沒在真實 AWS apply 過；§7.3 驗完再升 `v1.0.0` | §3.5 |
| 6 | 服務告警放在 `application` stack | 告警直接吃 service 與 target group 的輸出，避免 project-a `postdeploy` 在 tfvars 寫死 id；代價是調門檻也要動高頻變動的 stack | §4.10、§5.3 |
| 7 | ~~SG 由 `network` stack 建；`network` 不建 VPC，只登記既有 VPC／subnet 的 id~~ | **已作廢，由決策 18 取代。** SG 仍由 `network` 建；VPC 改成預設建立 | — |
| 8 | 資料層 stack 命名為 `data` | 涵蓋資料庫與快取 | §5.3 |
| 9 | 不提供 `stacks.sh` | project-a 的那支已經失效；八個 stack 照 `infra/README.md` 的順序手動跑，比一支沒人維護的腳本可靠 | §5.10 |
| 10 | 命名：範本用 `<project>-<env>-<component>`，module 收完整的 `name` | module 不管命名，project-c 那種客戶規範也接得上 | §4.1、§5.9 |
| 11 | module 不提交 `.terraform.lock.hcl`，範本 stack 提交 | Terraform 只採用 root module 的 lock；module 的 lock 對消費端沒有作用 | §4.1、§5.1 |
| 12 | tflint 第一版只用內建 terraform ruleset | 不用下載 plugin、CI 不用帶 token；aws ruleset 列為下一版 | §7.1 |
| 13 | `terraform test` 的 run 只有在有 `mock_provider "aws"` 的測試檔裡才可以用 `command = apply` | mock 下的 apply 不碰 AWS，讓 computed 值可以斷言（與 implement-process U5 一致） | §7.1 |
| 14 | SSM 合約的靜態檢查第一版只做兩條（只有 `ssm-publish` 可宣告 `aws_ssm_parameter`、讀取端不讀 `.value`）；「讀的 key 必須是更早的 stack 發布的」之後再補 | 第一版範圍要小；第三條要解析 HCL 做跨 stack 比對 | §5.6、§7.1 |
| 15 | ECR 預設 `IMMUTABLE`、`scan_on_push = true`、`force_delete = false` | 同一個 tag 不能被覆蓋，部署才可追溯；推上去就掃描；有映像時 destroy 會失敗，不會誤刪 | §5.3 |
| 16 | ECS Exec 的開關由 IAM stack（現在是 `iam-app`）發布到 SSM，`application` 讀同一個 key | 只有一個地方決定，不會出現 exec 開了卻沒有權限 | §5.4、§5.6 |
| 17 | 第一版 module 從 5 個變成 8 個，新增 `vpc`、`rds`、`alb`，做出最小三層架構（ALB 在 public，AP 與 DB 在 private） | 使用者決定：沒有網路與資料庫，範本示範不了完整的專案 | §1、§4.7–§4.10 |
| 18 | `network` stack 預設用 `vpc` module 建立 VPC；客戶自管時改為登記既有 VPC（模式 A）或整個交給客戶（模式 B）。取代決策 7 | 使用者決定；subnet 調整時 SSM key 名稱不變（§5.6） | §5.3、§5.6、§5.8 |
| 19 | `rds` 支援一般 RDS、Aurora、Aurora Serverless v2 三種型態，由一個變數選擇；RDS Proxy 是 module 內的選項 | 使用者決定 | §4.9 |
| 20 | `iam` 拆成 `iam-base` 與 `iam-app`，範本從 7 個 stack 變 8 個，順序 `foundation` → `containerimage` → `network` → `iam-base` → `data` → `iam-app` → `loadbalancer` → `application`。`iam-base` 建 execution role、Proxy role（只有 trust）、Enhanced Monitoring role（trust 加 inline policy，只到 `RDSOSMetrics`）；`data` 把 role ARN 傳進 `rds`；`iam-app` 讀 `database.secret_arn`，對 Proxy role 附加讀 secret 的 policy（有 CMK 時加 `kms:Decrypt` 搭配 `kms:ViaService`），並建 task role | Proxy 建立時要 role，role 的權限又要等 secret 存在；module 不建 IAM 的原則沒有例外。Proxy 在 role 尚無權限時能不能建立**未驗證**，兩種結果的對策見 §5.4 | §5.3、§5.4、§7.3 |
| 21 | flow log 送 S3，bucket 建在 `foundation`，不需要 IAM role；範本範例只在正式環境開啟 | 使用者決定 | §4.7、§5.3、§5.11 |
| 22 | NAT 支援 `none`、`single`、`per_az`；範本範例正式環境 `per_az`、PoC `single` | 使用者決定；project-c uat 關 NAT、prod 每個 AZ 一顆（§5.11 依據） | §4.7、§5.11 |
| 23 | ALB 沒有憑證時允許只開 HTTP，但 `network` 的 validation 不准 ALB SG 對 `0.0.0.0/0` 開 80，只能開給 CloudFront managed prefix list 或指定 CIDR；有憑證時開 443、80 一律 301、TLS policy 固定 `ELBSecurityPolicy-TLS13-1-2-2021-06` | 使用者決定；明文 HTTP 不能對全網開放 | §4.8、§5.3、§8.4 |
| 24 | 第一個版本 tag `<module>-v0.1.0` 由人手動打（8 個），manifest 維持登記 `0.1.0`；之後的版本交給 release-please | 使用者決定 | §3.5、`docs/guides/releasing-modules.md` |

### 9.3 待補資訊（不需要拍板，名稱定了填入即可）

| 項目 | 目前的佔位符 | 出現在 |
|---|---|---|
| GitHub org | `<org>` | §3.3、§3.6、§4.10、§5.1、§8.7 的 source 範例 |
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

