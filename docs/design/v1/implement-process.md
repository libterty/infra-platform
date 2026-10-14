# infra-platform 第一版實作流程

> 狀態：決策已拍板（見文末「已拍板決策」），等使用者確認後開工。模組介面（變數名稱、輸出、預設值）以 [`design-docs.md`](./design-docs.md) 為準；這份只講「怎麼一步一步做出來、每步怎麼驗收」。兩份衝突時，以 design-docs.md 為準，回頭改這份。
>
> 文中路徑除非特別註明，都相對於 `<workspace>/`。本 repo 內的路徑直接寫 repo 內相對路徑。「design §x.y」指 design-docs.md 的章節。

## 結論

第一版是 8 個 module 加 1 份 8 個 stack 的範本，做出最小三層架構：ALB 在 public subnet，AP 層與 DB 層在 private subnet。

分 9 個 Phase（0 到 8），一次做一個，主 agent 自己重跑驗證通過後 commit，才進下一個。**一個 module 一個 commit**，總共 11 個 commit（Phase 8 有修正才多一個）。

| Phase | 交付 | 驗收的一句話 | commit |
|---|---|---|---|
| 0 | repo 骨架：README、.gitignore、.tflint.hcl、`scripts/validate.sh`、CI 與 release 設定、CODEOWNERS、ADR 0001–0003 | `validate.sh` 在沒有任何 module 時回 0；每條靜態規則用暫存 fixture 證明會擋 | 1 |
| 1 | `ssm-publish`、`sns-alarm-topic` | 整套 module 結構（檔案、README、CHANGELOG、example、test）與 mock 寫法定型 | 2 |
| 2 | `vpc` | CIDR 自動切與明確指定、重疊擋下、三種 NAT 的 route、增減 AZ 不位移、endpoint、flow log 都有測試 | 1 |
| 3 | `ecs-cluster`、`ecs-service` | autoscaling、兩種 LB 接法、secrets、Service Connect 有測試；module 不建 IAM 與 SG | 2 |
| 4 | `alb`、`ecs-service-alarms` | 有無憑證兩種 listener、ELB 5xx 告警；服務告警 13 個的建立條件與 SNS 接線 | 2 |
| 5 | `rds` | 三種 `deployment` × Proxy 開關的資源切換、無 password、輸出統一、告警 | 1 |
| 6 | `templates/project-infra`（8 個 stack） | 每個 stack `init -backend=false`／`validate`／`test` 全過；network 的 SG 展開與 HTTP 收窄、iam-base／iam-app 的最小權限有測試 | 1 |
| 7 | `docs/guides/` 五份、`scripts/vendor-modules.sh` | 文件路徑都對得到真實檔案；vendor 腳本在暫存目錄跑過 | 1 |
| 8 | 整體驗收 | 乾淨狀態下 `validate.sh` 全綠，repo 沒有產物殘留，文件、tag、stack 清單一致 | 有修正才 1 |

整體驗收標準：`scripts/validate.sh` 在本機與 CI 都不需要任何 AWS 憑證就能全綠；全程沒有執行 `terraform plan`／`apply`、帶 backend 的 `init`、任何 `aws` 指令；commit 都在本機 `main`，沒有 push。

## 全局規則

### 硬性限制（每個 Phase 的派工 prompt 都要原文帶上）

1. 任何 terraform 指令都不准碰到 AWS。允許與禁止的指令如下，表外的 terraform 子指令（例如 `providers lock`、`import`、`state`、`console`）一律視為禁止，要用先問使用者。

   | 可以跑 | 條件 |
   |---|---|
   | `terraform fmt` | — |
   | `terraform init -backend=false` | 只從 registry 下載 provider，不碰帳號與 state |
   | `terraform validate` | — |
   | `terraform test` | 測試檔裡每個 provider 都是 `mock_provider` |

   | 不准跑 |
   |---|
   | `terraform plan`、`terraform apply`、帶 backend 的 `terraform init`（沒有 `-backend=false` 的 init 都算） |
   | 任何 `aws` 指令 |

2. `terraform test` 一律用 `mock_provider "aws"`，不得需要 AWS 憑證。`terraform test` 內部會跑 plan／apply，但對象是 mock，這是允許的。`run` block 預設 `command = plan`；`command = apply` 只准用在有 `mock_provider "aws"` 的測試檔（D6）。
3. 不准 `git push`，不准建立 GitHub remote 或 repo。執行 subagent 不 commit；commit 由主 agent 在自己重跑驗證通過後做（D4）。
4. commit message 用 Conventional Commits，author email 必須是 `<author-email>`。
5. 文件一律台灣繁體中文；程式碼註解精簡、一句話講事實、不要 icon。
6. 簡單優先：不為未來需求加抽象層；module 平坦組合、依賴從外部傳入，不用 `enable_xxx` 開關（資源要不要建由相依的輸入有沒有給決定）。
7. 本機沒有 terraform-docs、pre-commit、release-please：可以提供設定檔，驗收不能依賴它們。README 的 inputs／outputs 表手寫，表頭上方註明「之後改由 terraform-docs 產生」。
8. repo 目錄、module 清單、stack 清單、tag 格式（`<module>-v<semver>`）、變數名稱照 design-docs.md，不得自行改名。
9. 執行型 subagent 只能透過 `scripts/validate.sh` 跑 terraform，不得直接手打 terraform 指令。Phase 0 還沒有 `validate.sh` 時，手動跑的每一行 terraform 都要先套用下面「離線環境」的設定。

### 離線環境（第二道防線）

就算有測試漏寫 `mock_provider`，也要連不到 AWS。`scripts/validate.sh` 一開頭就做這件事，Phase 0 手動跑時照抄：

```bash
# 清掉所有 AWS_* 變數（含 AWS_PROFILE、AWS_VAULT、AWS_SESSION_TOKEN、AWS_ACCESS_KEY_ID、AWS_SECRET_ACCESS_KEY）
for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
```

第一道防線是每個測試檔都宣告 `mock_provider "aws"`，由 `validate.sh` 的靜態規則 S1 強制；這一段是第一道防線失守時的保險：沒有憑證、沒有設定檔、也拿不到 EC2 metadata，provider 只會因缺憑證而失敗。

### 每個 module／stack 的 TDD 節奏

Terraform 沒有「先寫實作才能編譯」的問題，RED 很容易變成「Reference to undeclared resource」這種假紅燈。這裡把 RED 定義得嚴格一點：

| 步驟 | 做什麼 | 要留下的證據 |
|---|---|---|
| 1. 介面 | 照 design-docs.md 先寫 `versions.tf`、`variables.tf`（含 validation），`main.tf` 只放空殼或最少資源 | — |
| 2. RED | 寫 `tests/<name>.tftest.hcl`，跑 `scripts/validate.sh <dir>`，**至少一個 assert 是因為條件不成立而失敗**，不是因為參照不存在 | 失敗輸出貼進 Phase 回報 |
| 3. GREEN | 補資源到測試全過 | 通過數量（例如 `Success! 9 passed, 0 failed.`） |
| 4. REFACTOR | 整理命名、拆檔、補 README／example，測試仍全過 | 重跑結果 |
| 5. 反向驗證 | 每個 validation 都要正反兩個方向各一個 run（合法邊界值通過、非法值被 `expect_failures` 擋下）；挑一個關鍵 assert 暫時改壞實作，確認測試會紅，再改回來 | 改壞時的失敗輸出 |

第 5 步的理由：只測一個方向的比對，拿掉實作也照樣會過（project-a 的 `infra-v2/terraform/application/tests/forwarded_allow_ips.tftest.hcl` 檔頭就自己註明了一條「拿掉 sort() 這份測試照樣會過」的盲點）。

下面各 Phase 的 run 表裡，「A 被擋；B 通過」寫在同一列代表兩個 run（一正一反）。

### module 的固定檔案

每個 module 都是 `main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`（aws `>= 6.0, < 7.0`）、`README.md`、`CHANGELOG.md`、`examples/basic/main.tf`、`tests/<name>.tftest.hcl`。不放 provider 與 backend，不放 `.terraform.lock.hcl`。**module 不建 IAM 資源，也不建服務用的 security group**（`vpc` 自己的 VPC endpoint SG 是唯一例外，屬於 vpc 內部資源）；role 與 SG 一律由呼叫端以 ARN／id 傳入。

`examples/` 只跑 `init -backend=false` 與 `validate`，不寫測試；它的用途是讓 README 有一份能被 CI 驗證的呼叫範例。

### 驗收指令

每個 Phase 都用同一支：

```bash
cd infra-platform
scripts/validate.sh                        # 全部
scripts/validate.sh modules/ssm-publish    # 只跑指定目錄（開發中用）
```

加上 Phase 自己的檢查（見各 Phase「驗收指令」）。主 agent 驗證時不 pipe 進 `tail`，要看完整輸出。

### commit 規則

- 時機：執行 subagent 回報完成 → 主 agent 自己重跑該 Phase 的驗收指令與全量 `scripts/validate.sh` → 全綠才 commit。驗證不過就退回 subagent，不 commit。
- 位置：直接在本機 `main`，不開分支，不 push。
- 粒度：**一個 module 一個 commit**，一個 commit 只動一個 module 目錄（release-please 依路徑歸屬，CHANGELOG 才不會互相污染）。非 module 的 Phase（0、6、7）各一個。
- commit 前確認 `git config user.email` 是 `<author-email>`，不符就停手提醒使用者。
- 格式：`<type>(<scope>): <subject>`，subject 英文、祈使句、50 字內。`git add` 逐檔列路徑，不用 `git add -A`。

| # | Phase | commit message（範例） |
|---|---|---|
| 1 | 0 | `chore(repo): add repo skeleton, offline validation and release config` |
| 2 | 1 | `feat(ssm-publish): add module with path and type tests` |
| 3 | 1 | `feat(sns-alarm-topic): add module with email and kms tests` |
| 4 | 2 | `feat(vpc): add vpc module with tiered subnets and nat modes` |
| 5 | 3 | `feat(ecs-cluster): add fargate cluster module` |
| 6 | 3 | `feat(ecs-service): add fargate service module with autoscaling` |
| 7 | 4 | `feat(alb): add alb module with optional tls and elb 5xx alarm` |
| 8 | 4 | `feat(ecs-service-alarms): add alarms and optional dashboard` |
| 9 | 5 | `feat(rds): add rds module with three deployments and proxy` |
| 10 | 6 | `feat(template): add project-infra template with eight stacks` |
| 11 | 7 | `docs(guides): add usage guides and vendor-modules script` |
| （12） | 8 | `chore(repo): fix issues found in final acceptance`（有修正才有） |

## Phase 拆分

### 順序的理由

| 順序 | 理由 |
|---|---|
| Phase 0 先做驗證工具 | 後面每個 Phase 才有同一把尺 |
| Phase 1 先做最小的兩個 module | 用最簡單的 module 把結構、README、mock 寫法定型，後面照抄；這兩個也是範本每個 stack 都會用到的 |
| Phase 2 `vpc` 放在 ECS 前面 | 三層架構的地基，也是新 module 裡邏輯最多的（CIDR 計算、重疊檢查、route 切換）；它的 subnet key 規則與輸出形狀決定 network stack 怎麼發布 SSM，越早定越好 |
| Phase 3 `ecs-cluster`、`ecs-service` | 原本規劃最成熟的部分，中間插入 vpc 不影響 |
| Phase 4 `alb` 與 `ecs-service-alarms` 放一起 | 兩者都在處理「LB 的接線與告警」：`alb` 的 `listener_arn`、`alb_arn_suffix` 是另外兩個 module 的輸入格式，ELB 5xx 告警也從 alarms 搬到 alb（design J4），放同一個 Phase 方便一起審 |
| Phase 5 `rds` 單獨一個 Phase | 最複雜（3 種型態 × Proxy 開關、mock 的 nested list 坑），獨立出來，出問題不會拖到其他 module |
| Phase 6 範本 | 要呼叫全部 8 個 module |
| Phase 7 文件 | 要引用範本的真實檔案 |

### 可平行與不可平行

判斷依據：**檔案不重疊**，而且**沒有測試依賴**（module 的測試都用字面值餵輸入，不引用其他 module 的程式碼；範本的測試才會同時用到多個 module）。

| 組合 | 能不能平行 | 理由 |
|---|---|---|
| Phase 0 與任何 Phase | 不行 | 其他 Phase 都依賴 `validate.sh` 與 `.gitignore` |
| Phase 1 內部兩個 module | 不行 | Phase 1 的用意是定型，要同一個人寫，結構才一致 |
| Phase 2、3、4、5 彼此之間 | 可以 | 各自只動自己的 `modules/<name>/`；release-please 設定在 Phase 0 已登記全部 8 個 module；測試全用字面值，彼此沒有測試依賴。最多同時 4 個執行 subagent |
| Phase 6 與 Phase 2–5 | 不行 | 範本的測試會 init 全部 module，任何一個 module 還在改，範本的測試就不穩 |
| Phase 7 與 Phase 6 | 部分可以 | `releasing-modules.md`、`team-roles.md`、`vendor-modules.sh` 只依賴 module，可在 Phase 5 後開始；`consuming-modules.md`、`project-infra-standard.md`、`delivering-to-customer.md` 要對到範本的真實檔案，等 Phase 6 |

預設照順序跑；跑完 Phase 1 再由使用者決定 Phase 2–5 要不要平行（D7）。平行時每個 module 仍各自驗證、各自 commit，commit 順序照上面的編號。

### Phase 0：repo 骨架

**目標**：驗證工具與 repo 規則先到位，後續 Phase 只新增 module 目錄，不再動共用檔（平行時才不會撞檔）。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `README.md` | 入口：這是什麼、四個團隊怎麼用、文件地圖（指向 `docs/design/v1/design-docs.md`、`docs/design/v1/implement-process.md`、`docs/guides/`、`docs/adr/`）。guides 還沒寫的連結先標「Phase 7 補」 |
| `.gitignore` | 保留既有的 `docs/slides/`，加 `.terraform/`、`.terraform-*/`、`*.tfstate`、`*.tfstate.*`、`*.tfplan`、`crash.log`、`.cache/`、`modules/**/.terraform.lock.hcl`；**不忽略** `*.tfvars` 與範本的 `.terraform.lock.hcl` |
| `.tflint.hcl` | 只啟用內建 terraform ruleset 的 `recommended` preset（D5） |
| `.pre-commit-config.yaml` | 只提供設定（terraform fmt、tflint），本次不驗證 |
| `scripts/validate.sh` | 見「驗證指令的具體寫法」 |
| `.github/workflows/ci.yml` | 跑 `scripts/validate.sh`；不給任何 AWS 憑證 |
| `.github/workflows/release.yml` | release-please，push 到 `main` 時產生 per-module release PR 與 tag；`contents: write` 只給這個 workflow |
| `release-please-config.json` | 一次登記全部 8 個 module：`release-type: terraform-module`、`include-component-in-tag: true`、`component` 等於目錄名 |
| `.release-please-manifest.json` | 8 個 module 的起始版本都是 `0.1.0`（D5），第一個 tag 是 `<module>-v0.1.0` |
| `.github/CODEOWNERS` | 照 design 的 CODEOWNERS 章節，team slug 用佔位符 |
| `docs/adr/0001-git-tag-monorepo-as-private-registry.md` | MADR，registry 機制，含升級路徑（HCP Terraform Free／boring-registry） |
| `docs/adr/0002-split-state-by-owner-and-change-rate.md` | MADR，8 個 stack 與 apply 順序，含 IAM 拆成 iam-base／iam-app 的理由（RDS Proxy 與 Enhanced Monitoring 的 role 要在 data 之前存在，讀 DB secret 的權限要在 data 之後才寫得出 Resource） |
| `docs/adr/0003-cross-stack-values-via-ssm-only.md` | MADR，SSM 而不是 `terraform_remote_state`；理由是客戶自管的 infra 不在我們的 state 裡（project-a 沒有寫成 ADR） |

8 個 module 一次登記進 release-please 設定，是刻意的：後面每個 Phase 都不必再動這兩個共用 JSON，Phase 2–5 才能平行。

**TDD 任務分解**：這個 Phase 沒有 Terraform 程式碼，「測試」是對 `validate.sh` 本身做反向驗證，在 scratchpad 的暫存複本裡做，不在 repo 裡留 fixture。

| 情境 | 預期 |
|---|---|
| repo 裡還沒有任何 module／template | 印出「沒有找到要驗證的目錄」，回 0 |
| 格式錯誤的 `.tf`（多餘空白） | `fmt -check` 失敗，回非 0，訊息列出該檔 |
| 靜態規則 S1–S7 各放一個違規 fixture（見「第 3 步的靜態規則」表） | 每一條各自回非 0，訊息指出規則編號與檔案 |
| S7：`modules/rds/variables.tf` 宣告 `variable "master_password"`；另一個 fixture 在 `modules/vpc/main.tf` 寫 `resource "random_password"` | 兩個都回非 0 |
| S4 的例外：`modules/vpc/` 宣告 `resource "aws_security_group" "vpce"` | 通過（vpc 的 endpoint SG 是唯一允許的 SG） |
| 第一個目錄失敗 | 仍跑完其餘目錄，最後列出全部失敗目錄（照 project-a CI 的做法） |
| 執行時 shell 裡有 `AWS_PROFILE`、`AWS_VAULT`、`AWS_ACCESS_KEY_ID`、`AWS_SESSION_TOKEN` | 腳本內 `env \| grep '^AWS_'` 只剩 `AWS_CONFIG_FILE=/dev/null`、`AWS_SHARED_CREDENTIALS_FILE=/dev/null`、`AWS_EC2_METADATA_DISABLED=true`（暫時加一行 debug 輸出驗證後拿掉） |
| 沒有 `mock_provider` 的測試檔，並在 shell 裡設好上一列的變數 | 第 3 步就失敗，不會進到 `terraform test` |

**驗收指令**

```bash
shellcheck -S warning scripts/validate.sh
scripts/validate.sh; echo "exit=$?"           # 預期 0
jq . release-please-config.json .release-please-manifest.json >/dev/null
jq -r '.packages | keys[]' release-please-config.json | wc -l   # 預期 8
grep -nE 'id-token|configure-aws-credentials|secrets\.|AWS_' .github/workflows/ci.yml   # 預期沒有輸出
grep -nE 'terraform[^|]*\b(plan|apply)\b|(^|[^_A-Za-z])aws ' scripts/validate.sh        # 預期沒有輸出
grep -n 'init' scripts/validate.sh            # 每一行 init 都帶 -backend=false
grep -nE 'AWS_CONFIG_FILE=/dev/null|AWS_SHARED_CREDENTIALS_FILE=/dev/null|AWS_EC2_METADATA_DISABLED=true' scripts/validate.sh   # 三行都要有
git status --short --ignored                   # 不得出現 .terraform*、.cache 以外的意外檔案
```

這個 Phase 還沒有 `validate.sh` 可用之前，執行者手動跑的 terraform 指令都要先套用「離線環境」那段設定，且只限 `fmt`、`init -backend=false`、`validate`、`test`。

**完成定義**：上表每個情境的輸出都貼在回報裡；ADR 三份照 MADR；CI 與 release workflow 的 action 用 commit SHA 釘版（`actions/checkout`、`hashicorp/setup-terraform` 可沿用 `project-a/.github/workflows/ci.yml` 的 SHA；release-please-action 與 tflint setup action 的 SHA 用 `gh api` 查，不能查就標「未釘版，待補」）；terraform 版本釘 `1.15.8`。主 agent 驗證後 commit。

**不在本次範圍**：任何 module；guides；`vendor-modules.sh`；pre-commit 與 release-please 的實際執行。

### Phase 1：`ssm-publish`、`sns-alarm-topic`

**目標**：做出前兩個 module，把 module 結構、README 格式、CHANGELOG 起始內容、mock 測試寫法定型。之後的 Phase 照這兩個抄。介面照 design 的 `ssm-publish`、`sns-alarm-topic` 章節。

**檔案清單**（兩個 module 各一套）

| 路徑 | 用途 |
|---|---|
| `modules/ssm-publish/{main,variables,outputs,versions}.tf` | 以 `project-a/infra-v2/terraform/modules/ssm-publish/` 為底；介面 `ssm_prefix`、`stack`、`strings`、`lists`，輸出 `names`、`arns`。project-a 把 `terraform {}` 寫在 `main.tf`，這裡拆到 `versions.tf` |
| `modules/ssm-publish/tests/ssm-publish.tftest.hcl` | 搬 project-a 的 `paths_and_types`，加下表的 negative test |
| `modules/ssm-publish/examples/basic/main.tf`、`README.md`、`CHANGELOG.md` | README 寫路徑規則 `/<project>/<env>/<stack>/<key>`、讀取端寫法（`data "aws_ssm_parameter"` 讀 `insecure_value`） |
| `modules/sns-alarm-topic/{main,variables,outputs,versions}.tf` | 以 `project-c-infra/modules/infra-platform/sns.tf` 的 email 訂閱為底，一次一個 topic，可選 `kms_master_key_id`；不管 topic policy |
| `modules/sns-alarm-topic/tests/sns-alarm-topic.tftest.hcl`、`examples/basic/main.tf`、`README.md`、`CHANGELOG.md` | README 註明 email 訂閱要收件人確認才生效 |

**`ssm-publish` 的 run block**

| run | 斷言 |
|---|---|
| `paths_and_types` | string 名稱是 `<ssm_prefix>/<stack>/<key>`、type `String`、`tier = "Standard"`、寫進 `insecure_value`；list 是 `StringList`、逗號串接（沿用 project-a） |
| `outputs_cover_both_maps` | `names` 與 `arns` 的 key 等於 strings 與 lists 的 key 聯集（`arns` 是 computed，見風險 R3） |
| `empty_maps_publish_nothing` | 兩個 map 都空時，兩種資源數量都是 0 |
| `prefix_format` | `/alpha/dev` 通過；`alpha/dev`、`/alpha/dev/network`、`/alpha/dev/` 被擋 |
| `stack_name_format` | `Net Work` 被擋；`network`、`iam-base` 通過 |
| `key_must_be_snake_case` | `vpc-id` 被擋；`vpc_id` 通過 |
| `rejects_empty_string_value` | `strings = { a = "" }` 被擋（SSM 不收空字串，可有可無的值包 JSON） |
| `value_length_limit` | 4097 字元被擋；4096 字元通過 |
| `rejects_empty_list` | `lists = { a = [] }` 被擋 |
| `rejects_list_element_with_comma` | `lists = { a = ["x,y"] }` 被擋（讀取端用 `split(",")` 會切錯） |
| `rejects_key_in_both_maps` | 同一個 key 同時出現在 strings 與 lists 被擋（project-a 的 outputs 用 `merge()`，撞 key 會靜默覆蓋） |

**`sns-alarm-topic` 的 run block**

| run | 斷言 |
|---|---|
| `creates_one_topic_with_name` | topic 名稱等於輸入；沒給 KMS 時 `kms_master_key_id` 為 null |
| `email_subscriptions_per_address` | 兩個 email → 兩個 `aws_sns_topic_subscription.email`，protocol `email`，`for_each` key 是 email 本身 |
| `no_subscribers_is_allowed` | email 清單為空 → 0 個訂閱、topic 仍建立 |
| `kms_key_is_applied` | 給 CMK ARN → topic 的 `kms_master_key_id` 等於它 |
| `email_format` | `not-an-email` 被擋；`ops@example.com` 通過 |
| `rejects_aws_managed_sns_key` | `alias/aws/sns` 被擋（CloudWatch 告警無法發布到用 AWS 受管金鑰加密的 topic） |
| `topic_name_format` | 含空白或超過 256 字被擋；含大寫與底線的合法名稱通過 |

**驗收指令**

```bash
scripts/validate.sh modules/ssm-publish modules/sns-alarm-topic
scripts/validate.sh
ls modules/*/.terraform.lock.hcl 2>/dev/null           # 預期沒有輸出
grep -rn 'aws_sns_topic_policy' modules/sns-alarm-topic   # 預期沒有輸出
```

**完成定義**：兩個 module 測試全過；每個 validation 有正反兩個 run；回報附 RED 輸出、反向驗證的失敗輸出、`n passed`；風險 R3（computed 值在 plan 階段未知）的處理方式與 `mock_resource`／`override_*` 的寫法在這個 Phase 定案並寫進回報，後面 Phase 照用。主 agent 驗證後，兩個 module 各 commit 一次。跑完停下來，由使用者決定 Phase 2–5 要不要平行（D7）。

**不在本次範圍**：Lambda／https／Slack／Chatbot 訂閱；topic policy；KMS key 本身；`SecureString`；讀取端 module。

### Phase 2：`vpc`

**目標**：照 design §4.7。一個 VPC、依 tier 切 subnet、三種 NAT 模式、一個 subnet 一張 route table、gateway／interface endpoint、清空 default SG、可選 flow log（S3）。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `modules/vpc/versions.tf`、`variables.tf` | 介面照 design §4.7：`name`、`cidr`、`azs`、`subnets`、`nat_mode`、`gateway_endpoints`、`interface_endpoints`、`flow_log`、`tags` |
| `modules/vpc/main.tf` | `aws_vpc.this`（DNS support／hostnames 都開，`lifecycle.precondition` 放全部跨變數檢查）、`aws_default_security_group.this`（不宣告規則）、`aws_subnet.this`（`for_each`，key `"<tier>/<az>"`）、`aws_internet_gateway.this` |
| `modules/vpc/locals.tf` | 自動切 CIDR、明確指定 CIDR、把 CIDR 換成起訖整數做兩兩比對 |
| `modules/vpc/routing.tf` | `aws_route_table.this`、`aws_route_table_association.this`（一個 subnet 一張，key 同 subnet）、`aws_eip.nat`、`aws_nat_gateway.this`、`aws_route.public_igw`、`aws_route.private_nat`；不寫 inline `route {}` |
| `modules/vpc/endpoints.tf` | `aws_vpc_endpoint.gateway`、`aws_security_group.vpce`＋`aws_vpc_security_group_ingress_rule.vpce_https`、`aws_vpc_endpoint.interface` |
| `modules/vpc/flow-log.tf` | `aws_flow_log.this`（S3，不需要 IAM role） |
| `modules/vpc/outputs.tf` | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids`、`subnet_cidrs`、`route_table_ids`（三者都是 `map(list(string))`，依 `azs` 順序）、`nat_gateway_ids`、`vpce_security_group_id` |
| `modules/vpc/tests/{subnets,routing,endpoints,validation}.tftest.hcl` | 見下表 |
| `modules/vpc/examples/basic/`（2 AZ、`public`／`app`／`data` 三個 tier、`single`）、`examples/explicit-cidrs/` | 兩種切法各一個呼叫範例 |
| `modules/vpc/README.md`、`CHANGELOG.md` | tier 命名合約（範本固定 `public`、`app`、`data`）、`netnum_base` 以 4 為間隔預留 AZ 槽位、IP 規劃公式 |

**run block**

precondition 都掛在 `aws_vpc.this`，negative test 寫 `expect_failures = [aws_vpc.this]`。

| 檔案 | run | 斷言 |
|---|---|---|
| subnets | `auto_cidr_two_az` | `cidr = "10.0.0.0/20"`、2 個 AZ、三個 tier 用 `newbits`＋`netnum_base` → 6 個 subnet；每個 `cidr_block` 等於 `cidrsubnet(var.cidr, newbits, netnum_base + az_index)`（斷言裡直接用 `cidrsubnet` 算預期值）；key 恰為 `public/<az1>`、`public/<az2>`、`app/<az1>`… |
| subnets | `auto_cidr_three_az` | 同上改成 3 個 AZ → 9 個 subnet，CIDR 公式相同 |
| subnets | `explicit_cidrs` | 每個 tier 給 `cidrs = { <az> = "<cidr>" }` → `cidr_block` 等於給的值 |
| subnets | `explicit_cidrs_must_match_azs` | `azs` 有 2 個、`cidrs` 只給 1 個 → 被擋；多給一個不在 `azs` 的 AZ → 被擋；剛好對上通過 |
| subnets | `exactly_one_layout` | 同一個 tier 同時給 `newbits` 與 `cidrs` → 被擋；`newbits` 有、`netnum_base` 沒有 → 被擋 |
| subnets | `netnum_slots_exhausted` | `netnum_base + length(azs) > pow(2, newbits)` → 被擋 |
| subnets | `subnet_outside_vpc` | 明確指定的 CIDR 不在 VPC CIDR 內 → 被擋 |
| subnets | `overlap_fails_precondition` | 兩個 tier 明確指定的 CIDR 重疊（`10.0.1.0/24` 與 `10.0.1.128/25`）→ 被擋；相鄰不重疊（`10.0.1.0/25` 與 `10.0.1.128/25`）通過 |
| subnets | `third_az_overlap_fails` | 自動切、2 個 AZ 時不重疊，加到第 3 個 AZ 時撞進下一個 tier 的區段（重現 project-a `infra-v2/terraform/network/subnets-app.tf` 的坑）→ 被擋 |
| subnets | `add_az_keeps_existing_keys` | 先跑 2 AZ，再跑 3 AZ：後者的 subnet key 包含前者全部的 key，且這些 key 的 `cidr_block` 相同（用 `run.auto_cidr_two_az` 的值比對）；新增的只有 `<tier>/<az3>` |
| subnets | `remove_az_keeps_remaining_keys` | 3 AZ 去掉中間那個：剩下的 key 與 CIDR 跟 3 AZ 時相同 |
| subnets | `outputs_grouped_by_tier_in_az_order` | `subnet_ids`、`subnet_cidrs`、`route_table_ids` 的 key 是 tier 名稱，每個 list 依 `azs` 順序（`command = apply`，id 才有 mock 值） |
| subnets | `default_sg_is_emptied` | 有 1 個 `aws_default_security_group.this`，`ingress` 與 `egress` 都是空的 |
| routing | `one_route_table_per_subnet` | `aws_route_table.this` 與 `aws_route_table_association.this` 的 key 集合等於 subnet 的 key 集合 |
| routing | `public_tier_routes_to_igw` | 有 public tier → 1 個 IGW；每張 public 表都有一筆 `aws_route.public_igw`（`0.0.0.0/0`） |
| routing | `nat_none` | `nat_mode = "none"` → NAT 與 EIP 都是 0、`aws_route.private_nat` 0 筆、`nat_gateway_ids = []` |
| routing | `nat_single` | `"single"` → 1 個 NAT 與 1 個 EIP，NAT 在第一個 AZ 的 public subnet；每張 private 表的 `aws_route.private_nat` 都指向這顆 |
| routing | `nat_per_az` | `"per_az"` → NAT 數等於 AZ 數；每張 private 表的預設路由指向同 AZ 的 NAT |
| routing | `isolated_tier_local_only` | 三種 `nat_mode` 下，isolated tier 的表都沒有任何 `aws_route` |
| routing | `nat_requires_public_tier` | `nat_mode = "single"` 且沒有 public tier → 被擋；`"none"` 且沒有 public tier 通過 |
| routing | `nat_mode_values` | `"dual"` 被擋；三個合法值各自通過 |
| routing | `no_inline_routes` | `routing.tf` 沒有 `route {` 區塊（grep，見驗收指令） |
| endpoints | `s3_gateway_by_default` | 預設 → 1 個 `aws_vpc_endpoint.gateway["s3"]`，`route_table_ids` 恰為全部 private 與 isolated 的表 |
| endpoints | `gateway_endpoint_values` | `["ec2"]` 被擋；`["s3", "dynamodb"]` 通過且建 2 個 |
| endpoints | `no_interface_endpoints_by_default` | `interface_endpoints = null` → interface endpoint、vpce SG、vpce 規則都是 0；`vpce_security_group_id` 為 null |
| endpoints | `interface_endpoints_in_tier` | `services = ["ecr.api", "logs"]`、`subnet_tier = "app"` → 2 個 endpoint，`private_dns_enabled = true`、subnet 等於 app tier 全部 subnet；vpce SG 只有一條 ingress：443 來自 VPC CIDR |
| endpoints | `interface_tier_must_exist_and_not_public` | `subnet_tier = "nope"` 被擋；`subnet_tier = "public"` 被擋 |
| endpoints | `interface_service_name_format` | `"com.amazonaws.ap-northeast-1.logs"` 被擋（只收 `com.amazonaws.<region>.` 之後那段）；`"ecr.api"` 通過 |
| endpoints | `no_flow_log_by_default` | `flow_log = null` → `aws_flow_log` 0 個 |
| endpoints | `flow_log_to_s3` | 給 S3 bucket ARN → 1 個 `aws_flow_log`，`log_destination_type = "s3"`、`traffic_type = "ALL"`、沒有 `iam_role_arn` |
| endpoints | `flow_log_validation` | `arn:aws:logs:...` 被擋；`traffic_type = "SOME"` 被擋；S3 ARN 加 `ACCEPT` 通過 |
| validation | `name_format` | 大寫、超過 48 字被擋；2 字元通過 |
| validation | `cidr_prefix_range` | `/15`、`/25`、`10.0.0.1/20`（不是網路位址）被擋；`/16`、`/24` 通過 |
| validation | `az_count_range` | 1 個與 5 個 AZ 被擋；2 個與 4 個通過 |
| validation | `rejects_duplicate_az` | 兩個相同 AZ 被擋 |
| validation | `tier_name_snake_case` | `App-Tier` 被擋；`app`、`data_2` 通過 |
| validation | `tier_type_values` | `type = "dmz"` 被擋 |
| validation | `at_most_one_public_tier` | 兩個 `public` tier 被擋；一個通過 |

`no_iam_resources` 這類「整個 module 不得有某種資源」的檢查不寫成 run，由 `validate.sh` 的 S4 負責。

**驗收指令**

```bash
scripts/validate.sh modules/vpc
grep -n 'count *=' modules/vpc/main.tf                          # subnet 不得用 count
grep -rnE '^\s*(route|ingress|egress)\s*\{' modules/vpc/         # 預期沒有輸出（不用 inline 路由與 SG 規則）
scripts/validate.sh
```

**完成定義**：上表每個 run 都存在且通過；`add_az_keeps_existing_keys` 用反向驗證證明有效（暫時把 subnet 改成 `count`，測試要紅）；`third_az_overlap_fails` 用反向驗證證明有效（暫時拿掉重疊檢查，測試要紅）。主 agent 驗證後 commit。

**不在本次範圍**：IPv6、private NAT、Transit Gateway、VPC peering；NACL；flow log 送 CloudWatch Logs；流量規格 preset（放範本 examples tfvars）。

### Phase 3：`ecs-cluster`、`ecs-service`

**目標**：兩個 ECS module，介面照 design 的 `ecs-cluster`、`ecs-service` 章節。兩個 module 都不建 IAM 與 SG：role 由範本的 iam-base／iam-app 建、SG 由 network 建，以 ARN／id 傳進來。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `modules/ecs-cluster/{main,variables,outputs,versions}.tf` | 以 `infra-platform/docs/slides/terraform-split/terraform-platform-example/platform/modules/core/main.tf` 為底，**拿掉其中的 execution role**；加 `project-c-infra/modules/infra-platform/ecs.tf` 的 Container Insights、FARGATE／FARGATE_SPOT、預建 performance log group、可選 Service Connect namespace |
| `modules/ecs-cluster/tests/ecs-cluster.tftest.hcl`、`examples/basic/`、`README.md`、`CHANGELOG.md` | 同 Phase 1 結構 |
| `modules/ecs-service/{main,variables,outputs,versions}.tf` | 以 `project-a/infra-v2/terraform/application/ecs-chat-gateway.tf` 的預設值為底，參考範例的 `platform/modules/ecs-web-service/`（**拿掉 task role 與 SG**，修掉寫死 `X86_64`、`name_prefix = "svc-"`、`ManagedBy` tag）。target tracking 取 `project-a/infra-v2/terraform/postdeploy/ecs-autoscaling.tf`，step 取 `project-c-app/modules/app-service/ecs-autoscaling.tf`。可拆 `autoscaling.tf`、`load-balancer.tf` |
| `modules/ecs-service/tests/{defaults,autoscaling,load-balancer,secrets-roles,validation}.tftest.hcl` | 見下表 |
| `modules/ecs-service/examples/basic/`（不接 LB）、`examples/with-alb/`（`listener_arn` 模式） | role ARN、SG id 用假值字串 |
| `modules/ecs-service/README.md`、`CHANGELOG.md` | 兩種 LB 接法、autoscaling 的固定數量與兩種 policy、execution role 需要的權限（對到範本 iam-base） |

**`ecs-cluster` 的 run block**

| run | 斷言 |
|---|---|
| `defaults` | `containerInsights = "enhanced"`；capacity providers 恰為 `FARGATE`、`FARGATE_SPOT`；預設策略只有 FARGATE、`weight = 1`、`base = 0` |
| `insights_log_group_when_enabled` | 預設時建 1 個 `aws_cloudwatch_log_group.container_insights`，名稱 `/aws/ecs/containerinsights/<name>/performance`，retention 等於 `log_retention_days` |
| `no_insights_log_group_when_disabled` | `container_insights = "disabled"` → log group 0 個 |
| `no_namespace_by_default` ／ `namespace_when_named` | `service_connect_namespace = null` → 0 個；給名稱 → 1 個 `aws_service_discovery_http_namespace` |
| `name_format` | 大寫、以數字開頭、超過 63 字被擋；2 字元的合法名稱通過 |
| `container_insights_values` | `"on"` 被擋；`disabled`、`enabled`、`enhanced` 通過 |
| `capacity_provider_values` | `EC2` 被擋 |
| `only_one_base` | FARGATE 與 FARGATE_SPOT 都設 `base > 0` 被擋；只有一個設 `base = 1` 通過 |
| `retention_values` | `10` 被擋；`30` 通過 |

**`ecs-service` 的 run block**

| 檔案 | run | 斷言 |
|---|---|---|
| defaults | `task_definition_defaults` | `FARGATE`、`awsvpc`、`ARM64`、`LINUX`、`cpu = 512`、`memory = 1024` |
| defaults | `container_defaults` | container 名稱 `app`、`initProcessEnabled = true`、`stopTimeout = 120`、`awslogs` 且 `mode = "non-blocking"`、指向 module 建的 log group |
| defaults | `service_defaults` | `assign_public_ip = false`；deployment 100／200；circuit breaker＋rollback；`propagate_tags = "SERVICE"`；`availability_zone_rebalancing = "ENABLED"`；`wait_for_steady_state = false`；`enable_execute_command = false` |
| defaults | `log_group_per_service` | 1 個 log group，名稱預設 `/ecs/<name>`；給 `log_group_name` 時用給的名稱 |
| defaults | `network_passed_through` | `subnets`、`security_groups` 等於 `network` 輸入 |
| defaults | `x86_override` | `cpu_architecture = "X86_64"` 時 task definition 跟著變 |
| autoscaling | `fixed_count_when_autoscaling_null` | `autoscaling = null` → 仍建 1 個 scalable target，`min = max = desired_count`；policy 與 scaling 用 alarm 都是 0 |
| autoscaling | `target_tracking_is_default_policy` | 給 `autoscaling` 不寫 `policy` → `aws_appautoscaling_policy.cpu`（target 60）；`requests` 0 個；step 相關 0 個 |
| autoscaling | `requests_policy_only_when_set` | `requests_per_target = 300` 且 `alb_arn_suffix` 有值 → 多建 `requests` |
| autoscaling | `step_policy_has_no_target_tracking` | `policy = "step"` → target tracking 0 個；CPU、記憶體各一組 scale-out（+1／+2／+3）與 scale-in（−1）；4 個 scaling 用 alarm 指向對應 policy；門檻 70／40、70／50 |
| autoscaling | `scalable_target_resource_id` | `resource_id = "service/<cluster_name>/<service_name>"`，`<cluster_name>` 從 `cluster_arn` 拆出 |
| autoscaling | `policy_values` | `"scheduled"` 被擋 |
| autoscaling | `capacity_range` | `min = 4, max = 2` 被擋；`min = 0` 被擋；`min = max = 1` 通過 |
| autoscaling | `desired_within_range` | `desired_count = 5`、`min = 1`、`max = 3` 被擋 |
| autoscaling | `requests_requires_alb_suffix` | `requests_per_target` 有值但 `alb_arn_suffix` 為 null → 被擋 |
| load-balancer | `no_load_balancer` | `load_balancer = null` → 沒有 `load_balancer` block；target group 與 listener rule 都是 0；`health_check_grace_period_seconds` 為 null（design 的預設 180 只在有 LB 時套用） |
| load-balancer | `grace_period_with_lb` | 有 LB 時為 180 |
| load-balancer | `external_target_group` | 只給 `target_group_arn` → service 的 `load_balancer.target_group_arn` 等於它；module 不建 target group 與 listener rule |
| load-balancer | `module_creates_target_group` | 給 `listener_arn`、`vpc_id`、`priority`、`path_patterns` → 1 個 target group（名稱 `<name>-<container_port>`、`target_type = "ip"`、`HTTP`、health check `/health`）、1 個 listener rule |
| load-balancer | `exactly_one_lb_mode` | 同時給 `target_group_arn` 與 `listener_arn` 被擋；兩個都不給也被擋 |
| load-balancer | `listener_mode_complete` | 缺 `vpc_id`、缺 `priority`、host 與 path 都空，各自被擋 |
| load-balancer | `container_port_required_with_lb` | 有 LB 但 `container_port = null` → 被擋 |
| load-balancer | `service_connect_configured` | 給 `service_connect` 與 `container_port` → 有 `service_connect_configuration`，`dns_name` 預設為 `name` |
| load-balancer | `container_port_required_with_service_connect` | 有 `service_connect` 但 `container_port = null` → 被擋 |
| secrets-roles | `secrets_use_value_from` | `secrets` 每一筆是 `{name, valueFrom}`，不出現在 `environment` |
| secrets-roles | `secret_arn_format` | `my-secret` 被擋；Secrets Manager 與 SSM 參數 ARN 通過 |
| secrets-roles | `role_arns_passed_through` | `execution_role_arn`、`task_role_arn` 分別等於輸入 |
| secrets-roles | `role_arn_format` | `my-role`、`arn:aws:iam::123456789012:user/x` 被擋（兩個 role 變數各測） |
| validation | `cpu_memory_pairs` | `256/4096` 被擋；`1024/2048` 通過 |
| validation | `network_shape` | 1 個 subnet、兩個相同 subnet、0 個 SG 各自被擋 |
| validation | `image_tag_required` | `repo:latest`、`repo` 被擋；`repo:1.2.3`、`repo@sha256:<64 hex>` 通過 |
| validation | `name_length` | 27 字元被擋；26 字元通過 |
| validation | `cluster_arn_format` | `my-cluster` 被擋 |
| validation | `tags_are_applied` | 輸入的 tags 出現在 service 與 task definition，另加 `Name` |

`lifecycle { ignore_changes = [desired_count] }` 用 grep 驗收。

**驗收指令**

```bash
scripts/validate.sh modules/ecs-cluster modules/ecs-service
grep -n 'ignore_changes' modules/ecs-service/*.tf          # 預期有 desired_count
grep -rnE 'resource "aws_(iam_|security_group)' modules/ecs-cluster modules/ecs-service   # 預期沒有輸出
grep -rn 'name_prefix *= *"svc-"\|ManagedBy' modules/ecs-*/*.tf   # 預期沒有輸出
scripts/validate.sh
```

**完成定義**：上表每個 run 都存在且通過。主 agent 驗證後，`ecs-cluster`、`ecs-service` 各 commit 一次。

**不在本次範圍**：IAM 與 SG；EC2 capacity provider；sidecar；排程擴縮與自訂指標的 step scaling；`readonlyRootFilesystem`；ALB 本身（Phase 4）；告警（Phase 4）。

### Phase 4：`alb`、`ecs-service-alarms`

**目標**：`alb` 照 design §4.8：`aws_lb_listener.http` 一律建立（有憑證時預設 action 301 轉 HTTPS，沒有憑證時回 404），有憑證才建 `aws_lb_listener.https`（預設回 404）；ELB 5xx 告警在這裡（一個 ALB 一份）。`ecs-service-alarms` 照 design §4.4，不含 ELB 5xx（design J4）。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `modules/alb/{main,variables,outputs,versions}.tf` | `aws_lb.this`、`aws_lb_listener.http`、`aws_lb_listener.https`、`aws_lb_listener_certificate.additional`、`aws_wafv2_web_acl_association.this`；輸出 `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol`、`alarm_arns` |
| `modules/alb/alarms.tf` | `aws_cloudwatch_metric_alarm.elb_5xx` |
| `modules/alb/tests/{listeners,options,validation}.tftest.hcl` | 見下表 |
| `modules/alb/examples/http-only/`、`examples/https/`、`README.md`、`CHANGELOG.md` | README 寫清楚「沒有憑證時 SG 必須收窄」是 network stack 的責任，以及 access log bucket 只能用 SSE-S3 |
| `modules/ecs-service-alarms/{main,variables,outputs,versions}.tf`、`dashboard.tf` | `alarm_config` 巢狀 `optional()`（`alarm_config.ecs.cpu_threshold` 這種結構，取自 `project-c-app/modules/app-platform/variables.tf`、`cloudwatch-alarms.tf`，拿掉 `enabled`）；`alarm_actions`／`ok_actions` 都接 `sns_topic_arns`（`project-a/infra-v2/terraform/postdeploy/alarms.tf`）；dashboard 參考 `project-a/infra-v2/terraform/postdeploy/dashboard.tf` |
| `modules/ecs-service-alarms/tests/{alarms,validation,dashboard}.tftest.hcl`、`examples/basic/`、`examples/with-alb/`、`README.md`、`CHANGELOG.md` | 見下表 |

**`alb` 的 run block**（介面照 design §4.8）

| 檔案 | run | 斷言 |
|---|---|---|
| listeners | `https_with_certificate` | 給 `certificate_arn` → `aws_lb_listener.https`：443、`HTTPS`、`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`、預設 action 是 fixed-response 404、`content_type = "text/plain"`；`aws_lb_listener.http`：80、預設 action 是 redirect 到 HTTPS、`status_code = "HTTP_301"`；`listener_protocol = "HTTPS"`，`listener_arn` 是 https 那一個（apply） |
| listeners | `http_only_without_certificate` | `certificate_arn = null` → `aws_lb_listener.https` 0 個；`aws_lb_listener.http` 預設 action 回 404；`listener_protocol = "HTTP"`，`listener_arn` 是 http 那一個（apply） |
| listeners | `additional_certificates` | `additional_certificate_arns` 給 2 個 → 2 個 `aws_lb_listener_certificate.additional` 掛在 https listener；給空集合 → 0 個 |
| listeners | `additional_certificates_need_primary` | `certificate_arn = null` 但有 `additional_certificate_arns` → 被擋 |
| options | `load_balancer_defaults` | `internal = false`、`load_balancer_type = "application"`、`idle_timeout = 60`、`enable_deletion_protection = true`、`drop_invalid_header_fields = true`；subnets 與 SG 等於輸入 |
| options | `no_access_logs_by_default` ／ `access_logs_when_given` | `access_logs = null` → 沒有啟用的 access log；給 `bucket`、`prefix` → `enabled = true` 且值相同；只給 `bucket` 時 prefix 為 null |
| options | `no_waf_by_default` ／ `waf_association_when_given` | `web_acl_arn = null` → `aws_wafv2_web_acl_association.this` 0 個；給值 → 1 個 |
| options | `elb_5xx_alarm` | 1 個 `aws_cloudwatch_metric_alarm.elb_5xx`，指標 `HTTPCode_ELB_5XX_Count`、門檻 1、週期 60；`alarm_actions == ok_actions == toset(sns_topic_arns)`；dimension `LoadBalancer` 是 `alb_arn_suffix`（apply）；`alarm_arns` 有這一個 |
| options | `alarm_config_override` | `alarm_config = { elb_5xx_threshold = 5 }` → 門檻 5，週期仍 60 |
| validation | `name_format` | 33 字元、以 `-` 開頭或結尾、以 `internal-` 開頭，各自被擋；32 字元通過 |
| validation | `idle_timeout_range` | 0 與 4001 被擋；1 與 4000 通過 |
| validation | `subnet_count` | 1 個（或兩個相同）subnet 被擋；2 個通過 |
| validation | `security_group_required` | `security_group_ids = []` 被擋 |
| validation | `certificate_arn_format` | 非 ACM ARN 被擋；`arn:aws:acm:...:certificate/...` 通過 |
| validation | `web_acl_arn_format` | 非 regional WAFv2 ARN 被擋 |
| validation | `sns_topic_required` | `sns_topic_arns = []` 被擋 |

**`ecs-service-alarms` 的 run block**

| 檔案 | run | 斷言 |
|---|---|---|
| alarms | `every_alarm_notifies_both_ways` | 對所有 `aws_cloudwatch_metric_alarm`：`alarm_actions` 與 `ok_actions` 都等於 `toset(var.sns_topic_arns)` |
| alarms | `base_set_without_lb_or_max` | 不給 `load_balancer`、`max_capacity` → 恰好 7 個：`cpu_high`、`memory_high`、`cpu_missing`、`memory_missing`、`tasks_below_desired`、`cpu_throttling`、`memory_pressure`；名稱 `<name>-<key>` |
| alarms | `service_alarm_defaults` | `cpu_high`、`memory_high` 門檻 80、300 秒 × 1；`*_missing` `breaching`、60 秒 × 2；`cpu_throttling` 0.9、`memory_pressure` 0.85 |
| alarms | `at_max_capacity_only_with_max` | `max_capacity = 6` → 多 1 個 `at_max_capacity`，門檻 6；`null` 時 0 個 |
| alarms | `alb_alarms_with_lb` | 給 `load_balancer` → 多 5 個：`target_5xx_ratio`（0.01）、`target_4xx_ratio`（0.05）、`latency_p95`（800 ms → 0.8 秒）、`unhealthy_hosts`（< 1）、`target_connection_errors`（> 0）；不含 ELB 5xx |
| alarms | `no_lb_no_alb_alarms` | 不給 `load_balancer` → 上一列 5 個都是 0 |
| alarms | `override_one_threshold_keeps_others` | `alarm_config = { ecs = { cpu_threshold = 90 } }` → `cpu_high` 90，`memory_high` 仍 80，`container`、`alb` 不變 |
| alarms | `dimensions_point_to_service` | ECS 告警含 `ClusterName`、`ServiceName`；ALB 告警含 `TargetGroup`、`LoadBalancer` |
| validation | `sns_topic_required` | `[]` 被擋；不給（必填）以 RED 階段實測的方式鎖住 |
| validation | `sns_arn_format` | SQS ARN 被擋；SNS ARN 通過 |
| validation | `suffix_prefixes` | `alb_arn_suffix` 不以 `app/` 開頭、`target_group_arn_suffix` 不以 `targetgroup/` 開頭各自被擋；兩個都正確時通過 |
| validation | `name_format` | 大寫或含空白被擋 |
| dashboard | `no_dashboard_by_default` | `dashboard_name = null` → 0 個，`dashboard_arn` 為 null |
| dashboard | `dashboard_body_is_valid_json` | 給名稱 → 1 個；`jsondecode(dashboard_body).widgets` 長度 > 0，metric widget 的 ServiceName 等於輸入 |
| dashboard | `dashboard_without_lb` | 沒有 LB 時仍可建立，不含 ALB widget |

**驗收指令**

```bash
scripts/validate.sh modules/alb modules/ecs-service-alarms
grep -n 'HTTPCode_ELB_5XX' modules/ecs-service-alarms/*.tf   # 預期沒有輸出
grep -n 'HTTPCode_ELB_5XX' modules/alb/*.tf                  # 預期有
grep -rnE 'resource "aws_(iam_|security_group)' modules/alb  # 預期沒有輸出
scripts/validate.sh
```

**完成定義**：`every_alarm_notifies_both_ways` 用反向驗證證明有效（拿掉一個 alarm 的 `ok_actions`，測試要紅）；`http_only_without_certificate` 用反向驗證證明 443 不會在沒有憑證時建出來。主 agent 驗證後，`alb`、`ecs-service-alarms` 各 commit 一次。

**不在本次範圍**：WAF Web ACL 本身（專案自建，只做關聯）；NLB；ALB 層的連線數告警；access log bucket 本身（foundation stack）；Bedrock／ElastiCache 告警；嚴重度分級。

### Phase 5：`rds`

**目標**：照 design §4.9。`deployment = "rds" | "aurora" | "aurora_serverless"` 三選一，RDS Proxy 是選項；module 不建 IAM、沒有 password 變數；三種型態的輸出格式一致。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `modules/rds/versions.tf`、`variables.tf` | 共用輸入與 `rds`／`aurora`／`serverless` 三個型態物件、`proxy`、`monitoring`、`sns_topic_arns`、`alarm_config`；交叉 validation（Terraform 1.9 以上，`required_version >= 1.10` 已滿足） |
| `modules/rds/main.tf` | `aws_db_subnet_group.this`、`random_id.final_snapshot`、`aws_cloudwatch_log_group.postgresql` |
| `modules/rds/instance.tf` | `deployment = "rds"`：`aws_db_parameter_group.rds`（`postgres<major>`）、`aws_db_instance.this` |
| `modules/rds/cluster.tf` | Aurora 兩型：`aws_rds_cluster_parameter_group.this`、`aws_db_parameter_group.aurora_instance`（`instance_parameters` 非空才建）、`aws_rds_cluster.this`（Serverless 加 `dynamic "serverlessv2_scaling_configuration"`）、`aws_rds_cluster_instance.this`（`count = 1 + reader_count`） |
| `modules/rds/proxy.tf` | `aws_db_proxy.this`、`aws_db_proxy_default_target_group.this`、`aws_db_proxy_target.this`、`aws_db_proxy_endpoint.read_only`、`aws_cloudwatch_log_group.proxy` |
| `modules/rds/alarms.tf` | `cpu_high`、`freeable_memory_low`（每個 instance 一個）、`connections_high`、`replica_lag_high`、`proxy_borrowed_high`、`proxy_pinned_high` |
| `modules/rds/outputs.tf` | design §4.9 的輸出表全部 |
| `modules/rds/tests/{deployments,proxy,safety,alarms,validation}.tftest.hcl` | 見下表 |
| `modules/rds/examples/rds/`、`examples/aurora-serverless-proxy/` | 兩種型態的呼叫範例 |
| `modules/rds/README.md`、`CHANGELOG.md` | 三種型態對照、`rds` 與 Aurora 互換是資料遷移、一般 RDS 用 `.address`、應用程式用 master secret 的風險 |

**mock 寫法**（每個測試檔開頭都要有；不給的話 `master_user_secret` 是空 list，取 `[0]` 會失敗）

```hcl
mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      address  = "app-db.abc123.ap-northeast-1.rds.amazonaws.com"
      endpoint = "app-db.abc123.ap-northeast-1.rds.amazonaws.com:5432"
      port     = 5432
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint        = "app-db.cluster-abc123.ap-northeast-1.rds.amazonaws.com"
      reader_endpoint = "app-db.cluster-ro-abc123.ap-northeast-1.rds.amazonaws.com"
      port            = 5432
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-x"
        kms_key_id    = "k"
        secret_status = "active"
      }]
    }
  }
}
```

`mock_resource` 的 `defaults` 只在 apply 階段填 computed 值，所以斷言輸出（端點、secret ARN）的 run 用 `command = apply`（D6），表中標「apply」；只斷言資源數量與設定值的 run 用 `plan`。Phase 1 若確認 `override_during = plan` 可用，改用 plan。

**run block**

| 檔案 | run | 斷言 |
|---|---|---|
| deployments | `rds_basic` | `deployment = "rds"` → 各 1 個 `aws_db_subnet_group.this`、`aws_db_parameter_group.rds`（family `postgres<major>`，major 取自 `engine_version` 第一段）、`aws_db_instance.this`、`aws_cloudwatch_log_group.postgresql`（`/aws/rds/instance/<name>/postgresql`）；`aws_rds_cluster*` 都是 0；`allocated_storage = 20`、`storage_type = "gp3"`、`multi_az = false`、`max_allocated_storage` 為 null |
| deployments | `aurora_basic` | `deployment = "aurora"`、`reader_count` 預設 1 → 1 個 `aws_rds_cluster.this`、1 個 `aws_rds_cluster_parameter_group.this`（`aurora-postgresql<major>`）、2 個 `aws_rds_cluster_instance.this`（class 等於輸入）；log group `/aws/rds/cluster/<name>/postgresql`；`aws_db_instance` 0 個；沒有 `serverlessv2_scaling_configuration` |
| deployments | `serverless_basic` | `deployment = "aurora_serverless"`、0.5～4 ACU → cluster 有 `serverlessv2_scaling_configuration`（min／max 等於輸入）；instance class 都是 `db.serverless`；`reader_count` 預設 0 → 1 個 instance |
| deployments | `aurora_instance_param_group_optional` | `instance_parameters = {}` → `aws_db_parameter_group.aurora_instance` 0 個；非空 → 1 個，family `aurora-postgresql<major>` |
| deployments | `fixed_settings_all_modes` | 三種型態各一次：`storage_encrypted = true`、`publicly_accessible = false`（rds）、`copy_tags_to_snapshot = true`、PI 開啟且保留 `performance_insights_retention_days`（預設 7）、log export 恰為 `["postgresql"]`、參數包含 `log_min_duration_statement = 500`、`log_lock_waits = 1`、`rds.force_ssl = 1`、`shared_preload_libraries = pg_stat_statements`；呼叫端給同名參數時覆蓋預設值 |
| deployments | `backup_and_windows` | `backup_retention_days = 7`、`backup_window = "18:00-19:00"`、`maintenance_window = "sun:19:00-sun:20:00"` 套用到 instance 或 cluster |
| deployments | `outputs_rds` | （apply）`writer_endpoint` 是 `.address`（不含 `:5432`）；`reader_endpoint == writer_endpoint`；`has_reader = false`；`port = 5432`；`identifier_type = "instance"`；`cluster_id = null`；`instance_ids` 長度 1；`cloudwatch_dimension.name = "DBInstanceIdentifier"` |
| deployments | `outputs_aurora` | （apply）`writer_endpoint`、`reader_endpoint` 是 cluster 的兩個端點；`has_reader = true`；`identifier_type = "cluster"`；`instance_ids` 長度 2；`cloudwatch_dimension.name = "DBClusterIdentifier"`；`master_user_secret_arn` 等於 mock 的 cluster secret |
| deployments | `outputs_serverless_no_reader` | （apply）`serverless.reader_count = 0` → `has_reader = false`、`reader_endpoint` 仍是 cluster 的 RO 端點 |
| proxy | `rds_proxy_off` ／ `aurora_proxy_off` ／ `serverless_proxy_off` | `proxy = null` → `aws_db_proxy*` 與 `aws_cloudwatch_log_group.proxy` 都是 0；（apply）`proxy_endpoint = null`、`app_endpoint == writer_endpoint`、`app_reader_endpoint == reader_endpoint` |
| proxy | `rds_proxy_on` ／ `aurora_proxy_on` ／ `serverless_proxy_on` | 給 `proxy` → 1 個 `aws_db_proxy.this`（`engine_family = "POSTGRESQL"`、`require_tls = true`、`idle_client_timeout = 1800`、`debug_logging = false`、`vpc_subnet_ids` 等於 data tier 的 `subnet_ids`）、1 個 default target group（`max_connections_percent = 50`、`max_idle_connections_percent = 25`）、1 個 `aws_db_proxy_target.this`（rds 用 `db_instance_identifier`、Aurora 兩型用 `db_cluster_identifier`）、log group `/aws/rds/proxy/<name>`；（apply）`app_endpoint == proxy_endpoint` |
| proxy | `aurora_proxy_ro` | `aurora`、`reader_count = 1`、開 Proxy → 1 個 `aws_db_proxy_endpoint.read_only`（`target_role = "READ_ONLY"`）；（apply）`app_reader_endpoint` 是 RO endpoint |
| proxy | `rds_proxy_no_ro` | `rds`、開 Proxy → RO endpoint 0 個；（apply）`app_reader_endpoint == proxy_endpoint`、`has_reader = false`。對照：`aurora_serverless`、`reader_count = 0`、開 Proxy 也是 0 個 RO endpoint |
| proxy | `proxy_role_passed_through` | `aws_db_proxy.this.role_arn` 等於 `proxy.role_arn`；`auth` 的 `auth_scheme = "SECRETS"`、`iam_auth = "DISABLED"`；（apply）`auth.secret_arn` 是 master secret；`vpc_security_group_ids` 等於 `proxy.security_group_ids` |
| proxy | `monitoring_role_passed_through` | `monitoring = { role_arn = ... }` → `monitoring_interval = 60`（預設）、`monitoring_role_arn` 等於輸入，rds 套在 instance、Aurora 套在每個 cluster instance；`monitoring = null` → `monitoring_interval = 0` |
| safety | `no_password_all_modes` | 三種型態各一次：`manage_master_user_password = true`，`password` 與 `password_wo` 都是 null；`master_username = "dbadmin"` |
| safety | `master_secret_kms` | 給 `master_user_secret_kms_key_arn` → `master_user_secret_kms_key_id` 等於它；`kms_key_arn` 套到 storage 加密 |
| safety | `final_snapshot` | `skip_final_snapshot = false`、`deletion_protection = true`；（apply）`final_snapshot_identifier` 是 `<name>-final-<random_id 的 hex>` |
| safety | `subnet_and_sg_from_inputs` | subnet group 的 `subnet_ids` 等於輸入；DB 的 SG 等於 `security_group_ids` |
| alarms | `alarms_per_deployment` | `rds`、無 Proxy → 3 個（`cpu_high`、`freeable_memory_low`、`connections_high`）；`aurora`、`reader_count = 1` → 6 個（`cpu_high` 與 `freeable_memory_low` 各 2，每個 instance 一個；`connections_high` 1；`replica_lag_high` 1）；同上開 Proxy → 8 個（加 `proxy_borrowed_high`、`proxy_pinned_high`）；`aurora_serverless`、`reader_count = 0` → 3 個（沒有 `replica_lag_high`）；每個的 `alarm_actions == ok_actions == toset(sns_topic_arns)` |
| alarms | `alarm_defaults` | `cpu_high` ≥ 80、300 秒 × 3；`freeable_memory_low` ≤ 209715200、60 秒 × 15；`replica_lag_high` ≥ 1000、300 秒 3 中 2；Proxy 兩條 > 80、> 20，60 秒 × 5 |
| alarms | `serverless_connections_formula` | `aurora_serverless`、沒給 `connections_threshold`、`max_capacity = 16` → `connections_high` 的門檻等於 `floor(min(16 × 2 × 1073741824 ÷ 9531392, 5000) × 0.8)`（斷言裡直接算） |
| alarms | `connections_threshold_override` | 有給 `connections_threshold` 時用給的值（三種型態都適用） |
| alarms | `connections_dimension` | rds 用 `DBInstanceIdentifier`、Aurora 用 `DBClusterIdentifier` |
| validation | `deployment_values` | `"mysql"` 被擋 |
| validation | `deployment_object_must_match` | `aurora` 卻給 `rds` 物件 → 被擋；給 `aurora` 又多給 `serverless` → 被擋；只給對應物件通過（三種型態各一組） |
| validation | `aurora_class_rules` | `db.serverless` 被擋；`r7g.large`（沒有 `db.`）被擋；`db.r7g.large` 通過 |
| validation | `acu_range` | `min = 2, max = 1` 被擋；`max = 257` 被擋；`min = -0.5` 被擋；`min = 0, max = 256` 通過 |
| validation | `acu_step` | `min = 0.75` 被擋；`max = 1.5` 通過 |
| validation | `reader_count_limit` | `reader_count = 16` 被擋；`15` 通過（aurora 與 serverless 各測） |
| validation | `rds_rejects_cluster_parameters` | `rds` 且 `cluster_parameters` 非空 → 被擋 |
| validation | `proxy_role_arn_required` | `proxy` 不給 `role_arn` → 被擋（`role_arn` 宣告成 `optional(string)`，用 validation 擋 null，`expect_failures` 才抓得到；見「跟 design 不一致」第 1 點） |
| validation | `proxy_role_arn_format` | `role_arn = "my-role"` 被擋；IAM role ARN 通過 |
| validation | `connections_threshold_required` | `rds` 或 `aurora` 沒給 `connections_threshold` → 被擋；`aurora_serverless` 沒給通過 |
| validation | `sns_topic_required` | `sns_topic_arns = []` 被擋 |
| validation | `name_format` | 大寫、`--`、以 `-` 結尾、超過 50 字被擋；50 字通過 |
| validation | `engine_version_format` | `12.1`、`16` 被擋；`16.4` 通過 |
| validation | `database_name_format` | `App-DB` 被擋；`app` 通過 |
| validation | `backup_retention_range` | 0 與 36 被擋；1 與 35 通過 |
| validation | `subnet_count` | 1 個 subnet 被擋 |

「所有組合都沒有 `aws_iam_*`」不寫成 run（`terraform test` 沒辦法列舉資源型別），由 `validate.sh` 的 S4 負責。

**驗收指令**

```bash
scripts/validate.sh modules/rds
grep -niE 'variable "[^"]*password' modules/rds/variables.tf    # 預期沒有輸出（S7）
grep -rn 'random_password' modules/                            # 預期沒有輸出（S7）
grep -n 'aws_db_instance\.this\.endpoint' modules/rds/*.tf     # 預期沒有輸出（一般 RDS 只能用 .address）
scripts/validate.sh
```

**完成定義**：design §7.1 的 rds 清單（`no_iam_resources` 除外，改由 S4）全部有對應 run 且通過；6 個 `{型態} × {proxy_off, proxy_on}` run 齊全；`proxy_role_passed_through` 與 `no_password_all_modes` 用反向驗證證明有效。主 agent 驗證後 commit。

**不在本次範圍**：一般 RDS 的 read replica、Multi-AZ DB cluster、混用 provisioned 與 serverless instance；應用程式專用 DB 帳號與 Proxy 的 IAM 認證；MySQL；任何 IAM 與 SG；型態互換與 0 ACU 的實測。

### Phase 6：`templates/project-infra`（8 個 stack）

**目標**：專案 app team 複製出去就能用的三層架構範本，照 design §5。IAM 分在 iam-base 與 iam-app、SG 集中在 network；兩個以上 stack 都要知道的開關只由上游一個 stack 決定（design J21 的單一決定點），下游讀取後用 precondition 檢查自己的設定跟上游一致。

**stack 與 apply 順序**（design §5.3）

| 順序 | stack | 內容 | 用到的 module | 從 SSM 讀（來源 stack） | 發布到 SSM |
|---|---|---|---|---|---|
| 1 | `foundation` | 告警 SNS、共用 CMK、app secret 容器、flow log bucket、ALB access log bucket | `sns-alarm-topic`、`ssm-publish` | — | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| 2 | `containerimage` | 各服務的 ECR repository（原生資源）；**服務清單的單一決定點** | `ssm-publish` | foundation | `services`、`ecr_<service>_url`、`ecr_<service>_arn` |
| 3 | `network` | 建 VPC（預設）或登記既有 VPC（模式 A）；ALB／服務／DB／Proxy 的 SG；**`alb_https`、`db_proxy`、`data_access` 的單一決定點** | `vpc`、`ssm-publish` | foundation、containerimage | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>`、`sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id`（有 interface endpoint 才發布）、`nat`、`alb_https`、`db_proxy`、`data_access` |
| 4 | `iam-base` | ECS execution role、RDS Proxy role（只有 trust）、Enhanced Monitoring role | `ssm-publish` | foundation、containerimage | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` |
| 5 | `data` | 資料庫（可選 Proxy）與資料庫告警 | `rds`、`ssm-publish` | foundation、network、iam-base | `database`（JSON） |
| 6 | `iam-app` | Proxy role 讀 secret 的 policy、各服務 task role、ECS Exec 開關 | `ssm-publish` | foundation、containerimage、network、iam-base、data | `role_<service>_task_arn`、`ecs_exec_<service>` |
| 7 | `loadbalancer` | ALB、listener、ELB 5xx 告警、WAF 關聯 | `alb`、`ssm-publish` | foundation、network | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| 8 | `application` | ECS cluster、service、autoscaling、服務告警、dashboard | `ecs-cluster`、`ecs-service`、`ecs-service-alarms` | 前七個 | 不發布 |

key 名稱與 JSON 格式以 design §5.6 的合約表為準；服務名稱的 `-` 在 key 裡轉成 `_`。

**每個 stack 共通的檔案**（相對於 `templates/project-infra/infra/terraform/<stack>/`）

| 路徑 | 用途 |
|---|---|
| `versions.tf` | `required_version = ">= 1.10"`、`aws ~> 6.0`、`backend "s3" {}` |
| `providers.tf` | `allowed_account_ids = [var.expected_account_id]`、`default_tags`（`Project`、`Environment`、`Managed = "terraform"`、`Stack`）、可選 `assume_role`。每個 stack 只差 `Stack` 的值 |
| `common.tf` | `project`、`env`、`aws_region`、`expected_account_id`（不給預設值）與 `accounts_by_env` 對照表 validation、`name_prefix`、`ssm_prefix`、`common_tags`。**8 個 stack 一字不差**（S5） |
| `variables.tf` | 只放這個 stack 自己的變數 |
| `ssm-inputs.tf` | design §5.6 的寫法：`local.ssm_inputs.strings`／`lists`＋`data "aws_ssm_parameter"`，只讀 `insecure_value`（foundation 不放） |
| `ssm-outputs.tf` | 只呼叫 `ssm-publish`（application 不放） |
| `<resource>.tf` | 這個 stack 的資源或 module 呼叫。module 用相對路徑 `source = "../../../../../modules/<name>"`（D2） |
| `outputs.tf` | 給人看的輸出 |
| `envs/dev.tfvars`、`envs/prod.tfvars` | 非機密值，進版控；不放 secret、不放其他 stack 的資源 id |
| `envs/dev.tfbackend`、`envs/prod.tfbackend` | key `<project>-<env>/<stack>/terraform.tfstate`（S6） |
| `tests/<stack>.tftest.hcl` | 共通 run 加上 stack 專屬 run，`mock_provider "aws"`＋`override_data` 逐 key 餵 SSM 值 |
| `.terraform.lock.hcl` | 進版控（D5） |

`network`、`data`、`loadbalancer` 另有：

| 路徑 | 用途 |
|---|---|
| `envs/examples/{poc,standard,high}.tfvars` | 流量規格範例（design §5.11），不直接 apply、沒有 tfbackend；不得含明文 secret（project-a `loadbalancer/envs/{uat,prod}.tfvars` 的 `chat_origin_lock_header_value` 不得照抄） |
| `tests/examples/examples.tftest.hcl` | 只放 `project`、`env`、`expected_account_id` 這類共通值與 SSM 的 `override_data`，其餘值由 `validate.sh` 用 `-var-file=envs/examples/<x>.tfvars` 帶入（R12）；斷言該組範例 plan 得出來，且關鍵數量符合 design §5.11 的表 |

範本根目錄 `templates/project-infra/infra/README.md`：stack 清單、apply 順序與 destroy 反序、SSM 合約表（每個 key 誰寫誰讀，照 design §5.6）、流量規格對照表、`TF_DATA_DIR=.terraform-<env>`、換環境一律 `init -reconfigure`、客戶自管模式 A／B、**第一次部署時 RDS Proxy 的兩段式步驟**（design §5.4：若建立失敗，先在 network 設 `data_stores.db.proxy = false` 跑到 iam-app，再改 `true` 依序 apply network、data；未驗證）、複製出去後把相對路徑 source 改成 `git::...?ref=<module>-v<semver>`（指向 `docs/guides/consuming-modules.md`）。不提供 `stacks.sh`。

**共通 run block（每個 stack 都有）**

| run | 斷言 |
|---|---|
| `env_format` | `Dev`、`d` 被擋；`dev` 通過 |
| `account_must_match_env` | `dev` 配 prod 的帳號被擋；表外的 env 被擋；對得上時通過（照 `project-a/infra-v2/terraform/bridge/tests/guard.tftest.hcl`） |
| `account_is_required` | 不給 `expected_account_id` → 報缺變數 |
| `publishes_under_stack_path` | 每個發布的 SSM 名稱都是 `/<project>/<env>/<stack>/<key>`（application 除外） |
| `dev_tfvars_creates_resources` | 用 `envs/dev.tfvars` 的值 plan，主要資源數量 ≥ 1，鎖住「開關預設全關、tfvars 不完整就規劃刪除」的坑。做法同 examples：`validate.sh` 另跑 `-var-file=envs/dev.tfvars` 與 `envs/prod.tfvars`（R12） |

`allowed_account_ids` 本身在 mock 下測不到，只鎖 validation。

#### foundation

| 檔案 | 用途 |
|---|---|
| `alarms.tf` | `sns-alarm-topic`，用本 stack 的 CMK |
| `kms.tf` | 共用 CMK，key policy 給 CloudWatch 與 CloudWatch Logs |
| `secrets.tf` | app secret 容器（不含值） |
| `log-buckets.tf` | flow log bucket 與 ALB access log bucket，兩個分開、一律建立（design J24） |

| run | 斷言 |
|---|---|
| `publishes_foundation_keys` | 發布 `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| `kms_policy_allows_cloudwatch_and_logs` | `jsondecode(key policy)` 有給 `cloudwatch.amazonaws.com` 與 `logs.<region>.amazonaws.com` 的 Statement |
| `log_buckets_always_created` | 不管 tfvars 怎麼設，兩個 bucket 都是 1 個（design J24） |
| `log_buckets_sse_s3` | 兩個 bucket 的加密都是 `AES256`，不是 `aws:kms`（ALB 用 CMK 會讓 log 無聲遺失，project-a `loadbalancer/access-logs.tf`） |
| `log_bucket_policies` | flow log bucket 的 principal 是 `delivery.logs.amazonaws.com`、ALB bucket 是該 region 的 ELB log delivery；兩者都帶本帳號的 `aws:SourceAccount` 條件 |
| `log_buckets_expire_after_90_days` | 兩個 bucket 都有 lifecycle rule，90 天過期 |
| `log_buckets_block_public_access` | 兩個 bucket 都有四項 Block Public Access |
| `secret_has_no_value` | 不宣告 `aws_secretsmanager_secret_version`（grep） |

#### containerimage

| run | 斷言 |
|---|---|
| `publishes_services` | `services = ["api", "worker"]` → 發布 `services`（StringList，值 `api,worker`） |
| `one_repository_per_service` | 兩個服務 → 兩個 `aws_ecr_repository`，名稱 `<project>-<env>-<service>` |
| `repository_defaults` | `image_tag_mutability = "IMMUTABLE"`、`scan_on_push = true`、`force_delete = false`、加密用 foundation 的 `kms_key_arn` |
| `lifecycle_policy` | 每個 repository 一份 lifecycle policy，`jsondecode` 後有兩條規則：未加 tag 的 7 天後刪除、有 tag 的保留最近 50 個 |
| `service_name_format` | 大寫或含空白被擋；`order-api` 通過 |
| `publishes_url_and_arn` | 每個服務都發布 `ecr_<service>_url`、`ecr_<service>_arn`；`order-api` 的 key 是 `ecr_order_api_url` |

#### network

| 檔案 | 用途 |
|---|---|
| `vpc.tf` | 建立模式：呼叫 `vpc` module；tier 固定 `public`（public）、`app`（private）、`data`（預設 isolated）；`flow_log = true` 時 `destination_arn` 用 foundation 的 `flow_log_bucket_arn` |
| `existing.tf` | 模式 A：`existing = { vpc_id, subnet_ids }`，`data "aws_vpc"`、`data "aws_subnet"` 用 `for_each` 確認存在 |
| `security-groups.tf` | 由 `services`、`data_stores`、`alb_ingress` 在 locals 展開成規則表（design §5.3），一律 `aws_vpc_security_group_ingress_rule`／`egress_rule` 搭配 `for_each`，來源用 `referenced_security_group_id`；Proxy SG 一律建立 |
| `envs/dev.tfvars` | `data_stores.db.proxy = false`（D19） |
| `envs/prod.tfvars` | `data_stores.db.proxy = true`（D19） |
| `envs/examples/{poc,standard,high}.tfvars` | poc：/20、2 AZ、`single`、不開 flow log、只有 S3 gateway、`alb_ingress.https = false` 只開給 CloudFront prefix list；standard：2 AZ、`per_az`、flow log、`ecr.api`／`ecr.dkr`／`logs`／`secretsmanager`／`kms`、`https = true`；high：/16、3 AZ、`per_az`、再加 `ssm`／`ssmmessages`／`xray`、`proxy = true` |

| run | 斷言 |
|---|---|
| `create_mode_publishes_keys` | 建立模式 → 發布 `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_{public,app,data}`、`subnet_cidrs_{public,app,data}`、`sg_alb_id`、每個服務的 `sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`nat`、`alb_https`、`db_proxy`、`data_access`；清單類以 StringList 發布 |
| `data_tier_isolated_by_default` | dev tfvars 下 `data` tier 的 `type = "isolated"` |
| `existing_mode_publishes_same_keys` | 模式 A → 發布的 key 集合跟 `create_mode_publishes_keys` 完全相同（`run.<name>` 比對）；`vpc` module 沒有被呼叫；`data "aws_subnet"` 的數量等於給的 subnet 數（`override_data` 餵 VPC CIDR 與 AZ） |
| `vpc_and_existing_are_exclusive` | 兩個都給被擋；兩個都不給被擋；只給一個通過 |
| `contract_tiers_required` | 建立模式的 `subnets` 缺 `data` 被擋；`existing.subnet_ids` 缺 `data` 被擋 |
| `services_must_match_containerimage` | `keys(var.services)` 多一個或少一個 `containerimage/services` 裡的服務 → precondition 失敗；一致時通過 |
| `references_must_exist` | `callers` 引用不存在的服務被擋；`data_access` 引用不存在的 data store 被擋 |
| `sg_rules_expand_from_services` | `api = { port = 8080, from_alb = true, data_access = ["db"] }`、`worker = { port = 9000, callers = ["api"] }` → api SG 一條 ingress 8080 來自 ALB SG；worker SG 一條 ingress 9000 來自 api SG；規則數等於展開表的長度 |
| `alb_egress_only_to_service_ports` | ALB SG 的 egress 恰為每個 `from_alb = true` 的服務 SG × 該服務 port，沒有 `0.0.0.0/0` |
| `service_egress_443_only` | 每個服務 SG 有一條 egress 443 到 `0.0.0.0/0`，沒有其他對外的 egress |
| `db_rules_with_proxy` | `proxy = true` → `data_access` 有 db 的服務 SG → Proxy SG 5432、Proxy SG → DB SG 5432；沒有服務直連 DB |
| `db_rules_without_proxy` | `proxy = false` → 服務 SG → DB SG 5432；Proxy SG 存在但沒有任何規則；`sg_db_proxy_id` 仍發布 |
| `sg_key_name_conversion` | 服務 `order-api` → 發布 `sg_order_api_id` |
| `no_inline_rules` | `security-groups.tf` 沒有 `ingress {`、`egress {`（grep） |
| `http_only_rejects_public_cidr` | `alb_ingress = { https = false, cidrs = ["0.0.0.0/0"] }` → 被擋；`cidrs = ["::/0"]` 也被擋 |
| `http_only_allows_prefix_list_or_cidr` | `https = false`、只給 CloudFront prefix list → 通過，ALB SG 只有 80 的 ingress；只給 `203.0.113.0/24` → 通過 |
| `ingress_needs_a_source` | `https = true` 或 `false` 但 `cidrs`、`prefix_list_ids` 都空 → 被擋 |
| `https_opens_443_and_80` | `https = true`、`cidrs = ["0.0.0.0/0"]` → ALB SG 有 443 與 80 兩條 ingress |
| `publishes_decision_points` | `alb_https` 是 `{"enabled":<https>}`、`db_proxy` 是 `{"enabled":<proxy>}`、`data_access` 是 `{"db":[有 db 權限的服務]}` |
| `nat_json` | `nat` 的 `jsondecode` 是 `{mode, ids}`，`mode` 等於 `nat_mode` |
| `vpce_sg_key_only_with_endpoints` | 沒有 interface endpoint → 不發布 `sg_vpce_id`；有 → 發布 |
| `flow_log_bucket_from_foundation` | `vpc.flow_log = true` 時 `vpc` module 的 `flow_log.destination_arn` 等於 SSM 讀到的 `flow_log_bucket_arn` |
| examples（`tests/examples/`） | poc：1 顆 NAT、2 AZ、0 個 interface endpoint、沒有 flow log、ALB SG 沒有 `0.0.0.0/0`；standard：NAT 數 2、5 個 interface endpoint、有 flow log；high：3 AZ、NAT 數 3、8 個 interface endpoint、`db_proxy` 為 true |

#### iam-base

| run | 斷言 |
|---|---|
| `three_roles_no_path` | 恰好 3 個 role：ECS execution、RDS Proxy、Enhanced Monitoring；`path` 都是 `/`（iam-app 從 ARN 最後一段取名稱，D21） |
| `trust_principals` | execution 只信任 `ecs-tasks.amazonaws.com`、Proxy 只信任 `rds.amazonaws.com`、monitoring 只信任 `monitoring.rds.amazonaws.com`；Action 只有 `sts:AssumeRole`；execution 與 Proxy 帶 `aws:SourceAccount` 條件 |
| `ecr_pull_only_from_published_repos` | execution role 的 `ecr:BatchGetImage`、`ecr:GetDownloadUrlForLayer`、`ecr:BatchCheckLayerAvailability` 的 Resource 恰為 containerimage 發布的 repo ARN |
| `execution_logs_scoped_by_name` | `logs:CreateLogStream`、`logs:PutLogEvents` 的 Resource 是 `arn:aws:logs:<region>:<account>:log-group:/ecs/<name_prefix>-*:*` |
| `execution_reads_app_secret_only` | `secretsmanager:GetSecretValue` 的 Resource 恰為 `[app_secret_arn]`（`valueFrom` 用）；有 CMK 時 `kms:Decrypt` 只到該 key。**沒有任何指向 DB secret 的權限**（DB secret 由 task role 讀，D20） |
| `proxy_role_has_no_policy` | Proxy role 沒有任何 `aws_iam_role_policy` 與 attachment |
| `monitoring_scoped_to_rdsosmetrics` | monitoring role 的 inline policy 恰為 6 個 logs action（`CreateLogGroup`、`PutRetentionPolicy`、`CreateLogStream`、`PutLogEvents`、`DescribeLogStreams`、`GetLogEvents`），Resource 只有 `RDSOSMetrics` 的 log group 與其 `:log-stream:*` |
| `no_wildcard_action` | 每份 policy 的每個 Statement：Action 不是 `*`、不以 `:*` 結尾 |
| `wildcard_resource_allowlist` | Resource 為 `*` 的只能是 `ecr:GetAuthorizationToken`。反向驗證：暫時加一個 `s3:GetObject` on `*`，測試要紅 |
| `no_aws_managed_policy` | 沒有任何 attachment 指到 `arn:aws:iam::aws:policy/` |
| `publishes_role_arns` | 發布三個 role ARN |

#### data

| 檔案 | 用途 |
|---|---|
| `database.tf` | 呼叫 `rds`（design §4.10）：subnet 來自 `subnet_ids_data`、SG 來自 `sg_db_id`、`kms_key_arn` 與告警 topic 來自 foundation、`monitoring.role_arn` 來自 iam-base；`network/db_proxy` 為 true 時才傳 `proxy`（SG 來自 `sg_db_proxy_id`、role 來自 `role_rds_proxy_arn`）；`var.db = null` 時不呼叫 |
| `envs/dev.tfvars` | `aurora_serverless` 0.5～4 ACU（Proxy 由 network 的 dev 設定關閉） |
| `envs/prod.tfvars` | `aurora_serverless` 2～16 ACU 加 1 個 reader（Proxy 由 network 的 prod 設定開啟） |
| `envs/examples/{poc,standard,high}.tfvars` | poc：`rds`、`db.t4g.micro`、單一 AZ、備份 1 天、`deletion_protection = false`；standard：`aurora_serverless` 2～16 ACU 加 1 個 reader、備份 7 天；high：`aurora`、`db.r7g.xlarge`、2 個 reader、備份 14 天（標註「沒有實測依據」）。三種型態都有示範 |

| run | 斷言 |
|---|---|
| `database_json_shape` | 開 DB 時 `database` 的 `jsondecode` 有 `enabled = true`、`deployment`、`port`、`name`、`secret_arn`、`app_endpoint`、`app_reader_endpoint`、`writer_endpoint`、`reader_endpoint`、`proxy_endpoint`、`has_reader`（apply，沿用 Phase 5 的 `mock_resource` 寫法） |
| `disabled_database` | `var.db = null` → `rds` module 沒有被呼叫，發布 `{"enabled":false}` |
| `proxy_follows_network` | `db_proxy = {"enabled":false}` → 傳進 `rds` 的 `proxy` 是 null；`{"enabled":true}` → `proxy.role_arn` 等於 `role_rds_proxy_arn`、`proxy.security_group_ids` 等於 `[sg_db_proxy_id]` |
| `wired_from_upstream` | `subnet_ids`、`security_group_ids`、`kms_key_arn`、`monitoring.role_arn`、`sns_topic_arns` 都等於 SSM 讀到的值 |
| `connections_threshold_given_for_provisioned` | examples 的 poc（`rds`）與 high（`aurora`）都有給 `connections_threshold`（design J23 要求必填，examples 不能漏） |
| examples（`tests/examples/`） | poc：`deployment = "rds"`；standard：`aurora_serverless`、1 個 reader；high：`aurora`、2 個 reader |

`data` 沒有自己的 Proxy 開關變數；開不開由 network 決定，所以不需要另一條「不一致就停」的 precondition。

#### iam-app

| run | 斷言 |
|---|---|
| `task_role_per_service` | 每個 `containerimage/services` 的服務 1 個 task role，trust 只給 `ecs-tasks.amazonaws.com` 並帶 `aws:SourceAccount`；預設沒有任何權限 |
| `proxy_policy_resource_is_secret` | 開 DB → 對 Proxy role（名稱取自 `role_rds_proxy_arn` 最後一段）附加 inline policy，`secretsmanager:GetSecretValue` 的 Resource 恰為 `database.secret_arn`；**不管 `db_proxy` 開不開都附加**（design §5.4 的兩段式部署需要） |
| `proxy_kms_via_service` | 有 CMK 時多一條 `kms:Decrypt`，Resource 是 foundation 的 key，Condition `kms:ViaService = secretsmanager.<region>.amazonaws.com` |
| `data_access_services_read_db_secret` | `network/data_access` 名單上的服務，task role 的 `secretsmanager:GetSecretValue` Resource 恰為 `database.secret_arn`（加同樣的 `kms:Decrypt`） |
| `others_cannot_read_db_secret` | 不在名單上的服務，task role 沒有任何 `secretsmanager:` action |
| `execution_role_untouched` | 這個 stack 沒有任何 `aws_iam_role_policy` 或 attachment 掛在 execution role 上（D20） |
| `no_db_no_db_permissions` | `database = {"enabled":false}` → Proxy policy 與 task role 的 secret 權限都是 0 個 |
| `exec_permissions_and_flag` | `ecs_exec_services = ["api"]` → api 的 task role 恰有 4 個 `ssmmessages:` 具名 action，發布 `ecs_exec_api = {"enabled":true}`；worker 沒有 `ssmmessages:`，發布 `{"enabled":false}` |
| `ecs_exec_services_must_be_known` | `ecs_exec_services` 含 `containerimage/services` 以外的名稱 → precondition 失敗 |
| `no_wildcard_action` ／ `no_aws_managed_policy` | 同 iam-base |
| `wildcard_resource_allowlist` | Resource 為 `*` 的只能是 ECS Exec 的 4 個 `ssmmessages` action；反向驗證同 iam-base |
| `publishes_task_role_arns` | 發布每個服務的 `role_<service>_task_arn` |

#### loadbalancer

| 檔案 | 用途 |
|---|---|
| `alb.tf` | 呼叫 `alb`（design §4.10）：subnet 來自 `subnet_ids_public`、SG 來自 `sg_alb_id`、`access_logs_enabled = true` 時用 foundation 的 `alb_log_bucket_name`、告警 topic 來自 foundation；precondition：`jsondecode(alb_https).enabled == (var.certificate_arn != null)` |
| `envs/examples/{poc,standard,high}.tfvars` | poc：`certificate_arn = null`、不開 access log、不掛 WAF、idle 60；standard：有憑證、access log、WAF；high：同 standard、`idle_timeout = 300` |

| run | 斷言 |
|---|---|
| `wired_from_upstream` | `alb` 的 `subnet_ids`、`security_group_ids`、`sns_topic_arns` 都等於 SSM 讀到的值；開 access log 時 `access_logs.bucket` 等於 `alb_log_bucket_name` |
| `tls_must_match_network` | `alb_https = {"enabled":true}` 但 `certificate_arn = null` → precondition 失敗；`{"enabled":false}` 但給了憑證 → precondition 失敗；兩邊一致時通過 |
| `publishes_listener_keys` | 發布 `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| examples（`tests/examples/`） | poc：沒有 https listener、`listener_protocol = "HTTP"`；standard 與 high：有 https listener、有 WAF association；high 的 `idle_timeout = 300`（每組各自的 `override_data` 讓 `alb_https` 跟憑證一致） |

#### application

| run | 斷言 |
|---|---|
| `reads_only_upstream_keys` | `local.ssm_inputs` 的 key 集合等於預期清單 |
| `services_must_match_containerimage` | 服務設定的 key 多一個或少一個 `containerimage/services` 裡的服務 → precondition 失敗 |
| `roles_from_iam_stacks` | `execution_role_arn` 等於 iam-base 的 `role_ecs_execution_arn`；`task_role_arn` 等於 iam-app 的 `role_<service>_task_arn` |
| `image_from_containerimage` | `image` 由 `ecr_<service>_url` 加 tfvars 的 tag 組成 |
| `network_from_network_stack` | `network.subnet_ids` 等於 `subnet_ids_app`；`security_group_ids` 等於 `[sg_<service>_id]` |
| `listener_from_loadbalancer` | `load_balancer.listener_arn` 等於 `listener_arn`、`vpc_id` 等於 network 的值；`alb_arn_suffix` 同時給 `ecs-service` 與 `ecs-service-alarms` |
| `database_env_single_decision_point` | `data_access` 名單上的服務有 `DB_HOST`（`app_endpoint`）、`DB_READER_HOST`（`app_reader_endpoint`）、`DB_PORT`、`DB_NAME`、`DB_SECRET_ARN` 五個環境變數；**DB secret 不出現在 `secrets`（不用 `valueFrom`）**；不讀 `proxy_endpoint`、`deployment` |
| `app_secret_via_value_from` | foundation 的 `app_secret_arn` 走 `secrets`（`valueFrom`） |
| `no_db_env_when_disabled` | `database = {"enabled":false}` → 沒有任何 `DB_*` 環境變數 |
| `exec_flag_from_iam_app` | `enable_execute_command` 等於 `jsondecode(ecs_exec_<service>).enabled`；application 沒有自己的 exec 變數 |
| `alarms_wired_to_foundation_topic` | `ecs-service-alarms` 的 `sns_topic_arns` 等於 `alarm_topic_arn` |
| `no_cross_stack_id_in_variables` | `variables.tf` 沒有任何 ARN／id 型的跨 stack 輸入（grep） |

mock 注意：`data.aws_ssm_parameter` 會回隨機字串，要用 `override_data` 逐 key 給對應型別的假值（role ARN、listener ARN、SNS ARN、subnet id 清單、`database` 與各個決定點的 JSON），見風險 R1。iam 兩個 stack 的 policy 一律用 `jsonencode()`（R2）。

**驗收指令**

```bash
scripts/validate.sh templates/project-infra/infra/terraform
ls templates/project-infra/infra/terraform/                                        # 恰為 8 個 stack
ls templates/project-infra/infra/terraform/*/.terraform.lock.hcl | wc -l           # 預期 8
ls templates/project-infra/infra/terraform/{network,data,loadbalancer}/envs/examples/   # 各有 poc、standard、high
grep -rn 'aws_iam_policy_document' templates/ modules/                             # 預期沒有輸出
grep -rln 'resource "aws_iam_' templates/project-infra/infra/terraform/            # 只有 iam-base/、iam-app/
grep -rln 'resource "aws_security_group' templates/project-infra/infra/terraform/  # 只有 network/
grep -rnE '^\s*(ingress|egress|route)\s*\{' templates/                             # 預期沒有輸出
grep -rn 'path *=' templates/project-infra/infra/terraform/iam-base/               # 預期沒有輸出（role 不加 path）
grep -rn 'terraform_remote_state' templates/                                       # 預期沒有輸出
grep -rn 'source *= *"git::' templates/                                            # 預期沒有輸出（D2）
scripts/validate.sh
```

**完成定義**：8 個 stack 各自 `init -backend=false`／`validate`／`test`（含 dev、prod 與 examples 的 `-var-file` 執行）全過；8 份 `common.tf` 完全相同；16 份 tfbackend 的 key 格式正確；README 的 apply 順序與合約表跟 design §5.3、§5.6 一致；`http_only_rejects_public_cidr`、`tls_must_match_network`、`services_must_match_containerimage`、`proxy_policy_resource_is_secret`、iam 兩個 stack 的 `wildcard_resource_allowlist` 都經反向驗證確認有效。主 agent 驗證後 commit。

**不在本次範圍**：WAF Web ACL 本身；Redis；GitHub Actions 部署 workflow；跨帳號 assume role 的實測；「讀的 key 必須是更早的 stack 發布的」靜態檢查（D10）；state bucket 本身；應用程式專用 DB 帳號。

### Phase 7：使用文件與 `vendor-modules.sh`

**目標**：四個團隊各自看得懂自己要做什麼。

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `docs/guides/consuming-modules.md` | 專案怎麼引用（`git::https://github.com/<org>/<repo>.git//modules/<name>?ref=<name>-v<semver>`）、私有 repo 的 git 認證、Git source 只能 `ref` 釘死、**從範本複製出去時把相對路徑 source 改成 git source**（一個 module 一行的手改方式，加一次改完的指令）、升版、讀 CHANGELOG、升級到真 registry 時消費端改什麼 |
| `docs/guides/project-infra-standard.md` | 8 個 stack 的拆法與 apply 順序、iam 為什麼拆兩個、SG 集中在 network、SSM 合約（含 subnet tier 調整時 key 怎麼變、下游怎麼接）、流量規格對照表與 IP 規劃公式、環境切換四件事、客戶自管模式 A／B |
| `docs/guides/releasing-modules.md` | 怎麼改 module、semver 規則（0.x 期間 MINOR 可以有破壞性變更；`rds` 的型態互換、`vpc` 的 subnet 位址變動屬於 MAJOR 等級的影響）、release-please 流程、一個 commit 只動一個 module、第一次發版前手動打 8 個 `<module>-v0.1.0` tag 的步驟與指令（D24） |
| `docs/guides/delivering-to-customer.md` | FDE：`vendor-modules.sh`、`terraform providers mirror`、客戶自管資源的 SSM 合約（模式 A 只交 VPC id，模式 B 交全部 network key）、客戶環境差異怎麼回報 |
| `docs/guides/team-roles.md` | 四個團隊的責任與交接點，對到 CODEOWNERS |
| `scripts/vendor-modules.sh` | 只做 `git::...?ref=<tag>` → vendored 相對路徑。`git archive <tag> modules/<name>` 解到目標的 `vendor/modules/<name>/`，只改寫完全符合的 source 行，寫 `vendor/modules/VERSIONS`（名稱、tag、commit SHA） |
| `README.md`（修改） | 把 Phase 0 標「Phase 7 補」的連結補上 |

**驗證任務**（全部在 scratchpad 做）

| 情境 | 預期 |
|---|---|
| 暫存 git repo 打 `ssm-publish-v0.1.0`（本機 tag，不 push），對一個 source 是 git 格式的暫存目標 repo 跑腳本 | 目標出現 `vendor/modules/ssm-publish/`，source 改寫成相對路徑，`VERSIONS` 有該行；`scripts/validate.sh <暫存目標路徑>` 過 |
| tag 不存在 | 回非 0，指出哪個 tag |
| tag 格式不是 `<module>-v<semver>` 或前綴跟 module 不一致 | 回非 0 |
| module 名稱不符 `^[a-z][a-z0-9-]*$`（例如 `../etc`） | 回非 0 |
| 目標不是 git repo 或有未提交變更 | 拒絕執行 |
| tag 內容含 symlink | 拒絕執行 |
| 目標 `.tf` 有一行 source 指向同 module 但 ref 不同 | 那一行不改寫，回報出來 |
| 照 `consuming-modules.md` 的指令把範本複製到暫存目錄後改 source | 8 個 stack 裡每個 module 的 source 都變成 git 格式且 ref 正確（只檢查文字，不 init） |
| 文件內的 repo 內路徑 | 每個都 `test -e` 得到 |

**驗收指令**

```bash
shellcheck -S warning scripts/vendor-modules.sh
grep -nE '\beval\b' scripts/vendor-modules.sh      # 預期沒有輸出
grep -rhoE '`(modules|templates|scripts|docs)/[^` ]+`' docs/guides README.md | tr -d '`' | sort -u | while read -r p; do test -e "$p" || echo "missing: $p"; done
grep -rnE '[a-z-]+/v[0-9]' docs/guides README.md   # 預期沒有斜線格式的 tag
git tag                                            # 預期沒有輸出
```

**完成定義**：五份文件結論放最前面、指令可照抄；暫存演練輸出貼在回報裡。主 agent 驗證後 commit。

**不在本次範圍**：core app team 的 repo；HCP Terraform 的實際設定；把範本相對路徑改成 git source 的腳本（手動步驟寫進文件）；投影片。

### Phase 8：整體驗收

由主 agent 自己做，不派 subagent。

| 檢查 | 指令或做法 | 預期 |
|---|---|---|
| 乾淨狀態全綠 | 刪掉 `.cache/` 後跑 `scripts/validate.sh` | 全綠（含 dev、prod、examples 的 `-var-file` 執行） |
| 沒留下產物 | `git status --short --ignored` | 只有 `.cache/` 與 `docs/slides/` 是 ignored |
| 沒有禁止的指令 | `grep -rnE 'terraform (plan\|apply)\|aws ' scripts/ .github/` | 只出現在註解或禁止說明 |
| CI 不給憑證 | 同 Phase 0 的 grep | 沒有輸出 |
| module 不建 IAM 與服務 SG | `grep -rnE 'resource "aws_(iam_\|security_group)' modules/` | 只有 `modules/vpc` 的 endpoint SG |
| 沒有 password | S7 的兩條 grep | 沒有輸出 |
| tag 格式一致 | release-please 設定（8 個 package）、guides、ADR 0001、各 module README、`vendor-modules.sh` | 都是 `<module>-v<semver>`，起始 `0.1.0` |
| stack 清單一致 | 範本目錄、範本 README、`project-infra-standard.md`、ADR 0002、design §5.3 | 都是 8 個、順序一致 |
| SSM key 一致 | 範本各 stack 的 `ssm-outputs.tf` 與 `ssm-inputs.tf`、範本 README 的合約表、design §5.6 的合約表 | key 名稱、型別、JSON 欄位一致 |
| 單一決定點 | `services`、`alb_https`、`db_proxy`、`data_access`、`ecs_exec_<service>` | 每一個只有一個 stack 發布，下游沒有同名的變數 |
| 介面與 design 一致 | 8 個 module 的 `variables.tf` 變數名、預設值、輸出名稱對照 design §4.2–§4.9 | 不一致要揭露，不自行改 design |
| README 表與變數一致 | 每個 module 比對 `variables.tf` 與 README inputs 表 | 沒有缺漏 |
| 測試數量 | 彙整每個 module／stack 的 `n passed` | 與各 Phase 回報一致，不一致要揭露 |
| commit 歷史 | `git log --format='%ae %s'`、`git remote -v` | 11 個 commit，每個 module 的 commit 只動該 module 目錄，author 都是 `<author-email>`；沒有 remote |
| 簡單優先 | 掃 `enable_` 開頭的變數 | 只有 design 列的 `enable_execute_command` |

## 驗證指令的具體寫法

### `scripts/validate.sh`

```bash
#!/usr/bin/env bash
# 離線驗證：fmt、init -backend=false、validate、test（mock）、tflint 與靜態規則。不碰 AWS。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${repo_root}/.cache"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${cache_root}/plugins}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"

# 第二道防線：測試漏寫 mock_provider 時要失敗，而不是拿到本機的 aws-vault session。
for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
```

腳本只會呼叫 `terraform fmt`、`init -backend=false`、`validate`、`test` 四種子指令，不得出現 `plan`、`apply`、不帶 `-backend=false` 的 `init`，也不呼叫 `aws`。

| 步驟 | 做法 | 理由 |
|---|---|---|
| 0. 離線環境 | 見上面的程式碼 | 第二道防線 |
| 1. 找目錄 | 沒給參數時：`modules/*`、`modules/*/examples/*`、`templates/project-infra/infra/terraform/*` 中有 `.tf` 的目錄；給參數時只跑那些路徑底下的（可以是 repo 外的路徑，Phase 7 在 scratchpad 的演練也走這支） | **不能從 repo 根目錄掃**：`docs/slides/` 有範例的 `.tf`，本機存在、CI 不存在 |
| 2. fmt | `terraform fmt -check -recursive modules templates` | 同上 |
| 3. 靜態規則 | 下表 S1–S7，任一條失敗就整支失敗，不進到第 4 步之後 | 便宜、能擋最常見的退化 |
| 4. init | 每個目錄 `TF_DATA_DIR="${cache_root}/tf-data/<目錄路徑把 / 換成 __>" terraform -chdir=<dir> init -backend=false -input=false`；範本 stack 加 `-lockfile=readonly` | 不在 module 目錄留 `.terraform/`（project-a CI 用相對的 `.terraform-ci`，會留在 `project-a/infra-v2/terraform/modules/ssm-publish/.terraform-ci`）；範本的 lock 檔被改動就失敗 |
| 5. validate | `terraform -chdir=<dir> validate` | — |
| 6. test | 目錄有 `tests/` 才跑 `terraform -chdir=<dir> test` | 同 project-a CI |
| 6a. tfvars test（只有範本 stack） | 對 `envs/dev.tfvars`、`envs/prod.tfvars` 各跑一次 `terraform -chdir=<dir> test -test-directory=tests/tfvars -var-file=envs/<env>.tfvars`；有 `envs/examples/` 的 stack，對每個 `envs/examples/<x>.tfvars` 跑 `test -test-directory=tests/examples -var-file=envs/examples/<x>.tfvars` | 測的是檔案本身，不在測試裡複製一份值（R12）。`tests/tfvars/`、`tests/examples/` 是子目錄，第 6 步預設的 `tests/` 不會掃到（未驗證，Phase 6 先實測；若會掃到，改放在 `tests-tfvars/`、`tests-examples/`） |
| 7. tflint | `tflint --chdir=<dir> --config="${repo_root}/.tflint.hcl"` | config 用絕對路徑；只用內建 ruleset，不需要 `tflint --init` |
| 8. 清掉 module 的 lock 檔 | init 若在 `modules/*`（含 examples）產生 `.terraform.lock.hcl`，跑完就刪 | lock 檔寫在工作目錄，不受 `TF_DATA_DIR` 控制；module 不提交 lock（D5） |
| 9. 彙整 | 一個目錄失敗不中斷，最後列出全部失敗目錄，有失敗就 `exit 1` | 同 project-a CI |

**第 3 步的靜態規則**

| # | 規則 | 為什麼 |
|---|---|---|
| S1 | 每個 `*.tftest.hcl`（含 `tests/tfvars/`、`tests/examples/`）都必須宣告 `mock_provider "aws"` | 第一道防線 |
| S2 | `resource "aws_ssm_parameter"` 只能出現在 `modules/ssm-publish/` | SSM 合約：只能透過 `ssm-publish` 寫入 |
| S3 | 範本的 `ssm-inputs.tf` 不得讀 `.value`（只能讀 `insecure_value`） | SSM 合約 |
| S4 | `modules/` 底下不得宣告 `resource "aws_iam_*"`；`resource "aws_security_group*"` 只允許出現在 `modules/vpc/`（endpoint SG）。這條取代各 module 的 `no_iam_resources` run | module 不建 IAM 與服務 SG；`terraform test` 無法列舉資源型別 |
| S5 | 範本 8 個 stack 的 `common.tf` 雜湊必須相同 | 修掉 project-a「common.tf 多版本漂移」 |
| S6 | 每份 `envs/<env>.tfbackend` 的 `key` 必須等於 `<project>-<env>/<stack>/terraform.tfstate`（`<stack>` 取目錄名、`<env>` 取檔名）；`envs/examples/` 不得有 tfbackend | 修掉 project-a「key 寫錯讀到別的環境」；examples 不是可部署的環境 |
| S7 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數（不分大小寫）；`modules/` 底下不得出現 `random_password` | 密碼一律由 RDS 管理（`manage_master_user_password`），值不進 tfvars、不進 state |

SSM 合約第一版只檢查 S2、S3；「讀的 key 必須是更早的 stack 發布的」不做（D10）。

`.cache/` 已在 `.gitignore`。provider 用 plugin cache 共用，40 多個目錄不會各下載一份 aws provider。範本 stack 用相對路徑引用 module（D2），`init -backend=false` 不需要 repo 在 GitHub 上、也不需要 tag 存在。

### `.github/workflows/ci.yml`

- 觸發：`pull_request`、push 到 `main`。
- `permissions: contents: read`，**不設** `id-token: write`，不用 `aws-actions/configure-aws-credentials`，不讀任何 `secrets.*`。
- 步驟：checkout → `hashicorp/setup-terraform`（`1.15.8`、`terraform_wrapper: false`）→ 安裝 tflint 0.64.0 → `actions/cache` 快取 `.cache/plugins` → `scripts/validate.sh`。

## subagent 分工方式

### 原則

- 每個 Phase 派一個執行 subagent（`tdd-guide`），背景執行；Phase 2–5 平行時一個 module 一個 subagent。執行 subagent 只能透過 `scripts/validate.sh` 跑 terraform，不 commit。
- 主 agent 等它回報後，自己重跑該 Phase 的驗收指令與全量 `scripts/validate.sh`，看 diff 範圍有沒有越界；結果跟 subagent 回報不一致就如實告訴使用者。全綠才由主 agent commit，一個 module 一個 commit。
- 每個 Phase 結束停下來，讓使用者決定要不要進下一個。
- Phase 8 由主 agent 自己做。

### 派工 prompt 要帶的資訊

```
你是 infra-platform 的 Phase <N> 執行者。
專案：infra-platform（Terraform module monorepo，AWS provider ~> 6.0，terraform 1.15.8），分支 main。

前一 Phase 基準線：commit <hash>；scripts/validate.sh 全綠，各目錄測試數：<目錄: n passed 清單>。

背景文件：docs/design/v1/design-docs.md（介面以它為準，本 Phase 對應 §<x.y>）、
  docs/design/v1/implement-process.md 的 Phase <N> 節與「已拍板決策」。
已拍板決策：<D1–D23 與本 Phase 相關的條目，原文>。
Phase 1 定案的寫法：<computed 值的處理方式、override_data／mock_resource 範本>。

硬性限制（逐條，原文）：<全局規則的 9 條，含允許／禁止的 terraform 指令表>。
  terraform 只能透過 scripts/validate.sh 跑，不得直接手打 terraform 指令（Phase 0 例外：照「離線環境」設定手動跑）。
  你不 commit，commit 由主 agent 驗證後做。

本 Phase 要做：<檔案清單>；TDD：<run block 表>；每個 validation 正反兩向；
  回報要附 RED 輸出、反向驗證的失敗輸出、n passed。

不在本次範圍：<該 Phase 的清單>。只能動 <允許的目錄>；發現需要動範圍外的檔案，或 design-docs 的介面寫不下去，停下來回報，不要順手做、不要自己改 design。

回報格式：完成的檔案、每個測試檔的 n passed、validate.sh 全量結果、跟計畫的差異、未決問題。
```

## 風險與緩解

| # | 風險 | 症狀 | 緩解 |
|---|---|---|---|
| R1 | mock provider 對 data source 回隨機字串，不符合 ARN 格式 | 被 validation 驗格式的欄位在 plan 失敗，看起來像 module 寫錯。範本每個讀 SSM 的 stack 都會撞到，JSON key（`database`、`alb_https`、`db_proxy`、`data_access`、`ecs_exec_*`）更會在 `jsondecode` 直接失敗 | `override_data` 逐 key 給對應型別的假值。project-a 的做法：`project-a/infra-v2/terraform/application/tests/forwarded_allow_ips.tftest.hcl`、`operation/tests/bastion_guard.tftest.hcl`、`agent/tests/guardrail_profiles.tftest.hcl`。network 模式 A 的 `data "aws_vpc"`／`data "aws_subnet"` 同樣要 override |
| R2 | `aws_iam_policy_document` 在 mock 下的 `json` 是隨機字串 | 斷言不到 policy 內容，iam 兩個 stack 的「不得出現 `*`」測不到 | policy 一律 `jsonencode()`（design §5.4）；Phase 6 驗收 grep 確認沒有 `aws_iam_policy_document`（project-a 的 `mock_data` 寫法見 `project-a/infra-v2/terraform/iam/tests/judge_batch_guard.tftest.hcl`，只能讓 plan 過） |
| R3 | `command = plan` 時 computed 屬性是 unknown | 斷言 `arn`、`id`、端點會報「無法判斷」。`ecs-service` 從 `cluster_arn` 拆名稱，範本傳的是 computed 的 `module.cluster.cluster_arn` | 斷言 computed 值的 run 用 `command = apply`（mock 下允許，D6）並搭配 `mock_resource` 給預設值；或 `override_module`／`override_resource`。Phase 1 實測 `override_during = plan`（需要 terraform 1.11+，未驗證）是否可用 |
| R4 | `rds` 的 `master_user_secret` 是 nested list，mock 預設給空 list | 取 `[0].secret_arn` 直接失敗，所有輸出相關的 run 都紅 | 照 Phase 5 的 `mock_resource` 寫法給 `aws_db_instance` 與 `aws_rds_cluster` 預設值；範本 data stack 的測試沿用同一段 |
| R5 | `lifecycle`、`allowed_account_ids`、IAM 實際權限、型態互換、0 ACU 在 `terraform test` 裡測不到 | 測試全綠但保護不存在 | `lifecycle` 用 grep 驗收；其餘列在 design §7.3 |
| R6 | RDS Proxy 建立時 role 還沒有讀 secret 的權限（權限要等 iam-app apply） | 未驗證：可能建立失敗，也可能建立成功但連不上 | 照 design §5.4 的表：建立成功就照正常順序；建立失敗就兩段式（network 先設 `proxy = false` 跑到 iam-app，再改 `true` 依序 apply network、data）。iam-app 不管 Proxy 開不開都附加 policy，所以第二輪不用再跑 iam-app。dev 預設不開 Proxy、prod 開（D19） |
| R7 | `init -backend=false` 需要網路 | 離線或限流時整批失敗 | plugin cache 共用；CI 快取 `.cache/plugins` |
| R8 | release-please 本機沒有、也不能 push 驗證 | 設定寫錯要等上 GitHub 才知道 | 只驗 JSON 語法與欄位；`releasing-modules.md` 標「未實測」 |
| R9 | terraform-docs 不在本機 | README 表與變數漂移 | 手寫，Phase 8 人工比對 |
| R10 | 範本複製出去忘了把相對路徑改成 git source | 專案 repo 的 source 指不到東西，或把整個 `modules/` 也複製過去、跟 registry 脫鉤 | 範本 README 第一步就寫改 source；`consuming-modules.md` 寫一次改完的指令 |
| R11 | 範本 lock 檔在 macOS 產生、CI 在 Linux 驗 | `-lockfile=readonly` 下因缺少平台雜湊而失敗 | lock 檔記錄全平台 `zh:` 雜湊，理論上可過（未驗證）；不行的話補雜湊要用 `terraform providers lock`，不在允許清單，要先問使用者 |
| R12 | tfvars（dev、prod、examples）的內容跟測試脫鉤 | 在測試裡複製一份值的話，tfvars 改了測試不會知道 | 不複製：`validate.sh` 第 6a 步對每份 tfvars 跑 `terraform test -var-file=...`，測試檔只放共通值與 `override_data`。`-test-directory` 子目錄的掃描行為未驗證，Phase 6 先實測 |
| R13 | 大流量規格與 `rds` 型態沒有實測依據 | 範例被當成驗證過的建議值 | examples tfvars 與流量規格表都標註（design §5.11） |
| R14 | `docs/slides/` 裡的範例 `.tf` 被 fmt／tflint 掃到 | 本機與 CI 結果不同 | `validate.sh` 只掃 `modules`、`templates` |
| R15 | 單一決定點的值沒有 override 就讀不到 | 範本測試裡 `network/db_proxy` 這類 JSON 沒有 override，`jsondecode` 失敗，所有 run 都紅 | 每個範本測試檔開頭把會讀的決定點 key 都寫一個 `override_data`，個別 run 再覆寫成要測的值 |

## 已判斷與已拍板

### 我已判斷（附理由，使用者不同意再改）

| # | 判斷 | 理由 |
|---|---|---|
| J1 | Phase 0 一次在 release-please 設定登記全部 8 個 module | 後面的 Phase 不必再改共用檔，Phase 2–5 才能平行 |
| J2 | `validate.sh` 只掃 `modules`、`templates` | `docs/slides/` 有不進 git 的 `.tf` |
| J3 | `validate.sh` 清掉全部 `AWS_*` 變數，設 `AWS_CONFIG_FILE`、`AWS_SHARED_CREDENTIALS_FILE` 為 `/dev/null`、`AWS_EC2_METADATA_DISABLED=true`（使用者也要求） | 漏寫 mock 的測試要失敗，不能拿本機 session 打 AWS |
| J4 | 反向驗證只在工作目錄暫時做，不留痕跡 | 證明測試有效，又不污染 diff |
| J5 | Phase 順序 vpc → ecs → alb＋alarms → rds | vpc 的 subnet key 與輸出形狀決定 network 的合約，越早定越好；rds 最複雜，獨立在最後，出問題不拖累其他 module |
| J6 | 輸出相關的 run 用 `command = apply` 搭配 `mock_resource` | `rds`、`vpc` 的輸出幾乎都是 computed；Phase 1 若證實 `override_during = plan` 可用就改回 plan |
| J7 | `vpc` 多加 `remove_az_keeps_remaining_keys`、`third_az_overlap_fails` 兩個 run | 前者是「增減 AZ」的另一半；後者直接重現 project-a 第三個 AZ 靜默重疊的坑（design §7.1 的 expect_failures 也列了這個案例） |
| J8 | dev／prod tfvars 也用 `-var-file` 跑測試，不在測試裡複製值 | 跟 examples 同一個做法（R12），鎖住「tfvars 不完整就規劃刪除」的坑 |
| J9 | `tests/tfvars/`、`tests/examples/` 放在子目錄 | 讓第 6 步的一般測試不會在沒有 `-var-file` 的情況下跑到它們（未驗證，見 R12） |

其他原本在這裡的判斷（ELB 5xx 放 `alb`、policy 用 `jsonencode()`、ECS Exec 開關走 SSM、ECR 預設值、`alb` 的 additional certificate 規則）已經寫進 design（J4、§5.4、決策 15、16、§4.8），不再列。

### 已拍板決策

| # | 決策 | 理由 |
|---|---|---|
| D1 | module 不建 IAM，沒有例外。role 在範本的 iam-base 與 iam-app 建，module 只收 ARN | 權限集中審查；客戶自管 IAM 時接得上（prod b2c 的 deploy role 不能改 IAM） |
| D2 | 範本在本 repo 內用相對路徑引用 module；專案複製出去時改成 `git::...?ref=<module>-v<semver>`，改法寫在 `consuming-modules.md`；`vendor-modules.sh` 只負責 `git::` → vendored 相對路徑 | repo 還不在 GitHub、tag 不存在時，範本也要能 `init -backend=false` |
| D3 | 範本 8 個 stack：foundation → containerimage → network → iam-base → data → iam-app → loadbalancer → application | Proxy 與 Enhanced Monitoring 的 role 要在 data 之前存在；讀 DB secret 的權限要等 data 產生 secret ARN 才寫得出 Resource |
| D4 | 一個 module 一個 commit，非 module 的 Phase 各一個，共 11 個；主 agent 自己重跑驗證通過後才 commit；直接在 `main`，不 push，author `<author-email>`，Conventional Commits | 使用者決定；release-please 依路徑歸屬，CHANGELOG 才不會互相污染 |
| D5 | lock 檔：module 不提交、範本 stack 提交。tflint 只用內建 terraform ruleset。起始版本 `0.1.0` | Terraform 只採用 root module 的 lock 檔；內建 ruleset 不需要下載 plugin；0.x 表示還沒在真實 AWS apply 過 |
| D6 | 有 `mock_provider "aws"` 的測試檔才允許 `command = apply` | mock 下不碰 AWS；S1 保證每個測試檔都有 mock |
| D7 | 跑完 Phase 1 再決定 Phase 2–5 要不要平行 | 看定型的品質與花的時間再決定 |
| D8 | GitHub org／repo、CODEOWNERS 的 team slug、state bucket 維持佔位符 | 尚未決定 |
| D9 | network 預設建立 VPC；客戶管 VPC 時改登記既有 VPC（模式 A），network 整個由客戶管時客戶發布全部 key（模式 B）；SG 一律在 network stack | 使用者推翻「network 不建 VPC」 |
| D10 | SSM 合約第一版只做 S2、S3 兩條靜態檢查；「讀的 key 必須是更早的 stack 發布的」不做 | 各 stack 的測試已鎖住讀取清單 |
| D11 | 不提供 `stacks.sh`；資料層 stack 叫 `data`；環境檔是 `envs/dev.*`、`envs/prod.*` | 使用者決定 |
| D12 | 服務告警放在 `application` stack，跟 service 同一份 state | 直接吃 module 輸出，不會重演 project-a postdeploy 寫死 id |
| D13 | 第一版 8 個 module：新增 `vpc`、`rds`、`alb` | 做出最小三層架構 |
| D14 | `rds` 用 `deployment` 選型態，RDS Proxy 是 module 內的選項 | 使用者要求 |
| D15 | flow log 送 S3，bucket 建在 foundation，不需要 IAM role；範本只在正式環境開 | 使用者決定 |
| D16 | `vpc` 的 NAT 支援 `none`、`single`、`per_az`；範例正式環境 `per_az`、PoC `single` | 使用者決定 |
| D17 | ALB 沒有憑證時只開 80，network 用 validation 擋住 ALB SG 對 `0.0.0.0/0` 開 80；有憑證時 443 用 `ELBSecurityPolicy-TLS13-1-2-2021-06`、80 一律 301 | 使用者決定 |
| D18 | `validate.sh` 加 S7：`modules/rds/variables.tf` 不得有含 password 的變數、`modules/` 不得出現 `random_password` | 使用者決定 |
| D19 | 單一決定點（design J21）：`containerimage/services`、`network/alb_https`、`network/db_proxy`、`network/data_access`，加上原有的 `iam-app/ecs_exec_<service>`；下游讀取，用 precondition 檢查自己的設定跟上游一致。Proxy 預設 dev 不開、prod 開（設在 network 的 `data_stores`） | 主 agent 決定 |
| D20 | DB secret 只由 task role 讀（design J22）：應用程式拿 `DB_SECRET_ARN` 自己讀，不用 `valueFrom`；execution role 沒有 DB secret 權限，iam-app 不對 execution role 附加任何 policy | 主 agent 決定 |
| D21 | iam-app 從 Proxy role ARN 的最後一段取名稱；iam-base 建 role 不加 path | 主 agent 決定 |
| D22 | `no_iam_resources` 不寫成 run，由 S4 負責；`proxy.role_arn` 宣告成 `optional(string)`，用 validation 擋 null | 主 agent 決定；`terraform test` 無法列舉資源型別，型別錯誤 `expect_failures` 抓不到 |
| D23 | tfvars（dev、prod、examples）不在測試裡複製值，由 `validate.sh` 對範本 stack 另跑 `terraform test -var-file=...` | 主 agent 決定 |
| D24 | 第一個版本 tag `<module>-v0.1.0` 由人手動打（8 個），manifest 維持 `0.1.0`；之後交給 release-please | 使用者決定；release-please 會把 manifest 的版本當成已發布 |

衝突時以 design-docs.md 為準。

### 跟 design-docs 不一致的點

無。上一輪列的三點（`proxy.role_arn` 改成 `optional(string)`、`no_iam_resources` 改由 S4 負責、examples 用 `-var-file` 跑）都已經在 design-docs 對齊。

### 待補資訊

| 項目 | 現在的寫法 | 誰補 |
|---|---|---|
| GitHub org 與 repo 名稱 | `<org>`、`<repo>` | 使用者 |
| CODEOWNERS 的 team slug | `@<org>/platform-team`、`@<org>/core-app-team`、`@<org>/project-app-reps`、`@<org>/fde-team` | 使用者 |
| state bucket 命名與由誰建立 | `<state-bucket>` | 使用者 |
| 範本 `common.tf` 的帳號對照表 | `dev = ["111111111111"]`、`prod = ["222222222222"]` | 專案複製範本時改 |
| CI 的 release-please-action、tflint setup action 的 commit SHA | Phase 0 用 `gh api` 查，查不到標「未釘版，待補」 | Phase 0 執行者 |
