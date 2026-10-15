# infra-platform 第一版實作流程

> 狀態：Phase 0–10 全部完成（Phase 10 的驗收結果見下方 Phase 表）。2026-10-15 改寫過 git 歷史，拿掉參考專案的名稱與作者資訊，文中的 commit hash 都已換成改寫後的值；19 個 `<module>-v0.1.0` tag 已打在 `28a8647`。本 repo 是範例，不部署到 AWS（2026-10-15 決定）。模組介面、stack 清單、SSM 合約、靜態規則以 [`design-docs.md`](./design-docs.md) 為準；這份只講「怎麼一步一步做出來、每步怎麼驗收」。兩份衝突時，以 design-docs.md 為準，回頭改這份。
>
> 增補（2026-10-15）：LLM 與 AgentCore 的 7 個 module、範本的 `agent` stack、`rds` 的 Data API 與兩個新輸出、`s3-bucket` 的不過期選項排成 Phase 11–16，見〈增補：Phase 11–16〉。Phase 11–14 已完成，15–16 未開始。
>
> 文中路徑除非特別註明，都相對於 `<workspace>/`；本 repo 內的路徑直接寫 repo 內相對路徑。「design §x.y」指 design-docs.md 的章節。

## 結論

第一版是 19 個 module 加 1 份 8 個 stack 的範本，做出最小三層架構：ALB 在 public subnet，AP 層與 DB 層在 private subnet。範本的 stack 只呼叫 module，唯一的原生 resource 是 `foundation` 的 secret 容器；IAM 只由 `iam-role`、`iam-role-policy` 建，SG 只由 `security-group`、`vpc-interface-endpoints` 建，`vpc` 只建 `aws_default_security_group`（design §1、§4.1、§5.6 S4）。

分 11 個 Phase（0 到 10），Phase 7 分成 A–D（7 個基礎 module）、E（觀測性）、F（拆出 `vpc-interface-endpoints`）。一次做一個，主 agent 自己重跑驗證通過後 commit，才進下一個。**一個 module 一個 commit**。全部完成，共 47 個 commit（含 Phase 10 的修正）。全量 `scripts/validate.sh`：52 個目錄通過（19 個 module、它們的 example、8 個 stack，約 9 分鐘）。

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| 0 | repo 骨架、`validate.sh`、CI、release 設定、ADR 0001–0003 | 已完成 | 1：`9ec62a5` |
| — | 記錄第一個 tag 手動打的決策 | 已完成（計畫外） | 1：`541ae3c` |
| — | `validate.sh` 沒有 lock 檔時也用 plugin cache | 已完成（計畫外） | 1：`19608d4` |
| 1 | `ssm-publish`、`sns-alarm-topic` | 已完成 | 2：`46d5a4d`、`5a0dcf3` |
| 2 | `vpc` | 已完成 | 1：`09c5342` |
| 3 | `ecs-cluster`、`ecs-service` | 已完成 | 2：`07552ef`、`4ebf5d9` |
| 4 | `alb`、`ecs-service-alarms` | 已完成 | 2：`04b33ef`、`74ea776` |
| 5 | `rds` | 已完成 | 1：`c916c46` |
| — | 7 個 module 的註解改成只用英文 | 已完成（計畫外） | 7：`0fe260b`、`ed58268`、`8630750`、`56e3bdf`、`4c61c92`、`a5a3c46`、`1bef047` |
| — | 設計文件擴充到 15 個 module、重排 Phase 6–10 | 已完成 | 1：`6e7fdaa` |
| 6 | 共用設定更新：release-please 加 7 個 module、`validate.sh` 的 S3／S4／S8、README 的 module 清單 | 已完成 | 1：`eec61df` |
| 7A–D | 7 個新 module：`iam-role`、`iam-role-policy`、`kms-key`、`s3-bucket`、`ecr-repository`、`ssm-read`、`security-group` | 已完成 | 7：`5de879a`、`5871875`、`9994403`、`d9f8e65`、`86560dc`、`9b56443`、`5675092` |
| 7E | 觀測性：共用設定、設計文件、`log-group`、`log-metric-alarm`、`xray`、`ecs-service` 的 `sidecars` | 已完成 | 6：`977cba7`、`21d6513`、`a6dd7ac`、`0cdd874`、`90adc72`、`0bde63f` |
| 7F | 拆出 `vpc-interface-endpoints`：設計文件、`refactor(vpc)`、新 module、共用設定（release-please 19 個、S4） | 已完成 | 4：`606ba1d`、`92b6200`、`7ebd512`、`d770756` |
| — | 兩個 IAM module 加上「Allow 不准搭配 `NotResource`」 | 已完成（計畫外） | 2：`5ab5d87`、`fce75f2` |
| — | 記錄 Phase 7 完成、更新 Phase 8 計畫 | 已完成（計畫外） | 1：`da2820e` |
| 8 | 專案範本（8 個 stack，全部改呼叫 module；network 加 `vpc-interface-endpoints`；application 加 `log-metric-alarm`、`xray`） | 已完成：8 個 stack 共 317 個測試，全量 52 個目錄全過（約 9 分鐘） | 1：`e71db48` |
| 9 | `docs/guides/` 六份、`scripts/vendor-modules.sh`、README 連結、Phase 8 差異寫回設計文件 | 已完成 | 1：`a89e478` |
| 9 補充 | outputs 註解與 D21 分級、`validate.sh` 支援客戶 repo、mirror repository、X-Ray 追蹤接進範本 | 已完成（計畫外，使用者決定） | 4：`6fcd3e2`、`79a6520`、`ff68ca4`、`feat(template): wire x-ray tracing into the template` |
| 10 | 整體驗收 | 已完成：刪掉 `.cache/` 後全量 52 個目錄全過（583 秒，provider 重新下載），測試 1,037 個（module 671、範本 366）；修正 ADR 0001 對 tag 檢查的錯誤說明 | 1：`docs: record phase 10 acceptance` |
| 11 | 增補：LLM 與 AgentCore 的設計文件（design 決策 37–53） | 已完成 | 2：`66d41d0`、`da991f7` |
| 12 | 增補：共用設定（release-please 26 個、S9、README、ADR 0001）、`rds-v0.2.0`（Data API 與兩個新輸出）、`s3-bucket-v0.2.0`（`never_expire`） | 已完成 | 3：`fdcaf99`、`8ca62c5`、`7324c41` |
| 13 | 增補：7 個新 module | 已完成：7 個 module 共 262 個測試，主 agent 逐一重跑 `validate.sh` 通過；差異記在 design §9.4 D30–D36 | 7：`0c79364`、`ea0a365`、`71e7550`、`8708820`、`1948aba`、`4048dbf`、`36d6ee5` |
| 14 | 增補：範本接線（新增 `agent`，改 6 個 stack） | 已完成：9 個 stack 共 462 個 run（Phase 14 之前 310），主 agent 對 9 個 stack 重跑 `validate.sh` 全綠、9 份 `common.tf` 一致；含安全審查後的修正；差異記在 design §9.4 D37–D46 | （commit 見 git log） |
| 15 | 增補：`docs/guides/llm-agentcore.md` 與相關文件 | 未開始 | 1 |
| 16 | 增補：整體驗收、manifest 登記 `rds` 與 `s3-bucket` 0.2.0、人手動打 9 個 tag | 未開始 | 0–1 |

整體驗收標準：`scripts/validate.sh` 在本機與 CI 都不需要任何 AWS 憑證就能全綠；全程沒有執行 `terraform plan`／`apply`、帶 backend 的 `init`、任何 `aws` 指令；commit 都在本機 `main`，沒有 push。

## 全局規則

### 硬性限制（每個 Phase 的派工 prompt 都要原文帶上）

1. 任何 terraform 指令都不准碰到 AWS。允許與禁止的指令如下，表外的 terraform 子指令（例如 `providers lock`、`providers mirror`、`import`、`state`、`console`）一律禁止，要用先問使用者。

   | 可以跑 | 條件 |
   |---|---|
   | `terraform fmt` | — |
   | `terraform init -backend=false` | 只從 registry 下載 provider，不碰帳號與 state |
   | `terraform validate` | — |
   | `terraform test` | 測試檔裡每個 provider 都是 `mock_provider` |

   | 不准跑 |
   |---|
   | `terraform plan`、`terraform apply`、帶 backend 的 `terraform init`（沒有 `-backend=false` 的 init 都算） |
   | `terraform providers lock` |
   | 任何 `aws` 指令 |

2. `terraform test` 一律用 `mock_provider "aws"`，不得需要 AWS 憑證。`run` block 預設 `command = plan`；`command = apply` 只准用在有 `mock_provider "aws"` 的測試檔（design 決策 13）。
3. 不准 `git push`，不准建立 GitHub remote 或 repo。執行 subagent 不 commit；commit 由主 agent 在自己重跑驗證通過後做。
4. commit message 用 Conventional Commits，author email 必須是 `<author-email>`。
5. 文件一律台灣繁體中文。
6. **`modules/` 底下的 `.tf` 與 `.tftest.hcl`，所有註解、`description`、`error_message` 一律只用英文，不可中英混雜，禁止任何 icon／emoji；註解只寫程式碼看不出來的原因。** `README.md`、`CHANGELOG.md` 不受限制（design §4.1、決策 26）。範本 stack 的註解比照辦理。
7. 簡單優先：不為未來需求加抽象層；module 平坦組合、依賴從外部傳入，不用 `enable_xxx` 開關。
8. 本機沒有 terraform-docs、pre-commit、release-please：可以提供設定檔，驗收不能依賴它們。README 的 inputs／outputs 表手寫。
9. 執行型 subagent 只能透過 `scripts/validate.sh` 跑 terraform，不得直接手打 terraform 指令。**唯一例外**是 Phase 8 產生範本 stack 的 `.terraform.lock.hcl`，指令與環境變數照 Phase 8〈lock 檔的產生方式〉原文執行，不得變更。
   增補：Phase 14 新增的 `agent` stack 也照同一段原文產生 lock 檔（design J65），其他 stack 的 lock 檔不重新產生。
10. repo 目錄、module 清單、stack 清單、tag 格式（`<module>-v<semver>`）、變數與輸出名稱照 design-docs.md，不得自行改名。

### 離線環境（第二道防線）

就算有測試漏寫 `mock_provider`，也要連不到 AWS。`scripts/validate.sh` 一開頭就做這件事：

```bash
# 清掉所有 AWS_* 變數（含 AWS_PROFILE、AWS_VAULT、AWS_SESSION_TOKEN、AWS_ACCESS_KEY_ID、AWS_SECRET_ACCESS_KEY）
for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
```

第一道防線是每個測試檔都宣告 `mock_provider "aws"`，由靜態規則 S1 強制。

### provider 下載與快取（Phase 0–5 的實測經驗）

| 規則 | 理由 |
|---|---|
| `validate.sh` 設 `TF_PLUGIN_CACHE_DIR=.cache/plugins` 與 `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true`（`19608d4`） | module 不提交 lock 檔。沒有 lock 檔時，terraform 預設不用快取，每個目錄都重新下載 aws provider，約 6 分鐘一個目錄 |
| **不准用 `TF_CLI_CONFIG_FILE` 指到本機的 provider mirror** | Phase 1 試過：會在 `.cache/plugins` 留下 symlink，之後正常跑 `init` 會失敗，只能刪掉整個 `.cache/` 重來 |
| 範本 stack 的 lock 檔不能在上面這組快取設定下產生 | 開了 `MAY_BREAK_DEPENDENCY_LOCK_FILE` 時，lock 檔只會記到本機平台的雜湊，CI（Linux）用 `-lockfile=readonly` 會失敗。產生方式見 Phase 8 |
| `override_during = plan` 在 terraform 1.15.8 可用 | Phase 1 實測（`modules/ssm-publish/tests/ssm-publish.tftest.hcl`）。要斷言 computed 值時，優先用 `override_resource`／`override_data` 加 `override_during = plan`，其次才用 `command = apply` |

### 每個 module／stack 的 TDD 節奏

| 步驟 | 做什麼 | 要留下的證據 |
|---|---|---|
| 1. 介面 | 照 design 先寫 `versions.tf`、`variables.tf`（含 validation），`main.tf` 只放空殼或最少資源 | — |
| 2. RED | 寫測試，跑 `scripts/validate.sh <dir>`，**至少一個 assert 是因為條件不成立而失敗**，不是因為參照不存在 | 失敗輸出貼進 Phase 回報 |
| 3. GREEN | 補資源到測試全過 | 通過數量（例如 `Success! 22 passed, 0 failed.`） |
| 4. REFACTOR | 整理命名、拆檔、補 README／example，測試仍全過 | 重跑結果 |
| 5. 反向驗證 | 每個 validation 正反兩個方向各一個 run（合法邊界值通過、非法值被 `expect_failures` 擋下）；挑關鍵 assert 暫時改壞實作，確認測試會紅，再改回來 | 改壞時的失敗輸出 |

下面各 Phase 的 run 表裡，「A 被擋；B 通過」寫在同一列代表兩個 run（一正一反）。「整個 module 不得有某種資源」這類檢查不寫成 run（`terraform test` 無法列舉資源型別），由 `validate.sh` 的靜態規則負責。

### module 的固定檔案

照 design §4.1：`main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`（aws `>= 6.0, < 7.0`）、`README.md`、`CHANGELOG.md`、`examples/<情境>/`（至少一個）、`tests/*.tftest.hcl`（可依主題拆檔）。不放 provider 與 backend，不放 `.terraform.lock.hcl`。

增補：Phase 13 的 7 個新 module 的 `versions.tf` 是 aws `>= 6.69, < 7.0`（design 決策 43）。

### commit 規則

- 時機：執行 subagent 回報完成 → 主 agent 自己重跑該 Phase 的驗收指令與全量 `scripts/validate.sh` → 全綠才 commit。
- 位置：直接在本機 `main`，不 push。
- 粒度：一個 module 一個 commit，一個 commit 只動一個 module 目錄（release-please 依路徑歸屬）。非 module 的 Phase 各一個。
- commit 前確認 `git config user.email` 是 `<author-email>`。
- 格式：`<type>(<scope>): <subject>`，subject 英文、祈使句、50 字內。`git add` 逐檔列路徑，不用 `git add -A`。

| Phase | commit message（範例） |
|---|---|
| 6 | `chore(repo): register seven new modules and tighten static rules` |
| 7A–D | `feat(kms-key): add customer managed key module`（其餘 6 個同格式，scope 是 module 名；實際 message 見 git log） |
| 7E | `docs(design): ...`、`chore(repo): register observability modules`、`feat(log-group): ...`、`feat(log-metric-alarm): ...`、`feat(xray): ...`、`feat(ecs-service): add sidecars for extra containers` |
| 8 | `feat(template): add project-infra template with eight stacks` |
| 9 | `docs(guides): add usage guides and vendor-modules script` |
| 10 | `chore(repo): fix issues found in final acceptance`（有修正才有） |

## Phase 拆分

### 順序的理由

| 順序 | 理由 |
|---|---|
| Phase 0–5 | 已完成。舊的 8 個 module 不受這次範圍變更影響（只有 S3、S4 的規則改寫，要在 Phase 6 確認它們仍然通過） |
| Phase 6 先做共用設定 | release-please 的兩個 JSON、`validate.sh`、README 是每個新 module 都會碰到的共用檔。先由一個 commit 改好，Phase 7 的 7 個 module 才能平行開發，不會撞到同一個檔；新的 S3、S4、S8 也要先就位，新 module 一寫錯就會被擋 |
| Phase 7 新 module | 範本的 8 個 stack 都要呼叫它們 |
| Phase 7E 觀測性 | 使用者在 7A–D 完成後追加。跟 Phase 6 一樣，先用一個 chore commit 改共用檔，3 個新 module 與 `ecs-service` 才能平行 |
| Phase 8 範本 | `application` 要呼叫 `log-metric-alarm`、`xray`，所以排在 7E 之後 |
| Phase 9 文件 | 要引用範本的真實檔案 |

### 可平行與不可平行

判斷依據：**檔案不重疊**，而且**沒有測試依賴**（module 的測試都用字面值餵輸入，不引用其他 module）。

| 組合 | 能不能平行 | 理由 |
|---|---|---|
| Phase 6 與任何 Phase | 不行 | 其他 Phase 都依賴它改的共用檔 |
| Phase 7 的 7 個 module | 可以 | 各自只動自己的 `modules/<name>/`；共用檔在 Phase 6 已改完 |
| Phase 7E 的 3 個新 module 與 `ecs-service` | 可以（7E 的 docs 與 chore commit 先做） | 各自只動自己的目錄 |
| Phase 8 與 Phase 7 | 不行 | 範本的測試會 init 全部 module |
| Phase 9 與 Phase 8 | 部分可以 | `releasing-modules.md`、`team-roles.md`、`vendor-modules.sh` 只依賴 module，可在 Phase 7 後開始；`observability.md` 要對照 `modules/ecs-service/examples/adot-sidecar/`，可在 7E 後開始；其餘三份要對到範本的真實檔案 |

**Phase 7A–D 的分組（4 個執行 subagent，已完成）**

| subagent | module | 為什麼放一起 |
|---|---|---|
| A | `iam-role`、`iam-role-policy` | 兩者的「禁止萬用動作」validation 必須一字不差（design §4.15），同一個人寫才不會漂移 |
| B | `kms-key`、`s3-bucket` | 都是 policy JSON 的組裝與斷言，都要 `override_data` 給 `data.aws_caller_identity`／`data.aws_elb_service_account` |
| C | `ecr-repository`、`ssm-read` | 兩個都小 |
| D | `security-group` | 規則展開與交叉 validation 最多，單獨一個 |

同一個 subagent 負責兩個 module 時，仍然一個 module 一個 commit。主 agent 逐一驗證，commit 順序：`iam-role` → `iam-role-policy` → `kms-key` → `s3-bucket` → `ecr-repository` → `ssm-read` → `security-group`。

### Phase 0–5：已完成

詳細的檔案清單與 run 表見 git 歷史（本文件在 `541ae3c` 時的版本）。以下只記錄結果與計畫外的變動。

| module | commit | 測試數 |
|---|---|---|
| `ssm-publish` | `46d5a4d` | 22 |
| `sns-alarm-topic` | `5a0dcf3` | 18 |
| `vpc` | `09c5342`（`92b6200` 後 69：搬走 4 個、刪掉 3 個） | 76 |
| `ecs-cluster` | `07552ef` | 22 |
| `ecs-service` | `4ebf5d9` | 67 |
| `alb` | `04b33ef` | 32 |
| `ecs-service-alarms` | `74ea776` | 25 |
| `rds` | `c916c46` | 108 |

全量 `scripts/validate.sh`：21 個目錄（8 個 module 加 13 個 example）通過。

| 計畫外的 commit | 內容 | 為什麼 |
|---|---|---|
| `541ae3c docs(design)` | 第一個 tag `<module>-v0.1.0` 由人手動打，manifest 維持登記 `0.1.0` | release-please 會把 manifest 的版本當成已發布，不會自己產生第一個 tag（design §3.5、決策 27） |
| `19608d4 fix(validate)` | 加 `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true` | module 沒有 lock 檔時不用快取，每個目錄要下載約 6 分鐘 |
| 7 個 `style(<module>)` | 註解、`description`、`error_message` 改成只用英文 | 新規則（硬性限制第 6 條）；`alb` 原本就符合 |

### Phase 6：共用設定更新（已完成，`eec61df`）

**實際結果**：全量 `scripts/validate.sh` 通過。跟計畫的差異：S3 放行 `each.value`（`for_each` 的迭代變數，不是參數值），寫在 `scripts/validate.sh` 的註解。

**目標**：一個 commit 改完所有共用檔，讓 Phase 7 可以平行。

**檔案清單**

| 路徑 | 改什麼 |
|---|---|
| `release-please-config.json` | `packages` 加 7 個 module，格式同既有的 8 個（`release-type: terraform-module`、`component` 等於目錄名） |
| `.release-please-manifest.json` | 7 個 module 都登記 `0.1.0` |
| `scripts/validate.sh` | 靜態規則照 design §5.6 改成 S1–S8，見「驗證指令的具體寫法」；沒列到的步驟不動 |
| `README.md` | module 清單改成 15 個，照 design §1 的分類 |

**`validate.sh` 的改動**

| 規則 | 改動 |
|---|---|
| S2 | 範圍確認涵蓋 `modules/` 與 `templates/`（現行已是） |
| S3 | 改寫：`data "aws_ssm_parameter"` 只能出現在 `modules/ssm-read/`；`modules/ssm-read/` 不得出現 `.value`。原本「範本 `ssm-inputs.tf` 不讀 `.value`」由這條涵蓋 |
| S4 | 改寫：`resource "aws_iam_*"` 只能出現在 `modules/iam-role/` 與 `modules/iam-role-policy/`（後者只允許 `aws_iam_role_policy`）；`aws_security_group`、`aws_vpc_security_group_ingress_rule`、`aws_vpc_security_group_egress_rule` 只能出現在 `modules/security-group/` 與 `modules/vpc-interface-endpoints/`；`aws_default_security_group` 只能出現在 `modules/vpc/`；範本 stack 都不得出現（`d770756` 起；Phase 6 時的版本允許 `modules/vpc/`） |
| S8 | 新增：範本 stack 裡 `resource "aws_*"` 只能是 design §5.3〈stack 裡的原生資源〉上的型別與 stack（目前只有 `foundation` 的 `aws_secretsmanager_secret`）。清單寫成腳本開頭的一個陣列，跟 design 的表一一對應 |

**反向驗證**（在 scratchpad 的暫存複本做，不在 repo 留 fixture）

| 情境 | 預期 |
|---|---|
| 範本 stack 裡寫 `data "aws_ssm_parameter"` | S3 失敗 |
| `modules/ssm-read/` 裡讀 `.value` | S3 失敗 |
| `modules/ssm-read/` 裡 `data "aws_ssm_parameter"` 只讀 `insecure_value` | 通過 |
| `modules/ecs-service/` 宣告 `resource "aws_iam_role"` | S4 失敗 |
| `modules/iam-role-policy/` 宣告 `resource "aws_iam_role"` | S4 失敗（只允許 `aws_iam_role_policy`） |
| `modules/iam-role/` 宣告 `aws_iam_role` 與 `aws_iam_role_policy` | 通過 |
| 範本 stack 宣告 `resource "aws_iam_role"` | S4 失敗 |
| `modules/alb/` 宣告 `resource "aws_security_group"` | S4 失敗 |
| `modules/security-group/`、`modules/vpc/` 宣告 SG 與 `aws_vpc_security_group_ingress_rule` | 通過 |
| 範本 `network` 宣告 `aws_vpc_security_group_ingress_rule` | S4 失敗 |
| 範本 `foundation` 宣告 `aws_secretsmanager_secret` | 通過 |
| 範本 `network` 宣告 `aws_secretsmanager_secret` | S8 失敗 |
| 範本 `foundation` 宣告 `aws_s3_bucket` | S8 失敗 |
| 範本 stack 宣告 `terraform_data` | 通過（不碰 AWS，design §5.3 允許） |

**驗收指令**

```bash
shellcheck -S warning scripts/validate.sh
jq . release-please-config.json .release-please-manifest.json >/dev/null
jq -r '.packages | keys[]' release-please-config.json | wc -l      # 預期 15
jq -r 'keys[]' .release-please-manifest.json | wc -l               # 預期 15
jq -r 'to_entries[] | .value' .release-please-manifest.json | sort -u   # 預期只有 0.1.0
scripts/validate.sh                                                # 既有 21 個目錄仍全部通過
```

**完成定義**：上表每個情境的輸出貼在回報裡；既有 8 個 module 在新規則下仍全綠。主 agent 驗證後 commit。

**不在本次範圍**：任何 module 程式碼；CI workflow（不用改，它只呼叫 `validate.sh`）；CODEOWNERS（`/modules/` 已涵蓋新 module）。

### Phase 7A–D：7 個基礎 module（已完成）

| module | commit | 測試數 |
|---|---|---|
| `iam-role` | `5de879a`（`5ab5d87` 後 34） | 30 |
| `iam-role-policy` | `5871875`（`fce75f2` 後 27） | 23 |
| `kms-key` | `9994403` | 27 |
| `s3-bucket` | `d9f8e65` | 28 |
| `ecr-repository` | `86560dc` | 17 |
| `ssm-read` | `9b56443` | 19 |
| `security-group` | `5675092` | 44 |

全量 `scripts/validate.sh`：35 個目錄通過。跟計畫的差異：`iam-role` 與 `iam-role-policy` 多了一條 validation，Allow statement 不准搭配 `NotAction`（`NotAction` 等於「除了這些以外全部允許」，會繞過禁止萬用動作的檢查）。兩個 module 這條的寫法也一字不差。

以下是當時的計畫，保留作為對照。

**目標**：照 design §4.10–§4.16 做出 7 個 module，run 表以 design §7.1 為基礎。每個 module 一個 commit。

**每個 module 的檔案**：`main.tf`、`variables.tf`、`outputs.tf`、`versions.tf`、`README.md`、`CHANGELOG.md`、`examples/basic/`、`tests/*.tftest.hcl`。

#### `kms-key`（design §4.10）

資源：`aws_kms_key.this`、`aws_kms_key_policy.this`、`aws_kms_alias.this`；key policy 的帳號 root 需要 `data "aws_caller_identity"`（測試用 `override_data` 給 12 位數帳號）。

| run | 斷言 |
|---|---|
| `key_defaults` | `enable_key_rotation = true`、`key_usage = "ENCRYPT_DECRYPT"`、`customer_master_key_spec = "SYMMETRIC_DEFAULT"`、`multi_region = false`、`deletion_window_in_days = 30` |
| `alias_name` | alias 是 `alias/<name>`，指向這把 key |
| `root_statement_first` | `jsondecode(policy).Statement[0]` 的 principal 是 `arn:aws:iam::<account>:root`、Action `kms:*` |
| `service_principal_statements` | `service_principals` 給兩個 → 多兩段 statement，principal、actions（預設 `kms:Decrypt`、`kms:GenerateDataKey*`、`kms:DescribeKey`）與 conditions 照輸入 |
| `no_service_statements_by_default` | `service_principals = {}` → 只有 root 一段 |
| `administrator_statement_only_when_given` | `administrator_arns = []` → 沒有管理者 statement；給一個 role ARN → 多一段 |
| `outputs` | `key_arn`、`key_id`、`alias_name`、`alias_arn` 有值（`override_during = plan`） |
| `deletion_window_range` | 6 與 31 被擋；7 與 30 通過 |
| `name_rules` | `aws/foo` 被擋；含空白被擋；`alpha-dev` 通過 |
| `service_principal_format` | `*`、`logs.amazonaws.org` 被擋；`logs.ap-northeast-1.amazonaws.com` 通過 |
| `service_actions_no_wildcard` | actions 給 `*` 或 `kms:*` 被擋 |
| `administrator_arn_format` | 含 `*` 或不是 role／user ARN 被擋 |

#### `ecr-repository`（design §4.11）

| run | 斷言 |
|---|---|
| `repository_defaults` | `image_tag_mutability = "IMMUTABLE"`、`scan_on_push = true`、`force_delete = false` |
| `aes256_without_kms` | `kms_key_arn = null` → `encryption_type = "AES256"` |
| `kms_when_given` | 給 key ARN → `encryption_type = "KMS"`、`kms_key` 等於輸入 |
| `lifecycle_defaults` | `jsondecode(policy).rules` 恰兩條：untagged 超過 7 天刪除、`tagStatus = "any"` 超過 50 個刪除；優先序照 design |
| `lifecycle_override` | `untagged_expire_days = 3`、`keep_count = 20` → 兩條規則跟著變 |
| `outputs` | `repository_url`、`arn`、`name`、`registry_id` |
| `name_format` | 含大寫或空白被擋；`alpha-dev-api`、`team/api` 通過 |
| `lifecycle_minimums` | `untagged_expire_days = 0`、`keep_count = 0` 各自被擋；1 通過 |

#### `s3-bucket`（design §4.12）

`alb_access_logs` 會讀 `data "aws_elb_service_account"`，`vpc_flow_logs` 的條件要帳號 ID，測試都用 `override_data`。

| run | 斷言 |
|---|---|
| `public_access_blocked` | public access block 四項全是 `true` |
| `ownership_enforced` | `object_ownership = "BucketOwnerEnforced"` |
| `tls_only_deny_always` | `log_delivery = []` 時 bucket policy 只有一段 `Deny`，條件 `aws:SecureTransport = false` |
| `alb_access_logs_statements` | `log_delivery = ["alb_access_logs"]` → 多兩段：ELB 服務帳號與 `logdelivery.elasticloadbalancing.amazonaws.com`，`s3:PutObject` on `<bucket>/*AWSLogs/<account>/*`，後者帶 `aws:SourceAccount` |
| `vpc_flow_logs_statements` | `log_delivery = ["vpc_flow_logs"]` → `delivery.logs.amazonaws.com` 的 `s3:PutObject`（帶 `aws:SourceAccount` 與 `s3:x-amz-acl = bucket-owner-full-control`）與 `s3:GetBucketAcl` |
| `sse_s3_by_default` | `kms_key_arn = null` → `sse_algorithm = "AES256"` |
| `sse_kms_when_given` | 給 key → `aws:kms`、`kms_master_key_id` 等於輸入 |
| `lifecycle` | 過期天數預設 90；未完成的 multipart upload 7 天清除 |
| `force_destroy_default` | `force_destroy = false` |
| `outputs` | `bucket_name`、`arn`、`bucket_regional_domain_name` |
| `name_format` | 含 `.`、大寫、`--` 各自被擋；`alpha-dev-flow-logs` 通過 |
| `expiration_range` | 0 與 3651 被擋；1 與 3650 通過 |
| `log_delivery_values` | `["cloudtrail"]` 被擋 |
| `alb_logs_reject_kms` | `log_delivery = ["alb_access_logs"]` 加 `kms_key_arn` → 被擋；`vpc_flow_logs` 加 `kms_key_arn` 通過 |

#### `ssm-read`（design §4.13）

data source 的 target 是 `data.aws_ssm_parameter.this["<stack>/<key>"]`。

| run | 斷言 |
|---|---|
| `strings_output` | `strings = { vpc_id = "network/vpc_id" }`、`override_data` 給 `insecure_value = "vpc-0abc"` → `strings["vpc_id"] == "vpc-0abc"`；讀的 name 是 `<ssm_prefix>/network/vpc_id` |
| `lists_split_by_comma` | `insecure_value = "subnet-a,subnet-b"` → `lists["subnet_ids_app"] == ["subnet-a", "subnet-b"]` |
| `same_path_read_once` | 兩個本地名稱指向同一個 `<stack>/<key>` → data source 只有 1 個，兩個輸出都有值 |
| `empty_inputs_no_data_source` | 兩個 map 都空 → data source 0 個，輸出都是空 map |
| `json_values_untouched` | 值是 JSON 字串時原樣回傳，由呼叫端 `jsondecode` |
| `prefix_format` | `alpha/dev`、`/alpha/dev/` 被擋；`/alpha/dev` 通過 |
| `value_format` | `network/VPC_ID`、`/network/vpc_id`、`network` 被擋；`iam-base/role_rds_proxy_arn` 通過 |

#### `iam-role`（design §4.14）

| run | 斷言 |
|---|---|
| `trust_principals_only` | `jsondecode(assume_role_policy)` 的 Principal 恰為輸入的服務主體、Action 只有 `sts:AssumeRole` |
| `source_account_condition` | 給 `source_account` → 有 `aws:SourceAccount` 條件；沒給 → 沒有條件 |
| `inline_policy_per_entry` | `inline_policies` 給兩個 → 兩個 `aws_iam_role_policy.this`，內容等於輸入 |
| `no_inline_policies` | `inline_policies = {}` → 0 個 |
| `permissions_boundary` | 照輸入；預設 null |
| `outputs` | `arn`、`name`、`id`；`arn` 的 output 有 `depends_on = [aws_iam_role_policy.this]`（grep） |
| `name_length` | 65 字元被擋；64 字元通過 |
| `trust_validation` | 空集合、`*`、`example.com` 各自被擋 |
| `source_account_format` | `1234` 被擋 |
| `policy_must_be_json` | `"not json"`、沒有 `Statement` 的 JSON 各自被擋 |
| `allow_rejects_wildcard_action` | Allow 的 Action 是 `"*"`（字串）、`["*"]`（清單）、`"s3:*"`、`["s3:GetObject", "s3:*"]` 各自被擋 |
| `deny_wildcard_is_allowed` | Deny statement 用 `"*"` → **通過**（反向） |

#### `iam-role-policy`（design §4.15）

| run | 斷言 |
|---|---|
| `policy_per_entry` | `policies` 給兩個 → 兩個 `aws_iam_role_policy.this`，內容等於輸入 |
| `role_name_from_arn` | `role_arn = "arn:aws:iam::111111111111:role/alpha-dev-db-proxy"` → 每個資源的 `role = "alpha-dev-db-proxy"`；`role_name` 輸出相同 |
| `outputs` | `policy_names` 等於 `keys(policies)` |
| `role_arn_format` | 帶 path（`role/service/x`）被擋；`user/x` 被擋；無 path 的 role ARN 通過 |
| `policies_required` | `policies = {}` 被擋 |
| `policy_must_be_json` | 非 JSON 被擋 |
| `allow_rejects_wildcard_action` | Allow 的 Action 是 `"*"`、`"secretsmanager:*"`（字串與清單）各自被擋 |
| `deny_wildcard_is_allowed` | Deny 用 `"*"` → **通過**（反向） |

驗收時另外比對兩個 module 的「禁止萬用動作」validation 是否一字不差（見驗收指令）。

#### `security-group`（design §4.16）

| run | 斷言 |
|---|---|
| `one_group_per_key` | `security_groups` 給 3 個 → 3 個 `aws_security_group.this`，`name`、`description`、`vpc_id` 照輸入 |
| `rules_split_by_type` | `type = "ingress"` 的規則都在 `aws_vpc_security_group_ingress_rule.this`、`egress` 的都在 `egress_rule.this`，key 跟 `rules` 的 key 相同 |
| `peer_group_resolves_to_id` | `peer_group = "alb"` → `referenced_security_group_id` 等於同一次呼叫裡 `alb` SG 的 id（`override_during = plan` 給 SG 固定 id） |
| `external_peer_and_cidr_and_prefix_list` | `peer_group_id`、`cidr_ipv4`、`prefix_list_id` 各一條規則，各自對應到 resource 的同名屬性 |
| `to_port_defaults_to_from_port` | 只給 `from_port = 443` → `to_port = 443` |
| `all_protocol_has_no_port` | `ip_protocol = "-1"` → `from_port`、`to_port` 都是 null |
| `ingress_internet_with_flag` | ingress `0.0.0.0/0` 加 `allow_internet = true` → 通過 |
| `egress_internet_without_flag` | egress `0.0.0.0/0` 不寫 `allow_internet` → **通過**（反向） |
| `outputs` | `security_group_ids`、`security_group_arns` 的 key 等於 `security_groups` 的 key |
| `groups_required` | `security_groups = {}` 被擋；key `Alb` 被擋 |
| `rule_group_must_exist` | `security_group = "nope"`、`peer_group = "nope"` 各自被擋 |
| `exactly_one_peer` | 沒有 peer 被擋；`peer_group` 加 `cidr_ipv4` 被擋 |
| `type_values` | `type = "both"` 被擋 |
| `port_rules` | tcp 沒有 `from_port` 被擋；`to_port < from_port` 被擋；`from_port = 70000` 被擋；`-1` 卻給 port 被擋 |
| `ingress_internet_needs_flag` | ingress `0.0.0.0/0` 沒寫 `allow_internet = true` → 被擋 |
| `cidr_format` | `10.0.0.0/33`、`not-a-cidr` 被擋 |

**驗收指令**

```bash
scripts/validate.sh modules/<name>                       # 每個 module 各跑一次
grep -rnP '[^\x00-\x7F]' modules/<name>/*.tf modules/<name>/tests/   # 預期沒有輸出（只用英文、沒有 icon）
grep -rn 'aws_iam_role_policy_attachment\|aws_iam_policy"\|aws_iam_role_policies_exclusive' modules/iam-role modules/iam-role-policy   # 預期沒有輸出
diff <(awk '/Allow statements must not use/{f=0} /condition = alltrue\(flatten/{f=1} f' modules/iam-role/variables.tf) \
     <(awk '/Allow statements must not use/{f=0} /condition = alltrue\(flatten/{f=1} f' modules/iam-role-policy/variables.tf | sed 's/var.policies/var.inline_policies/')   # 預期沒有輸出
grep -rnE '^\s*(ingress|egress)\s*\{' modules/security-group/   # 預期沒有輸出
scripts/validate.sh                                       # 全量
```

**完成定義**：7 個 module 的 run 都存在且通過；design §7.1 表中每一項都有對應的 run；`allow_rejects_wildcard_action`、`ingress_internet_needs_flag`、`alb_logs_reject_kms` 經反向驗證確認有效。主 agent 每驗完一個 module 就 commit 一次。

**不在本次範圍**：design 各章節「刻意不做」的項目；範本（Phase 8）；`secret` module（design 決策 30）。

### Phase 7E：觀測性（已完成）

| commit | 內容 | 測試數 |
|---|---|---|
| `977cba7 chore(repo)` | release-please 加 `log-group`、`log-metric-alarm`、`xray`；README 改成 18 個 | — |
| `21d6513 docs(design)` | 設計文件的 7E 變更，並補記 Phase 7 的計畫外差異 | — |
| `a6dd7ac` | `log-group` | 18 |
| `0cdd874` | `log-metric-alarm` | 27 |
| `90adc72` | `xray` | 22 |
| `0bde63f` | `ecs-service` 的 `sidecars` | `ecs-service` 合計 90；既有 5 個測試檔沒有變動 |

跟計畫的差異：

- 順序是 chore 先、docs 後（計畫是 docs 先），結果相同。
- `examples/adot-sidecar/` 的 collector 設成 `essential = false`：觀測工具掛掉，不應該讓 ECS 把整個 task 連應用程式一起重啟。`observability.md` 要照這個寫。

以下是當時的計畫，保留作為對照。


**目標**：照 design §4.17–§4.20、§7.1、決策 31–33，新增 `log-group`、`log-metric-alarm`、`xray`，並讓 `ecs-service` 支援 sidecar。module 總數從 15 變 18。

**commit 順序**（共 6 個）

| # | commit | 內容 | 誰做 |
|---|---|---|---|
| 1 | `docs(design): add observability modules and ecs-service sidecars` | design-docs.md 與本文件的 7E 變更 | 主 agent |
| 2 | `chore(repo): register observability modules` | `release-please-config.json`、`.release-please-manifest.json` 加 3 個 module（`0.1.0`）；`README.md` 的 module 清單改成 18 個 | 主 agent 或執行 subagent，主 agent 驗證 |
| 3 | `feat(log-group): add log group module with optional subscription` | `modules/log-group/` | 執行 subagent |
| 4 | `feat(log-metric-alarm): add metric filter and alarm module` | `modules/log-metric-alarm/` | 執行 subagent |
| 5 | `feat(xray): add sampling rule and group module` | `modules/xray/` | 執行 subagent |
| 6 | `feat(ecs-service): add sidecars for extra containers` | `modules/ecs-service/`：`sidecars` 變數、新增的測試檔、`examples/adot-sidecar/`、README、CHANGELOG | 執行 subagent |

commit 1、2 先做：commit 2 改的是共用檔，做完後 3–6 可以平行。commit 6 屬於 MINOR（新增有預設值、預設維持原行為的變數），因為 `ecs-service` 還沒打過第一個 tag，所以併進 `v0.1.0`（design §4.20）。

**分組**：E1 負責 `log-group` 與 `log-metric-alarm`（都是 CloudWatch Logs，`log-metric-alarm` 的 SNS 接線要沿用 `ecs-service-alarms` 的寫法）；E2 負責 `xray`；E3 負責 `ecs-service` 的 `sidecars`（動既有 module，單獨一個人，迴歸要求最嚴）。

#### commit 2 的驗收

```bash
jq -r '.packages | keys[]' release-please-config.json | wc -l      # 預期 18
jq -r 'keys[]' .release-please-manifest.json | wc -l               # 預期 18
jq -r 'to_entries[] | .value' .release-please-manifest.json | sort -u   # 預期只有 0.1.0
scripts/validate.sh                                                # 既有 35 個目錄仍全部通過
```

#### `log-group`（design §4.17）

| run | 斷言 |
|---|---|
| `defaults` | `retention_in_days = 30`；`kms_key_id` 為 null；`subscription = null` 時 `aws_cloudwatch_log_subscription_filter.this` 0 個 |
| `retention_override` | `retention_days = 365` → `retention_in_days = 365` |
| `kms_when_given` | 給 key ARN → `kms_key_id` 等於輸入 |
| `lambda_subscription_without_role` | Lambda 目的地、`role_arn = null` → 1 個 subscription filter，`role_arn` 為 null、`filter_pattern = ""` |
| `firehose_subscription_with_role` | Firehose 目的地加 `role_arn` → subscription filter 帶 `role_arn` |
| `outputs` | `name`、`arn` |
| `retention_values` | `0`、`2` 被擋；`1`、`3653` 通過 |
| `name_rules` | `aws/foo` 被擋；含空白被擋；`/alpha/dev/worker` 通過 |
| `destination_arn_format` | S3 ARN 被擋 |
| `stream_destinations_need_role` | Kinesis 或 Firehose 目的地沒給 `role_arn` → 被擋 |

#### `log-metric-alarm`（design §4.18）

| run | 斷言 |
|---|---|
| `one_filter_and_alarm_per_entry` | `alarms` 給兩個 → 兩個 `aws_cloudwatch_log_metric_filter.this`、兩個 `aws_cloudwatch_metric_alarm.this`，名稱是 `<name_prefix>-<key 的 _ 換成 ->` |
| `filter_defaults` | `metric_transformation` 的 `value = "1"`、`default_value = 0`、`namespace` 與 `name` 照輸入；`log_group_name` 照輸入 |
| `alarm_defaults` | `statistic = "Sum"`、`period = 60`、`evaluation_periods = 1`、`threshold = 1`、`GreaterThanOrEqualToThreshold`、`notBreaching` |
| `alarm_override` | 改 `period = 300`、`threshold = 60`、`datapoints_to_alarm = 2`、`evaluation_periods = 3` → 照輸入 |
| `every_alarm_notifies_both_ways` | 每個 alarm 的 `alarm_actions` 與 `ok_actions` 都等於 `toset(sns_topic_arns)`。反向驗證：拿掉一個的 `ok_actions`，測試要紅 |
| `empty_alarms_creates_nothing` | `alarms = {}` → 兩種資源都是 0 個 |
| `outputs` | `alarm_arns`、`alarm_names`、`metric_filter_names` 的 key 等於 `alarms` 的 key |
| `sns_topic_required` | `sns_topic_arns = []` 被擋 |
| `key_and_text_rules` | key `PersistenceFailed` 被擋；`pattern = " "` 被擋；`description = ""` 被擋 |
| `statistic_values` | `statistic = "p99"` 被擋；`Average` 通過 |
| `period_values` | `period = 45` 被擋；`10`、`30`、`120` 通過 |
| `datapoints_within_periods` | `datapoints_to_alarm = 3`、`evaluation_periods = 2` 被擋 |
| `namespace_rules` | `AWS/ECS` 被擋；`Alpha/dev` 通過 |
| `name_prefix_format` | 大寫被擋 |

alarm 對 filter 的 `depends_on` 用 grep 驗收。

#### `xray`（design §4.19）

| run | 斷言 |
|---|---|
| `one_rule_per_entry` | `sampling_rules` 給兩個 → 兩個 `aws_xray_sampling_rule.this`，`rule_name = <name_prefix>-<key>`；`priority`、`fixed_rate`、`reservoir_size` 照輸入 |
| `rule_wildcard_defaults` | 沒給的 `service_name`、`service_type`、`host`、`http_method`、`url_path` 都是 `*`；`reservoir_size` 預設 1 |
| `one_group_per_entry` | `groups` 給兩個 → 兩個 `aws_xray_group.this`，`group_name = <name_prefix>-<key>`、`filter_expression` 照輸入；`insights_configuration` 的兩個值照輸入（預設都是 false） |
| `empty_inputs_create_nothing` | 兩個 map 都空 → 兩種資源都是 0 個 |
| `outputs` | `sampling_rule_arns`、`group_arns` 的 key 等於輸入的 key |
| `name_length` | `<name_prefix>-<key>` 超過 32 字（rule 與 group 各測）被擋；剛好 32 字通過 |
| `priority_range` | `0`、`10000` 被擋；`1`、`9999` 通過 |
| `fixed_rate_range` | `1.5`、`-0.1` 被擋；`0`、`1` 通過 |
| `priority_unique` | 兩條 rule 的 `priority` 相同 → 被擋 |
| `group_filter_required` | `filter_expression = ""` 被擋 |
| `notifications_need_insights` | `notifications_enabled = true`、`insights_enabled = false` → 被擋；兩個都 true 通過 |

#### `ecs-service` 的 `sidecars`（design §4.20）

**迴歸要求**：`modules/ecs-service/tests/` 底下既有的 5 個測試檔（`autoscaling`、`defaults`、`load-balancer`、`secrets-roles`、`validation`，共 67 個 run）**一行都不改**，全部通過。新增的斷言放在新檔 `tests/sidecars.tftest.hcl`。

| run | 斷言 |
|---|---|
| `no_sidecars_keeps_single_container` | `sidecars = []`（預設）→ `jsondecode(container_definitions)` 長度 1；主 container 沒有 `dependsOn` 欄位；跟 commit 前的 task definition 完全相同（反向驗證：在 `sidecars = []` 時也加一個空的 `dependsOn`，這條要紅） |
| `one_sidecar_order` | 一個 sidecar → 長度 2，`[0].name = "app"`、`[1].name` 是 sidecar 名稱 |
| `sidecar_logs_share_group` | sidecar 的 `logConfiguration` 是同一個 log group、同樣的 `mode = "non-blocking"`，`awslogs-stream-prefix` 是 sidecar 名稱；給 `log_stream_prefix` 時用給的值 |
| `sidecar_defaults` | sidecar 有 `initProcessEnabled = true`、`stopTimeout = 120`；`essential` 預設 false |
| `app_waits_only_when_asked` | `app_depends_on = "START"` → 主 container 有 `dependsOn = [{ containerName = <sidecar>, condition = "START" }]`；不設時沒有 `dependsOn` |
| `sidecar_secrets_value_from` | sidecar 的 `secrets` 轉成 `[{name, valueFrom}]` |
| `sidecar_port_mappings_and_health_check` | `port_mappings`、`health_check`、`cpu`、`memory_reservation`、`command`、`environment` 照輸入寫進 sidecar 的定義 |
| `sidecar_name_rules` | 名稱 `app`、兩個 sidecar 同名、`App` 各自被擋 |
| `sidecar_image_tag_required` | `:latest` 或沒有 tag 被擋 |
| `app_depends_on_values` | `READY` 被擋；`HEALTHY` 沒有 `health_check` 被擋；`HEALTHY` 有 `health_check` 通過 |
| `sidecar_port_conflict` | sidecar 的 `container_port` 跟主 container 相同、或兩個 sidecar 相同 → 被擋 |
| `sidecar_secret_format` | secret 值不是 ARN → 被擋 |

**`examples/adot-sidecar/`**：照 design §4.20 的表，示範一個 ADOT collector sidecar（映像帶明確 tag、`AOT_CONFIG_CONTENT` 用 `environment` 帶入、health check、`app_depends_on = "START"`、主 container 的 `OTEL_EXPORTER_OTLP_ENDPOINT = http://localhost:4317`）。只跑 `init -backend=false` 與 `validate`。

**驗收指令**

```bash
scripts/validate.sh modules/log-group modules/log-metric-alarm modules/xray modules/ecs-service
git diff --stat <commit 2 的 hash> -- modules/ecs-service/tests/   # 只有新增 tests/sidecars.tftest.hcl，既有 5 個檔沒有變動
grep -rnP '[^\x00-\x7F]' modules/log-group modules/log-metric-alarm modules/xray modules/ecs-service --include='*.tf' --include='*.tftest.hcl'   # 預期沒有輸出
grep -rn 'resource "aws_iam_' modules/log-group modules/log-metric-alarm modules/xray   # 預期沒有輸出（S4 也會擋）
grep -n 'depends_on' modules/log-metric-alarm/*.tf                 # alarm 有 depends_on filter
scripts/validate.sh                                                # 全量
```

**完成定義**：design §7.1 表中 `log-group`、`log-metric-alarm`、`xray`、`ecs-service` 的 `sidecars` 每一項都有對應的 run 且通過；`ecs-service` 既有 67 個 run 不改一行仍全部通過；`every_alarm_notifies_both_ways` 與 `no_sidecars_keeps_single_container` 經反向驗證確認有效。主 agent 每驗完一個 module 就 commit 一次。

**不在本次範圍**：把 `ecs-service`、`rds`、`ecs-service-alarms` 改成呼叫 `log-group` 或 `log-metric-alarm`（design 決策 33）；範本預設開追蹤或放 ADOT sidecar（design J43）；`iam-app` 的 X-Ray 權限與 `tracing_<service>`（寫在 `observability.md`，不進範本）；帳號層級的 X-Ray 設定。其中 ADOT sidecar 與 X-Ray 權限後來被 design 決策 36 推翻，範本已接好（預設關閉），見「Phase 9 補充」。

### Phase 7F：拆出 `vpc-interface-endpoints`（已完成）

使用者在 7E 之後決定（design 決策 34）：interface endpoint 不碰路由，從 `vpc` 拆出來，network stack 在自建 VPC 與客戶既有 VPC（模式 A）兩種情況都能呼叫。IGW、NAT、gateway endpoint、flow log 留在 `vpc`。`vpc` 還沒打過 tag，併進 `v0.1.0`。

| commit | 內容 | 測試數 |
|---|---|---|
| `606ba1d docs(design)` | design §4.7、§4.21、§5.3、§5.6 S4、§5.8、§7.1 | — |
| `92b6200 refactor(vpc)` | 移除 `interface_endpoints` 變數、endpoint SG、`vpce_security_group_id` 輸出 | 69（原本 76：4 個搬到新 module、3 個刪除，對照表在 design §7.1） |
| `7ebd512 feat(vpc-interface-endpoints)` | interface endpoint 加專用 SG（只對 `allowed_cidrs` 開 443，獨立 rule 資源，沒有 egress） | 22 |
| `d770756 chore(repo)` | release-please 改成 19 個；S4 改成 SG 只能在 `security-group` 與 `vpc-interface-endpoints`、`aws_default_security_group` 只能在 `vpc` | — |

### Phase 8：`templates/project-infra`（8 個 stack，已完成，`e71db48`）

結果：8 個 stack 共 317 個測試全過，全量 `scripts/validate.sh` 52 個目錄全過（約 9 分鐘）。跟下面計畫的差異：`reads_only_listed_keys`、`publishes_under_stack_path` 改成斷言 local 與 `module.ssm_publish.names`；loadbalancer 的 tfvars 與 examples 測試改成每個 run 釘住 `certificate_arn`；設計面的差異記在 design §9.4 D20、D21。

**目標**：照 design §5。8 個 stack 只呼叫 module，唯一的原生 resource 是 `foundation` 的 `aws_secretsmanager_secret`（S8）；跨 stack 讀寫一律透過 `ssm-read`／`ssm-publish`；兩個以上 stack 都要知道的開關只由上游一個 stack 決定（design §5.6「單一決定點」），下游用 precondition 檢查自己的設定跟上游一致。

**stack、module 與 SSM**（design §5.3）

| 順序 | stack | 呼叫的 module | 從 SSM 讀（來源 stack） | 發布到 SSM |
|---|---|---|---|---|
| 1 | `foundation` | `kms-key`、`sns-alarm-topic`、`s3-bucket` ×2、`ssm-publish`；原生 `aws_secretsmanager_secret` | — | `alarm_topic_arn`、`kms_key_arn`、`app_secret_arn`、`flow_log_bucket_arn`、`alb_log_bucket_name` |
| 2 | `containerimage` | `ecr-repository`（`for_each` 服務）、`ssm-read`、`ssm-publish` | foundation | `services`、`ecr_<service>_url`、`ecr_<service>_arn` |
| 3 | `network` | `vpc`（只在建立模式）、`vpc-interface-endpoints`（兩種模式都呼叫）、`security-group`、`ssm-read`、`ssm-publish` | foundation、containerimage | `vpc_id`、`vpc_cidr`、`azs`、`subnet_ids_<tier>`、`subnet_cidrs_<tier>`、`sg_alb_id`、`sg_<service>_id`、`sg_db_id`、`sg_db_proxy_id`、`sg_vpce_id`（由 `vpc-interface-endpoints` 的 `security_group_id` 發布；`services` 為空時不發布）、`nat`、`alb_https`、`db_proxy`、`data_access` |
| 4 | `iam-base` | `iam-role` ×3、`ssm-read`、`ssm-publish` | foundation、containerimage | `role_ecs_execution_arn`、`role_rds_proxy_arn`、`role_rds_monitoring_arn` |
| 5 | `data` | `rds`、`ssm-read`、`ssm-publish` | foundation、network、iam-base | `database`（JSON） |
| 6 | `iam-app` | `iam-role-policy`、`iam-role`（`for_each` 服務）、`ssm-read`、`ssm-publish` | foundation、containerimage、network、iam-base、data | `role_<service>_task_arn`、`ecs_exec_<service>` |
| 7 | `loadbalancer` | `alb`、`ssm-read`、`ssm-publish` | foundation、network | `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol` |
| 8 | `application` | `ecs-cluster`、`ecs-service`、`ecs-service-alarms`、`log-metric-alarm`、`xray`、`ssm-read` | 前七個 | 不發布 |

key 名稱與 JSON 格式以 design §5.6 的合約表為準。

**每個 stack 共通的檔案**（相對於 `templates/project-infra/infra/terraform/<stack>/`）

| 路徑 | 用途 |
|---|---|
| `versions.tf` | `required_version = ">= 1.10"`、`aws ~> 6.0`、`backend "s3" {}` |
| `providers.tf` | `allowed_account_ids = [var.expected_account_id]`、`default_tags`（`Project`、`Environment`、`Managed = "terraform"`、`Stack`）、可選 `assume_role`；每個 stack 只差 `Stack` 的值 |
| `common.tf` | `project`、`env`、`aws_region`、`expected_account_id`（不給預設值）與 `accounts_by_env` 對照表 validation、`name_prefix`、`ssm_prefix`、`common_tags`。8 個 stack 一字不差（S5） |
| `variables.tf` | 只放這個 stack 自己的變數 |
| `ssm-inputs.tf` | `module "in"` 呼叫 `ssm-read`（design §5.6 的寫法），下游用 `module.in.strings[...]`、`module.in.lists[...]`；foundation 不放 |
| `ssm-outputs.tf` | 只呼叫 `ssm-publish`；application 不放 |
| `<主題>.tf` | 這個 stack 的 module 呼叫。module 用相對路徑 `source = "../../../../../modules/<name>"` |
| `outputs.tf` | 給人看的輸出 |
| `envs/dev.tfvars`、`envs/prod.tfvars` | 非機密值，進版控；不放 secret、不放其他 stack 的資源 id |
| `envs/dev.tfbackend`、`envs/prod.tfbackend` | key `<project>-<env>/<stack>/terraform.tfstate`（S6） |
| `tests/<stack>.tftest.hcl` | 共通 run 加 stack 專屬 run |
| `tests/tfvars/tfvars.tftest.hcl` | 只放共通值與 `override_data`，由 `validate.sh` 用 `-var-file=envs/<env>.tfvars` 跑 |
| `.terraform.lock.hcl` | 進版控，產生方式見下 |

`network`、`data`、`loadbalancer`、`application` 另有 `envs/examples/{poc,standard,high}.tfvars`（design §5.11，不 apply、沒有 tfbackend、不得含明文 secret）與 `tests/examples/examples.tftest.hcl`（由 `validate.sh` 用 `-var-file=envs/examples/<x>.tfvars` 跑；測試檔不得在 `variables {}` 寫死會蓋掉範例值的變數，斷言寫成對任何合法輸入都成立的形式，design §7.1）。

範本根目錄 `templates/project-infra/infra/README.md`：stack 清單、apply 順序與 destroy 反序、SSM 合約表（照 design §5.6）、流量規格對照表、`TF_DATA_DIR=.terraform-<env>`、換環境一律 `init -reconfigure`、客戶自管模式 A／B、RDS Proxy 第一次部署的兩段式步驟（design §5.4，未驗證）、複製出去後把相對路徑 source 改成 `git::...?ref=<module>-v<semver>`（指向 `docs/guides/consuming-modules.md`）。不提供 `stacks.sh`。

**測試怎麼餵 SSM 值**

`ssm-read` 裡的 data source 要用 `override_data` 給值，target 寫成：

```hcl
override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}
```

每個測試檔開頭把會讀的 key 都寫一次（ARN 要給 ARN 形狀、清單給逗號串接、JSON key 給合法 JSON），個別 run 再覆寫要測的值。漏一個 key，mock 會回隨機字串，`jsondecode` 或下游的 ARN validation 直接失敗（R1、R12）。

**lock 檔的產生方式**（硬性限制第 9 條的唯一例外）

`validate.sh` 的快取設定會讓 lock 檔只記本機平台的雜湊，CI 用 `-lockfile=readonly` 會失敗。範本 stack 第一次產生 lock 檔時，對每個 stack 照下面原文執行一次，不得變更：

```bash
(
  for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
  export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_EC2_METADATA_DISABLED=true
  unset TF_PLUGIN_CACHE_DIR TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE TF_CLI_CONFIG_FILE
  export TF_DATA_DIR="<scratchpad>/lockgen/<stack>"
  terraform -chdir=templates/project-infra/infra/terraform/<stack> init -backend=false -input=false
)
grep -c 'zh:' templates/project-infra/infra/terraform/<stack>/.terraform.lock.hcl   # 預期大於 0
```

| 規則 | 理由 |
|---|---|
| 不用快取、不用 `TF_CLI_CONFIG_FILE` | 直接從 registry 下載，lock 檔才會記錄全平台的 `zh:` 雜湊 |
| `TF_DATA_DIR` 指到 scratchpad | 不在 repo 留下 `.terraform/` |
| 不准用 `terraform providers lock` | 不在允許清單 |
| 8 個 stack 的 aws provider 版本要相同 | 產生完比對 `version = "..."`，不同就停下來回報 |

產生後一律回到 `scripts/validate.sh` 驗證（`-lockfile=readonly`）。之後 module 不換 provider 版本，就不用重新產生。

**共通 run（每個 stack 都有）**

| run | 斷言 |
|---|---|
| `env_format` | `Dev`、`d` 被擋；`dev` 通過 |
| `account_must_match_env` | `dev` 配 prod 的帳號被擋；表外的 env 被擋；對得上時通過（照 `project-a/infra-v2/terraform/bridge/tests/guard.tftest.hcl`） |
| `account_is_required` | 不給 `expected_account_id` → 報缺變數 |
| `reads_only_listed_keys` | `ssm-inputs.tf` 的 local（`ssm_input_strings`、`ssm_input_lists`，`iam-base` 與 `application` 另有 `ssm_service_strings`）等於這個 stack 預期的 key 清單（foundation 除外）。斷言 local 而不是 `ssm-read` 的輸入，因為 `terraform test` 讀不到 module 的輸入值（R16） |
| `publishes_under_stack_path` | `module.ssm_publish.names` 等於上表每個 key 對應的 `/<project>/<env>/<stack>/<key>`，路徑裡的 stack 等於目錄名（application 除外） |
| tfvars（`tests/tfvars/`） | dev、prod 各跑一次：主要 module 有被呼叫，鎖住「開關預設全關、tfvars 不完整就規劃刪除」的坑 |

`allowed_account_ids` 本身在 mock 下測不到，只鎖 validation。

#### foundation

| 檔案 | 用途 |
|---|---|
| `kms.tf` | `kms-key`：`service_principals` 給 CloudWatch Logs（帶 `kms:EncryptionContext:aws:logs:arn` 條件）、CloudWatch、SNS（design §4.10） |
| `alarms.tf` | `sns-alarm-topic`，`kms_master_key_id` 用本 stack 的 key |
| `log-buckets.tf` | `s3-bucket` ×2：flow log（`log_delivery = ["vpc_flow_logs"]`）、ALB access log（`["alb_access_logs"]`），都是 `kms_key_arn = null`、`expiration_days = 90`，一律建立 |
| `secrets.tf` | 原生 `aws_secretsmanager_secret`（不含值，S8 唯一例外） |

| run | 斷言 |
|---|---|
| `publishes_foundation_keys` | 發布 5 個 key，值來自對應 module 的輸出 |
| `kms_service_principals` | `kms-key` 的 `service_principals` 包含 logs、cloudwatch、sns；logs 帶 EncryptionContext 條件 |
| `topic_uses_project_key` | `sns-alarm-topic` 的 `kms_master_key_id` 等於 `kms-key` 的 `key_arn` |
| `log_buckets_sse_s3` | 兩個 `s3-bucket` 的 `kms_key_arn` 都是 null |
| `log_buckets_delivery` | flow log bucket 的 `log_delivery = ["vpc_flow_logs"]`；ALB bucket 是 `["alb_access_logs"]` |
| `log_buckets_always_created` | 不管 tfvars 怎麼設，兩個 `s3-bucket` 都被呼叫 |
| `secret_has_no_value` | 沒有 `aws_secretsmanager_secret_version`（grep） |

#### containerimage

| run | 斷言 |
|---|---|
| `publishes_services` | `services = ["api", "worker"]` → 發布 `services`（StringList） |
| `one_repository_per_service` | `ecr-repository` 被呼叫兩次，`name` 是 `<project>-<env>-<service>`，`kms_key_arn` 等於 SSM 讀到的 `kms_key_arn` |
| `lifecycle_defaults_passed` | 沒有覆寫時用 module 預設（7 天、50 個） |
| `service_name_format` | 大寫或含空白被擋；`order-api` 通過 |
| `publishes_url_and_arn` | 每個服務發布 `ecr_<service>_url`、`ecr_<service>_arn`；`order-api` 是 `ecr_order_api_url` |

#### network

| 檔案 | 用途 |
|---|---|
| `vpc.tf` | 建立模式：`vpc` module，tier 固定 `public`、`app`、`data`（data 預設 isolated）；`vpc.flow_log = true` 時 `destination_arn` 用 SSM 讀到的 `flow_log_bucket_arn` |
| `existing.tf` | 模式 A：`existing = { vpc_id, subnet_ids }`，`data "aws_vpc"`、`data "aws_subnet"` 用 `for_each` 確認存在；precondition 檢查 `data.aws_vpc.this` 的 `enable_dns_support` 與 `enable_dns_hostnames` 都是 true（`private_dns_enabled = true` 的 endpoint 需要，design §5.8）。路由、IGW、NAT、gateway endpoint、default SG 一律不碰 |
| `endpoints.tf` | `vpc-interface-endpoints`，兩種模式都呼叫：`services` 與 `subnet_tier` 來自最上層變數 `interface_endpoints`（預設 `{}`，`subnet_tier` 預設 `app`）；建立模式的 `vpc_id`、`allowed_cidrs = [vpc_cidr]`、`subnet_ids` 來自 `vpc` 的輸出；模式 A 來自 `existing` 與 `data.aws_vpc.this`（`allowed_cidrs` 是 `cidr_block_associations` 的全部 CIDR）。validation：`subnet_tier` 必須存在而且不是 `public`（這條從 `vpc` module 搬到這裡） |
| `security-groups.tf` | locals 把 `services`、`data_stores`、`alb_ingress` 展開成 `security_groups` 與 `rules`，呼叫 `security-group` 一次（design §4.16、§5.3 的規則表） |
| `envs/dev.tfvars` | `data_stores.db.proxy = false` |
| `envs/prod.tfvars` | `data_stores.db.proxy = true` |
| `envs/examples/{poc,standard,high}.tfvars` | 照 design §5.11 |

| run | 斷言 |
|---|---|
| `create_mode_publishes_keys` | 發布上表全部 key（清單類為 StringList） |
| `data_tier_isolated_by_default` | dev 的 `data` tier `type = "isolated"` |
| `existing_mode_publishes_same_keys` | 模式 A 發布的 key 集合跟建立模式相同；`vpc` module 沒被呼叫；`override_data` 餵 `data "aws_vpc"`、`data "aws_subnet"` |
| `vpc_and_existing_are_exclusive` | 兩個都給被擋；兩個都不給被擋；只給一個通過 |
| `contract_tiers_required` | 建立模式缺 `data` tier 被擋；`existing.subnet_ids` 缺 `data` 被擋 |
| `services_must_match_containerimage` | `keys(var.services)` 跟 `containerimage/services` 多一個或少一個 → precondition 失敗；一致時通過 |
| `references_must_exist` | `callers` 引用不存在的服務被擋；`data_access` 引用不存在的 data store 被擋 |
| `sg_groups_expand` | `security-group` 的 `security_groups` 包含 `alb`、每個服務、`db`、`db_proxy`（Proxy SG 一律建立） |
| `sg_rules_expand_from_services` | `api = { port = 8080, from_alb = true, data_access = ["db"] }`、`worker = { port = 9000, callers = ["api"] }` → `rules` 有 api 來自 alb 的 8080 ingress、alb 到 api 的 8080 egress、worker 來自 api 的 9000 ingress；規則數等於規則表展開的數量 |
| `service_egress_443_only` | 每個服務一條 egress 443 到 `0.0.0.0/0`（`allow_internet` 不需要），沒有其他對外 egress |
| `db_rules_with_proxy` | `proxy = true` → 服務 → Proxy、Proxy → DB；沒有服務直連 DB |
| `db_rules_without_proxy` | `proxy = false` → 服務 → DB；Proxy SG 沒有任何規則；`sg_db_proxy_id` 仍發布 |
| `http_only_rejects_public_cidr` | `alb_ingress = { https = false, cidrs = ["0.0.0.0/0"] }` → 被擋；`::/0` 也被擋 |
| `http_only_allows_prefix_list_or_cidr` | `https = false`、只給 CloudFront prefix list 或 `203.0.113.0/24` → 通過，ALB 只有 80 的 ingress，規則都沒有 `allow_internet = true` |
| `ingress_needs_a_source` | `cidrs`、`prefix_list_ids` 都空 → 被擋（https 為 true 或 false 都測） |
| `https_opens_443_and_80` | `https = true`、`cidrs = ["0.0.0.0/0"]` → ALB 有 443 與 80 ingress，`allow_internet = true` |
| `publishes_decision_points` | `alb_https`、`db_proxy`、`data_access` 的 JSON 內容照輸入 |
| `sg_key_name_conversion` | 服務 `order-api` → 發布 `sg_order_api_id` |
| `endpoints_in_create_mode` | 建立模式、`interface_endpoints.services = ["ecr.api", "logs"]` → `vpc-interface-endpoints` 的 `vpc_id` 等於 `vpc` 的 `vpc_id`、`allowed_cidrs` 等於 `[vpc_cidr]`、`subnet_ids` 等於 app tier 的 subnet |
| `endpoints_in_existing_mode` | 模式 A、同樣的 `services` → `vpc_id` 等於 `existing.vpc_id`、`allowed_cidrs` 等於 `override_data` 給的 `cidr_block_associations` 全部 CIDR（給兩段，驗證 secondary CIDR 也在）、`subnet_ids` 等於 `existing.subnet_ids["app"]` |
| `endpoints_none_by_default` | `interface_endpoints = {}` → `vpc-interface-endpoints` 的 `services` 是空集合，不發布 `sg_vpce_id` |
| `vpce_sg_key_from_module` | 有 `services` 時 `sg_vpce_id` 等於 `vpc-interface-endpoints` 的 `security_group_id`（`override_module` 或 `override_during = plan` 給固定值） |
| `interface_tier_must_exist_and_not_public` | `subnet_tier = "nope"` 被擋；`subnet_tier = "public"` 被擋；`app` 通過 |
| `existing_vpc_needs_dns` | 模式 A、`override_data` 讓 `enable_dns_support = false` → precondition 失敗；`enable_dns_hostnames = false` 也失敗；兩個都是 true 通過 |
| `existing_mode_does_not_touch_routing` | 模式 A → `vpc` module 沒被呼叫（沒有 route table、IGW、NAT、gateway endpoint、default SG） |
| `nat_json` | `nat` 是 `{mode, ids}` |
| examples（`tests/examples/`） | interface endpoint 數等於 `interface_endpoints.services` 的數量；`nat_mode = "per_az"` 時 NAT 數等於 AZ 數；`alb_ingress.https = false` 時 ALB 沒有 `0.0.0.0/0` ingress；`vpc.flow_log` 為 true 時 flow log 指向 foundation 的 bucket |

#### iam-base

| 檔案 | 用途 |
|---|---|
| `roles.tf` | `iam-role` ×3：execution（inline policy 用 `jsonencode()`）、Proxy（`inline_policies = {}`）、monitoring（`RDSOSMetrics` 的 inline policy）；`source_account` 都設本帳號；role 不加 path |

| run | 斷言 |
|---|---|
| `three_roles` | `iam-role` 被呼叫 3 次 |
| `trust_principals` | execution 只有 `ecs-tasks.amazonaws.com`、Proxy 只有 `rds.amazonaws.com`、monitoring 只有 `monitoring.rds.amazonaws.com`；都有 `source_account` |
| `proxy_role_trust_only` | Proxy role 的 `inline_policies` 是空的 |
| `ecr_pull_only_from_published_repos` | execution role policy 的 ECR 拉映像 action，Resource 恰為 containerimage 發布的 `ecr_<service>_arn` |
| `execution_logs_scoped_by_name` | logs 的 Resource 是 `arn:aws:logs:<region>:<account>:log-group:/ecs/<name_prefix>-*:*` |
| `execution_reads_app_secret_only` | `secretsmanager:GetSecretValue` 的 Resource 恰為 `[app_secret_arn]`；`kms:Decrypt` 只到 foundation 的 key；**沒有任何指向 DB secret 的 Resource** |
| `monitoring_scoped_to_rdsosmetrics` | monitoring policy 的 6 個 logs action，Resource 只有 `RDSOSMetrics` 的 log group 與 log stream |
| `wildcard_resource_allowlist` | 所有 policy 裡 Resource 為 `*` 的只能落在允許清單：`ecr:GetAuthorizationToken`、ECS Exec 的 4 個 `ssmmessages` action、X-Ray 的 `xray:PutTraceSegments`、`PutTelemetryRecords`、`GetSamplingRules`、`GetSamplingTargets`（design §5.4；範本預設不開追蹤，清單先放好讓專案照 `observability.md` 加權限時不會被擋）。反向驗證：暫時加一個 `s3:GetObject` on `*`，測試要紅 |
| `publishes_role_arns` | 發布三個 role ARN |

「沒有萬用 action」「沒有 managed policy」由 `iam-role` module 的 validation 與 S4 保證，不在這裡重測（design §5.4 的兩層測試）。

#### data

| 檔案 | 用途 |
|---|---|
| `database.tf` | `rds`：subnet 是 `subnet_ids_data`、SG 是 `sg_db_id`、`kms_key_arn`、`master_user_secret_kms_key_arn` 與告警 topic 來自 foundation、`monitoring.role_arn` 來自 iam-base；`db_proxy.enabled` 為 true 才傳 `proxy`（`sg_db_proxy_id`、`role_rds_proxy_arn`）；`var.db = null` 時不呼叫 |
| `envs/dev.tfvars`、`envs/prod.tfvars` | dev：`aurora_serverless` 0.5～4 ACU；prod：`aurora_serverless` 2～16 ACU 加 1 個 reader |
| `envs/examples/{poc,standard,high}.tfvars` | 照 design §5.11，三種 `deployment` 都要示範；`rds`、`aurora` 一定要給 `connections_threshold` |

| run | 斷言 |
|---|---|
| `database_json_shape` | 發布的 `database` JSON 有 design §5.6 的全部欄位（沿用 `rds` 測試的 `mock_resource` 給 `master_user_secret` 與端點；或 `override_module` 給 `module.db` 的輸出） |
| `disabled_database` | `var.db = null` → `rds` 沒被呼叫，發布 `{"enabled":false}` |
| `proxy_follows_network` | `db_proxy = {"enabled":false}` → `proxy` 是 null；`true` → `proxy.role_arn` 等於 `role_rds_proxy_arn`、`security_group_ids` 等於 `[sg_db_proxy_id]` |
| `wired_from_upstream` | `subnet_ids`、`security_group_ids`、`kms_key_arn`、`monitoring.role_arn`、`sns_topic_arns` 都等於 SSM 讀到的值 |
| examples（`tests/examples/`） | 對任何範例都成立：`deployment` 跟對應物件一致；`deployment` 是 `rds` 或 `aurora` 時有 `connections_threshold` |

#### iam-app

| 檔案 | 用途 |
|---|---|
| `proxy-policy.tf` | `iam-role-policy`：`role_arn` 是 `role_rds_proxy_arn`；`database.enabled` 為 true 才呼叫，不管 Proxy 開不開 |
| `task-roles.tf` | `iam-role`（`for_each` `containerimage/services`）：預設沒有權限；`data_access` 名單上的服務加讀 DB secret；`ecs_exec_services` 上的服務加 4 個 `ssmmessages` action |

| run | 斷言 |
|---|---|
| `proxy_policy_resource_is_secret` | `iam-role-policy` 的 `role_arn` 等於 `role_rds_proxy_arn`；`secretsmanager:GetSecretValue` 的 Resource 恰為 `database.secret_arn` |
| `proxy_kms_via_service` | `kms:Decrypt` 的 Resource 是 foundation 的 key，Condition `kms:ViaService = secretsmanager.<region>.amazonaws.com` |
| `proxy_policy_even_when_proxy_off` | `db_proxy = {"enabled":false}` 但有 DB → 仍呼叫 `iam-role-policy` |
| `no_db_no_db_permissions` | `database = {"enabled":false}` → 沒有 `iam-role-policy` 呼叫，任何 task role 都沒有 `secretsmanager:` |
| `task_role_per_service` | `iam-role` 對每個服務呼叫一次，trust 只有 `ecs-tasks.amazonaws.com` 並有 `source_account` |
| `data_access_services_read_db_secret` | 名單上的服務 task role 讀 DB secret，Resource 恰為 `secret_arn` |
| `others_cannot_read_db_secret` | 不在名單上的服務沒有 `secretsmanager:` |
| `no_execution_role_changes` | 這個 stack 不對 `role_ecs_execution_arn` 呼叫 `iam-role-policy`（DB secret 只由 task role 讀，design §8.2） |
| `exec_permissions_and_flag` | `ecs_exec_services = ["api"]` → api 有 4 個 `ssmmessages` action、發布 `ecs_exec_api = {"enabled":true}`；worker 兩者都沒有 |
| `ecs_exec_services_must_be_known` | 名單含 `containerimage/services` 以外的名稱 → precondition 失敗 |
| `wildcard_resource_allowlist` | 同 iam-base 的允許清單（design §5.4）；反向驗證同 iam-base。另一個反向：暫時對 api 的 task role 加 `xray:PutTraceSegments` on `*`，測試要**通過** |
| `publishes_task_role_arns` | 發布每個服務的 `role_<service>_task_arn` |

#### loadbalancer

| 檔案 | 用途 |
|---|---|
| `alb.tf` | `alb`：subnet 是 `subnet_ids_public`、SG 是 `sg_alb_id`、`access_logs_enabled` 時用 `alb_log_bucket_name`、告警 topic 來自 foundation；precondition `jsondecode(alb_https).enabled == (var.certificate_arn != null)` |
| `envs/examples/{poc,standard,high}.tfvars` | 照 design §5.11 |

| run | 斷言 |
|---|---|
| `wired_from_upstream` | `subnet_ids`、`security_group_ids`、`sns_topic_arns`、`access_logs.bucket` 都等於 SSM 讀到的值 |
| `tls_must_match_network` | `alb_https = true` 但沒有憑證 → precondition 失敗；`false` 但給了憑證 → 失敗；一致時通過 |
| `publishes_listener_keys` | 發布 6 個 key |
| tfvars（`tests/tfvars/`）與 examples（`tests/examples/`） | 測試讀不到 `-var-file` 的值（R16），所以每個 run 在 `variables {}` 釘住 `certificate_arn`，並用 `override_data` 給對應的 `alb_https`：沒有憑證時 `listener_protocol = "HTTP"`、有憑證時是 `HTTPS`。tfvars 另加一個 run，用 `file()` 讀 `envs/<env>.tfvars` 與 `../network/envs/<env>.tfvars`，比對「這邊有 `certificate_arn`」等於「network 那邊 `https = true`」。**限制**：examples 檔自己寫的憑證值被每個 run 釘住的值蓋掉，驗不到；examples 只驗得到其他設定（access log、idle timeout） |

#### application

| 檔案 | 用途 |
|---|---|
| `ecs.tf` | `ecs-cluster`、`ecs-service`（`for_each` 服務）、`ecs-service-alarms` |
| `observability.tf` | `log-metric-alarm`（`for_each = var.log_alarms`，服務名稱 → `alarms` map，`log_group_name` 取對應服務的 `log_group_name` 輸出、`sns_topic_arns` 是 `alarm_topic_arn`）、`xray`（`sampling_rules = var.xray_sampling_rules`、`groups = var.xray_groups`）；三個變數預設都是 `{}`，什麼都不建（design §5.3） |
| `envs/examples/{poc,standard,high}.tfvars` | `log_alarms`、`xray_sampling_rules`、`xray_groups` 的範例值（design §4.19 的範例：濾掉 health check、5% 抽樣、errors 與 slow 兩個 group） |

| run | 斷言 |
|---|---|
| `services_must_match_containerimage` | 服務設定的 key 跟 `containerimage/services` 不一致 → precondition 失敗 |
| `roles_from_iam_stacks` | `execution_role_arn` 來自 iam-base、`task_role_arn` 來自 iam-app |
| `image_from_containerimage` | `image` 由 `ecr_<service>_url` 加 tfvars 的 tag 組成 |
| `network_from_network_stack` | `subnet_ids` 是 `subnet_ids_app`；`security_group_ids` 是 `[sg_<service>_id]` |
| `listener_from_loadbalancer` | `load_balancer.listener_arn` 是 `listener_arn`；`alb_arn_suffix` 同時給 `ecs-service` 與 `ecs-service-alarms` |
| `database_env` | `data_access` 名單上的服務有 `DB_HOST`、`DB_READER_HOST`、`DB_PORT`、`DB_NAME`、`DB_SECRET_ARN`；DB secret 不出現在 `secrets`；不讀 `proxy_endpoint`、`deployment` |
| `app_secret_via_value_from` | foundation 的 `app_secret_arn` 走 `secrets`（`valueFrom`） |
| `no_db_env_when_disabled` | `database = {"enabled":false}` → 沒有 `DB_*` |
| `exec_flag_from_iam_app` | `enable_execute_command` 等於 `ecs_exec_<service>` 的 `enabled` |
| `alarms_wired_to_foundation_topic` | `ecs-service-alarms` 的 `sns_topic_arns` 是 `alarm_topic_arn` |
| `no_cross_stack_id_in_variables` | `variables.tf` 沒有 ARN／id 型的跨 stack 輸入（grep） |
| `observability_off_by_default` | `log_alarms`、`xray_sampling_rules`、`xray_groups` 都是 `{}` → `log-metric-alarm` 沒被呼叫（或 `alarms = {}`）、`xray` 的兩個 map 都空，沒有任何 filter、alarm、rule、group |
| `log_alarms_wired` | `log_alarms = { api = { ... } }` → `log-metric-alarm` 的 `log_group_name` 是 api 服務的 log group、`sns_topic_arns` 是 `[alarm_topic_arn]` |
| `log_alarms_services_known` | `log_alarms` 的 key 不在 `containerimage/services` → precondition 失敗 |
| examples（`tests/examples/`） | 對任何範例都成立：`xray` 的 rule 數等於 `xray_sampling_rules` 的數量、`log-metric-alarm` 的每個 alarm 都接 `alarm_topic_arn` |

**驗收指令**

```bash
scripts/validate.sh templates/project-infra/infra/terraform
ls templates/project-infra/infra/terraform/                                         # 恰為 8 個 stack
for f in templates/project-infra/infra/terraform/*/.terraform.lock.hcl; do echo "$f $(grep -c 'zh:' "$f")"; done   # 8 份，每份大於 0
grep -h 'version *=' templates/project-infra/infra/terraform/*/.terraform.lock.hcl | sort -u   # 只有一個版本
grep -rnE '^\s*resource\s+"aws_' templates/                                          # 只有 foundation 的 aws_secretsmanager_secret
grep -rn 'aws_iam_policy_document\|data "aws_ssm_parameter"\|terraform_remote_state' templates/   # 預期沒有輸出
grep -rn 'source *= *"git::' templates/                                              # 預期沒有輸出
scripts/validate.sh
```

**完成定義**：8 個 stack 各自 `init -backend=false`／`validate`／`test`（含 dev、prod、examples 的 `-var-file` 執行）全過；8 份 `common.tf` 完全相同；16 份 tfbackend 的 key 格式正確；8 份 lock 檔都有 `zh:` 雜湊；`http_only_rejects_public_cidr`、`tls_must_match_network`、`services_must_match_containerimage`、`proxy_policy_resource_is_secret`、iam 兩個 stack 的 `wildcard_resource_allowlist` 經反向驗證確認有效。主 agent 驗證後 commit。

**不在本次範圍**：WAF Web ACL 本身；Redis；部署 workflow；跨帳號 assume role 的實測；「讀的 key 必須是更早的 stack 發布的」靜態檢查；state bucket 本身；應用程式專用 DB 帳號；`secret` module。

### Phase 9：使用文件與 `vendor-modules.sh`

**檔案清單**

| 路徑 | 用途 |
|---|---|
| `docs/guides/consuming-modules.md` | 怎麼引用（`git::https://github.com/<org>/<repo>.git//modules/<name>?ref=<name>-v<semver>`）、私有 repo 的 git 認證、Git source 只能 `ref` 釘死、從範本複製出去時把相對路徑改成 git source（一個 module 一行的手改方式，加一次改完的指令）、升版、讀 CHANGELOG、升級到真 registry 時消費端改什麼 |
| `docs/guides/project-infra-standard.md` | 8 個 stack 與 apply 順序、stack 只呼叫 module（例外清單）、iam 為什麼拆兩個、單一決定點、SSM 合約（含 tier 調整時 key 怎麼變）、流量規格對照表與 IP 規劃公式、環境切換四件事、客戶自管模式 A／B |
| `docs/guides/releasing-modules.md` | 怎麼改 module、semver 規則、release-please 流程、一個 commit 只動一個 module、**第一次發版前在整體驗收通過的 commit 上手動打 19 個 `<module>-v0.1.0` tag 的步驟與指令**（design §3.5、決策 27）、module 的註解只用英文 |
| `docs/guides/observability.md` | 照 design §4.20 的表：ADOT collector 設定檔範例（OTLP receiver、batch、memory_limiter、濾掉 health check、`awsxray` exporter）、`iam-app` 給 task role 的 X-Ray 與 CloudWatch 權限（`Resource = "*"` 的四個 X-Ray 動作）、`iam-base` 給 execution role 拉 ADOT 映像的權限、`xray` module 的 sampling rule 怎麼配與 remote sampling 的前提、`iam-app` 的 `tracing` 當單一決定點（原規劃是 `tracing_<service>`，決策 36 之後改成範本已接好、單一個 `tracing` 清單）、`log-metric-alarm` 怎麼接應用程式的 JSON log。HCL 片段要跟 `modules/ecs-service/examples/adot-sidecar/` 逐行對照（guide 不會被 CI 驗證），collector 照 example 寫 `essential = false` 並說明理由；interface endpoint 的 `xray` 服務由 network 的 `interface_endpoints` 加 |
| `docs/guides/delivering-to-customer.md` | FDE：`vendor-modules.sh`、`terraform providers mirror`（給客戶環境用，不是本 repo 的驗證流程）、客戶自管資源的 SSM 合約、客戶環境差異怎麼回報 |
| `docs/guides/team-roles.md` | 四個團隊的責任與交接點，對到 CODEOWNERS |
| `scripts/vendor-modules.sh` | 只做 `git::...?ref=<tag>` → vendored 相對路徑（design §8.7）。tag 的 module 名稱清單從 `modules/` 目錄讀 |
| `README.md`（修改） | 補上 guides 的連結 |

**驗證任務**（全部在 scratchpad 做）

| 情境 | 預期 |
|---|---|
| 暫存 git repo 打 `ssm-read-v0.1.0`（本機 tag，不 push），對一個 source 是 git 格式的暫存目標 repo 跑腳本 | 目標出現 `vendor/modules/ssm-read/`，source 改寫成相對路徑，`VERSIONS` 有該行；`scripts/validate.sh <暫存目標路徑>` 過 |
| tag 不存在、格式錯、前綴跟 module 不一致、module 名稱含 `../` | 各自回非 0 |
| 目標不是 git repo、有未提交變更、tag 內容含 symlink | 拒絕執行 |
| 目標 `.tf` 有一行 source 指向同 module 但 ref 不同 | 那一行不改寫，回報出來 |
| 照 `consuming-modules.md` 的指令把範本複製到暫存目錄後改 source | 8 個 stack 裡每個 module 的 source 都變成 git 格式（只檢查文字） |
| 文件內的 repo 內路徑 | 每個都 `test -e` 得到 |

**驗收指令**

```bash
shellcheck -S warning scripts/vendor-modules.sh
grep -nE '\beval\b' scripts/vendor-modules.sh      # 預期沒有輸出
grep -rhoE '`(modules|templates|scripts|docs)/[^` ]+`' docs/guides README.md | tr -d '`' | sort -u | while read -r p; do test -e "$p" || echo "missing: $p"; done
grep -rnE '[a-z-]+/v[0-9]' docs/guides README.md   # 預期沒有斜線格式的 tag
git tag                                            # 預期沒有輸出：tag 留給人在發版時手動打
```

**完成定義**：六份文件結論放最前面、指令可照抄；暫存演練輸出貼在回報裡。主 agent 驗證後 commit。

**不在本次範圍**：core app team 的 repo；HCP Terraform；實際打 tag。

### Phase 9 補充：客戶 repo 驗證、mirror repository、X-Ray 追蹤接進範本

Phase 9 的六份文件與 `vendor-modules.sh` 完成後，又有四件事在 Phase 10 之前做完，共 4 個 commit。

| commit | 內容 | 影響的測試 |
|---|---|---|
| `6fcd3e2` `docs(template): mark outputs as human-only and set D21 release levels` | 8 份 `outputs.tf` 檔頭註明下游不讀、跨 stack 只走 SSM；D21 依 §3.5 分級（`ecs-service` 是 PATCH，`rds` 與 `vpc-interface-endpoints` 是 MINOR） | 無 |
| `79a6520` `fix(scripts): validate vendored modules and stacks in customer repos` | `scripts/validate.sh` 能在客戶 repo 裡驗證 vendored 的 module 與 stack（路徑對照到本 repo 的規則），`delivering-to-customer.md` 對應補上 | 沒有改任何 module 或 stack 的測試 |
| `ff68ca4` `feat(template): add mirror repositories for external images` | `containerimage` 新增 `mirrored_images`（每個名稱一個 `<project>-<env>-mirror-<name>` repository，發布 `mirrored_images`、`ecr_mirror_<name>_url`、`ecr_mirror_<name>_arn`）；`iam-base` 讀它，execution role 的 ECR 拉取權限涵蓋 mirror；`observability.md` 補上沒有 NAT 時的做法 | `containerimage`、`iam-base` 的測試增加 |
| `feat(template): wire x-ray tracing into the template` | X-Ray 追蹤完整接進範本，預設關閉，見下 | `iam-app` 30 到 37、`application` 48 到 70、`network` 90 到 97 |

**本次的範圍**：使用者要求「第一版就讓 X-Ray 能完整用起來」。這推翻 design 決策 32 的後半句（ADOT、collector 設定、task role 的 X-Ray 權限由專案自己決定）與 §4.20「範本預設不開追蹤，放進範本會讓每個專案都背一個預設關閉的 sidecar」的理由；新增決策 36。`modules/` 一個檔案都沒動：`ecs-service` 的 `sidecars` 介面夠用。

| stack | 變更 |
|---|---|
| `iam-app` | 新增 `var.tracing`（`set(string)`，預設 `[]`）、`terraform_data.tracing_services_are_known`（必須是 `containerimage/services` 的子集）、被追蹤服務的 task role 多一個 `tracing` policy（四個 `xray:` 動作，`Resource = "*"`）、發布 `tracing`（JSON 陣列的 String，已排序，沒有時 `[]`） |
| `application` | 新增 `var.adot_collector = { tag, source }`（`tag` 不得 `latest`、`source` 只收 `public`、`mirror`）、`adot-collector.yaml`、`tracing.tf`（讀 `iam-app/tracing`，被追蹤的服務加 collector sidecar 與兩個 OTEL 環境變數；沒追蹤時第二個 `ssm-read` 的 key 清單是空的）、四個 precondition（有追蹤要有 `adot_collector`、mirror 模式 `containerimage` 要有 `adot-collector`、沒有 NAT 要用 mirror、沒有 NAT 要有 `xray`／`ecr.api`／`ecr.dkr` endpoint） |
| `network` | 新增發布 `interface_endpoints`（JSON 陣列的 String，已排序，沒有時 `[]`）；不動 SG（服務 SG 本來就有 443 egress，endpoint SG 對 VPC CIDR 開 443）；不動 S3 gateway endpoint（`modules/vpc` 預設已有） |

**驗證方式**：TDD。先寫會紅的測試再實作；實作改壞後測試確實轉紅（漏一個 X-Ray 動作、所有服務都加 policy、所有服務都掛 collector、放行 `latest`、不檢查 mirror、沒有 NAT 放行 public 映像、漏檢查 `xray` endpoint、`interface_endpoints` 永遠發布 `[]`）。每個有改的 stack 都更新了 `envs/*.tfvars`、`tests/tfvars`，有 examples 的 stack 更新 `tests/examples`；`application/envs/examples/high.tfvars` 示範 `adot_collector`。範本預設不開追蹤。

**驗不到、留給 §7.3 第 13 項的**：collector 在真實 task 裡是否 healthy、trace 是否進 X-Ray、`v0.43.1` 在 ECR Public 是否存在、沒有 NAT 時 mirror 映像加 endpoint 是否拉得到映像與送得出 trace、remote sampling 是否生效。

### Phase 10：整體驗收

由主 agent 自己做，不派 subagent。

| 檢查 | 指令或做法 | 預期 |
|---|---|---|
| 乾淨狀態全綠 | 刪掉 `.cache/` 後跑 `scripts/validate.sh` | 全綠（19 個 module、它們的 example、8 個 stack 與各自的 `-var-file` 執行） |
| 沒留下產物 | `git status --short --ignored` | 只有 `.cache/` 與 `docs/slides/` 是 ignored |
| 沒有禁止的指令 | `grep -rnE 'terraform (plan\|apply\|providers lock)\|aws ' scripts/ .github/` | 只出現在註解或禁止說明 |
| module 只用英文 | `grep -rnP '[^\x00-\x7F]' modules/ --include='*.tf' --include='*.tftest.hcl'` | 沒有輸出 |
| IAM 與 SG 的邊界 | S4；另外 `grep -rn 'resource "aws_security_group"' modules/vpc/` | S4 通過；`modules/vpc/` 只有 `aws_default_security_group` |
| stack 只呼叫 module | S8 | 通過 |
| tag 格式一致 | release-please 設定（19 個 package）、guides、ADR 0001、各 module README、`vendor-modules.sh` | 都是 `<module>-v<semver>`，起始 `0.1.0` |
| stack 清單、SSM key、單一決定點 | 範本 README、`project-infra-standard.md`、ADR 0002、design §5.3、§5.6 | 一致 |
| 介面與 design 一致 | 19 個 module 的變數名、預設值、輸出對照 design §4.2–§4.21 | 不一致要揭露，不自行改 design |
| 測試數量 | 彙整每個 module／stack 的 `n passed` | 與各 Phase 回報一致 |
| commit 歷史 | `git log --format='%ae %s'`、`git remote -v` | 47 個 commit（含 Phase 9 補充 4 個與 Phase 10 的 1 個），每個 module 的 commit 只動該 module 目錄，author 都是 `<author-email>`；沒有 remote；沒有 tag |

### 增補：Phase 11–16（LLM 與 AgentCore，design 決策 37–53）

**結論**：在 v1 上增補 7 個新 module、範本的 `agent` stack、`rds-v0.2.0`（Data API 加 `deployment`、`database_name` 兩個輸出）、`s3-bucket-v0.2.0`（`never_expire`）。分 6 個 Phase，規則全部沿用上面的〈全局規則〉（硬性限制 10 條、TDD 節奏、一個 module 一個 commit、主 agent 自己重跑驗證才 commit、不 push）。19 個既有的 `<module>-v0.1.0` tag 留在 `28a8647`，整個增補過程不得移動。

| Phase | 內容 | 只能動的路徑 | commit |
|---|---|---|---|
| 11 | 設計文件：design §4.23–§4.32、§5.3〈增補：`agent` stack〉、§5.4 增補、§5.6、§7.1、§7.3 第 15–25 項、§8.8、§9 的 J50–J70、決策 37–53、D22–D29、§9.5；本文件 Phase 11–16 | `docs/design/v1/` | 1：`docs(design): add llm and agentcore addendum` |
| 12 | 共用設定、`rds-v0.2.0`（Data API 與兩個新輸出）、`s3-bucket-v0.2.0`（不過期） | `release-please-config.json`、`.release-please-manifest.json`、`README.md`、`docs/adr/0001-*`、`docs/guides/releasing-modules.md`、`scripts/validate.sh`、design §3.2 那一行；`modules/rds/`；`modules/s3-bucket/` | 3：`chore(repo): register llm modules and forbid guardrail versions`、`feat(rds): add data api switch and deployment outputs`、`feat(s3-bucket): add never_expire for content buckets` |
| 13 | 7 個新 module，可以平行 | 各自的 `modules/<name>/` | 7，一個 module 一個 |
| 14 | 範本接線：新增 `agent`，改 `containerimage`、`network`、`iam-base`、`data`、`iam-app`、`application` | `templates/project-infra/` | 1：`feat(template): add agent stack for agentcore and bedrock` |
| 15 | 文件：新增 `docs/guides/llm-agentcore.md`，更新其他 guide 與範本 README | `docs/guides/`、`templates/project-infra/infra/README.md`、`README.md` | 1：`docs(guides): add llm and agentcore guide` |
| 16 | 整體驗收、manifest 登記、手動打 tag | 視驗收結果；tag 由人打 | 0–2 |

**順序的理由**

| 順序 | 理由 |
|---|---|
| 11 先 | 介面、SSM key、決策先定案，後面的 Phase 才有依據；這個 Phase 不動任何程式 |
| 12 在 13 之前 | release-please 的兩個 JSON、`validate.sh`、README 是每個新 module 都會碰的共用檔，先由一個 commit 改好，13 才能平行；S9 先就位，新 module 一寫錯就被擋。`rds`、`s3-bucket` 的 MINOR 跟新 module 沒有檔案重疊，放在 12 是因為它們是 14 的前提（`data` 要讀 `rds` 的新輸出、`agent` 要用 `never_expire` 建語料 bucket），而且各自要單獨一個 commit |
| 13 在 14 之前 | 範本的測試會 init 所有 module |
| 15 在 14 之後 | guide 要引用範本的真實檔案與變數名 |

**每個 Phase 都要跑的檢查**（主 agent 在 commit 前重跑）

```bash
for m in $(ls modules | grep -vE '^(bedrock-|agentcore-|log-delivery$)'); do git rev-parse --short "$m-v0.1.0^{commit}"; done | sort -u   # 只有 28a8647，舊 tag 沒動
git tag -l '*-v0.1.0' | wc -l                      # Phase 16 之前是 19
grep -rnP '[^\x00-\x7F]' modules/ --include='*.tf' --include='*.tftest.hcl'   # 沒有輸出
git diff --stat HEAD                               # 只有該 Phase 允許的路徑
```

#### Phase 11：設計文件（docs only）

**檔案**：`docs/design/v1/design-docs.md`、`docs/design/v1/implement-process.md`。

**驗收**

```bash
git diff --stat                                    # 只有 docs/design/v1/ 兩個檔
# 文件引用的本 repo 路徑都存在；新 module 與新 stack 的路徑是「待建」，列出來人工確認
grep -ohE '`(modules|templates|scripts|docs)/[^` ]+`' docs/design/v1/*.md | tr -d '`' | grep -v '[<*{]' | sort -u \
  | while read -r p; do test -e "$p" || echo "待建或錯誤: $p"; done
grep -nE '[a-z-]+/v[0-9]' docs/design/v1/design-docs.md | grep -v 'v1/'   # 沒有斜線格式的 tag
```

「待建或錯誤」的輸出只能是 7 個新 module、`templates/project-infra/infra/terraform/agent`、`docs/guides/llm-agentcore.md` 底下的路徑，以及 `modules/rds/tests/data-api.tftest.hcl`、`modules/rds/tests/deployment-outputs.tftest.hcl`、`modules/s3-bucket/tests/never-expire.tftest.hcl`；另外有 4 個是 v1 原文引用參考專案時省略了專案前綴（docs/reports 的客戶自管網路報告、docs/spec/infra.md、modules/app-platform/iam.tf、scripts/lib/env-guard.sh），不是本 repo 的路徑，維持原樣。其他的都要修；增補段落引用參考專案一律寫成 `project-a/…`、`project-b/…`、`project-c-…/` 開頭的完整相對路徑。保密檢查：文件不得出現參考專案的真實名稱、客戶名稱、本機絕對路徑、真實帳號 id（用 `grep -P` 加 `\b` 對照名單檢查，名單不寫進 repo）。

#### Phase 12：共用設定、`rds-v0.2.0`、`s3-bucket-v0.2.0`

**commit 1（`chore(repo)`）**

| 路徑 | 改什麼 |
|---|---|
| `release-please-config.json` | `packages` 加 7 個 module，格式同既有的 19 個 |
| `.release-please-manifest.json` | 7 個新 module 都登記 `0.1.0`（比照決策 27：第一個 tag 由人打）；`rds`、`s3-bucket` 維持 `0.1.0`，Phase 16 才改 |
| `scripts/validate.sh` | 新增 S9：`resource "aws_bedrock_guardrail_version"` 出現在 `modules/` 或 `templates/` 任何 `.tf` 就失敗；註解與輸出格式同 S1–S8 |
| `README.md` | module 清單改成 26 個，照 design §1 的分類加一組「LLM 與 AgentCore」 |
| `docs/adr/0001-*`、`docs/guides/releasing-modules.md` | 「19 個」改成「v1 的 19 個加增補的 7 個」；手動打 tag 的步驟加上 Phase 16 的 9 個 tag（7 個 `<module>-v0.1.0`、`rds-v0.2.0`、`s3-bucket-v0.2.0`） |
| design §3.2 | tag regex 加 7 個 module 名稱 |

**commit 2（`feat(rds)`）**：照 design §4.31（決策 39、52）。`variables.tf` 加 `data_api`（含 validation）、`cluster.tf` 加 `enable_http_endpoint = var.data_api`、`outputs.tf` 加 `deployment`、`database_name` 兩個輸出（值取變數）、README 的輸入表與輸出表、`examples/aurora-serverless-proxy` 不動（預設維持原行為）、`CHANGELOG.md` 加 `## 0.2.0` 一段（寫明兩件事：新變數 `data_api`，既有消費端 plan 應零差異，這是讀 schema 推論，未以 plan 驗證；新輸出 `deployment`、`database_name`，D21 的待辦）、新測試檔 `tests/data-api.tftest.hcl` 與 `tests/deployment-outputs.tftest.hcl`。

| run | 斷言 |
|---|---|
| `data_api_off_by_default_aurora` | `aurora`，不給 `data_api` → `aws_rds_cluster.this[0].enable_http_endpoint == false` |
| `data_api_off_by_default_serverless` | `aurora_serverless`，同上 |
| `data_api_on_aurora` | `data_api = true` → `true` |
| `data_api_rejected_for_rds` | `deployment = "rds"` 配 `data_api = true` → `expect_failures = [var.data_api]` |
| `data_api_false_passes_for_rds` | `deployment = "rds"` 配 `data_api = false` → 通過（反向） |
| `deployment_output_rds`、`deployment_output_aurora`、`deployment_output_serverless`（`deployment-outputs.tftest.hcl`） | 三種型態各自 `output.deployment` 等於輸入 |
| `database_name_output_follows_input` | `database_name = "kb"`（非範例預設值）時 `output.database_name == "kb"` |

**commit 3（`feat(s3-bucket)`）**：照 design §4.32（決策 51、J67）。`variables.tf` 的 `expiration_days` 預設改 `null`、validation 改成條件式，新增 `never_expire`（`nullable = false`、互斥 validation）；`main.tf` 加 `local.expiration_days`、rule id 依 `never_expire` 切換、`expiration` 改成 dynamic；README 的用途改成「log 與內容 bucket」、輸入表與「刻意不做」（versioning 仍不做）；`CHANGELOG.md` 加 `## 0.2.0`（寫明既有消費端 plan 應零差異、`expiration_days` 傳 null 從失敗改成當成 90）；`examples/basic` 不動；新測試檔 `tests/never-expire.tftest.hcl`（mock 與 `override_resource` 照既有測試檔開頭的寫法）。**既有的 `tests/s3-bucket.tftest.hcl` 一行不改。**

| run | 斷言 |
|---|---|
| `never_expire_drops_expiration` | `never_expire = true` → rule 的 `expiration` 長度 0、`abort_incomplete_multipart_upload` 的 `days_after_initiation == 7`、`id == "abort-incomplete-uploads"`、`status == "Enabled"` |
| `default_keeps_expire_rule` | 不給兩個變數 → `id == "expire-objects"`、`expiration.days == 90` |
| `explicit_null_days_means_90` | `expiration_days = null` → `expiration.days == 90`（不是不過期） |
| `null_never_expire_means_false` | `never_expire = null` → `expiration.days == 90` |
| `days_without_never_expire` | `never_expire = false`、`expiration_days = 30` → `expiration.days == 30`（互斥的反向） |
| `never_expire_rejects_expiration_days` | `never_expire = true`、`expiration_days = 30` → `expect_failures = [var.never_expire]` |

**驗收**

```bash
shellcheck -S warning scripts/validate.sh
jq -r '.packages | keys[]' release-please-config.json | wc -l      # 26
jq -r 'keys[]' .release-please-manifest.json | wc -l               # 26
jq -r 'to_entries[] | .value' .release-please-manifest.json | sort -u   # 只有 0.1.0
git show --stat <feat(rds) 的 commit> -- modules/rds/tests/ | grep -vE 'data-api|deployment-outputs'   # 既有 5 個測試檔沒有改動
git show --stat HEAD -- modules/s3-bucket/tests/ | grep -v never-expire        # 既有測試檔沒有改動
scripts/validate.sh modules/rds                                    # 回報 n passed（Phase 5 是 108，加 9 個）
scripts/validate.sh modules/s3-bucket                              # 回報 n passed（Phase 7 是 28，加 6 個）
scripts/validate.sh templates/project-infra/infra/terraform/foundation   # 兩個 log bucket 的測試不改仍全過
scripts/validate.sh                                                # 全量全綠
```

S9 的反向驗證在 scratchpad 的暫存複本做（同 Phase 6）：

| 情境 | 預期 |
|---|---|
| 暫存的 module 宣告 `resource "aws_bedrock_guardrail_version"` | S9 失敗 |
| 暫存的範本 stack 宣告同一個 resource | S9 失敗 |
| 只有 `resource "aws_bedrock_guardrail"` | 通過 |
| 註解裡出現 `aws_bedrock_guardrail_version` 字樣 | 通過（只比對 `resource "..."` 宣告） |

`rds` 的反向驗證：暫時把 `enable_http_endpoint` 寫死 `true`，`data_api_off_by_default_*` 要紅；暫時拿掉 validation，`data_api_rejected_for_rds` 要紅；暫時把 `deployment` 輸出寫死 `"aurora"`，`deployment_output_rds` 要紅。`s3-bucket` 的反向驗證：暫時讓 `never_expire = true` 也送 `expiration`，`never_expire_drops_expiration` 要紅；暫時拿掉互斥 validation，`never_expire_rejects_expiration_days` 要紅；暫時拿掉 `coalesce`，`explicit_null_days_means_90` 要紅；暫時把 rule id 寫死成 `abort-incomplete-uploads`，既有測試檔不會紅、`default_keeps_expire_rule` 要紅（這條證明新檔補到既有測試沒鎖的地方）。

#### Phase 13：7 個新 module（可平行，一個 module 一個 commit；已完成）

| module | commit | 測試數 |
|---|---|---|
| `log-delivery` | `0c79364` | 28 |
| `bedrock-guardrail` | `ea0a365` | 45 |
| `bedrock-inference-profile` | `71e7550` | 14 |
| `agentcore-memory` | `8708820` | 24 |
| `agentcore-runtime` | `1948aba` | 47 |
| `agentcore-gateway` | `4048dbf` | 54 |
| `bedrock-knowledge-base` | `36d6ee5` | 50 |

主 agent 對每個 module 重跑 `scripts/validate.sh modules/<name>`，全部通過，並另外確認 aws provider 6.69.0 在 plan 時拒收 Memory 保留天數 3（`value must be between 7 and 365, got: 3`）。git 歷史的 commit 順序是 `bedrock-inference-profile` → `agentcore-runtime` → `agentcore-memory` → `bedrock-knowledge-base` → `log-delivery` → `agentcore-gateway` → `bedrock-guardrail`，跟下面計畫的順序不同；module 之間沒有檔案重疊，結果相同。

跟計畫的差異（設計面的細節回寫在 design 各 module 章節，總表在 design §9.4 D30–D36）：

- `agentcore-memory` 的保留天數下限是 7，不是 3（provider 的限制，D33）；strategy 的 `namespaces` 送進 provider 的 `namespace_templates`。
- `log-delivery` 的 `replace_triggered_by` 改經 `terraform_data.source_arn[each.key]`：Terraform 1.15.8 不能在 `replace_triggered_by` 用 `each.value.source` 索引別的 resource（D35）。
- `bedrock-guardrail` 的 `tier_config` 是屬性指派，不是 block；「至少一種 policy」是 resource precondition（D30）。
- 各 module 多了幾條 validation（gateway 的 `--`、S3 URI、Lambda ARN；KB 的 `role_arn`；inference profile 的名稱字元；runtime 的 SG 不重複），對應的 run 已補進 design §7.1。
- 核對程式碼時另外發現、實作者沒有回報的：`bedrock-inference-profile` 的 profile 沒有加 `Name` tag（D31）。

以下是當時的計畫，保留作為對照。


每個 module 照〈每個 module／stack 的 TDD 節奏〉做，run 表以 design §7.1 的增補表為準；固定檔案照〈module 的固定檔案〉，**唯一差別是 `versions.tf` 的 aws 是 `>= 6.69, < 7.0`**（design 決策 43）。README 要有「要修掉的坑」一節，內容照 design 各節。

| subagent | module | 為什麼放一起 | 主要 example |
|---|---|---|---|
| A | `bedrock-guardrail` | validation 最多，`PROMPT_ATTACK`、tier 與 profile 的交叉條件要一個人寫完 | `examples/basic`（`STANDARD` 加 profile）、`examples/zh-tw-standard`（中文 topic 與 content filter） |
| B | `agentcore-runtime`、`log-delivery` | project-a 的 Runtime 與它的 log／trace delivery 是同一組資源 | runtime：`examples/vpc`；log-delivery：`examples/runtime-logs-and-traces` |
| C | `agentcore-memory`、`bedrock-inference-profile` | 兩個都小 | 各一個 `examples/basic` |
| D | `agentcore-gateway` | 型別對應欄位的交叉 validation 最多，而且沒有部署過的參考 | `examples/lambda-and-mcp-server` |
| E | `bedrock-knowledge-base` | 沒有任何參考實作，單獨一個 | `examples/aurora-pgvector`（README 附 design §4.30 的 SQL） |

commit 順序：`log-delivery` → `bedrock-guardrail` → `bedrock-inference-profile` → `agentcore-memory` → `agentcore-runtime` → `agentcore-gateway` → `bedrock-knowledge-base`。commit message：`feat(<module>): add <一句話> module`。

**每個 module 的驗收**

```bash
scripts/validate.sh modules/<name>                 # 回報 n passed；example 也一起跑
grep -n 'version' modules/<name>/versions.tf       # aws ">= 6.69, < 7.0"
grep -rn 'resource "aws_iam_' modules/<name>/      # 沒有輸出（S4 也會擋）
grep -rn 'ignore_changes' modules/agentcore-runtime/   # 沒有輸出（只檢查 runtime）
grep -rn 'replace_triggered_by' modules/log-delivery/  # 有一處
git show --stat HEAD                               # 只動 modules/<name>/
```

**每條 validation 兩個方向**：design §7.1 增補表的每一格「被擋」都要有一個 `expect_failures` run，括號裡的「通過」都要有一個不帶 `expect_failures` 的 run。回報時附上：RED 的失敗輸出（至少一個 assert 是條件不成立而失敗）、每個 module 至少兩個「改壞實作測試要紅」的例子（例如 guardrail 拿掉 `topic_policy_config` 的 `tier_config`、runtime 只送 `idle_runtime_session_timeout`、gateway 讓 MCP server target 也帶 `gateway_iam_role`、KB 把 `custom_metadata_field` 預設成 `"custom_metadata"`）。

**測試的 mock 寫法**：`bedrock-guardrail` 的 `data.aws_region`、`data.aws_caller_identity`、`data.aws_partition` 用 `override_data`（R1）；`agentcore-runtime` 的 `workload_identity_details`、`agentcore-gateway` 的 `gateway_url` 這類 computed 值，要斷言時用 `override_resource` 加 `override_during = plan`（R3）。

**完成定義**：7 個 module 各自全綠，全量 `scripts/validate.sh` 全綠；`git tag -l '*-v0.1.0' | wc -l` 仍是 19。

**不在本次範圍**：任何範本 stack；credential provider、OpenAPI／Smithy target、`s3-vectors`、Bedrock 告警、`iam-role` 的 `aws:SourceArn`（design 決策 40、47）。

#### Phase 14：範本接線（已完成，commit 見 git log）

| stack | run 區塊數（Phase 14 之前） | 這次動到什麼 |
|---|---|---|
| `agent`（新） | 91（—） | 整個 stack：`agent.tftest.hcl` 86、`tests/tfvars/` 1、`tests/examples/` 4 |
| `containerimage` | 48（38） | Runtime 清單與每個 Runtime 一個 repository |
| `network` | 89（78） | Runtime 的 SG、`agent_data_access`、拒收 `bedrock-agentcore-control` |
| `iam-base` | 32（25） | Runtime execution role、KB 與 Gateway role（只有 trust）、`agent_service_roles` |
| `data` | 33（28） | `data_api`、`database` JSON 的 `cluster_arn`、`data_api`，`deployment`、`name` 改取 `rds` 輸出 |
| `iam-app` | 53（35） | Runtime、KB、Gateway role 的權限，task role 的 `agent` policy，`agent_access` |
| `application` | 67（57） | 注入 Runtime ARN 與模型、guardrail、KB 的 id，沒有 NAT 時的 endpoint 檢查 |
| `foundation`、`loadbalancer` | 22、27（不變） | 沒有改 |

run 區塊數是數各 stack `tests/**/*.tftest.hcl` 裡的 `run "` 區塊，9 個 stack 共 462 個；`validate.sh` 回報的 `n passed` 比這個多，因為 `tests/tfvars/` 對 dev、prod 各跑一次、`tests/examples/` 對每個範例各跑一次。主 agent 對 9 個 stack 重跑 `scripts/validate.sh`，全部通過；9 份 `common.tf` 一字不差（S5）。

跟計畫的差異（設計面的細節回寫在 design §5.3、§5.4、§5.6、§7.1、§7.3、§8.8，總表在 design §9.4 D37–D46）：

- `agent/knowledge_bases` 每個 KB 多發布 `data_source_ids`（data source key → id），給 `StartIngestionJob` 用（D39）。
- design 的 precondition 表多數實作成變數 validation，`guards.tf` 只留要讀 SSM 才判斷得了的；`subnet_tier` 存不存在由讀 `subnet_ids_<tier>` 失敗擋下；design 那句「跨帳號時 KB 不得引用模型」跟 J66 矛盾，照 J66 不擋（D37）。
- `agent` 不讀 `foundation`；Runtime 的 `OTEL_*` 固定六個；log delivery 的 destination 名稱是 `<project>-<env>-<rt>` 與 `<project>-<env>-xray_traces`（D38）。
- `iam-base` 的 Runtime log 權限拆成 log group 與 log stream 兩條；Runtime 的 DB 權限與 `DB_*` 只看 `agent_data_access` 的 `db`；沒有任何權限的 Runtime 不附加 policy；`application` 只在 `agent_access` 有列服務時才讀 `agent`（D40）。
- 安全審查後的修正：`agent/agentcore_gateway` 多發布 `tool_schema_arns`，Gateway role 多 `ReadToolSchemas`（D42）；KB 的 `credentials_secret_arn` 必須是帶 6 字元後綴的完整 ARN，`iam-app` 在授權端再檢查一次（D43）；沒有 NAT 時連 DB 的 VPC Runtime 要 `secretsmanager` endpoint（D44，未實測）；範本 README 寫了已部署環境的升級順序（D45）。審查列出但這一輪不修的 M1、M4、L1–L5 記在 design §8.8（D46）。
- 計畫裡的單一 run 多半拆成「被擋」與「通過」兩個 run，名稱照程式碼列在 design §7.1〈增補：範本 Phase 14 的測試〉（D41）。

以下是當時的計畫，保留作為對照。

照 design §5.3〈增補：`agent` stack〉與 §5.4 增補。新增 `templates/project-infra/infra/terraform/agent/`，檔案同其他 stack（`versions.tf`、`providers.tf`、一字不差的 `common.tf`、`variables.tf`、`ssm-inputs.tf`、`ssm-outputs.tf`、依主題拆的 `.tf`、`outputs.tf`、`guards.tf`、`envs/{dev,prod}.{tfvars,tfbackend}`、`envs/examples/{poc,standard,high}.tfvars`、`tests/`、`tests/tfvars/`、`tests/examples/`）。lock 檔照 Phase 8〈lock 檔的產生方式〉原文產生（硬性限制第 9 條的例外延伸到這一個 stack，design J65），產生後確認 aws 版本跟其他 8 個 stack 相同。

**每個 stack 要加的 run**（design §5.3、§5.4 增補已列出的不重複）

| stack | run | 斷言 |
|---|---|---|
| `containerimage` | `agent_runtimes_default_empty` | 預設不建任何 `ecr_agent`，發布 `agent_runtimes = "[]"` |
| `containerimage` | `agent_runtime_name_clash` | Runtime 名稱等於服務名稱或 mirror 名稱被擋；不撞名通過 |
| `containerimage` | `agent_runtime_name_too_long` | `<project>_<env>_<rt>` 49 字被擋；48 字通過 |
| `network` | `agent_sg_rules_expand` | Runtime 的 443 egress 與 `data_access` 展開後的規則 key 集合（比照 `sg_rules_expand_from_services`） |
| `network` | `agent_runtimes_must_match_containerimage` | key 不一致被擋；一致通過 |
| `network` | `control_plane_endpoint_rejected` | `interface_endpoints.services` 含 `bedrock-agentcore-control` 被擋；`bedrock-agentcore` 通過 |
| `network` | `publishes_agent_data_access` | 預設發布 `{}` |
| `iam-base` | design §5.4 增補的 `iam-base` 三列 | — |
| `data` | `data_api_passed_and_published` | `db.data_api = true` 時傳給 `rds`，`database` JSON 有 `cluster_arn` 與 `data_api = true`；預設時 `data_api = false` |
| `data` | `database_json_from_rds_outputs` | `database` JSON 的 `deployment`、`name` 等於 `module.db[0].deployment`、`module.db[0].database_name`（`override_module` 給跟 `var.db` 不同的值，證明取的是輸出不是變數；決策 52）；既有的 `database_json_shape` 不改仍通過 |
| `agent` | `nothing_by_default` | 所有輸入預設時，七種 module 呼叫都是 0 個，發布的 JSON 都是空的（`{}`、`{"enabled":false}`） |
| `agent` | `guardrail_defaults_standard` | `guardrails` 只給名稱與一個 filter 時，傳給 module 的 tier 是 `STANDARD` |
| `agent` | `invoke_arns_shapes` | 三種模型設定（沒有 prefix、有 prefix、tracked）各自的 `invoke_arns`；foundation-model 的 region 一律是 `*`；`global` prefix 多一條 region 與帳號都空白的 foundation-model ARN |
| `agent` | `runtime_env_only_from_ssm_and_stack` | Runtime 的環境變數只有 design 那張表的名稱加 `environment`；DB 的值等於 `override_data` 餵的 `database`；`TRACELOOP_TRACE_CONTENT` 預設 `"false"`、`environment` 明寫 `"true"` 時是 `"true"`；`environment` 用了 `MODEL_ID_X` 這種範本名稱被擋 |
| `agent` | `nat_none_requires_endpoints` | `nat.mode = "none"`、VPC Runtime、`interface_endpoints` 少 `bedrock-runtime` 或少 `bedrock-agentcore` 各被擋；都有時通過；`external` 時不檢查；PUBLIC Runtime 時不檢查；有 tracing 少 `xray`、有 `bedrock_invoke` 少 `sts`、有 KB 少 `bedrock-agent-runtime` 各被擋 |
| `agent` | `nat_none_blocks_gateway` | `nat.mode = "none"` 且有 Runtime `gateway = true` 被擋；有 NAT 時通過 |
| `agent` | `kb_requires_aurora_data_api` | `database` 是 `rds` 型態、或 `data_api = false`、或 `agent_service_roles` 沒有 `knowledge_base` 各被擋；三者都滿足時通過 |
| `agent` | `kb_corpus_bucket` | 每個 KB 一個 `s3-bucket` 呼叫，名稱 `<project>-<env>-kb-<key>-<account_id>`、`never_expire = true`、`kms_key_arn = null`、`log_delivery = []`；KB 的每個 data source 的 `bucket_arn` 都等於同一個 KB 的 bucket；`knowledge_bases = {}` 時沒有任何 `s3-bucket` 呼叫；名稱超過 63 字被擋（決策 51） |
| `agent` | `kb_secret_not_master` | `credentials_secret_arn` 等於 `override_data` 餵的 `database.secret_arn` 被擋；不是 Secrets Manager ARN、region 或帳號不同各被擋；另一個 secret ARN 通過，且原樣傳給 module 的 `aurora.credentials_secret_arn`（決策 53） |
| `agent` | `publishes_kb_bucket_and_secret` | `knowledge_bases` JSON 有 `bucket_name`、`bucket_arn`、`credentials_secret_arn`，值等於 bucket 的輸出與 tfvars |
| `agent` | `public_runtime_without_db` | PUBLIC Runtime 在 `agent_data_access` 上被擋 |
| `agent` | `cross_account_rules` | `bedrock_invoke.session_seconds = 899` 被擋（900 通過）；同時有 `tracked` 模型被擋 |
| `agent` | `publishes_agent_keys` | 發布的 key 集合等於 design §5.6 增補列出的 `agent` key 加每個 Runtime 一個 `agent_runtime_<rt>` |
| `iam-app` | design §5.4 增補的 `iam-app` 各列（含「KB role 不讀 master secret」「KB role 只讀自己的語料 bucket」） | — |
| `iam-app` | `agent_access_must_reference_known` | `agent_access` 的服務不在 `containerimage/services`、或引用 `agent` 沒發布的 key，各被擋 |
| `application` | `no_agent_access_no_change` | `agent_access = {}` 時 task definition 跟加這個功能之前完全相同（迴歸，比照決策 36） |
| `application` | `agent_env_injected` | 有列的服務多 `AGENTCORE_RUNTIME_ARN_<RT>` 等環境變數，值等於 `override_data` 餵的 `agent_runtime_<rt>`；沒列的服務沒有 |
| `application` | `nat_none_requires_endpoints_for_services` | 同 `agent` 那條，對象換成 `agent_access` 有列的服務 |

**驗收**

```bash
scripts/validate.sh                                # 全量全綠：9 個 stack 各自的 test 加 dev、prod、examples 的 -var-file 執行
grep -c 'zh:' templates/project-infra/infra/terraform/agent/.terraform.lock.hcl   # 大於 0
grep -h 'version = ' templates/project-infra/infra/terraform/*/.terraform.lock.hcl | sort -u   # 只有一個版本
grep -n 's8_allowed' -A3 scripts/validate.sh       # 例外清單沒有變長
```

反向驗證（暫時改壞、確認變紅、改回）：`agent` 永遠發布 `{}`；`invoke_arns` 把 region 寫死成 `var.aws_region`；`iam-app` 給所有服務 `InvokeAgentRuntime`；guardrail profile 的 id 寫成 `*`；`application` 對沒列的服務也注入 Runtime ARN；拿掉 `nat_none` 的 `bedrock-agentcore` 檢查；KB role 的 secret Resource 改回 `database.secret_arn`；拿掉 `agent` 的「不等於 master secret」precondition；語料 bucket 改成 `never_expire = false`；`data` 的 `deployment` 改回取 `var.db`。

**完成定義**：上面全綠；`common.tf` 9 份一致（S5）；18 份 tfbackend 的 key 格式正確（S6）；範本預設的 dev、prod tfvars 不開任何 AI 功能（`agent` 什麼都不建）。

**不在本次範圍**：Lambda 本身（Gateway 的 Lambda ARN 是外部輸入）、資料庫 migration 與 KB 帳號的建立（專案的事，SQL 在 design §4.30）、KB 帳號的 secret（專案在範本外建，design 決策 53；要不要改由範本建見 design §9.5 Q1）、Bedrock 告警、Memory 的自訂 strategy。KB 的語料 bucket 改由 `agent` 建（design 決策 51，取代 J50），在本次範圍內。

#### Phase 15：文件

| 路徑 | 內容 |
|---|---|
| `docs/guides/llm-agentcore.md`（新增） | 結論先講：範本已接好、預設關閉，開一個 Runtime 要改哪幾份 tfvars、照什麼順序 apply。然後是：Runtime 換版（只改 `image_tag` 再 apply，不用 API 換版）與映像要求（arm64、OTEL 的啟動方式，照 project-a 的經驗寫，標未實測）；guardrail 三條紅線（tier、不發佈版本、input 不放 PII 遮罩）與「資源就位不等於生效」；guardrail profile 的 IAM 為什麼是 region `*`；跨帳號的 A、B 兩側分工與 B 側要做的事；沒有 NAT 時要開哪些 endpoint；`TRACELOOP_TRACE_CONTENT`；Transaction Search（`aws/spans`）的前置條件；模型使用權的檢查方式；**Knowledge Base：design §4.30 的 SQL 原樣收錄（含第 4 步的 KB 專用帳號與 GRANT）、欄位對照表、〈帳號的密碼〉四個步驟的可照抄指令（建 secret 時用 `foundation` 的 `kms_key_arn`、密碼不進 shell history、換密碼時兩邊一起改）、`data` → 建 secret 與 migration → `agent` 的順序、語料 bucket 的名稱怎麼查（`agent/knowledge_bases` 的 `bucket_name`）與上傳權限由誰給、`StartIngestionJob` 怎麼跑、權限不夠時只在那張表補、不改成 schema 層級的 `ALL`；PostgreSQL 14 以前 `public` schema 的 `CREATE` 要不要收回由專案決定** |
| `docs/guides/project-infra-standard.md` | 9 個 stack 與 apply 順序、新的單一決定點、SSM 合約表的增補列 |
| `docs/guides/observability.md` | Runtime 的追蹤走 `agent_runtimes[*].tracing`（不是 `iam-app/tracing`），兩者的差別 |
| `templates/project-infra/infra/README.md` | 9 個 stack、合約表、流量規格表加 AgentCore ENI 的說明、第一次部署有 KB 時的順序（含專案建 secret、跑 migration、設密碼三步） |
| `README.md` | guides 連結加一份 |

**驗收**（同 Phase 9 的寫法）

```bash
grep -rhoE '`(modules|templates|scripts|docs)/[^` ]+`' docs/guides README.md templates/project-infra/infra/README.md \
  | tr -d '`' | sort -u | while read -r p; do test -e "$p" || echo "missing: $p"; done   # 沒有輸出
grep -rnE '[a-z-]+/v[0-9]' docs/guides README.md   # 沒有斜線格式的 tag
diff <(sed -n '/^```sql/,/^```/p' docs/guides/llm-agentcore.md | head -40) \
     <(sed -n '/^```sql/,/^```/p' docs/design/v1/design-docs.md | head -40)   # KB 的 SQL 與 design 一致
```

**完成定義**：guide 結論在最前面、指令可以照抄、未實測的地方都有標；主 agent 對照範本的真實變數名逐一核對 HCL 片段（guide 不會被 CI 驗）。

#### Phase 16：整體驗收與打 tag

由主 agent 自己做，不派 subagent。

| 檢查 | 指令或做法 | 預期 |
|---|---|---|
| 乾淨狀態全綠 | 刪掉 `.cache/` 後跑 `scripts/validate.sh` | 全綠：26 個 module、它們的 example、9 個 stack 與各自的 `-var-file` 執行 |
| 舊 tag 沒動 | 每支 Phase 前的 19 個 tag 跑 `git rev-parse "<tag>^{commit}"` | 全部是 `28a8647` |
| module 只用英文 | 同 Phase 10 | 沒有輸出 |
| 靜態規則 | S1–S9 | 通過 |
| 介面與 design 一致 | 7 個新 module、`rds`、`s3-bucket` 的變數名、預設值、輸出對照 design §4.24–§4.32；範本的 key 對照 §5.6 增補 | 不一致要揭露，回寫 design §9.4，不自行改 design 的決策 |
| 測試數量 | 彙整每個 module／stack 的 `n passed` | 與 Phase 12–14 的回報一致 |
| commit 歷史 | `git log --format='%ae %s' 28a8647..HEAD` | Phase 11–15 的 commit，每個 module 的 commit 只動該 module 目錄，author 都是 `<author-email>`；沒有 remote |

驗收通過後，主 agent 用一個 commit 把 `.release-please-manifest.json` 的 `rds` 與 `s3-bucket` 改成 `0.2.0`（`chore(repo): record rds and s3-bucket 0.2.0 as released`），理由同決策 27：release-please 把 manifest 的版本當成已發布。**tag 由人打**，在這個 commit 上手動打 9 個：7 個 `<module>-v0.1.0`、`rds-v0.2.0`、`s3-bucket-v0.2.0`，指令寫在 `docs/guides/releasing-modules.md`（Phase 12 已加）。主 agent 不打 tag。

```bash
git tag -l '*-v0.1.0' | wc -l      # 打完是 26
git tag -l 'rds-v*'                # rds-v0.1.0、rds-v0.2.0
git tag -l 's3-bucket-v*'          # s3-bucket-v0.1.0、s3-bucket-v0.2.0
```

## 驗證指令的具體寫法

### `scripts/validate.sh`

| 步驟 | 做法 | 理由 |
|---|---|---|
| 0. 離線環境 | 清掉 `AWS_*`、設 `AWS_CONFIG_FILE`／`AWS_SHARED_CREDENTIALS_FILE=/dev/null`、`AWS_EC2_METADATA_DISABLED=true` | 第二道防線 |
| 0a. 快取 | `TF_PLUGIN_CACHE_DIR=.cache/plugins`、`TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true`；不設 `TF_CLI_CONFIG_FILE` | 見「provider 下載與快取」 |
| 1. 找目錄 | 沒給參數時：`modules/*`、`modules/*/examples/*`、`templates/project-infra/infra/terraform/*`；給參數時只跑那些路徑底下的（可以是 repo 外的路徑） | 不從 repo 根目錄掃：`docs/slides/` 有 `.tf`，本機存在、CI 不存在 |
| 2. fmt | `terraform fmt -check -recursive` 對上一步的根目錄 | — |
| 3. 靜態規則 | 下表 S1–S8，任一條失敗就整支失敗，不進到第 4 步之後 | — |
| 4. init | 每個目錄 `TF_DATA_DIR=.cache/tf-data/<路徑>` 加 `init -backend=false -input=false`；範本 stack 加 `-lockfile=readonly` | 不在目錄裡留 `.terraform/`；lock 檔被改動就失敗 |
| 5. validate | `terraform validate` | — |
| 6. test | 有 `tests/` 才跑 `terraform test` | — |
| 6a. tfvars test | 範本 stack：對 `envs/dev.tfvars`、`envs/prod.tfvars` 跑 `test -test-directory=tests/tfvars -var-file=...`；有 `envs/examples/` 的 stack 對每個範例跑 `test -test-directory=tests/examples -var-file=...` | 測的是 tfvars 檔本身，不在測試裡複製一份值 |
| 7. tflint | `tflint --chdir=<dir> --config=<repo>/.tflint.hcl` | 只用內建 ruleset |
| 8. 清掉 module 的 lock 檔 | `modules/*` 底下 init 產生的 `.terraform.lock.hcl` 跑完就刪 | module 不提交 lock |
| 9. 彙整 | 一個目錄失敗不中斷，最後列出全部失敗目錄 | — |

**第 3 步的靜態規則**（design §5.6）

| # | 規則 |
|---|---|
| S1 | 每個 `*.tftest.hcl`（含 `tests/tfvars/`、`tests/examples/`）都宣告 `mock_provider "aws"` |
| S2 | `resource "aws_ssm_parameter"` 只能出現在 `modules/ssm-publish/`（範圍含 `modules/` 與 `templates/`） |
| S3 | `data "aws_ssm_parameter"` 只能出現在 `modules/ssm-read/`；`modules/ssm-read/` 不得出現 `.value` |
| S4 | `resource "aws_iam_*"` 只能出現在 `modules/iam-role/` 與 `modules/iam-role-policy/`（後者只允許 `aws_iam_role_policy`）；`aws_security_group`、`aws_vpc_security_group_ingress_rule`、`aws_vpc_security_group_egress_rule` 只能出現在 `modules/security-group/` 與 `modules/vpc-interface-endpoints/`；`aws_default_security_group` 只能出現在 `modules/vpc/`；範本 stack 都不得出現（`d770756` 起；Phase 6 時的版本允許 `modules/vpc/`） |
| S5 | 範本 8 個 stack 的 `common.tf` 雜湊相同 |
| S6 | 每份 `envs/<env>.tfbackend` 的 `key` 等於 `<project>-<env>/<stack>/terraform.tfstate`；`envs/examples/` 不得有 tfbackend |
| S7 | `modules/rds/variables.tf` 不得宣告名稱含 `password` 的變數；`modules/` 底下不得出現 `random_password` |
| S8 | 範本 stack 裡的 `resource "aws_*"` 只能是 design §5.3 例外清單上的型別與 stack（目前只有 `foundation` 的 `aws_secretsmanager_secret`）；`terraform_data` 這類不碰 AWS 的資源允許 |
| S9 | 增補（Phase 12 實作）：`resource "aws_bedrock_guardrail_version"` 不得出現在 `modules/` 與 `templates/`（design 決策 46） |

「讀的 key 必須是更早的 stack 發布的」第一版不做（design §5.6、決策 14）。

### `.github/workflows/ci.yml`

不用改（Phase 0 已完成）：`permissions: contents: read`，不給 `id-token: write`，不用 `aws-actions/configure-aws-credentials`，不讀 `secrets.*`；步驟是 setup terraform 1.15.8 → 安裝 tflint 0.64.0 → 快取 `.cache/plugins` → `scripts/validate.sh`。

## subagent 分工方式

### 原則

- 每個 Phase 派執行 subagent（`tdd-guide`），背景執行；Phase 7A–D 派了 4 個，7E 依 J7 派 3 個。執行 subagent 只能透過 `scripts/validate.sh` 跑 terraform（Phase 8 的 lock 檔產生除外），不 commit。
- 主 agent 等回報後，自己重跑該 Phase 的驗收指令與全量 `scripts/validate.sh`，看 diff 範圍有沒有越界；結果跟回報不一致就如實告訴使用者。全綠才 commit，一個 module 一個 commit。
- 每個 Phase 結束停下來，讓使用者決定要不要進下一個。

### 派工 prompt 要帶的資訊

```
你是 infra-platform 的 Phase <N> 執行者（負責 <module 清單或範圍>）。
專案：infra-platform（Terraform module monorepo，AWS provider ~> 6.0，terraform 1.15.8），分支 main。

基準線：HEAD <hash>；scripts/validate.sh 全綠，各目錄測試數：<目錄: n passed 清單>。

背景文件：docs/design/v1/design-docs.md（介面以它為準，本次對應 §<x.y>）、
  docs/design/v1/implement-process.md 的 Phase <N> 節。

硬性限制（逐條，原文）：<全局規則的 10 條，含允許／禁止的 terraform 指令表>。
  - terraform 只能透過 scripts/validate.sh 跑，不得直接手打 terraform 指令。
  - modules/ 底下的註解、description、error_message 只用英文，不可中英混雜，不准 icon／emoji。
  - 不准設 TF_CLI_CONFIG_FILE 指到本機 provider mirror（會在 .cache/plugins 留下 symlink，之後 init 失敗）。
  - 你不 commit，commit 由主 agent 驗證後做。
已知可用：override_during = plan 在 1.15.8 可用；寫法參考 modules/ssm-publish/tests/ssm-publish.tftest.hcl。

本次要做：<檔案清單>；TDD：<run 表>；每個 validation 正反兩向；
  回報要附 RED 輸出、反向驗證的失敗輸出、n passed。

不在本次範圍：<清單>。只能動 <允許的目錄>；需要動範圍外的檔案，或 design 的介面寫不下去，停下來回報，不要順手做、不要改 design。

回報格式：完成的檔案、每個測試檔的 n passed、validate.sh 全量結果、跟計畫的差異、未決問題。
```

## 風險與緩解

| # | 風險 | 症狀 | 緩解 |
|---|---|---|---|
| R1 | mock provider 對 data source 回隨機字串 | ARN validation 失敗、JSON key 在 `jsondecode` 失敗，看起來像 module 寫錯 | 範本測試對 `module.in.data.aws_ssm_parameter.this["<stack>/<key>"]` 逐 key 給 `override_data`；`kms-key`、`s3-bucket` 的 `data.aws_caller_identity`、`data.aws_elb_service_account` 同樣要 override |
| R2 | `aws_iam_policy_document` 在 mock 下的 `json` 是隨機字串 | 斷言不到 policy 內容 | policy 一律 `jsonencode()`，傳進 `iam-role`／`iam-role-policy`（design §5.4） |
| R3 | `command = plan` 時 computed 屬性是 unknown | 斷言 `arn`、`id` 報「無法判斷」 | 優先用 `override_resource`／`override_data` 加 `override_during = plan`（1.15.8 已驗證可用），其次 `command = apply` |
| R4 | 用 `TF_CLI_CONFIG_FILE` 指到本機 mirror | `.cache/plugins` 留下 symlink，之後 init 失敗 | 禁止（硬性限制與派工 prompt 都寫）；出事時刪掉整個 `.cache/` |
| R5 | 開了 `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE` 時產生範本 lock 檔 | lock 檔只有本機平台的雜湊，CI 的 `-lockfile=readonly` 失敗 | 照 Phase 8〈lock 檔的產生方式〉不用快取產生，驗收檢查每份都有 `zh:` |
| R6 | 範本測試會 init 全部 19 個 module 與它們的 provider | 第一次跑很慢 | plugin cache 共用；CI 快取 `.cache/plugins` |
| R7 | `-test-directory` 的子目錄會不會被一般 `terraform test` 掃到 | 會的話，`tests/tfvars/`、`tests/examples/` 在沒有 `-var-file` 時被跑到而失敗 | 未驗證，Phase 8 第一個 stack 先實測；會掃到就改目錄名（例如 `tests-tfvars/`）並同步改 `validate.sh` |
| R8 | `rds` 的 `master_user_secret` 是 nested list | 範本 data stack 取 `[0]` 失敗 | 沿用 `modules/rds/tests/` 的 `mock_resource` 寫法，或用 `override_module` 給 `module.db` 的輸出 |
| R9 | RDS Proxy 建立時 role 還沒有讀 secret 的權限 | 未驗證：可能建立失敗，也可能建立成功但連不上 | 照 design §5.4 的兩種對策；dev 預設不開 Proxy、prod 開 |
| R10 | `kms-key` 給各服務的條件 key 沒有在實環境驗證 | 實際 apply 時服務用不了這把 key | design §4.10 已標未驗證，列在 design §7.3 |
| R11 | `security-group` 的 `peer_group` 解析成 id 在 mock 下是 unknown | 斷言 `referenced_security_group_id` 失敗 | `override_resource` 給 `aws_security_group.this` 固定 id，加 `override_during = plan` |
| R12 | 範本 8 個 stack 的測試要 override 的 key 很多 | 漏一個就整個測試檔失敗 | 每個測試檔開頭集中寫齊，個別 run 只覆寫要測的值 |
| R13 | release-please 本機沒有、也不能 push 驗證 | 設定寫錯要等上 GitHub 才知道 | 只驗 JSON；`releasing-modules.md` 標「未實測」 |
| R14 | 範本複製出去忘了把相對路徑改成 git source | 專案 repo 的 source 指不到東西 | 範本 README 第一步就寫；`consuming-modules.md` 寫一次改完的指令 |
| R15 | tflint 用變數的預設值求值 local（Phase 8 實測） | 物件變數預設是 `null` 時，tflint 對 `var.x.attr` 這類 local 報錯，`terraform validate` 與 `test` 卻都過 | 相關 local 寫成 null 安全：`try(var.vpc.flow_log, false)`、`var.x == null ? ... : ...` |
| R16 | 測試檔的 `override_*` 與 `variables {}` 讀不到 `-var-file` 的值（Phase 8 實測） | 想在 tfvars／examples 測試裡依 tfvars 的值給對應的 SSM 值（例如憑證有無對應 `alb_https`）寫不出來；`terraform test` 也讀不到 module 的輸入值 | 每個 run 自己釘住相關變數並給一致的 override；跨檔一致性改用 `file()` 讀 tfvars 比對；要斷言 module 輸入時，先把輸入放進 local 再斷言 local |

## 已判斷與已拍板

### 我已判斷（附理由，使用者不同意再改）

| # | 判斷 | 理由 |
|---|---|---|
| J1 | Phase 6 一次改完共用檔，Phase 7 才開始 | 7 個新 module 都會碰到 release-please 設定與 `validate.sh`，先改完才能平行 |
| J2 | Phase 7 分 4 個 subagent，`iam-role` 與 `iam-role-policy` 同一個人寫 | 兩者的 validation 要一字不差；其餘依大小與相似度分組 |
| J3 | Phase 7 每個 module 的驗收加一條非 ASCII 字元的 grep | 把「只用英文、沒有 icon」從約定變成檢查 |
| J4 | S8 只限制 `resource "aws_*"`，`terraform_data` 這類不碰 AWS 的資源允許 | design §5.3 明文允許；S8 的文字寫的是 `resource "<type>"`，這裡照 §5.3 的意思實作 |
| J5 | 範本測試優先用 `override_during = plan`，其次 `command = apply` | Phase 1 已證實可用，plan 較快 |
| J6 | 反向驗證只在暫存複本或工作目錄暫時做，不留痕跡 | 證明測試有效，又不污染 diff |
| J7 | 7E 分 3 個 subagent：`log-group`＋`log-metric-alarm`、`xray`、`ecs-service` 的 `sidecars` | 動既有 module 的那份迴歸要求最嚴，單獨一個人；兩個 CloudWatch Logs 的 module 放一起 |
| J8 | `sidecars` 的新斷言放在新檔 `tests/sidecars.tftest.hcl` | 「既有測試檔一行都不改」用 `git diff --stat` 就驗得到 |
| J9 | 範本 iam 兩個 stack 的 `wildcard_resource_allowlist` 先把 4 個 X-Ray 動作放進允許清單，範本本身不給 X-Ray 權限 | design §5.4 的允許清單已含 X-Ray；範本預設不開追蹤，專案照 `observability.md` 加權限時才不會被自己的測試擋 |

### 已拍板決策（本文件特有；其餘以 design §9.2 為準）

| # | 決策 |
|---|---|
| P1 | 一個 module 一個 commit，非 module 的 Phase 各一個；主 agent 驗證後才 commit；直接在 `main`，不 push，author `<author-email>` |
| P2 | 執行型 subagent 只能透過 `scripts/validate.sh` 跑 terraform；唯一例外是 Phase 8 產生範本 lock 檔，照原文執行 |
| P3 | 不准 `terraform providers lock`；不准用 `TF_CLI_CONFIG_FILE` 指到本機 mirror |
| P4 | `validate.sh` 設 `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true`（`19608d4`） |
| P5 | 第一個 tag 由人手動打 19 個 `<module>-v0.1.0`，本 repo 的實作流程不打 tag（`541ae3c`、design 決策 27） |
| P6 | `modules/` 底下的註解、`description`、`error_message` 只用英文，禁止 icon（design 決策 26） |
| P7 | 新增 7 個 module（再加 7E 的 3 個、7F 的 `vpc-interface-endpoints`，共 19 個）；IAM 只由 `iam-role`、`iam-role-policy` 建；SG 只由 `security-group`、`vpc` 建；stack 只呼叫 module，例外只有 foundation 的 secret 容器（design 決策 24、25、28、29、30） |
| P8 | tfvars（dev、prod、examples）不在測試裡複製值，由 `validate.sh` 對範本 stack 另跑 `terraform test -var-file=...` |
| P9 | Phase 7E：先一個 docs commit（設計文件）、一個 chore commit（release-please 加 3 個 module、README 改成 18 個），再 3 個新 module 與 `feat(ecs-service)` 的 sidecars 各一個 commit；`ecs-service` 既有測試檔一行都不改（design 決策 31–33） |
| P10 | 增補 Phase 11–16 沿用 P1–P6；19 個既有 tag 留在 `28a8647`，不得移動（design 決策 37） |
| P11 | Phase 12 的 `feat(rds)` 是單獨一個 commit，既有 5 個測試檔一行不改；`rds` 發 `0.2.0`，內容是 `data_api` 加 `deployment`、`database_name` 兩個輸出（MINOR，design 決策 39、52、§4.31） |
| P12 | Phase 16 驗收後，manifest 的 `rds`、`s3-bucket` 由主 agent 改成 `0.2.0`；7 個 `<module>-v0.1.0`、`rds-v0.2.0`、`s3-bucket-v0.2.0` 由人手動打，主 agent 不打 tag（比照 P5、design 決策 27） |
| P13 | Phase 14 的 `agent` lock 檔照 Phase 8 原文產生，是硬性限制第 9 條例外的延伸（design J65） |
| P14 | Phase 12 的 `feat(s3-bucket)` 是單獨一個 commit，既有 `tests/s3-bucket.tftest.hcl` 一行不改；`s3-bucket` 發 `0.2.0`（MINOR，design 決策 51、§4.32）。KB 用專用資料庫帳號、secret 由專案在範本外建（design 決策 53）；範本不建 secret 容器，除非使用者對 design §9.5 Q1 改變決定 |

### 跟 design-docs 不一致的點

上一輪列的三點（§5.1 的樹缺 `application/envs/examples/`、§5.11 沒有觀測性的列、S3 沒寫 `each.value` 例外）design 都已改正。這一輪核對後：

| # | 位置 | 狀況 | 建議 |
|---|---|---|---|
| 1 | design §5.6 S4 的說明欄 | 還寫「`scripts/validate.sh` 現在的 S4 允許 `modules/vpc`，要跟著改」。`d770756` 已經改好 | design 拿掉這句，或改成「`d770756` 起生效」 |

### 待補資訊

| 項目 | 現在的寫法 | 誰補 |
|---|---|---|
| GitHub org 與 repo 名稱 | `<org>`、`<repo>` | 使用者 |
| CODEOWNERS 的 team slug | `@<org>/platform-team`、`@<org>/core-app-team`、`@<org>/project-app-reps`、`@<org>/fde-team` | 使用者 |
| state bucket 命名與由誰建立 | `<state-bucket>` | 使用者 |
| 範本 `common.tf` 的帳號對照表 | `dev = ["111111111111"]`、`prod = ["222222222222"]` | 專案複製範本時改 |
