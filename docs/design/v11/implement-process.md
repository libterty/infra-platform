# infra-platform v11 實作流程：CI/CD module 與 templates/example9

> 狀態：L0–L7 全部完成（2026-10-30）。實作時跟設計不同的決定記在 design §14。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 [`design-docs.md`](./design-docs.md) 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 8 個 Phase（L0–L7）。

- **module（L1–L3）**：3 個新 module 加 3 個 minor 版，每個 Phase 合併後發版、HCP 登記並從消費端抓一次。L1–L3 的目錄互不重疊，可以在各自的 worktree 平行做。
- **範本（L4–L7）**：module 全部在 HCP 上之後才做，因為範本 stack 從 HCP 抓 module（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

沿用 v8–v10 的教訓：

- **release PR 衝突**：多個 release PR 同時存在時，每個都從 main 重建再 squash。
- **Actions API 額度**：連續發版會用完，用完時等額度重置再重跑。
- **worktree**：
  - 裡面不准 `git add -A`，只 stage 明確的路徑；`.cache` 是 symlink。
  - 每個 worktree 用自己的 `TF_PLUGIN_CACHE_DIR`，避免共用 plugin cache 互相改寫。
- **合併**：每個 check 都是 `pass` 才合併；不要在等待迴圈後面無條件接 `gh pr merge`。
- **release-please 重複開 PR**：已發布的 module 又出現沒有差異的 release PR 時，關掉。

## 限制（每個 Phase、每個 subagent 都適用）

- **不碰 AWS**：
  - 不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；tflint 不開 `deep_check`。
  - Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
  - 不准跑 `terraform providers lock`；範本只用 aws provider，lock 檔從既有 aws-only stack 複製。
- **環境與佔位值**：
  - code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
  - 帳號 `111111111111`（dev）、`222222222222`（sit）；GitHub repo `example-org/example-app`；`<state-bucket>`、`<state-kms-key-arn>`。
  - buildspec 範例不能出現真實的 repo、帳號、映像檔名稱。
- **module 規則**：module 不建 `aws_iam_*` 與 SG（S4），不用 `random_password`（S7）；範本 stack 只呼叫 module（S8）。
- **commit 與 PR**：
  - 一個 commit 只動一個 module 目錄；新 module 與既有 module 的 minor 版都用 `feat(<module>)`。
  - PR 用 merge commit 合併（[`releasing-modules.md`](../../guides/releasing-modules.md)）。
- **文字**：`description` 用台灣繁體中文；註解與 `error_message` 用英文。README 表格由 terraform-docs 產生（S11）。
- **範本變動範圍**：example2–example6、account-baseline、project-infra 不能有任何變動。每個 Phase 驗收時看 `git diff origin/main --stat` 確認。

## Phase 表

| Phase | 內容 | 狀態 | PR |
|---|---|---|---|
| L0 | v11 設計文件與實作流程 | 完成（2026-10-29 確認） | #293 |
| L1 | `codeconnections-connection`、`codebuild-project` | 完成：發版、HCP ok | #296 |
| L2 | `codepipeline` | 完成：發版、HCP ok | #294 |
| L3 | `ecs-service` 0.3.0、`lambda-function` 0.2.0、`iam-role` 0.6.0 | 完成：發版、HCP ok | #299 |
| L4 | 範本骨架、`containerimage`、`foundation`、`network`、`iam` | 完成 | #303 |
| L5 | `loadbalancer`、`application`、`web` | 完成 | #304 |
| L6 | `pipeline` | 完成 | #305 |
| L7 | 文件、根 README、標準指南、全量驗證、價格查證、design §14 | 完成 | |

## 每個 Phase 的做法與驗收

### module 共用做法（L1–L3）

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

### L0：設計文件

- 做法：`docs/design/v11/design-docs.md`、`implement-process.md`。`docs:` commit，不發版。
- 驗收：使用者看過設計，並說可以開始。

### L1：connection 與建置專案

- 做法：`codeconnections-connection`、`codebuild-project`（design §5.1、§5.2）。
- 額外：查 CodeConnections 的價格、CodeBuild ARM small 的單價與映像名稱，結果記到 design §10、§14。
- 額外驗收：`codebuild-project` 的 mutation check 要包含「拿掉 `PLAINTEXT` 變數名稱的檢查」與「把 source 類型改成 `GITHUB`」。

### L2：pipeline

- 做法：`codepipeline`（design §5.3）。
- 額外：查 AWS 文件確認 V2 pipeline 沒有 `trigger` 區塊、`DetectChanges = "false"` 時不會自動觸發（design §2 第 7 點），結果記到 design §14。
- 額外驗收：測試確認 source action 的 `DetectChanges` 是 `"false"`，而且 pipeline 沒有 `trigger`。

### L3：既有 module 的 minor 版（審閱重點）

1. `ecs-service` 0.3.0（design §5.4）：
   - 先跑一次既有測試記下結果，加完功能後既有測試不改就要全部通過。
   - `moved` 從 `aws_ecs_service.this` 到 `aws_ecs_service.this[0]`；listener rule 一樣。用 `examples/basic` 在 0.2.1 與 0.3.0 各做一次 `validate`，確認位址變動有 `moved` 涵蓋。
   - 三個 service 版本用 `count` 互斥，測試要確認任何輸入下都只有一個被建立。
2. `lambda-function` 0.2.0（design §5.5）：做法同上。
3. `iam-role` 0.6.0（design §5.6）：查 AWS 文件確認 `AmazonECSInfrastructureRolePolicyForLoadBalancers` 的完整 ARN，結果記到 design §14。

### L4：範本前段

- 做法：建 `templates/example9/infra/terraform/`，結構照 example6（`stacks.sh`、`check-ssm-contract.sh`、每個 stack 的 `common.tf` 一致）。做 `containerimage`、`foundation`、`network`、`iam`（design §8.1）。
- 驗收：
  - 這 4 個 stack 通過；`check-ssm-contract.sh` 通過。
  - `iam` 的測試確認每個建置 role 只能碰自己的元件，`iam:PassRole` 有 `iam:PassedToService` 條件（design §4）。

### L5：應用程式

- 做法：`loadbalancer`、`application`、`web`（design §8.1）。
- 驗收：`application` 的測試確認 api service 是 `pipeline_managed`、rolling，fn 有 alias `live` 且是 `pipeline_managed`。

### L6：pipeline

- 做法：`pipeline`（design §8.2、K4、K6、K7）。
- 驗收：
  - 測試確認三條 pipeline 的 stage 順序；sit 有 Approval、dev 沒有。
  - fn 的 Deploy 用 `PublishedTargetVersion`；dev 是 `AllAtOnce`、sit 是 `Canary10Percent5Minutes`。
  - 失敗通知的 EventBridge rule 只轉 `FAILED` 狀態，送到告警 topic。

### L7：收尾

1. `infra/README.md`、`REFERENCE.md`、`architecture.drawio.svg`，REFERENCE 的內容照 design §8.5。
2. 根 README：module 數改成 94，分類表加「CI/CD」類，範本表加 `example9`。
3. `docs/guides/project-infra-standard.md` 提到範本清單的地方加 `example9`。
4. 查官方價格，更新 design §10、§13。
5. 全量 `scripts/validate.sh`；設計與實作的差異寫進 design §14；這份的 Phase 表填狀態與 PR 編號。

驗收（里程碑完成的條件）：

- 全部 run 綠燈，包括 release PR。
- 94 個 module 的 latest tag 等於 main 與 manifest。
- HCP 狀態 94 個 ok。
- 沒有開著的 PR，遠端只剩 `main`。
