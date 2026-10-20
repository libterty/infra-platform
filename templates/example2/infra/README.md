# 範本 example2：11 個 stack 的專案 infra

> 狀態：骨架。目前只有共用檔案、環境檔、`stacks.sh`、`check-ssm-contract.sh` 與 SSM 合約；各 stack 的 module 呼叫與資源會在後續階段補上，這份文件也會跟著補完。設計見 [`docs/design/v2/design-docs.md`](../../../docs/design/v2/design-docs.md) 第 5 章。

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

環境只有 `dev` 與 `sit`。帳號對照表在 `common.tf` 的 `accounts_by_env`，`state` bucket 在 `.tfbackend` 裡是 `<state-bucket>`，複製出去後換成真正的 bucket。

## apply 順序

依賴是單向的：下游只讀上游發布的 key。apply 照下表由上往下，destroy 反過來。順序的唯一來源是 `stacks.sh` 的 `ORDER`，`check-ssm-contract.sh` 也從那裡讀。

| 順序 | stack | 讀 | 發布 |
|---|---|---|---|
| 1 | `containerimage` | 無 | 服務清單、Runtime 清單、ECR URL 與 ARN |
| 2 | `foundation` | 無 | 告警 topic、secret ARN |
| 3 | `network` | containerimage | VPC、各層 subnet、各 security group、peering |
| 4 | `database` | foundation、network | 資料庫與 Proxy endpoint、secret ARN、Redis endpoint |
| 5 | `iam` | foundation、containerimage、database | 各 role ARN |
| 6 | `bridge` | 前面所有 stack（樹 A） | 樹 B |
| 7 | `loadbalancer` | 樹 B | ALB 與 target group 的識別、WAF 名稱 |
| 8 | `agent` | 樹 B | Runtime、Memory、guardrail 的 ARN 與 id |
| 9 | `application` | 樹 B、loadbalancer、agent | cluster、服務、log group 名稱 |
| 10 | `operation` | 樹 B | bucket、Lambda 名稱 |
| 11 | `postdeploy` | 樹 B、loadbalancer、application、agent | 不發布 |

實際的 key 以各 stack 的 `ssm-inputs.tf`、`ssm-outputs.tf` 為準。

## SSM 合約：樹 A 與樹 B

- **樹 A**：`/<project>/<env>/<stack>/<key>`。前段 stack 與 loadbalancer、agent、application 發布到這裡，下游用 `ssm-read` 讀。
- **樹 B**：`/<project>-shared/<env>/infra/<key>`，一個共用前綴底下的扁平 key。loadbalancer、agent、application、operation、postdeploy 只讀樹 B（外加其他後段 stack 的樹 A key），不直接讀前段 stack。這樣樹 B 改由外部發布時，後段 stack 照樣能跑。

樹 B 由誰寫：

- 預設由 `bridge` stack 讀樹 A 再寫過去（`ssm_prefix = local.shared_ssm_prefix`、`stack = "infra"`）。
- 列在 `stacks.sh` 的 `EXTERNAL_SHARED_ENVS` 裡的 env，樹 B 由外部發布：`stacks.sh <env> all` 自動跳過 `bridge`，單獨指定 `bridge` 會報錯。外部要發布的 key 就是 `bridge/ssm-outputs.tf` 發布的那份清單，名稱、型別（String 或 StringList）都要一致。`EXTERNAL_SHARED_ENVS` 預設是空的，所有 env 都跑 `bridge`。

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

骨架階段還沒有資源可以接，所以 `ssm-outputs.tf` 只有 `# planned_strings: <key>...` 與 `# planned_lists: <key>...` 註解行，列出打算發布的 key；`check-ssm-contract.sh` 把它們當成已發布。加上 `module "ssm_publish"` 與 `published_*` 時，同一個 PR 把註解行換掉，不要兩種並存。

## check-ssm-contract.sh

```bash
bash infra/terraform/check-ssm-contract.sh
```

只檢查兩件事，其他規則（`common.tf` 一致、`data "aws_ssm_parameter"` 的位置、tfbackend 的 key）由 `scripts/validate.sh` 負責，`validate.sh` 也會呼叫這支腳本：

1. 每個讀的 `<stack>/<key>`：發布它的 stack 在 `ORDER` 裡排在讀它的 stack 前面、真的有發布這個 key、型別（strings 或 lists）相同。樹 B 的 `infra/<key>` 對應到 `bridge`。
2. 同一個 env 裡，各 stack 的 tfvars 在 `SHARED_CONFIG_KEYS`（`project`、`env`、`aws_region`、`expected_account_id`、`deploy_role_arn`）上的值一致，而且 `env` 等於檔名。

錯誤訊息會指出哪個 stack 的哪一個 key。

## stacks.sh

```bash
cd infra/terraform
./stacks.sh <env> <stack|all> <init|validate|plan|apply|destroy|output> [--yes] [--dry-run] [-- <terraform 參數>...]
```

- env 檔從 `<stack>/envs/<env>.tfvars`、`<stack>/envs/<env>.tfbackend` 讀。
- `TF_DATA_DIR=.terraform-<env>`，`init` 一律 `-reconfigure`。
- `validate` 做 `init -backend=false`（用 `-lockfile=readonly`）再 `validate`，用另一個 data directory `.terraform-<env>-validate`，不會蓋掉 `init` 留下的 backend 設定。
- `all` 依 `ORDER` 跑，`destroy all` 反向；任何一個 stack 失敗就停。
- `--yes` 讓 `apply`、`destroy` 加 `-auto-approve`；`--dry-run` 只印指令、不執行 terraform。
- `--` 之後的參數原樣交給 `plan`、`apply`、`destroy`、`output`。

## 環境切換

手打 `terraform` 時，環境由四個彼此獨立的選擇決定：AWS 身分（`aws-vault exec <profile> --`）、backend（`-backend-config=envs/<env>.tfbackend`）、變數（`-var-file=envs/<env>.tfvars`）、工作目錄（`TF_DATA_DIR=.terraform-<env>`）。`stacks.sh` 把後三個綁在一起，只剩 AWS 身分要自己換；`allowed_account_ids` 會擋下打到錯的帳號。

## 驗證

```bash
scripts/validate.sh templates/example2/infra/terraform
```

做 `fmt`、靜態規則、`check-ssm-contract.sh`、`bash -n` 與 shellcheck，然後每個 stack 跑 `init -backend=false`、`validate`、`terraform test`，並對 `dev`、`sit` 兩份 tfvars 各跑一次 `tests/tfvars`。全部離線，不需要 AWS 憑證；stack 從 HCP private registry 抓 module，需要 registry token。
