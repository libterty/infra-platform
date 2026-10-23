# infra-platform v5 實作流程：tflint aws ruleset 與 terraform-docs

> 狀態：E0 完成（#78），E1 進行中。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 design-docs.md 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。

## 結論

一個里程碑分 11 個 Phase，每個 Phase 一層 stacked PR（`gh stack`）。先把工具接好（E1 tflint、E2 terraform-docs），再分 7 批改寫 description 並產生 README（E3–E9），每批合併後發版，最後收緊檢查（E10）。

E3 第一個 module 發版後，先到 HCP 確認中文顯示正常，才繼續後面的 module 與批次。

一次做一個 Phase，主 agent 自己重跑驗收通過後 commit 並 `gh stack submit`，才進下一個。

## 限制（每個 Phase、每個 subagent 都適用）

- 不碰 AWS：不准 `terraform plan`、`apply`、帶 backend 的 `init`，不准任何 `aws` 指令；tflint 不開 `deep_check`。Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
- 不准跑 `terraform providers lock`。
- 改寫 description 的 commit 只能改 `description` 的值與 README；型別、預設、validation、resource、output 的值一行都不能動（design §7）。
- 註解與 `error_message` 維持英文。
- 中文一律用台灣繁體中文與台灣用語。
- 一個 module 一個 commit。commit 在 feature branch 上做，不推 `main`。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| E0 | v5 設計文件與實作流程 | 完成：審過並合併（#78） | `e63d6b2` |
| E1 | tflint aws ruleset | 未開始 | — |
| E2 | terraform-docs 設定、S11、CI、規則文件 | 未開始 | — |
| E3 | 第 1 批：`kms-key`、`ecr-repository`、`s3-bucket`、`sns-alarm-topic`、`security-group`、`ssm-publish`、`ssm-read` | 未開始 | — |
| E4 | 第 2 批：`vpc`、`vpc-interface-endpoints`、`alb`、`waf-web-acl`、`vpc-peering`、`nlb`、`lb-traffic-breaker` | 未開始 | — |
| E5 | 第 3 批：`ecs-cluster`、`ecs-service`、`ecs-service-alarms`、`lambda-function`、`ec2-bastion`、`ec2-instance`、`ec2-asg` | 未開始 | — |
| E6 | 第 4 批：`iam-role`、`iam-role-policy`、`iam-oidc-provider`、`rds`、`elasticache-redis` | 未開始 | — |
| E7 | 第 5 批：`log-group`、`log-delivery`、`log-metric-alarm`、`metric-alarm`、`xray`、`xray-transaction-search` | 未開始 | — |
| E8 | 第 6 批：`eks-cluster`、`eks-addons`、`eks-iam-policies`、`eks-workload-alarms` | 未開始 | — |
| E9 | 第 7 批：`bedrock-guardrail`、`bedrock-inference-profile`、`agentcore-runtime`、`agentcore-memory`、`agentcore-gateway`、`bedrock-knowledge-base` | 未開始 | — |
| E10 | S11 要求每個 module 都有 marker、打開 documented 規則、收尾 | 未開始 | — |

## 每個 Phase 的做法與驗收

### E1：tflint aws ruleset

做法（design §4）：

1. `.tflint.hcl` 加 `plugin "aws"`，釘 0.49.0；更新檔頭註解。
2. `validate.sh`：設 `TFLINT_PLUGIN_DIR`、迴圈前跑一次 `tflint --init`；範本 stack 逐一帶 tfvars 跑 `--call-module-type=all`。
3. CI：快取 `.cache/tflint-plugins`，Validate 步驟加 `GITHUB_TOKEN`。
4. 文件：`README.md`〈開發〉、`CONTRIBUTING.md`、`docs/guides/delivering-to-customer.md` 提到 plugin 與第一次會下載。

驗收：

- 全量 `scripts/validate.sh` 通過。
- 突變：在一個 module 的 example 寫不存在的 instance type → 失敗；在一個範本 stack 的 `envs/*.tfvars` 寫不存在的 node type → 失敗；plugin 目錄是空的又連不到 GitHub → 失敗。
- 空的 plugin 目錄重跑會重新下載並通過；已有 plugin 時，`tflint --init` 與 `tflint` 在不連網（`HTTPS_PROXY=http://127.0.0.1:9`）下都通過。`terraform init` 本來就要連 registry 查 provider，不在這項檢查內。
- CI 綠燈，第二次跑命中 plugin 快取。

### E2：terraform-docs 設定、S11、CI、規則文件

做法（design §5、§6.3）：

1. 新增 `.terraform-docs.yml`。外層型別的 regex 用 42 個 module 的實際型別驗證：在 scratchpad 對所有 module 產生一次，型別欄只能出現 `string`、`number`、`bool`、`list(…)`、`set(…)`、`map(…)`、`object`、`map(object)`、`list(object)` 這類外層形式，不能有 `{`。
2. `validate.sh` 加 S11（只檢查有 marker 的 module；沒有 `.terraform-docs.yml` 就略過）；找不到 terraform-docs 就失敗。
3. CI 下載 terraform-docs 並比對 sha256。
4. 改 `CONTRIBUTING.md`〈語言〉〈開發環境〉、`docs/guides/releasing-modules.md` 步驟 3、4 與 semver 表、`README.md`〈開發〉。

這個 Phase 不動任何 module，所以 S11 還沒有實際檢查的對象。

驗收：

- 全量 `scripts/validate.sh` 通過。
- 突變（在 scratchpad 的 module 副本上，或暫時改一個 module 再還原）：放 marker 並產生表格後，手改一格 → S11 失敗；改一個 description 不重新產生 → S11 失敗；拿掉 `.terraform-docs.yml` → S11 略過；`PATH` 裡沒有 terraform-docs → 失敗。
- CI 綠燈，sha256 比對步驟有跑。

### E3–E9：每一批的做法

每個 module：

1. 讀 README 的輸入／輸出表與「## 注意」，跟 `variables.tf`、`outputs.tf` 對照，照 design §6.1 改寫每個 `description`。
2. 4 個有子表或點號列的 module（nlb、lb-traffic-breaker 在 E4，eks-addons 在 E8，bedrock-knowledge-base 在 E9）先把子表搬到 marker 外的新小節，或併進對應的 description。
3. README 的「## 輸入」「## 輸出」兩節換成 marker，跑 `terraform-docs -c .terraform-docs.yml modules/<m>` 產生表格；拿掉「之後改由 terraform-docs 產生」的提示。
4. commit：`fix(<module>): rewrite the input and output descriptions in Chinese`，內文寫「Documentation only; no type, default, validation or resource changes.」。

每批驗收：

- 每個 module 都過 design §7 的三項行為不變證明。證明用的腳本放在 scratchpad，不進 repo。
- 產生的表格人工抽看：沒有 `n/a`、沒有被吃掉的 `<…>`、型別欄沒有 `{`、搬出來的子表內容沒有遺失（逐列比對改寫前的 README）。
- 每個 description 的中文用語檢查（台灣用語，沒有簡體字）。
- `scripts/validate.sh --changed-since main` 通過，S11 對這批 module 生效。
- PR 合併後，release PR 一次合併一個；每發一版確認 `gh release view <m>-v<ver>` 與 HCP 的 `version-statuses`。
- **E3 額外**：第一個發版的 module 到 HCP 看 Inputs 分頁與 README 的中文顯示正常，有問題就停下來回報，不繼續。

### E10：收尾

做法：

1. S11 改成「每個 `modules/*` 的 README 都必須有 marker」。
2. `.tflint.hcl` 打開 `terraform_documented_variables`、`terraform_documented_outputs`。
3. `README.md` 與 design-docs 狀態更新；這份記錄每個 Phase 的結果。

驗收：

- 全量 `scripts/validate.sh` 通過。
- 突變：拿掉一個 module 的 marker → S11 失敗；清空一個 description → tflint 失敗。
- 42 個 module 都有新的 PATCH 版，HCP 都讀得到。
- `grep -r '之後改由 terraform-docs 產生' modules` 沒有結果。
