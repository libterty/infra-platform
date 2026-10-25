# infra-platform v8 實作流程：IoT Edge AI module 與 templates/example5

> 狀態：H0–H9 完成，H10 起進行中（2026-10-25）。實作時跟設計不同的決定記在 design §14。這份只講「一步一步怎麼做、每步怎麼驗收」；兩份衝突時以 [`design-docs.md`](./design-docs.md) 為準，回頭改這份。
> 文中路徑除非特別註明，都是 repo 內相對路徑。「design §x」指 design-docs.md 的章節。example5 的路徑都在 `templates/example5/infra/terraform/` 底下。

## 結論

一個里程碑分 14 個 Phase（H0–H13）。先做 module（H1–H6）：17 個新 module，每個 Phase 合併後發版、HCP 登記並從消費端抓一次；全部在 HCP 上之後才做範本（H7–H13），因為範本 stack 從 HCP 抓 module（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

H1 的 `validate.sh` 變更（S4、S8 擴充到 awscc）要在任何 awscc module 之前合併。H2–H6 的 module 目錄互不重疊，在各自的 worktree 平行做；共用檔（`release-please-config.json`、根 `README.md`）由主 agent 在每個 Phase rebase 到 main 之後整合。

多個 release PR 同時存在時，合併一個之後其他的狀態會先變成 `UNKNOWN` 再變成衝突；做法是每個都照 [`releasing-modules.md`](../../guides/releasing-modules.md)〈同時有多個 release PR〉從 main 重建再 squash。連續發 17 版會用完 Actions 的 API 額度，Release run 失敗在 `API rate limit exceeded for installation`，等額度重置後重跑最後一次 Release run。

使用者授權（2026-10-25）：每個 Phase 驗證通過就 commit、開 PR，CI 綠燈就合併、發版、HCP 登記，不必逐一確認。只有需要使用者決定的事或擋住的問題才停下來問。

Phase 代號用 H，接在 v7 的 G 之後。

## 限制（每個 Phase、每個 subagent 都適用）

- 不碰 AWS：不准 `terraform plan`、`apply`、帶 backend 的 `init`、任何 `aws` 指令；tflint 不開 `deep_check`。Terraform 只透過 `scripts/validate.sh` 跑 `init -backend=false`、`validate`、`test`。
- 不准跑 `terraform providers lock`。awscc 與 opensearch provider 的 lock hash 由使用者在自己的終端機產生（design K5）。
- code、tfvars、tests、註解、commit message 只出現 `dev`、`sit` 兩個環境名稱。
- 佔位值：帳號 `111111111111`（dev）、`222222222222`（sit）、網段 `10.40.0.0/20`、`10.41.0.0/20`、網域 `example.com`、`<state-bucket>`、`<state-kms-key-arn>`。測試與範例不放真的憑證、密碼或私鑰。
- module 不建 `aws_iam_*`、`awscc_iam_*`、SG（S4），不用 `random_password`（S7）。範本 stack 只呼叫 module（S8），沿用 example4 的例外。
- 一個 commit 只動一個 module 目錄；新 module 用 `feat(<module>)`；PR 用 merge commit 合併（[`releasing-modules.md`](../../guides/releasing-modules.md)）。
- `description` 用台灣繁體中文；註解與 `error_message` 用英文。README 表格由 terraform-docs 產生（S11）。
- example2、example3、example4、project-infra 與既有 module 不能有任何變動：每個 Phase 驗收都確認 `git diff origin/main -- templates/example2 templates/example3 templates/example4 templates/project-infra` 是空的，`modules/` 底下只有新 module 的目錄。
- worktree 裡的 `.cache` 一律 symlink 到主 repo 的 `.cache`，不要複製（2.3 GB）。

## Phase 表

| Phase | 內容 | 狀態 | PR |
|---|---|---|---|
| H0 | v8 設計文件與實作流程 | 完成 | #213 |
| H1 | `validate.sh` S4、S8 擴充到 awscc；`sqs-queue`、`eventbridge-rule`、`scheduler-schedule` | 完成：發版、HCP ok | #215 |
| H2 | `iot-fleet`、`iot-account-settings`、`iot-topic-rule` | 完成：發版、HCP ok | #219 |
| H3 | `ota-signing`、`acm-pca` | 完成：發版、HCP ok | #223 |
| H4 | `greengrass-component`、`greengrass-deployment`、`iot-job-template` | 完成：發版、HCP ok | #224 |
| H5 | `iot-device-defender`、`iotsitewise`、`kinesis-video-stream` | 完成：發版、HCP ok | #227 |
| H6 | `sagemaker-model-registry`、`sagemaker-pipeline`、`sagemaker-endpoint` | 合併；發版中 | #231 |
| H7 | example5 骨架、`foundation`、`network`、`vpn`、`pki` | 完成（`pki` 跟 H8、H9 一起） | #214、#238 |
| H8 | `storage`、`iam-base` | 完成 | #238 |
| H9 | `search`、`search-config` | 完成 | #238 |
| H10 | `fleet`、`iam-app`、`ingest` | | |
| H11 | `sitewise`、`edge` | | |
| H12 | `ml`、`inference` | | |
| H13 | README、架構圖、REFERENCE、全量驗證、驗證表 | | |

## 每個 Phase 的做法與驗收

### H0：設計文件

做法：`docs/design/v8/design-docs.md`、`implement-process.md`。`docs:` commit，不發版。

驗收：使用者看過設計（2026-10-25 授權開始實作）。

### H1：驗證規則與通用 module

1. `chore(repo)` commit：`scripts/validate.sh` 的 S4 加 `awscc_iam_` 與 `awscc_ec2_security_group`（含 ingress／egress）前綴，S8 掃 `resource "awscc_`；例外清單不加 awscc。用暫存目錄的假 module 與假 stack 確認新規則擋得到、既有目錄全過。
2. `sqs-queue`、`eventbridge-rule`、`scheduler-schedule`（design §5.8、§5.15、§5.16），照下面的 module 共用做法。

驗收：全量 `scripts/validate.sh` 通過；假 module 裡的 `awscc_iam_role` 被 S4 擋、假 stack 裡的 `awscc_*` 被 S8 擋。

### 每個 module Phase 共用的做法（H1–H6）

每個新 module：

1. 建目錄：`versions.tf`、`variables.tf`、`main.tf`、`outputs.tf`、`README.md`（用法、〈注意〉、〈刻意不做〉、terraform-docs marker）、`examples/<name>/main.tf`、`tests/*.tftest.hcl`。版本限制：aws `>= 6.0, < 7.0`；awscc `>= 1.107, < 2.0`（design K1）；`required_version = ">= 1.10"`。
2. TDD：先寫 design §9 的 run（正向與每條 validation 的負向），跑 `scripts/validate.sh modules/<m>` 看到失敗，再實作到全過。
3. `terraform-docs -c .terraform-docs.yml modules/<m>` 產生表格。
4. 一個 module 一個 `feat(<m>): ...` commit。
5. 主 agent 整合：`release-please-config.json` 加 `"initial-version": "0.1.0"` 的一列（manifest 不加）；根 `README.md` 的 module 表加一列、module 數量改正（最後是 73）。不先建 `CHANGELOG.md`。

驗收（每個 module）：

- `scripts/validate.sh modules/<m>` 全過。
- 突變：每條固定的安全設定（CMK 必填、`ROLLBACK`、`sql_version`、network isolation、不開 CRL 等）各改一次，測試要抓到。
- `grep` 確認 module 裡沒有 `aws_iam_`、`awscc_iam_`、`aws_security_group`、`awscc_ec2_security_group`、`random_password`。
- awscc module 的 tag 轉換有測試斷言（design K3）。

### 發版（每個 module Phase 合併後）

照 [`releasing-modules.md`](../../guides/releasing-modules.md) 與 v7 的經驗：

1. 合併 Phase 的 PR（merge commit）。stacked PR 的上層合併前先確認 base 是 `main`，合併後用 `git merge-base --is-ancestor` 確認進了 main。
2. 每個 module 一個 release PR；看過 diff，一次合併一個，等 Release run 跑完、`gh release view <m>-v0.1.0` 查得到才合下一個。tag 已經存在的 release PR 直接關掉。
3. 新 module 照 [`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md) §3 用 API 登記（registry 的 provider 名稱一律 `aws`，awscc module 也一樣，消費端地址保持 `app.terraform.io/libterty/<module>/aws`），§4 從消費端抓一次確認。

驗收：每個 module 有 tag 與 GitHub Release；HCP `version-statuses` 是 `ok`；消費端 `terraform get` 抓得到；所有 CI 與 Release run 綠燈。

### H2–H6：module 的未確認事項

實作時先核對，跟設計衝突的記進 design §14；需要使用者決定的才問。

- H2：`aws_iot_logging_options` 是否對應 `SetV2LoggingOptions`；provisioning template 的 `type`（`FLEET_PROVISIONING`）；thing group 階層的建立順序。
- H3：Signer 有效期的上限；`AWSIoTDeviceManagement-SHA256-ECDSA` 是否需要 `signing_material`；ACM PCA 的 `key_storage_security_standard` 在 Tokyo 的預設；IoT Core 連線時是否查 CRL。
- H4：awscc `inline_recipe`（write-only）在 plan 的表現；`components` map 的 nested 屬性；job template 的 `document` 與 `document_source` 擇一。
- H5：KVS edge connector 要的 SiteWise asset model 欄位；`awscc_iot_account_audit_configuration` 的 check 名稱格式；mitigation action 的參數。
- H6：`aws_sagemaker_model` 用 `model_package_name` 時能否同時給 `image`；serverless 與 `enable_network_isolation`；blue/green 的 traffic routing 參數。

### H7–H12：範本

前提：H1–H6 的 module 都在 HCP 上。

共用做法：照 example4（v7 implement-process G8–G12）。每個 stack 的固定檔：`common.tf`（所有 stack 一字不差）、`versions.tf`、`providers.tf`、`envs/{dev,sit}.tfvars`、`envs/{dev,sit}.tfbackend`（含 `kms_key_id` 佔位）、`tests/`、`tests/tfvars/`；aws 的 lock 從 example4 複製。用到 awscc 的 stack（`fleet`、`sitewise`、`edge`）：`provider "awscc"` 跟 `provider "aws"` 用同一組 `aws_region`、`deploy_role_arn`（design K4），測試斷言；lock 請使用者產生（給一行指令，用 `!` 在 session 裡跑）。

- H7：`stacks.sh`、`check-ssm-contract.sh`（只改 ORDER）、`foundation`、`network`、`vpn`（只有 Client VPN，預設零資源）、`pki`（預設零資源，`envs/examples/pki.tfvars` 示範開啟）。
- H8：`storage`（design §7.2 的 bucket、Kinesis、兩個 SQS）、`iam-base`（design §8，Resource 斷言）。
- H9：`search`、`search-config` 從 example4 複製；`project-infra-standard.md`〈例外清單〉加 example5（design K30）。
- H10：`fleet`（design §4.1 的 provisioning template 與 thing group、帳號層設定的選填物件）、`iam-app`、`ingest`（IoT rule → Kinesis、Firehose 兩條）。
- H11：`sitewise`、`edge`（`edge/components/` 的範例 recipe、precondition、`cameras`）。
- H12：`ml`（範例 pipeline definition、排程、核准事件）、`inference`（預設零資源）。

驗收（每個範本 Phase）：

- `scripts/validate.sh templates/example5/infra/terraform/<stack>/` 全過；`check-ssm-contract.sh` 通過；`stacks.sh dev all plan --dry-run` 依 ORDER 印出指令。
- `grep -rniE 'uat|prod' templates/example5` 沒有結果。
- 突變：IAM Resource 改成 `*`、讀了更晚的 stack 的 key、預設零資源的 stack 多建了資源、`edge` 引用不存在的元件版本，都被抓到。

### H13：收尾

- `templates/example5/infra/README.md`（66–90 行，跟其他範本一樣精簡）、`infra/REFERENCE.md`（SSM 合約、前置作業、安全取捨 design §4.1、runbook、驗證表）、`infra/architecture.drawio.svg`。
- 根 `README.md`：範本表加 example5、module 表 73 個、〈文件地圖〉加 v8。
- 全量 `scripts/validate.sh`。
- design、implement-process 的狀態改成已實作。

驗收：全量通過；所有 CI 與 Release run 綠燈；每個 module 的最新 tag 等於 main；HCP 全部 `ok`。
