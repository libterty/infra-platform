# infra-platform v7 實作流程：資料平台 module 與 templates/example4

> 狀態：G0–G13 全部完成（2026-10-24；G0–G9 是 #172–#206，G10–G13 是本 PR 系列）。實作時跟設計不同的決定記在 design §14。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 [`design-docs.md`](./design-docs.md) 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。example4 的路徑都在 `templates/example4/infra/terraform/` 底下。

## 結論

一個里程碑分 15 個 Phase（G0–G13，另有 G1r），每個 Phase 一層 stacked PR（`gh stack`）。先做 module（G1–G7）：14 個新 module 加 `s3-bucket` 0.4.0，每個 Phase 合併後發版、HCP 登記並從消費端抓一次；全部在 HCP 上之後才做範本（G8–G13），因為範本 stack 從 HCP 抓 module（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

一次做一個 Phase：主 agent 自己重跑驗收通過後 commit 並 `gh stack submit`，才進下一個；每個 Phase 結束先跟使用者確認。合併、發版、HCP 登記之前先問使用者。

Phase 代號用 G，避開 v4 的 C、v5 的 E、v6 的 F。

## 限制（每個 Phase、每個 subagent 都適用）

- 不碰 AWS：不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；tflint 不開 `deep_check`。Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
- 不准跑 `terraform providers lock`。opensearch provider 的 lock hash 由使用者在自己的終端機產生（G10）。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- 佔位值：帳號 `111111111111`（dev）、`222222222222`（sit）、網段 `10.30.0.0/20`、`10.31.0.0/20`、網域 `example.com`、`<state-bucket>`、`<state-kms-key-arn>`。tfvars、測試、範例都不放真的密碼；mock 的 secret 值用明顯的假字串。
- module 不建 `aws_iam_*`、SG（S4），不用 `random_password`（S7）；`opensearch-domain`、`redshift-serverless`、`redshift-cluster` 沒有含 password 的變數（S7 擴充）。範本 stack 只呼叫 module（S8），例外：`foundation` 的 `aws_secretsmanager_secret`、`search-config` 的 ephemeral 讀取（design K19）、`warehouse` 的 `terraform_data` 防呆（design §7.3）。
- 一個 commit 只動一個 module 目錄；新 module 用 `feat(<module>)`；PR 標題不用 Conventional Commit 格式，用 merge commit 合併（[`releasing-modules.md`](../../guides/releasing-modules.md)）。
- `description` 用台灣繁體中文；註解與 `error_message` 用英文。README 表格由 terraform-docs 產生（S11）。
- example2、example3、project-infra 不能有任何變動：每個 Phase 驗收都確認 `git diff main -- templates/example2 templates/example3 templates/project-infra` 是空的。
- commit 在 feature branch 上做，不推 `main`。

## Phase 表

| Phase | 內容 | 狀態 | commit |
|---|---|---|---|
| G0 | v7 設計文件與實作流程 | 完成：審過並合併 | #172 |
| G1 | `s3-bucket` 0.4.0（`transitions`、`eventbridge`）、`kinesis-stream`、`dynamodb-table` | 完成：`s3-bucket` 既有測試不改全過，新增 transition、`eventbridge` 的正負向 run | #173 |
| G1r | G1 合併、發版、HCP 登記並確認（之後每個 module Phase 照做） | 完成：G1–G7 每個 module 照做，14 個 `v0.1.0` 加 `s3-bucket-v0.4.0` 都有 tag 與 GitHub Release、在 HCP 登記並從消費端抓到；新 module 不先建 CHANGELOG | — |
| G2 | `glue-catalog`、`glue-catalog-encryption`（帳號層）、`glue-etl`（含 EventBridge 事件觸發） | 完成：`glue-etl` 的 EVENT trigger、rule pattern、target 用 `jsondecode` 斷言；另加「一個 workflow 只有一個起始 trigger」的 validation | #179 |
| G3 | `opensearch-domain`（internal user database、S7 擴充）、`opensearch-config` | 完成：S7 擴充到 `opensearch-domain`；`opensearch-config` 用 `mock_provider "opensearch"` | #186 |
| G4 | `firehose-stream`、`athena-workgroup` | 完成：`athena-workgroup` 的 cutoff 下限是 provider 的 10485760 | #194 |
| G5 | `redshift-serverless`、`redshift-cluster`（S7 擴充） | 完成：S7 擴充到兩個 module；輸出名稱一致；`check-output-parity.sh` 在只 vendor 一個 module 時跳過 | #188 |
| G6 | `quicksight-data` | 完成：credentials 只收 `secret_arn` | #189 |
| G7 | `vpn-site-to-site`、`client-vpn` | 完成：PSK 固定 `SecretsManager`；弱演算法依通行的密碼學建議擋掉 | #190 |
| G8 | example4 骨架：`stacks.sh`、`check-ssm-contract.sh`、`foundation`、`network` | 完成：`foundation`、`network`、`stacks.sh`、`check-ssm-contract.sh` | #195 |
| G9 | `vpn`、`storage`（raw bucket 開 EventBridge）、`iam-base` | 完成：`vpn` 預設零資源、`storage` 只有 raw 開 EventBridge、`iam-base` 的 Resource 斷言 | #206 |
| G10 | `search`（dev、sit 都冷熱）、`search-config`（lock 由使用者產生） | 完成：dev、sit 都是冷熱；`search-config` 改用離線 aws provider 測試（S1 放寬，使用者選擇） | 本 PR 系列 |
| G11 | `analytics`、`iam-app`、`pipeline`（事件觸發 workflow） | 完成：workflow 與 rule 的命名規則兩個 stack 各自斷言 | 本 PR 系列 |
| G12 | `warehouse`（雙模式與 `prevent_destroy` 防呆）、`bi` | 完成：`check-warehouse-guard.sh`；Serverless `enhanced_vpc_routing` 預設 `false` | 本 PR 系列 |
| G13 | README（成本、安全例外、前置作業、runbook）、文件、全量驗證、驗證表 | 完成：example4 README、範例 Glue job、根 README、規範文件；全量 `validate.sh`：12 個 stack、305 個 run 通過 | 本 PR 系列 |

發版數量：14 個 `v0.1.0` 加 `s3-bucket-v0.4.0`，共 15 版，分散在 7 個 Phase。

## 每個 Phase 的做法與驗收

### G0：設計文件

做法：`docs/design/v7/design-docs.md`、`implement-process.md`。`docs:` commit，不發版。

驗收：使用者審過。

### 每個 module Phase 共用的做法（G1–G7）

先派唯讀 planner 對照 design §2 與 AWS 文件確認該 Phase 的未確認事項（每個 Phase 下面列出），結果跟設計衝突的先回來問使用者。

每個新 module：

1. 建目錄：`versions.tf`、`variables.tf`、`main.tf`、`outputs.tf`、`README.md`（用法、〈注意〉、〈刻意不做〉、marker）、`examples/<name>/main.tf`、`tests/*.tftest.hcl`。
2. TDD：先寫 design §9 的 run（正向與每條 validation 的負向），跑 `scripts/validate.sh modules/<m>` 看到失敗，再實作到全過。
3. `release-please-config.json` 加 `"initial-version": "0.1.0"` 的一列；manifest 不加。
4. repo 根 `README.md` 的 module 表加一列（分類「資料平台」或「網路與入口」），module 數量改正（最後是 56）。
5. `terraform-docs -c .terraform-docs.yml modules/<m>` 產生表格。
6. 一個 module 一個 `feat(<m>): ...` commit。

驗收（每個 module）：

- `scripts/validate.sh modules/<m>` 全過。
- 突變：每條固定的安全設定（加密、HTTPS、不公開、密碼代管、log 必開、FGAC）各改一次，測試要抓到。
- `grep` 確認 module 裡沒有 `aws_iam_`、`aws_security_group`、`random_password`；S7 擴充的三個 module 沒有含 password 的變數名稱。
- 改到的檔案只有該 module 目錄、`release-please-config.json`、`README.md`（G3、G5 另有 `scripts/validate.sh`）。

### G1r（以及 G2–G7 的發版）

照 [`releasing-modules.md`](../../guides/releasing-modules.md)：

1. 合併 stack 的 PR（merge commit）。
2. 每個 module 一個 release PR；看過 diff，**一次合併一個**，等 Release run 跑完、`gh release view <m>-v<ver>` 查得到才合下一個（衝突時照〈同時有多個 release PR〉重建）。
3. release-please 一次只建一個 tag，自然符合「一次 push 最多 3 個 tag」；不手動打 tag。
4. 新 module 照 [`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 登記，§4 從消費端抓一次確認。HCP 登記要 organization 的 token，先問使用者。
5. 不先建 `CHANGELOG.md`，第一次發版時由 release-please 產生（先建 `# Changelog` 的話，它會在尾端留下被降級的 `## Changelog`，事後刪掉又會讓 module 目錄跟 tag 不一致，2026-10-24 G1、G2 遇到）。
6. 額度：15 版分散在 7 個 Phase，不會用完 `GITHUB_TOKEN` 的每小時 1000 次；真的用完就等一小時 `gh run rerun`。
7. 「tag 已經存在」的空 release PR 直接關掉並刪分支。

驗收：每個 module 有 tag 與 GitHub Release；HCP `version-statuses` 是 `ok`；消費端 `terraform init` 抓得到。

### G1：`s3-bucket` 0.4.0、`kinesis-stream`、`dynamodb-table`

未確認事項：lifecycle transition 的最小天數；`aws_s3_bucket_notification` 只開 `eventbridge` 的寫法；DynamoDB GSI `key_schema` 與 `attribute` 的驗證規則。

- `s3-bucket`（design §6）：`transitions`（預設 `[]`）、`eventbridge`（預設 `false`）。notification 在 `lambda_notifications` 非空或 `eventbridge = true` 時建立。既有三個測試檔不改就全過；新增的 run：transition 寫進 rule、`eventbridge` 單獨開、與 Lambda 並存、validation 負向。README〈刻意不做〉拿掉 EventBridge。CHANGELOG 寫「不給新變數時 plan 零差異」。
- `kinesis-stream`、`dynamodb-table`：design §5.3、§5.4。

### G2：`glue-catalog`、`glue-catalog-encryption`、`glue-etl`

未確認事項：`glue_version`、`worker_type`；security configuration 的 mode 值；`aws_glue_data_catalog_encryption_settings` 在 destroy 時的行為；`aws_cloudwatch_event_rule` 的 `event_pattern` 用 `prefix` 比對 `detail.object.key` 的寫法；Glue job 與 crawler 的最低計費時間。

- `glue-catalog-encryption`（design §5.7）：README 開頭照 `xray-transaction-search` 寫「每個帳號、每個 region 只能由一處呼叫」與 KMS 權限的影響、「同帳號第二個專案設 `null`」。
- `glue-catalog`：design §5.6。
- `glue-etl`（design §5.8）：`event_trigger` 有給時建 EVENT trigger（workflow 的起始 trigger）、EventBridge rule、target。測試：`jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern)` 斷言 `source`、`detail-type`、bucket 名稱、key 前綴；target 的 `arn` 是 workflow ARN、`role_arn` 是輸入；trigger 的 `type = "EVENT"`、`workflow_name`、`event_batching_condition`；負向：沒有 `workflow`、batch_size 0 與 101、window 0 與 901、role 格式。

### G3：`opensearch-domain`、`opensearch-config`

未確認事項：可用的 `engine_version`；master 密碼的字元規則；log group 層的 resource policy 是否支援 OpenSearch；opensearch provider 2.6.0 各 resource 的欄位，以及 `mock_provider "opensearch"` 能否 plan。

- `opensearch-domain`（design §5.1）：`master_user_secret_arn` 由 module 內的 data source 讀，`jsondecode` 取帳密；測試用 `mock_data` 回假 JSON，斷言 `internal_user_database_enabled = true`、master 名稱來自 secret、access policy 只含 `access_principal_arns`。README〈注意〉寫 design §4.1 的安全例外。
- `scripts/validate.sh` 的 S7：`modules/opensearch-domain/variables.tf` 不得宣告含 password 的變數（獨立的 `chore(repo)` commit；G5 再加 redshift 兩個）。
- `opensearch-config`（design §5.2）：ISM JSON 的狀態順序、`warm_migration`、`cold_migration.timestamp_field`、`cold_delete` 用 `jsondecode` 斷言；`firehose_writer` 的權限照 AWS 文件；mapping `all_access`、`security_manager` 被擋。S1 要求 `mock_provider "opensearch"`。

### G4：`firehose-stream`、`athena-workgroup`

未確認事項：`error_output_prefix` 規則；`buffering_interval` 上限（設計假設 900 秒）；OpenSearch 目的地 `vpc_config.role_arn` 能否跟主 role 相同；`index_rotation_period` 值；Athena `enable_minimum_encryption_configuration` 的行為。

做法：design §5.5、§5.9。

### G5：`redshift-serverless`、`redshift-cluster`

未確認事項：Serverless 的 `require_ssl` config key；`log_exports` 值；`ra3.large` single-node 在 Tokyo 是否可用；`aws_redshift_logging` 寫 CloudWatch 的 log group 命名。

做法：design §5.10、§5.11。兩個 module 的輸出名稱一致（`endpoint_address`、`port`、`database_name`、`admin_secret_arn`），各寫一個 run 斷言。S7 擴充到兩者。`redshift-serverless` README〈注意〉寫「namespace 沒有 final snapshot，刪除即丟資料」。

### G6：`quicksight-data`

未確認事項：owner／reader 的 action 清單；VPC connection role 的權限。

做法：design §5.12。credentials 只能是 `secret_arn`。

### G7：`vpn-site-to-site`、`client-vpn`

未確認事項：tunnel 參數合法值；`SecretsManager` 模式的 KMS／IAM 需求；mutual 與 SAML 並用的寫法；連線 log 用 CMK 的 key policy 需求。

做法：design §5.13、§5.14。

### G8：example4 骨架

前提：G1–G7 的 module 都在 HCP 上。

做法：

1. 建 `templates/example4/infra/terraform/`，從 project-infra 複製 `stacks.sh`、`check-ssm-contract.sh`，只改 ORDER（先列 `foundation network`）與註解裡的範本名稱。
2. 每個 stack 的固定檔：`common.tf`（`accounts_by_env` 改 `dev`、`sit`，所有 stack 一字不差）、`versions.tf`、`providers.tf`（`Stack` tag）、`envs/{dev,sit}.tfvars`、`envs/{dev,sit}.tfbackend`（key `<project>-<env>/<stack>/terraform.tfstate`，另加 `kms_key_id = "<state-kms-key-arn>"`，design K24）、`tests/`、`tests/tfvars/`；`.terraform.lock.hcl` 從 project-infra 複製。
3. `foundation`：`kms-key`、`sns-alarm-topic`、flow log 的 `s3-bucket`、`aws_secretsmanager_secret.opensearch_master`（容器，CMK，值在 Terraform 外寫入）、`glue-catalog-encryption`（選填物件 `glue_catalog_encryption`，`null` 不呼叫；dev、sit tfvars 都給值；description 與 tfvars 註解寫「同帳號第二個專案設 `null`」，design D13）。發布 design §7.2 的 4 個 key。
4. `network`：`vpc`（`app`、`data`、`nat_mode = "none"`、gateway endpoint `s3`、`dynamodb`）、`security-group`（Firehose→OpenSearch 443、Client VPN→OpenSearch 443 與 Redshift 5439、QuickSight→Redshift 5439、search admin runner→OpenSearch 443）。

驗收：

- `scripts/validate.sh templates/example4/infra/terraform/*/` 全過；`check-ssm-contract.sh` 通過；`stacks.sh dev all plan --dry-run` 依 ORDER 印出指令。
- `grep -rniE 'uat|prod' templates/example4` 沒有結果。
- 突變：SG 規則方向或 port 改錯、tfvars 的 `env` 跟檔名不同、`glue_catalog_encryption = null` 時仍建了 module、給了非 KMS ARN，都被抓到。

### G9：`vpn`、`storage`、`iam-base`

- `vpn`：兩個物件預設 `null` 時零資源，發布 `{"enabled":false}`；`envs/examples/vpn.tfvars` 示範開啟（mutual TLS、1 個 subnet 關聯、授權只到 data subnet）。
- `storage`：design §6 的四個 bucket（raw：`transitions`、`eventbridge = true`）、`glue-catalog`、`kinesis-stream`、`dynamodb-table`、`metric-alarm`。測試斷言 raw 的 `eventbridge` 是 true、其他 bucket 是 false。
- `iam-base`：design §8 的 6 個 role。`firehose` 只有 trust（測試斷言 inline policy 是空的）；`glue-events` 的 Resource 是命名規則組出的單一 workflow ARN、trust 的 `source_arn` 是單一 rule ARN（測試斷言字串完全相等，沒有 `*`）；其他 role 的 Resource 來自 `storage`、`foundation`，測試斷言沒有 `*`（`ec2:Describe*` 等白名單除外）。

驗收：同 G8；ORDER 加入三個 stack。

### G10：`search`、`search-config`

- `search`：`opensearch-domain`，dev、sit 都是 design §7.5 的冷熱規格；`access_principal_arns = [role_firehose_arn]`；`master_user_secret_arn` 讀 `foundation`；`metric-alarm`（ClusterStatus.red、FreeStorageSpace、JVMMemoryPressure；warm 指標名稱實作時核對）。`tests/tfvars/` 斷言兩個環境都有 warm 與 cold、master 不是 T3。
- `search-config`：`ephemeral "aws_secretsmanager_secret_version"` 讀 master 帳密；provider `opensearch` 用 `url`、`username`、`password`、`sign_aws_requests = false`；ISM 天數照 design §7.5；`writer_roles.firehose_writer.backend_role_arns = [role_firehose_arn]`；`ultrawarm_manager`、`cold_manager` 對應維運 role（tfvars，可空）。
- 先驗證 ephemeral 在 `terraform test` 的 mock 下能不能跑；不行就照 design §11 的備案，並回報使用者。
- lock：aws 的部分從其他 stack 複製；opensearch provider 給使用者一行指令（`terraform -chdir=templates/example4/infra/terraform/search-config init -backend=false` 與 `providers lock -platform=darwin_arm64 -platform=linux_amd64`），請他用 `!` 在這個 session 跑。

驗收：同 G8；S10 對 `search-config` 通過；突變：access policy 改成 `*`、ISM 少 `timestamp_field`、mapping `all_access`、dev 拿掉 warm，都被抓到。

### G11：`analytics`、`iam-app`、`pipeline`

- `analytics`：`athena-workgroup`。
- `iam-app`：`iam-role-policy` 對 `role_firehose_name` 附加 policy；`iam-role` 建 `quicksight-athena`。測試斷言 Resource。
- `pipeline`：
  - 兩條 `firehose-stream`：Kinesis→S3 raw（`prefix = "raw/..."`、`buffering_interval = 900`、`buffering_size = 64`）、Kinesis→OpenSearch（S3 備份寫 `errors/`）。
  - `glue-etl`：workflow `<project>-<env>-raw-to-curated`；`event_trigger = { bucket_name = raw, key_prefix = "raw/", role_arn = role_glue_events_arn, batch_size = 100, batch_window_seconds = 900, actions = [job] }`；raw crawler 每日 SCHEDULED。workflow 名稱必須跟 `iam-base` 組 ARN 的命名規則一致：`tests/` 斷言 `glue-etl` 的 `workflow_name` 等於 `iam-base` 用的同一個 local（兩個 stack 各自從 `name_prefix` 推，測試寫死期望值）。
  - `metric-alarm`（Firehose DataFreshness）。
  - 範例 job 腳本放 `templates/example4/etl/`（design K10），用 job bookmark。

驗收：同 G8；突變：Firehose policy 的 S3 Resource 改成整個 bucket、讀了更晚的 stack 的 key、rule 的前綴改成整個 bucket、workflow 名稱跟 `iam-base` 不一致，都被抓到。

### G12：`warehouse`、`bi`

- `warehouse`（design §7.3）：
  - `warehouse_mode` 與兩個物件的交叉 validation；兩個 module 各自 `count`，都 `depends_on` guard；`one(concat(...))` 收輸出；發布 5 個 key。
  - `guard.tf`：`terraform_data.warehouse_mode_guard`，`triggers_replace = var.warehouse_mode`、`prevent_destroy = true`。
  - `tests/warehouse.tftest.hcl`：兩種模式各一個 run（只建一個 module、5 個 key 有值、`triggers_replace == var.warehouse_mode`）；模式與物件不一致的負向 run。
  - `tests/check-warehouse-guard.sh`（可執行、只用 `grep`／`awk`、離線）：`guard.tf` 有 `prevent_destroy = true` 與 `triggers_replace = var.warehouse_mode`，兩個 module 都 `depends_on` guard。
  - dev、sit 預設 `serverless`，`envs/examples/provisioned.tfvars` 示範 provisioned。
  - `prevent_destroy` 本身 `terraform test` 驗證不了（design §2 第 19 點），驗證紀錄寫明，列為雲端驗證。
- `bi`：Athena 來源一定建；`redshift_secret_arn` 有給才建 Redshift 來源與 VPC connection；`redshift_host`、`port`、`database` 從 `warehouse` 讀，不看 `redshift_mode`。

驗收：同 G8；`check-ssm-contract.sh` 對 12 個 stack 通過；突變：`prevent_destroy` 改 `false`（`check-warehouse-guard.sh` 擋）、`triggers_replace` 改綁別的值（測試擋）、`bi` 改讀 `redshift_mode`、`publicly_accessible` 改 true、沒給 secret 卻建了 Redshift 來源，都被抓到。

### G13：收尾

- `templates/example4/infra/README.md`：
  - 第一段：dev、sit 各約 1,150–1,300 美元／月起，主要是 OpenSearch 冷熱（design §10，標為估計）。
  - stack 清單與 apply 順序、SSM 合約表。
  - 〈前置作業〉，依序：
    1. state bucket 的強化（design §4.2）：專用 CMK 並填進 `.tfbackend` 的 `kms_key_id`、bucket policy、舊版本 30 天過期、CloudTrail data event；
    2. 寫入 OpenSearch master secret 的值（`get-random-password`）；
    3. Glue catalog 加密「同帳號只能一處，第二個專案設 `null`」；
    4. QuickSight 訂閱與 secret 授權；
    5. Redshift 唯讀 DB user 與 secret；
    6. Lake Formation 用 IAM 模式；
    7. 特權操作清單（design §4）。
  - 〈安全例外〉：design §4.1 全文。
  - `search-config` 的執行環境。
  - 〈EventBridge 觸發〉：流程、batch 設定、觸發次數與成本估計、改回排程的方法（raw bucket `eventbridge = false`、`glue-etl` 拿掉 `event_trigger`、加 SCHEDULED trigger）。
  - 〈`warehouse_mode` 切換〉與〈destroy〉的 runbook，含本機解除 `prevent_destroy`、不 commit、還原後 plan 零差異；dev 拆環境會停在 `warehouse`。
  - destroy 前要做的事：清空 bucket、warm／cold index 先刪或搬回、DynamoDB 關 deletion protection、Redshift final snapshot 或 UNLOAD。
  - 已知限制、兩張驗證表。
- repo 根 `README.md`：範本表加 example4、module 表 56 個、〈文件地圖〉加 v7。
- [`project-infra-standard.md`](../../guides/project-infra-standard.md)：提到 example4；〈例外清單〉加 `search-config` 的 ephemeral 讀取，以及 S1 對「有 ephemeral 的 stack 可用離線 aws provider 測試」的例外。
- 全量 `scripts/validate.sh`。
- 驗證紀錄：
  - **靜態驗證通過**：`validate.sh`、`check-ssm-contract.sh`、`check-warehouse-guard.sh`、`stacks.sh --dry-run`、環境名稱 `grep`。
  - **雲端整合待驗證**：冷熱搬移（ISM）、warm 最小台數、Firehose 寫進 VPC 內的 OpenSearch（SigV4＋FGAC mapping）、Dashboards 的 basic auth 只能從 VPN 連、master 密碼輪替、S3 → EventBridge → Glue workflow 的批次觸發與實際次數、Glue job 成本、catalog 加密後各角色的 KMS 權限、Redshift Spectrum、`warehouse_mode` 切換被 `prevent_destroy` 擋下與解除流程、QuickSight 兩種來源、Client VPN、Site-to-Site 的 PSK 是否出現在 state、log group 層的 resource policy、`.tfbackend` 的 `kms_key_id`；實作後加入：Site-to-Site 的 `customer_gateway_configuration` 在 SecretsManager 模式下是否含 PSK、VPN 與 Client VPN 的 log 用 CMK 能否寫入、`ra3.large` single-node 在 Tokyo 的可用性、flow log 用 CMK 寫 S3、QuickSight VPC connection 的 ENI 權限、IAM 動作清單、OpenSearch 告警的 `ClientId`、範例 Glue job、`search-config` 從 Client VPN 執行。

驗收：全量通過；使用者審過 README 與兩張驗證表；`docs/design/v7` 的狀態改成已實作。
