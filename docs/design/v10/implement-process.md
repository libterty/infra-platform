# infra-platform v10 實作流程：帳號層治理 module 與 templates/account-baseline

> 狀態：還沒開始。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 [`design-docs.md`](./design-docs.md) 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 10 個 Phase（J0–J9）。

- **module（J1–J5）**：11 個新 module 加 2 個 minor 版，每個 Phase 合併後發版、HCP 登記並從消費端抓一次。
  - J1 的 S4 例外要先合併。
  - J2–J5 的目錄互不重疊，可以在各自的 worktree 平行做。
- **範本（J6–J9）**：module 全部在 HCP 上之後才做，因為範本 stack 從 HCP 抓 module（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

沿用 v8、v9 的教訓：

- **release PR 衝突**：多個 release PR 同時存在時，每個都從 main 重建再 squash。
- **Actions API 額度**：連續發版會用完，用完時等額度重置再重跑。
- **worktree**：
  - 裡面不准 `git add -A`，只 stage 明確的路徑；`.cache` 是 symlink。
  - 每個 worktree 用自己的 `TF_PLUGIN_CACHE_DIR`，避免共用 plugin cache 互相改寫。
- **合併**：每個 check 都是 `pass` 才合併；不要在等待迴圈後面無條件接 `gh pr merge`。

## 限制（每個 Phase、每個 subagent 都適用）

- **不碰 AWS**：
  - 不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；tflint 不開 `deep_check`。
  - Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
  - 不准跑 `terraform providers lock`；範本只用 aws provider，lock 檔從既有 aws-only stack 複製。
- **環境與佔位值**：
  - code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
  - 帳號 `111111111111`（dev）、`222222222222`（sit）；資安帳號佔位 `333333333333`、organization ID `o-exampleorgid`，只用在 module 測試與 REFERENCE。
  - 網域 `example.com`、`<state-bucket>`、`<state-kms-key-arn>`。
- **module 規則**：
  - module 不建 `aws_iam_*`，只有 `account-security-defaults` 的 `aws_iam_account_password_policy` 例外（design K3）；也不建 SG（S4），不用 `random_password`（S7）。
  - 範本 stack 只呼叫 module（S8）。
- **commit 與 PR**：
  - 一個 commit 只動一個 module 目錄；新 module 與既有 module 的 minor 版都用 `feat(<module>)`。
  - PR 用 merge commit 合併（[`releasing-modules.md`](../../guides/releasing-modules.md)）。
- **文字**：`description` 用台灣繁體中文；註解與 `error_message` 用英文。README 表格由 terraform-docs 產生（S11）。
- **範本變動範圍**：example2–example6、project-infra 不能有任何變動。每個 Phase 驗收時看 `git diff origin/main --stat` 確認。

## Phase 表

| Phase | 內容 | 狀態 | PR |
|---|---|---|---|
| J0 | v10 設計文件與實作流程 | 待審 | |
| J1 | S4 例外；`s3-bucket` 0.6.0、`sns-alarm-topic` 0.2.0；`account-security-defaults`、`access-analyzer` | | |
| J2 | `cloudtrail`、`config-recorder` | | |
| J3 | `guardduty`、`securityhub`、`inspector` | | |
| J4 | `backup-vault`、`backup-plan`、`budgets` | | |
| J5 | `organization-delegated-admin` | | |
| J6 | 範本骨架、`foundation`、`defaults`、`iam` | | |
| J7 | `audit`、`detect` | | |
| J8 | `backup`、`budget` | | |
| J9 | 文件、根 README、標準指南、全量驗證、價格查證、design §14 | | |

## 每個 Phase 的做法與驗收

### module 共用做法（J1–J5）

1. 先寫 `tests/` 的正向與反向情境（design §9），跑 `validate.sh modules/<name>`，確認反向情境因為缺 validation 而失敗。
2. 寫 `variables.tf`、`main.tf`、`outputs.tf`、`versions.tf`（`required_version >= 1.10`、aws `>= 6.0, < 7.0`）、`examples/basic`，跑到全部通過。
3. 固定的安全設定逐一改壞一次，確認有測試失敗（mutation check），再還原。
4. `README.md` 的說明段落用中文寫，表格由 terraform-docs 產生。
5. `release-please-config.json` 加 package；根 README 的 module 表加一列。這兩個共用檔由主 agent 在 rebase 之後整合。
6. 合併、release PR 合併、tag 出現之後，在 HCP 登記並確認狀態 ok。

驗收（每個 module）：

- `scripts/validate.sh modules/<name>` 通過。
- 反向情境各自被正確的 validation 擋下。
- `git diff origin/main --stat` 只動到這個 Phase 該動的目錄。
- 發版：tag 等於 manifest，HCP 狀態 ok。

### J0：設計文件

- 做法：`docs/design/v10/design-docs.md`、`implement-process.md`。`docs:` commit，不發版。
- 驗收：使用者看過設計，並說可以開始。

### J1：S4 例外與帳號層基礎

1. `chore(repo)` commit：`scripts/validate.sh` 的 S4 加 `modules/account-security-defaults` 的 case，只准 `aws_iam_account_password_policy`。用暫存目錄的假 module 確認：該 module 寫 `aws_iam_role` 仍被擋，其他 module 寫 `aws_iam_account_password_policy` 也被擋。
2. `s3-bucket` 0.6.0、`sns-alarm-topic` 0.2.0（design §5.12）：既有測試不改就全部通過。
3. `account-security-defaults`、`access-analyzer`（design §5.6、§5.10）。

### J2：稽核

- 做法：`cloudtrail`、`config-recorder`（design §5.1、§5.2）。
- 額外：查 AWS 文件確認 CloudTrail 的 log group ARN 格式，結果記到 design §14。

### J3：偵測

- 做法：`guardduty`、`securityhub`、`inspector`（design §5.3–§5.5）。
- 額外：查 AWS 文件確認 FSBP 與 CIS 的標準 ARN、CIS 的最新版本、Security Hub CSPM 改名對 provider 的影響，結果記到 design §14。

### J4：備份與成本

- 做法：`backup-vault`、`backup-plan`、`budgets`（design §5.7–§5.9）。
- 額外驗收：`backup-vault` 的 mutation check 要包含「拿掉 compliance acknowledged 的檢查」。

### J5：Organizations

- 做法：`organization-delegated-admin`（design §5.11）。
- 額外：查 AWS 文件確認 GuardDuty、Security Hub、Inspector 的委派是否還要同時寫 `aws_organizations_delegated_administrator`，結果記到 design §14。

### J6：範本前段

- 做法：建 `templates/account-baseline/infra/terraform/`，結構照 example6（`stacks.sh`、`check-ssm-contract.sh`、每個 stack 的 `common.tf` 一致）。做 `foundation`、`defaults`、`iam`（design §8.1）。
- 驗收：這 3 個 stack 通過；`check-ssm-contract.sh` 通過。

### J7：稽核與偵測

- 做法：`audit`、`detect`（design §8.1、K5–K7、K13）。
- 驗收：
  - `audit` 的測試確認 trail 是 multi-region、log file validation 開、用 CMK；兩個 metric filter 告警送資安 topic。
  - `detect` 的測試確認 Security Hub 訂閱 FSBP 與 CIS，EventBridge rule 只轉高嚴重度。

### J8：備份與預算

- 做法：`backup`、`budget`（design §8.1、K10–K12）。
- 驗收：`backup` 的測試確認 vault deny delete、governance lock、selection tag 是 `backup = "daily"`。

### J9：收尾

1. `infra/README.md`、`REFERENCE.md`、`architecture.drawio.svg`。REFERENCE 要有：
   - Organizations 分工（design §4.2）
   - 其他 region 的啟用
   - 既有 trail、recorder、detector 的 import
   - Backup tag 約定
   - destroy 之前的注意事項
2. 根 README：module 數改成 91，分類表加新 module，範本表加 `account-baseline`。
3. `docs/guides/project-infra-standard.md` 提到範本清單的地方加 `account-baseline`。
4. 查官方價格，更新 design §10、§13。
5. 全量 `scripts/validate.sh`；設計與實作的差異寫進 design §14；這份的 Phase 表填狀態與 PR 編號。

驗收（里程碑完成的條件）：

- 全部 run 綠燈，包括 release PR。
- 91 個 module 的 latest tag 等於 main 與 manifest。
- HCP 狀態 91 個 ok。
- 沒有開著的 PR，遠端只剩 `main`。
