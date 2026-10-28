# 專案 infra 規範：怎麼照範本開 `infra/` 目錄

給專案的 app team。結論：把 `templates/project-infra/infra/` 整個複製到專案 repo 根目錄，換掉 module source、帳號、state bucket 與 tfvars 的佔位值，再照 9 個 stack 的順序 apply（`infra/terraform/stacks.sh` 依順序執行）。stack 只呼叫 module，跨 stack 只透過 SSM 傳值，兩個 stack 都要知道的開關只在上游決定一次。

這份以 `project-infra` 範本為準。repo 另有五份拆法不同的範本：`templates/example2/`（14 個 stack）、它的 EKS 版 `templates/example3/`（13 個 stack）、資料平台 `templates/example4/`（12 個 stack）、IoT Edge AI `templates/example5/`（15 個 stack），以及 serverless 的 `templates/example6/`（9 個 stack），環境都是 `dev`、`sit`。複製與改值的做法一樣，細節看各自的 `infra/README.md`。

這份講「怎麼做、為什麼」；stack 清單、SSM 合約表、單一決定點、流量規格表的完整內容在範本的 `templates/project-infra/infra/README.md` 與 `REFERENCE.md`，複製出去之後就是專案的 `infra/README.md`、`infra/REFERENCE.md`，這裡不重複。

## 開 `infra/` 目錄：六個步驟

```bash
# 在專案 repo 根目錄
cp -R <platform-repo>/templates/project-infra/infra ./infra
```

| 步驟 | 改什麼 | 在哪裡 |
|---|---|---|
| 1 | module 的 `source` 已經是 `app.terraform.io/libterty/<module>/aws`。用自己的 HCP organization 時換掉 `libterty`；拿不到 HCP token 時改成 `git::...?ref=<module>-v<semver>` | 指令見 [`consuming-modules.md`](./consuming-modules.md)〈從範本複製出去〉與〈備案〉 |
| 2 | `common.tf` 的 `accounts_by_env`：填入各環境的帳號。8 個 stack 的 `common.tf` 必須一字不差，改一份就複製到其他 7 份 | `infra/terraform/*/common.tf` |
| 3 | 每份 `envs/<env>.tfbackend` 的 `bucket`（`<state-bucket>` 佔位符）與 key 的 `alpha` 前綴 | `infra/terraform/*/envs/*.tfbackend` |
| 4 | 每份 `envs/<env>.tfvars` 的 `project`、`expected_account_id`；以及告警 email、`image_tag`、ACM 憑證 ARN、`alb_ingress` 的來源 | `infra/terraform/*/envs/*.tfvars` |
| 5 | 環境不只 dev、prod 時，每個 stack 加一組 `envs/<env>.tfvars` 與 `envs/<env>.tfbackend`，並在 `common.tf` 的 `accounts_by_env` 加一列 | 同上 |
| 6 | 範本 README 與 REFERENCE 裡指向設計文件的相對連結會失效，改成指向本 repo 的網址或刪掉 | `infra/README.md`、`infra/REFERENCE.md` |

在本 repo，`scripts/validate.sh` 的 S5 會比對雜湊，確認 `common.tf` 一字不差；複製出去之後要由專案 CI 自己比，最簡單的寫法：

```bash
test "$(sha256sum infra/terraform/*/common.tf | cut -d' ' -f1 | sort -u | wc -l)" -eq 1
```

## stack 怎麼拆、state 放哪裡

一個 stack 一份 state。拆的依據只有兩個：誰擁有（客戶可能接手的網路、資料庫、IAM，跟我們一定自己管的服務分開），以及變動頻率（每週換版的服務不跟一年動一次的 VPC 放一起）。依賴是單向的，上游不讀下游。

| 順序 | stack | 放什麼 | 變動頻率 |
|---|---|---|---|
| 1 | `foundation` | KMS key、告警 SNS、兩個 log bucket、secret 容器 | 低 |
| 2 | `containerimage` | ECR；服務清單的決定點 | 低（新增服務時） |
| 3 | `network` | VPC（或登記既有 VPC）、interface endpoint、所有 SG | 低 |
| 4 | `iam-base` | execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | 低 |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | 低 |
| 6 | `agent` | AgentCore 與 Bedrock（Runtime、guardrail、Memory、Gateway、Knowledge Base）；預設關閉，沒設定時什麼都不建 | 中 |
| 7 | `iam-app` | Proxy 讀 secret 的 policy、各服務 task role、ECS Exec 開關 | 低到中 |
| 8 | `loadbalancer` | ALB、listener、ELB 5xx 告警 | 低到中 |
| 9 | `application` | ECS cluster、service、autoscaling、服務告警、log 告警、X-Ray 抽樣 | 高 |

state key 固定是 `<project>-<env>/<stack>/terraform.tfstate`，例如 `alpha-dev/application/terraform.tfstate`；bucket 開 versioning、SSE、Block Public Access，用 `use_lockfile = true`（S3 原生 lock，不用 DynamoDB）。bucket 本身不在專案 stack 裡建。

多個環境的 state 放同一個 bucket、只靠 key 前綴分開時，key 寫錯就會讀到別的環境。所以 key 的格式寫死，本 repo 的 `scripts/validate.sh`（S6）會檢查。

### apply 與 destroy 的順序

apply 照上表 1 到 9。`infra/terraform/stacks.sh <env> all apply` 依這個順序跑，順序寫在它的 `ORDER`；先加 `--dry-run` 看會執行哪些指令。

destroy 反過來（9 到 1，`stacks.sh <env> all destroy`），之前先做三件事，否則會失敗：

1. `loadbalancer` 的 `deletion_protection`、`data` 的 `db.deletion_protection` 改成 `false` 並 apply。
2. 清空每個 ECR repository（`force_delete = false`，有映像時刪不掉）。
3. 清空 `foundation` 的兩個 log bucket。

### 新增專案自己的 stack

專案特有的東西（例如維運工具），自己加 stack，規則跟範本一樣：

- 目錄、`common.tf`（複製，一字不差）、`versions.tf`、`providers.tf`（只改 `Stack` tag）、`envs/` 照範本。
- 只呼叫 module。真的需要原生 resource 時，先跟 platform team 討論要不要做成 module。
- 讀上游值寫在 `ssm-inputs.tf`，發布寫在 `ssm-outputs.tf`；只能讀 apply 順序比自己早的 stack。
- 把 stack 加進 `infra/terraform/stacks.sh` 的 `ORDER`，並在 `infra/README.md` 的 apply 順序表與 `infra/REFERENCE.md` 的 SSM 合約表加上它；`check-ssm-contract.sh` 會檢查它讀的 key 都由更早的 stack 發布。

## stack 只呼叫 module：例外清單

範本的 stack 只呼叫 module，不宣告原生 AWS resource。例外只有下面這些：

| stack | resource | 理由 |
|---|---|---|
| `search-config`（example4、example5） | `ephemeral "aws_secretsmanager_secret_version"`（讀 OpenSearch master 帳密） | opensearch provider 的帳密只能在 stack 設定；ephemeral 值不進 state 與 plan 檔（v7 design K19）。example4 與 example5 的 `search-config` 是範本 stack 僅有的 ephemeral block |
| 有 ephemeral 讀取的 stack 的測試（example4、example5 的 `search-config`） | 用離線的 `provider "aws"` 取代 S1 要求的 `mock_provider "aws"` | Terraform 1.15 的 mock provider 不能開 ephemeral resource。`validate.sh` 的 `offline_aws_provider` 只在 stack 有 `ephemeral "aws_..."` 時放行，而且測試檔的 provider 要把 `skip_credentials_validation`、`skip_requesting_account_id`、`skip_metadata_api_check` 三個都設 `true`、所有網址都是 `http://127.0.0.1:`，連不出這台機器。ephemeral 本身與 provider 的帳密接線只有 `terraform validate` 與雲端驗證覆蓋 |

可以留在 stack 的：`data "aws_caller_identity"`、`data "aws_region"`、模式 A 的 `data "aws_vpc"`／`data "aws_subnet"`、`terraform_data`（範本用它放 precondition；example4 的 `warehouse` 用它加 `prevent_destroy` 擋住誤切 `warehouse_mode`）。不可以的：`data "aws_ssm_parameter"`（只能經 `ssm-read`）、任何 `aws_iam_*`（只能經 `iam-role`、`iam-role-policy`）、任何 SG 資源（只能經 `security-group`）。

只有 `iam-base`、`iam-app` 兩個 stack 會呼叫 IAM module，所以權限審查只要看這兩個地方；客戶的部署 role 不能改 IAM 時，也只要把這兩個 stack 交給客戶。

## 為什麼 IAM 拆成兩個 stack

因為依賴方向。RDS Proxy 建立時要給 role ARN，所以 role 要在 `data` 之前存在（`iam-base`）；但 role 讀 secret 的權限要指到 master secret 的 ARN，secret 要等 `data` 建好才有（`iam-app`）。

| stack | 時間點 | 建什麼 |
|---|---|---|
| `iam-base` | `data` 之前 | execution role、Proxy role（只有 trust，沒有 policy）、Enhanced Monitoring role |
| `iam-app` | `data` 之後 | 對 Proxy role 附加讀 secret 的 policy（Resource 恰為那個 secret）、各服務 task role、ECS Exec 開關 |

Proxy role 還沒有讀 secret 的權限時，AWS 是讓 Proxy 建立失敗，還是建立成功但連不上，**未驗證**。兩種結果的第一次部署步驟寫在 `infra/REFERENCE.md`〈RDS Proxy 第一次部署：兩段式步驟〉。

## 單一決定點

兩個以上的 stack 都要知道的開關，只由上游一個 stack 決定並發布到 SSM，下游讀同一個 key，並用 precondition 檢查自己的設定跟它一致。不一致時 plan 就停，不會 apply 出「SG 以為有 HTTPS、ALB 實際只開 HTTP」這種組合。

範本目前有這些：`containerimage/services`、`containerimage/mirrored_images`、`network/alb_https`、`network/db_proxy`、`network/data_access`、`iam-app/ecs_exec_<service>`、`iam-app/tracing`。各自誰決定、誰讀、怎麼檢查，見 `infra/REFERENCE.md`〈單一決定點〉。

自己加開關時照同一個做法：

1. 選一個上游 stack 當決定者，變數只放在那裡。
2. 發布成 JSON：`{"enabled":true}`（SSM 不收空字串，可有可無的值一律包 JSON）。
3. 下游在 `ssm-inputs.tf` 讀它，用 `jsondecode(...).enabled`；下游自己不放同名變數。
4. 下游如果也有相關設定（例如 `loadbalancer` 的 `certificate_arn`），用 `terraform_data` 加 precondition 比對。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`，整個專案只有一棵樹。純量用 `String`、清單用 `StringList`、可有可無或多欄位的值用 `String` 裝 JSON；SSM 只放非機密值，secret 只放 ARN。服務名稱的 `-` 在 key 裡換成 `_`（`order-api` → `sg_order_api_id`）。完整的 key 清單在 `infra/REFERENCE.md`〈SSM 合約〉。

### 讀取寫法

`ssm-inputs.tf` 先把 key 清單放進 local，再傳給 `ssm-read`。放 local 是因為 `terraform test` 讀不到 module 的輸入值；測試要斷言「這個 stack 只讀這些 key」，只能對 local 斷言：

```hcl
locals {
  ssm_input_strings = {
    kms_key_arn    = "foundation/kms_key_arn"
    app_secret_arn = "foundation/app_secret_arn"
  }
  ssm_input_lists = {
    services = "containerimage/services"
  }
}

module "in" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ssm-read?ref=ssm-read-v0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
```

有些 key 每個服務一組（例如 `containerimage/ecr_<service>_arn`），名稱要看服務清單，而服務清單本身也從 SSM 讀。讀這類 key 的 stack 要用第二個 `ssm-read`，範本的 `iam-base` 與 `application` 都是這樣寫：

```hcl
locals {
  service_key         = { for s in module.in.lists["services"] : s => replace(s, "-", "_") }
  ssm_service_strings = { for s, k in local.service_key : "ecr_${k}_arn" => "containerimage/ecr_${k}_arn" }
}

module "in_services" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ssm-read?ref=ssm-read-v0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_service_strings
}
```

`application` 的服務清單取自自己的 `var.services`，再用 precondition 確認跟 `containerimage/services` 相同。

### tier 與 AZ 調整時 key 怎麼變

| 調整 | 發布端的變化 | 下游要改什麼 |
|---|---|---|
| AZ 從 2 個加到 3 個 | `azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>` 清單變長，key 名稱不變 | 不用改程式碼，重新 apply（ECS service 會滾動部署；資料庫的 subnet group 應該是就地更新，未驗證） |
| 改 NAT 模式 | `nat` 的 JSON 內容變 | 不用改 NAT 的 id（沒有 stack 讀它）；`application` 只在有服務被追蹤時讀 `mode`，改成 `none` 前要先確認 mirror 映像與 `xray`、`ecr.api`、`ecr.dkr` endpoint 已備好，否則 plan 會停 |
| 新增一個 tier（例如 `batch`） | 多發布 `subnet_ids_batch`、`subnet_cidrs_batch` | 只有要用它的 stack 在 `ssm-inputs.tf` 加讀取 |
| 改既有 tier 的 CIDR 大小 | 清單內容變，subnet 會重建 | 不用改程式碼，但上面的 ENI 要先清空；實務上用新增 tier 再遷移 |
| 改 tier 名稱 | — | 不允許。`public`、`app`、`data` 寫進了合約 |

## 流量規格與 IP 規劃

規格不放進 module，放在 `network`、`data`、`loadbalancer`、`application` 的 `envs/examples/{poc,standard,high}.tfvars`。挑一份最接近的複製成 `envs/<env>.tfvars` 再改。對照表在 `infra/REFERENCE.md`〈依流量調整規格〉；大流量那一欄與所有抽樣比例都沒有實測依據，第一個用到的專案要自己量。

app tier 的 subnet 大小用這個公式估（一個 Fargate task 佔 1 個 IP，每個 subnet AWS 保留 5 個）：

```
app tier 每個 AZ 需要的 IP ≥ ceil(max_task 數 × 2 ÷ AZ 數)     # 部署時 max 200%，新舊 task 同時存在
                           + interface endpoint 數               # 放在 app tier 時，每個 endpoint 每個 AZ 1 個
                           + 預留（建議再加 50%）
                           + 5                                   # AWS 保留
public tier 每個 AZ ≥ ALB 節點用量（subnet 至少 /27、至少 8 個可用 IP）+ NAT 數 + 5
data tier 每個 AZ   ≥ DB instance 數 + Proxy 的 ENI + 5
```

例：max 50 個 task、2 個 AZ、5 個 interface endpoint → `ceil(50 × 2 ÷ 2) + 5 = 55`，加 50% 約 83，加 5 約 88，`/25`（123 個可用）就夠。範例 tfvars 給 `/22`，是留給服務數量成長。Proxy 每個 subnet 用掉幾個 IP，AWS 沒有固定數字，**未驗證**。

## 環境切換：四件事

手打 `terraform` 時，環境由四個彼此獨立的選擇決定，沒有任何東西把它們綁在一起。其中最容易忘了換、還留在上一個環境的是 AWS 身分。

| 選擇 | 怎麼指定 | 忘了換的後果 |
|---|---|---|
| AWS 身分 | `aws-vault exec <profile> --` | 打到錯的帳號（會被 `allowed_account_ids` 擋下） |
| backend | `-backend-config=envs/<env>.tfbackend` | 讀寫到別的環境的 state |
| 變數 | `-var-file=envs/<env>.tfvars` | 用錯的設定規劃 |
| 工作目錄 | `TF_DATA_DIR=.terraform-<env>` | 沿用上一個環境的 backend 設定與 provider 快取 |

```bash
cd infra/terraform/application
export TF_DATA_DIR=.terraform-dev
aws-vault exec <dev-profile> -- terraform init -reconfigure -backend-config=envs/dev.tfbackend
aws-vault exec <dev-profile> -- terraform plan -var-file=envs/dev.tfvars
```

- 換環境一律 `init -reconfigure`，不要用 `-migrate-state`（它會把 state 搬過去）。
- 環境名稱只有一層：`env` 同時用在檔名、資源名稱、SSM 路徑、state key。不要拆成檔名一套、資源名稱另一套的兩層命名：兩者填反時，檢查會比對到空集合然後「通過」。
- `expected_account_id` 沒有預設值，漏帶 tfvars 直接報缺變數；帳號不在 `accounts_by_env` 的那一列，plan 之前就停。

## 客戶自管資源：模式 A 與模式 B

| | 模式 A：客戶管 VPC、我們管 SG | 模式 B：整個 stack 由客戶管 |
|---|---|---|
| 適用 | 客戶有既有 VPC 規範，但讓我們開 SG | 客戶的網路團隊連 SG 都要自己管 |
| 我們怎麼做 | `network` 的 tfvars 不給 `vpc`，改給 `existing = { vpc_id, subnet_ids }`。stack 用 data source 確認 id 存在、檢查 VPC 開了 DNS support 與 DNS hostnames，SG 與 interface endpoint 仍由我們建；路由、IGW、NAT、gateway endpoint、default SG 一律不碰 | 該環境不放這個 stack 的 `envs/<env>.tfbackend` 與 `envs/<env>.tfvars`，沒有檔案就無法 init |
| 誰發布 `network/*` | `network` stack（`nat` 發布 `{"mode":"external","ids":[]}`） | 客戶照 SSM 合約表發布全部 key，包含 `sg_*`、三個 JSON 決定點與 `interface_endpoints`（`application` 在追蹤且沒有 NAT 時才讀） |
| 下游 | 不變 | 不變 |

`foundation`、`containerimage`、`iam-base`、`data`、`iam-app` 也可以照模式 B 交給客戶。客戶的部署 role 不能改 IAM 時，`iam-base` 與 `iam-app` 一定要交給客戶。

建議客戶在給我們的部署 role 上，對客戶擁有的路徑明確 Deny `ssm:PutParameter`、`ssm:DeleteParameter`，當第二道防線。跨帳號部署用 `providers.tf` 的 `deploy_role_arn`，空字串代表用呼叫者自己的身分。

交付到連不到我們 GitHub 的客戶環境，見 [`delivering-to-customer.md`](./delivering-to-customer.md)。

## LLM 與 AgentCore

`agent` stack 排在 `data` 與 `iam-app` 之間，預設不建任何東西。開 Runtime、guardrail、Memory、Gateway 或 Knowledge Base 的步驟與坑，見 [`llm-agentcore.md`](./llm-agentcore.md)。

## 範本刻意的取捨

- `foundation` 多建兩個 log bucket；`containerimage` 依服務清單建 ECR repository。
- `network` 用 `vpc` module，SG 規則由服務清單展開。
- `data` 用 `rds` module；ElastiCache 不在第一版。
- IAM 拆成 `iam-base`、`iam-app` 兩個 stack，理由見上。
- 只有一棵 SSM 樹，不需要轉寫用的 stack。
- `loadbalancer` 用 `alb` module；target group 由 `ecs-service` 建。
- autoscaling 與告警收進 module 與 `application`，不另開 stack，也不把 id 寫死在 tfvars。
- 專案特有的功能不放進範本，由專案自己加 stack。

## 驗證

複製出去之後，每個 stack 的 `tests/` 仍然可以離線跑（`mock_provider "aws"`；example4 的 `search-config` 用離線的 aws provider，見〈例外清單〉）：

```bash
cd infra/terraform/network
TF_DATA_DIR=.terraform-test terraform init -backend=false
TF_DATA_DIR=.terraform-test terraform test
TF_DATA_DIR=.terraform-test terraform test -test-directory=tests/tfvars -var-file=envs/dev.tfvars
```

mock 驗不到 IAM 實際權限、AWS API 的參數檢查、配額、apply 時序與網路流量，這些要在真實帳號上補驗，清單見設計文件 §7.2、§7.3（README 的文件地圖有連結）。
