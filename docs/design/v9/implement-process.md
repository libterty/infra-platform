# infra-platform v9 實作流程：邊緣層與 serverless module、example2 接 CDN、templates/example6

> 狀態：I0–I10 全部完成（2026-10-28）。實作時跟設計不同的決定記在 design §14。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 [`design-docs.md`](./design-docs.md) 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 11 個 Phase（I0–I10）。

- **module（I1–I5）**：7 個新 module 加 3 個 minor 版，每個 Phase 合併後發版、HCP 登記，並從消費端抓一次。I1–I5 的目錄互不重疊，可以在各自的 worktree 平行做。
- **範本（I6–I10）**：module 全部在 HCP 上之後才做，因為範本 stack 從 HCP 抓 module（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。
- **I1 例外**：I1 同時改 module 與範本，因為 secret 搬遷要用新 module。它的範本 commit 要等 `secrets-manager-secret` 0.1.0 在 HCP 上之後才推。

使用者授權（2026-10-28）：每個 Phase 驗證通過就 commit、開 PR，CI 綠燈就合併、發版、HCP 登記，不必逐一確認。只有需要使用者決定的事或擋住的問題才停下來問。

發版沿用 v8 的教訓：

- **release PR 衝突**：多個 release PR 同時存在時，每個都從 main 重建再 squash。
- **Actions API 額度**：連續發版會用完。用完時等額度重置，再重跑最後一次 Release run。

## 限制（每個 Phase、每個 subagent 都適用）

- **不碰 AWS**：
  - 不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；tflint 不開 `deep_check`。
  - Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
  - 不准跑 `terraform providers lock`。example6 只用 aws provider，lock 的處理跟 example2 一樣。
- **環境與佔位值**：
  - code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
  - 帳號 `111111111111`（dev）、`222222222222`（sit）、網域 `example.com`、`<state-bucket>`、`<state-kms-key-arn>`。
  - 測試與範例不放真的憑證、密碼、私鑰或 origin verify 值。
- **module 規則**：module 不建 `aws_iam_*`、SG（S4），不用 `random_password`（S7）。範本 stack 只呼叫 module（S8）。
- **commit 與 PR**：
  - 一個 commit 只動一個 module 目錄；新 module 用 `feat(<module>)`。
  - 既有 module 的 minor 版也用 `feat(<module>)`，release-please 才會升 minor。
  - PR 用 merge commit 合併（[`releasing-modules.md`](../../guides/releasing-modules.md)）。
- **文字**：`description` 用台灣繁體中文；註解與 `error_message` 用英文。README 表格由 terraform-docs 產生（S11）。
- **範本變動範圍**：
  - example3、example4、example5、project-infra 只准改 I1 的 secret 搬遷。
  - example2 只准改 I1、I6、I7 列出的檔案。
  - 每個 Phase 驗收時看 `git diff origin/main --stat` 確認。
- **worktree**：`.cache` 一律 symlink 到主 repo 的 `.cache`。
- **CI**：4 個 shard 平行跑（`validate.sh --shard k/4`），PR 只看彙總的 `validate` job。

## Phase 表

| Phase | 內容 | 狀態 | PR |
|---|---|---|---|
| I0 | v9 設計文件與實作流程 | 完成（2026-10-28 確認） | #242 |
| I1 | `secrets-manager-secret`；6 處 secret 搬遷；S8 例外清單；標準指南 | 完成：發版、HCP ok；範本搬遷另一個 PR | #243、#258 |
| I2 | `route53-zone`、`route53-record`、`acm-certificate` | 完成：發版、HCP ok | #244 |
| I3 | `waf-web-acl` 0.2.0、`s3-bucket` 0.5.0、`log-delivery` 0.2.0 | 完成：waf-web-acl 0.2.0、s3-bucket 0.5.0、log-delivery 0.3.0，HCP ok | #252 |
| I4 | `apigateway-http`、`cognito-user-pool` | 完成：發版、HCP ok | #250 |
| I5 | `cloudfront-distribution` | 完成：發版、HCP ok；spa_fallback 改 CloudFront Function | #249 |
| I6 | example2 `dns`、`certificate`、`bridge`、`loadbalancer` HTTPS | 完成 | #260 |
| I7 | example2 `edge`、tfvars、README、REFERENCE、架構圖 | 完成 | #262 |
| I8 | example6 骨架、`containerimage`、`foundation`、`dns`、`certificate`、`data`、`iam` | 完成 | #259 |
| I9 | example6 `auth`、`api`、`web` | 完成 | #261 |
| I10 | example6 文件、根 README、全量驗證、價格查證、design §14 | 完成 | I10PR |

## 每個 Phase 的做法與驗收

### module 共用做法（I1–I5）

1. 先寫 `tests/` 的正向與反向情境（design §9），跑 `validate.sh modules/<name>`，確認反向情境因為缺 validation 而失敗。
2. 寫 `variables.tf`、`main.tf`、`outputs.tf`、`versions.tf`（`required_version >= 1.10`、aws `>= 6.0, < 7.0`）、`examples/basic`，跑到全部通過。
3. `README.md` 的說明段落用中文寫，表格由 terraform-docs 產生。
4. `release-please-config.json` 加 package，`.release-please-manifest.json` 加 `0.0.0`（新 module）；根 README 的 module 表加一列。這兩個共用檔由主 agent 在 rebase 之後整合。
5. 合併、release PR 合併、tag 出現之後，在 HCP 登記並從消費端抓一次（`scripts/` 的 HCP 腳本）。

驗收（每個 module）：

- `scripts/validate.sh modules/<name>` 通過。
- 反向情境各自被正確的 validation 擋下，錯誤訊息指到欄位。
- `git diff origin/main --stat` 只動到這個 Phase 該動的目錄。
- 發版：tag 等於 manifest，HCP 狀態 ok。

### I0：設計文件

- 做法：`docs/design/v9/design-docs.md`、`implement-process.md`。`docs:` commit，不發版。
- 驗收：使用者看過設計，並說可以開始。

### I1：secret module 與搬遷

1. `secrets-manager-secret`（design §5.1），照 module 共用做法發 0.1.0。
2. HCP 上有 0.1.0 之後，每個範本一個 commit：照 design §6 改 `foundation`（和 project-infra 的 `agent`），加 `moved` block。stack 測試確認名稱、KMS、recovery window 跟搬遷前一樣。
3. `chore(repo)` commit：`scripts/validate.sh` 的 `s8_allowed` 拿掉兩條 secret 例外；用暫存的假 stack 確認 `aws_secretsmanager_secret` 會被擋，既有目錄全過。
4. `docs/guides/project-infra-standard.md`〈例外清單〉與各範本 README 的對應句子一起改。

驗收：

- 全量 `validate.sh` 通過。
- `grep -rn 'resource "aws_secretsmanager_secret"' templates --include='*.tf'`（排除 `.terraform/`）沒有結果。
- project-infra `agent` 的整組 `moved` 若不被接受，改在 REFERENCE 寫 `terraform state mv` 指令，並記到 design §14。

### I2：DNS 與憑證

- 做法：`route53-zone`、`route53-record`、`acm-certificate`（design §5.2–§5.4）。`acm-certificate` 依賴 zone ID 但不依賴另外兩個 module，三個可以平行做。
- 額外驗收：`acm-certificate` 的 apex 加 wildcard 測試要確認驗證 record 只有一筆。

### I3：既有 module 的 minor 版

- 做法：`waf-web-acl`、`s3-bucket`、`log-delivery`（design §5.8）。
- 額外驗收：
  - 既有的測試不改就全部通過，證明預設值的行為沒變。
  - 用到這三個 module 的範本 stack 不升版，全量驗證仍通過。

### I4：API 與身分驗證

- 做法：`apigateway-http`、`cognito-user-pool`（design §5.6、§5.7）。
- 額外做法：查 AWS WAF 文件，確認 HTTP API 不支援 WAF（design §2 第 6 點），結果記到 design §14。

### I5：CloudFront

- 做法：`cloudfront-distribution`（design §5.5）。
- 額外驗收：origin verify 的測試確認 plan 裡 header 值是 sensitive。

### I6：example2 前段

1. 新 stack `dns`、`certificate`（design §7.1），檔案結構照 example2 其他 stack：`common.tf`、`providers.tf`、`versions.tf`、`variables.tf`、`envs/`、`tests/`、`ssm-outputs.tf`。
2. `stacks.sh` 的 ORDER 加兩個 stack；`common.tf` 在 14 個 stack 保持一致。
3. `bridge` 轉寫 4 個新 key（design §7.1）。
4. `loadbalancer` 從樹 B 讀 ALB 憑證，開 HTTPS listener。

驗收：

- `scripts/validate.sh templates/example2/infra/terraform` 通過。
- `check-ssm-contract.sh` 通過。
- loadbalancer 的測試確認有 HTTPS listener，而且 80 只做 redirect。

### I7：example2 邊緣

1. 新 stack `edge`（design §7.1）；`stacks.sh` 的 ORDER 加 `edge`。
2. `network`、`application` 的 tfvars（design §7.1）。
3. README〈apply 順序〉〈部署〉（第一次 apply 的流程，design §7.2）；REFERENCE 補〈第一次 apply〉〈destroy 之前〉〈已知限制的細節〉；更新架構圖。

驗收：

- 全部 example2 stack 通過，SSM 合約通過。
- `edge` 的測試確認 WAF 的 scope 是 CLOUDFRONT、origin 是 `https-only`、header 值是 sensitive。

### I8：example6 前段

- 做法：建 `templates/example6/infra/terraform/`，結構照 example5（`stacks.sh`、`check-ssm-contract.sh`、每個 stack 的 `common.tf` 一致）。先做 `containerimage`、`foundation`、`dns`、`certificate`、`data`、`iam`（design §8.1）。
- 驗收：這 6 個 stack 通過；`check-ssm-contract.sh` 在 ORDER 只列到 `iam` 時通過。

### I9：example6 後段

- 做法：`auth`、`api`、`web`（design §8.1–§8.3）。
- 驗收：
  - 全部 9 個 stack 通過，SSM 合約通過。
  - `api` 的測試確認每條 route 都有 authorizer，或明寫 `public`。
  - `web` 的測試確認 bucket policy 只允許這個 distribution。
  - `web` 的測試確認 WAF 掛在 distribution、`/api/*` 帶 origin verify header 且值是 sensitive；`api` 的測試確認 Lambda 拿得到 header 名稱與 secret ARN。

### I10：收尾

1. example6 的 `infra/README.md`、`REFERENCE.md`、`architecture.drawio.svg`。
2. 根 README：module 數改成 80，分類表加新 module，範本表加 example6。
3. `docs/guides/project-infra-standard.md` 提到範本的地方加 example6。
4. 查 Tokyo 價格，更新 design §10、§13。
5. 全量 `scripts/validate.sh`；設計與實作的差異寫進 design §14；這份的 Phase 表填狀態與 PR 編號。

驗收（里程碑完成的條件）：

- 全部 run 綠燈，包括 release PR。
- 80 個 module 的 latest tag 等於 main 與 manifest。
- HCP 狀態 80 個 ok。
- 沒有開著的 PR。
