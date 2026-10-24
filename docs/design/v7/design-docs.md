# infra-platform v7 設計文件：資料平台 module 與 templates/example4

> 狀態：已實作（2026-10-24，G0–G13，見 [`implement-process.md`](./implement-process.md)）。§3.1 的 D1–D16 是使用者拍板的決策；§3.2 的 K 是照慣例的判斷。實作時跟設計不同的決定記在 §14，兩邊不同時以 §14 與程式碼為準。
> 範圍：新增資料平台用的 module（OpenSearch、DynamoDB、Glue、Redshift、Athena、QuickSight、Kinesis、Firehose、Site-to-Site VPN、Client VPN，以及 Glue Data Catalog 的帳號層加密），`s3-bucket` 升 0.4.0，照 `templates/project-infra` 的標準新建獨立範本 `templates/example4`。不改 example2、example3、project-infra。
> 文中路徑除非特別註明，都是 repo 內相對路徑。example4 的路徑都在 `templates/example4/infra/terraform/` 底下，下文省略這段前綴。
> provider schema、AWS 行為與價格是 2026-10-24 查證的結果，怎麼查與來源列在 §13。標「未確認」的要在實作或真實環境驗證。環境只有 `dev`、`sit`。

## 1. 結論

- **新 module 14 個**，每個發 0.1.0、在 HCP 登記：`opensearch-domain`、`opensearch-config`、`dynamodb-table`、`kinesis-stream`、`firehose-stream`、`glue-catalog`、`glue-catalog-encryption`、`glue-etl`、`athena-workgroup`、`redshift-serverless`、`redshift-cluster`、`quicksight-data`、`vpn-site-to-site`、`client-vpn`。repo 的 module 從 42 個變成 56 個。
- **`s3-bucket` 0.4.0**：加 `transitions`（lifecycle 分層）與 `eventbridge`（S3 事件送 EventBridge）。不加 bucket policy 白名單：同帳號的服務都用自己 role 的 identity policy 存取 bucket（§2 第 8 點）。
- **module 不建 IAM、不建 SG**（S4）。example4 照 project-infra 拆 `iam-base`（之後的資源一建立就要用的 role）與 `iam-app`（要等資源存在才寫得出 ARN 的 policy），module 只收 role ARN（§8）。
- **資料管線**：Kinesis Data Streams → Firehose → S3 raw（GZIP JSON）→ S3 事件經 EventBridge 觸發 Glue workflow（批次觸發）→ Glue job 轉 Parquet 寫 curated 並更新 catalog → Athena 查詢、Redshift 用 Spectrum 或 COPY 讀 curated → QuickSight。另一條分支 Firehose → VPC 內的 OpenSearch（hot），ISM 搬到 UltraWarm 再到 cold。
- **Firehose 不直送 Redshift**：AWS 規定 Firehose 的 Redshift 目的地必須 publicly accessible（§2 第 1 點），跟「Redshift 不公開」衝突。
- **OpenSearch**：dev 與 sit 都是完整冷熱（3 台 dedicated master、2 台 hot data、2 台 UltraWarm、cold），每個環境約 1,052 美元／月；example4 兩個環境合計約 2,400–2,450 美元／月（§10）。
- **OpenSearch 的 master user 用 internal user database 帳密**，密碼會進 `search` stack 的 state。這是寫明的安全例外，有補償控制與移除的 checkpoint（§4.1）。
- **ISM 與 FGAC 設定**用 `opensearch-config`（opensearch provider），`search-config` stack 從 VPC 內執行，用 master 帳密的 basic auth，帳密以 ephemeral 讀取，不進 state。
- **Redshift**：tfvars `warehouse_mode` 在 Serverless 與 provisioned 之間切換，兩種都發布同名的 host、port、database；`terraform_data` 加 `prevent_destroy` 擋住誤切（§7.3）。
- **Glue Data Catalog 加密**：帳號層 module `glue-catalog-encryption`，由 `foundation` 依選填輸入呼叫；同帳號的第二個專案要設 `null`（§5.7）。
- **example4**：12 個 stack，ORDER `foundation network vpn storage iam-base search search-config analytics iam-app pipeline warehouse bi`。VPN stack 預設零資源。
- **state bucket 不歸範本管**：它在範本外由 platform team 或帳號開通時建立（[v1 design §5.5](../v1/design-docs.md)）。§4.1 要求的強化（專用 CMK、bucket policy、舊版本過期、CloudTrail）寫成 example4 README 的前置作業（§4.2）。
- **Phase**：G0 文件；G1–G7 module；G8–G13 範本。範本 Phase 等它用到的 module 都在 HCP 上才開始（§12）。
- **不碰 AWS**：只跑 [`scripts/validate.sh`](../../../scripts/validate.sh)。

## 2. 查證發現

1. **Firehose 的 Redshift 目的地要求 Redshift 公開**：「If your Amazon Redshift provisioned cluster or Amazon Redshift Serverless workgroup is in a virtual private cloud (VPC), it must be publicly accessible with a public IP address」（§13 Firehose）。`firehose-stream` 不做 Redshift 目的地。
2. **aws provider 沒有 ISM、index template、role mapping 的 resource**。opensearch-project/opensearch provider（2.6.0）有 `opensearch_ism_policy`、`opensearch_role`、`opensearch_roles_mapping`、`opensearch_composable_index_template`、`opensearch_user` 等，provider 設定支援 `username`、`password`（basic auth，搭配 `sign_aws_requests = false`）。執行端要連得到 domain endpoint。
3. **UltraWarm／cold 的前置條件**：OpenSearch 6.8 以上（cold 7.9 以上）、要有 dedicated master、data node 不能是 T2/T3、Multi-AZ with Standby 時 warm 數量要是 AZ 數的倍數、cold 必須同時開 warm、ISM 搬到 cold 一定要有 `timestamp_field`、啟用後 UltraWarm 可能要幾小時才能用；warm index 唯讀；停用 warm／cold 前要先刪掉或搬回所有 index。設定 API：`DedicatedMasterCount`「must be greater than 2 and not 4」，`InstanceCount`「must be greater than 1」，`WarmType` 只有 `ultrawarm1.medium|large|xlarge.search`。warm 最小台數、T3 master 能不能搭 UltraWarm，文件沒寫（未確認）。quotas 頁另列 OI2（`oi2.*.search`）可當 warm node，provider 的寫法未確認。
4. **`aws_opensearch_domain` 的 `master_user_password` 沒有 write-only 版本**；aws provider 有 ephemeral `aws_secretsmanager_secret_version`，但 ephemeral 值只能用在 provider 設定、write-only 屬性、locals 這類地方，不能接到這個屬性。所以用 internal user database 時，密碼至少以 domain 屬性的形式留在 state 一份。
5. **basic auth 的請求不經過 domain access policy**：「HTTP Basic Auth requests bypass the access policy and are controlled entirely by fine-grained access control roles」；SigV4 的請求則兩層都要過。access policy 可以只列 IAM principal（例如 Firehose role）。FGAC 開了不能關；master user 之後可以換成 IAM（換了就關掉 basic auth）。Firehose 寫入要一個 FGAC role（`cluster_composite_ops`、`cluster_monitor`；index `create_index`、`manage`、`crud`）並把 Firehose 的 IAM role 對應成 backend role。VPC 內 role mapping 的 `hosts` 不生效。
6. **QuickSight**（文件已改名 Amazon Quick Sight，API 與 provider 仍是 `quicksight`）：provider 的 `parameters.redshift` 只有 `cluster_id`、`host`、`port`、`database`，沒有 IAM 參數，只能用 `credentials.secret_arn` 或 `credential_pair`（密碼進 state）。用 secret 時，QuickSight 管理者要在主控台勾選 secret，而且「Amazon Quick authorizes `secretsmanager:GetSecretValue` access to the secret based on the API caller's IAM policy」，所以 deploy role 要能讀那個 secret；secret 要有 `username`、`password`。Athena 來源可以指定自己的 role（`parameters.athena.role_arn`）。
7. **Firehose 其他限制**：Parquet 轉換一定要有 Glue table（`schema_configuration.table_name` 必填）；來源是 Kinesis 時 at-rest 加密在 stream 端，SSE 只給 Direct PUT；VPC 內的 OpenSearch 目的地，role 要 8 個 `ec2:*NetworkInterface*`／`Describe*` 動作，建好後不能收回；CMK 要 symmetric。
8. **同帳號的服務存取 S3 不需要 bucket policy**：Firehose、Glue、Redshift、Athena、QuickSight 都 assume 我們給的 role。Redshift 稽核 log 寫 S3 才需要 bucket policy，改寫 CloudWatch Logs 就避開了（provider 6.x 的 `aws_redshift_logging.log_destination_type`）。
9. **s3-bucket 0.3.1 的缺口**：只有一條 expiration rule，沒有 transition；notification 只有 Lambda；README〈刻意不做〉明列 EventBridge 與其他 principal 寫入的 bucket policy。
10. **EventBridge 驅動 Glue**：Glue workflow 用 `type = "EVENT"` 的 trigger 當**起始 trigger**；`event_batching_condition { batch_size, batch_window }`：`BatchSize` 1–100 必填，`BatchWindow` 1–900 秒，沒給是 900，視窗從第一個事件開始算，兩者先到先觸發。EventBridge 的 target 是 workflow ARN，要一個讓 EventBridge assume 的 role，權限是對該 workflow 的 `glue:notifyEvent`。Glue「does not provide guaranteed delivery… performs no deduplication」，處理要冪等。S3 開 EventBridge 通知後的事件是 `source = "aws.s3"`、`detail-type = "Object Created"`，欄位 `detail.bucket.name`、`detail.object.key`，不需要 CloudTrail（Glue 文件的範例走 CloudTrail 是舊做法）。provider 6.x 有 `aws_cloudwatch_event_rule`、`aws_cloudwatch_event_target`，`aws_s3_bucket_notification.eventbridge`；repo 沒有 EventBridge 的 module。
11. **S4、S8 的影響**：module 不能建 `aws_iam_*`（Client VPN 的 SAML provider、EventBridge 的 role 都不能放 module）；範本 stack 不能宣告例外清單以外的 `aws_*` resource（EventBridge rule 不能直接寫在 stack）。`terraform_data` 與 ephemeral block 不是 `aws_*`，S8 不擋；`foundation` 已允許 `aws_secretsmanager_secret`。`iam-role` 的白名單沒有 Glue 這類 managed policy，資料服務的 role 一律 inline。
12. **service-linked role 會自動建立**，前提是 apply 的身分有 `iam:CreateServiceLinkedRole`。
13. **Site-to-Site VPN 的 PSK 預設進 state**（provider 文件：「will be stored in the raw state as plain-text」），設 `preshared_key_storage = "SecretsManager"` 就改存 Secrets Manager；`customer_gateway_configuration` 在這個模式下是否含 PSK 未確認。
14. **Redshift**：Serverless base 最低 4 RPU，Tokyo 支援；4 RPU 建議 32 TB、100 欄以內，擴到 8 以上就不會縮回 4；沒開 EVR 至少 2 個 subnet 跨 2 AZ，開了要 3 AZ。**`aws_redshiftserverless_namespace` 沒有任何 final snapshot 屬性**，刪掉就沒了；`aws_redshift_cluster` 有 `skip_final_snapshot`。provisioned 的 `ra3.large`、`ra3.xlplus` 有 single-node（文件說不建議 production）。6.x 的 `aws_redshift_cluster` 把 logging 與 snapshot copy 拆成獨立 resource；`admin_username` 是 sensitive。
15. **DynamoDB**：6.x 的 GSI `hash_key`／`range_key` 已 deprecated，改用 GSI 裡的 `key_schema`；contributor insights 與 resource policy 是獨立 resource。
16. **tflint aws ruleset 0.49.0 抓不到 OpenSearch 與 Redshift 的規格值**：故意寫錯 `aws_opensearch_domain` 的 `instance_type`、`warm_type`、`aws_redshift_cluster` 的 `node_type`（`ra3.bogus`）都沒被抓；DynamoDB 的 `billing_mode`、Kinesis 的 `encryption_type`、Glue trigger 的 `type`、Client VPN 的 `transport_protocol` 會被抓。規格值要靠 module validation。
17. **Glue Data Catalog 的加密是帳號加 region 一份**（`aws_glue_data_catalog_encryption_settings`）。前例 [`xray-transaction-search`](../../../modules/xray-transaction-search/README.md) 寫「每個帳號、每個 region 只能由一處呼叫…不要放進專案範本的 stack」。開了 CMK 加密後，所有讀寫 catalog 的身分都要有那把 key 的權限，包括同帳號其他專案。
18. **state bucket 在範本外**：[v1 design §5.5](../v1/design-docs.md) 寫「放 state 的帳號一個 bucket，不在專案 stack 裡建（由 platform team 或帳號開通時建好）；開 versioning、SSE、Block Public Access」；範本的 `.tfbackend` 只有 `<state-bucket>` 佔位、`encrypt = true`、`use_lockfile = true`。Terraform 文件只寫 `encrypt`「Enable server side encryption」、`kms_key_id` 指定 KMS key，沒寫不給 `kms_key_id` 時用哪種加密，所以要用專用 CMK 就在 `.tfbackend` 明寫 `kms_key_id`。HCP 只當 module registry（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。
19. **`prevent_destroy`**：Terraform 文件：「Terraform rejects plans that would destroy the infrastructure object… and returns an error」、會擋 `terraform destroy`、只能寫字面值、拿掉設定就不再保護。`terraform_data` 的 `triggers_replace`：「Terraform replaces the resource when the value changes」。兩者合起來：`triggers_replace` 綁 `warehouse_mode`，模式一改就要 replace（先 destroy），plan 就被擋。文件沒有明寫「replace 也算 destroy」，這是推論，沒有實測。`terraform test` 的 `expect_failures` 只接受可檢查的物件（變數、output、check、resource 的 condition），抓不到 `prevent_destroy` 的錯誤；`command = plan` 的 run 也沒有既有 state，觸發不了。
20. **opensearch provider 是第二個 provider**：`search-config` 的 lock 要 darwin＋linux 兩個 `h1:`（S10），由使用者在自己的終端機產生（同 v4 E13）。
21. **範本從 HCP 抓 module**：module 沒發版、HCP 沒登記之前，範本的 init 會失敗（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

## 3. 決策

### 3.1 使用者拍板（2026-10-24）

| # | 主題 | 決定 | 理由 |
|---|---|---|---|
| D1 | ISM 與 FGAC 設定 | 新 module `opensearch-config`（opensearch provider）；example4 加 `search-config` stack，從 VPC 或連得到的網路執行；lock 由使用者產生 | ISM 是冷熱架構的核心，要能審查、能偵測漂移；repo 已有 module 用第二個 provider、stack 從 VPC 執行的前例（example3 `eks-addons`） |
| D2 | OpenSearch 存取控制 | **使用者選擇**：FGAC 開，master user 用 internal user database 帳密，Dashboards 立即可用；接受密碼進 state。規劃時建議的是 IAM master user | 安全例外見 §4.1 |
| D3 | module 拆法 | Glue 拆 `glue-catalog`＋`glue-etl`；VPN 拆 `vpn-site-to-site`＋`client-vpn`；Redshift 拆 `redshift-serverless`＋`redshift-cluster`；OpenSearch 一個 `opensearch-domain` | resource 不重疊、擁有者與變動頻率不同；Redshift 兩種沒有共用 resource，不學 `rds` |
| D4 | `s3-bucket` | **使用者選擇**：加 `transitions` 與 EventBridge 通知開關，發 0.4.0；不做 bucket policy 白名單。規劃時建議的是只加 `transitions` | D14 用到 EventBridge |
| D5 | Firehose 輸出 | GZIP JSON 寫 raw，Glue job 轉 Parquet 寫 curated；不開 dynamic partitioning | 不必在 Terraform 定義 Glue table |
| D6 | OpenSearch 在 dev、sit | **使用者選擇**：dev 與 sit 都開完整冷熱。規劃時建議的是 dev 只有 hot | 兩個環境行為一致；每個環境約 1,052 美元／月（§10）；master 不用 T3 |
| D7 | 範本的 Redshift | **使用者選擇**：tfvars 在 Serverless 與 provisioned 之間切換。規劃時建議的是只用 Serverless | 設計見 §7.3 |
| D8 | Client VPN 驗證 | module 支援 mutual TLS、SAML、兩者並用；範本預設 mutual TLS，VPN stack 預設關閉；SAML provider 在外部建，ARN 從 tfvars 給 | S4 不准 module 建 SAML provider |
| D9 | Site-to-Site 終點 | module 支援自建 VGW 或既有 TGW 擇一，範本用 VGW；PSK 一律 `SecretsManager`，module 不收 PSK | PSK 不進 state |
| D10 | QuickSight 連 Redshift | 專用唯讀 DB user，secret 在 repo 外建立，ARN 從 tfvars 給；沒給就只建 Athena data source | 最小權限 |
| D11 | IAM stack | **使用者選擇**：學 project-infra 拆 `iam-base`／`iam-app`。規劃時建議的是一個 `iam` | 依 [ADR-0002](../../adr/0002-split-state-by-owner-and-change-rate.md) 的兩段式；拆法見 §8 |
| D12 | Glue Data Catalog 加密 | **使用者選擇**：帳號層 module `glue-catalog-encryption`，`foundation` 呼叫。規劃時建議的是範本不管 | catalog metadata 用 CMK 加密 |
| D13 | `glue-catalog-encryption` 的呼叫方式 | `foundation` 收選填物件 `glue_catalog_encryption`，`null` 就不呼叫；example4 的 dev、sit tfvars 都給值；README 寫「同帳號的第二個專案要設 `null`」 | 跟 `xray-transaction-search` 的前例有張力（§2 第 17 點），留一個明確的關閉方式 |
| D14 | 範本用 EventBridge 驅動 ETL | **使用者選擇**：擴充 `glue-etl` 支援事件觸發（Glue workflow 的 EVENT trigger，含 batch size／window）；範本用 `s3-bucket` 的 EventBridge 開關＋EventBridge rule／target＋role 驅動 raw → Glue workflow。規劃時建議的是範本照排程 | 設計見 §7.4 |
| D15 | state 的補償控制 | 維持 S3 backend，強化：專用 CMK、bucket policy 只允許 deploy role 與 break-glass role、舊版本 30 天過期、CloudTrail 記錄讀取 | state bucket 在範本外，控制寫成前置作業（§4.2） |
| D16 | `warehouse_mode` 切換防呆 | **使用者選擇**：`terraform_data`＋`prevent_destroy` 擋住誤切。規劃時建議的是只靠 runbook | 設計、解除步驟、能驗證到哪裡見 §7.3 |

### 3.2 照慣例的判斷（審閱時可以推翻）

| # | 判斷 | 理由 |
|---|---|---|
| K1 | 新 module 一律發 0.1.0，`release-please-config.json` 加 `"initial-version": "0.1.0"`，CHANGELOG 只放 `# Changelog` | [`releasing-modules.md`](../../guides/releasing-modules.md)〈新增 module〉 |
| K2 | 每個 module 收 `kms_key_arn`，資料類資源**必填** CMK；module 自己建的 log group 用同一把 key；key 由 `foundation` 用 `kms-key` 建 | 照 `elasticache-redis`、`rds` |
| K3 | 密碼一律交給服務代管或從 Secrets Manager 讀：`redshift-serverless`、`redshift-cluster`、`opensearch-domain` 都沒有 password 變數，S7 擴充到這三個 module | 照 `rds` |
| K4 | OpenSearch、Redshift 一律在 VPC 內，`publicly_accessible = false` 寫死 | 安全原則 |
| K5 | OpenSearch `enforce_https = true`、`Policy-Min-TLS-1-2-PFS-2023-10` 寫死；Redshift `require_ssl = true`（Serverless 的 config key 未確認） | 加密傳輸不留開關 |
| K6 | log group 由 module 自己建；OpenSearch 的 log resource policy 用掛在 log group 上的版本（`aws_cloudwatch_log_resource_policy.resource_arn`，OpenSearch 支不支援未確認，不支援就退回帳號層 policy） | 照 `rds`、`xray-transaction-search` |
| K7 | v7 的 module 不內建告警；範本用既有的 `metric-alarm` | 不重造 |
| K8 | 資源要不要建由輸入是否為 `null`／空決定。`s3-bucket` 的 `eventbridge` 是布林，對應 S3 API 的同名屬性，預設 `false`，跟既有的 `never_expire`、`force_destroy` 同類 | module 規則 |
| K9 | 測試：`mock_provider "aws"`、`command = plan`、每條 validation 正反各一個 run、至少一個 example；`opensearch-config` 另外 `mock_provider "opensearch"` | S1 |
| K10 | Glue job 腳本放 `templates/example4/etl/`，由 CI 上傳到 `glue-assets` bucket；Terraform 不上傳物件 | S8 |
| K11 | Kinesis：dev、sit 用 provisioned 1 shard | 成本 |
| K12 | VPC：`nat_mode = "none"`，gateway endpoint `s3`、`dynamodb`；不建 interface endpoint；Glue job 不放進 VPC | 成本 |
| K13 | `common.tf`、`providers.tf`、`versions.tf` 從 project-infra 複製，`accounts_by_env` 改 `dev`、`sit`；aws 的 lock 從既有 stack 複製 | S5、S10 |
| K14 | `check-ssm-contract.sh` 與 `stacks.sh` 從 project-infra 複製，只改 ORDER | 三份範本操作一致 |
| K15 | 佔位值：帳號 `111111111111`（dev）、`222222222222`（sit）、網段 `10.30.0.0/20`、`10.31.0.0/20`、網域 `example.com` | 跟既有範本一致 |
| K16 | `warehouse_mode` 的預設：dev、sit 都是 `serverless`；`envs/examples/provisioned.tfvars` 示範 provisioned | Serverless 沒查詢時不計算費、可封頂 |
| K17 | OpenSearch：master 3 × `m7g.large.search`、data 2 × `m7g.large.search`（20 GiB gp3）、warm 2 × `ultrawarm1.medium.search` | D6；不用相容性未確認的 T3 master；warm 最小台數未確認，取 2 |
| K18 | 人員登入 Dashboards 不共用 master：master 只給 `search-config` 與緊急使用；人員帳號由 master 在 Dashboards 建，不經 Terraform（`opensearch_user` 也會讓密碼進 state） | 縮小 §4.1 例外的影響 |
| K19 | `search-config` 用 `ephemeral "aws_secretsmanager_secret_version"` 讀 master 帳密餵給 opensearch provider；這是範本 stack 第一個 ephemeral block，[`project-infra-standard.md`](../../guides/project-infra-standard.md)〈例外清單〉加一列 | ephemeral 值不進 state；provider 設定只能在 stack |
| K20 | EventBridge rule 與 target 放在 `glue-etl` module 裡（輸入 `event_trigger`），EventBridge 的 role 在 `iam-base` 建 | S8 不准 stack 寫 `aws_cloudwatch_event_*`；S4 不准 module 建 role；不必多一個 EventBridge module（§7.4） |
| K21 | EventBridge role 的 policy 在 `iam-base` 就寫好，Resource 用命名規則組出的**單一** workflow ARN（`workflow/<project>-<env>-raw-to-curated`），trust 帶 `source_arn` = 單一 rule ARN | workflow 在 `pipeline` 才建，`iam-base` 拿不到 SSM 的值；project-infra `iam-base` 用命名規則限定 log group 是前例（`/ecs/${name_prefix}-*`）；這裡更窄，不用萬用字元 |
| K22 | 事件觸發的 workflow 只跑 job（job bookmark 增量處理、寫 curated 時更新 catalog），不在每次事件跑 crawler；raw 的 crawler 每日排程一次 | crawler 每次執行有最低計費時間（實作時核對），跟著事件跑會放大成本 |
| K23 | `warehouse` 的防呆解除是**本機暫時修改、不 commit**：執行切換或拆環境的人在自己的工作目錄把 `prevent_destroy` 改成 `false`、apply 完還原；`tests/check-warehouse-guard.sh` 在 CI 擋住任何把它改掉的 commit | D16 要「改程式碼才能切換」；放進 commit 就等於永久拿掉防呆 |
| K24 | example4 的 `.tfbackend` 多一行 `kms_key_id = "<state-kms-key-arn>"` 佔位；其他範本不動 | D15 的專用 CMK；S6 只檢查 `key` 那一行 |

## 4. trust boundary 與特權操作

| 邊界 | 誰 → 誰 | 控制 |
|---|---|---|
| 資料進入 | producer → Kinesis | producer 的 IAM 只給 `kinesis:PutRecord(s)` 到單一 stream；stream 用 CMK |
| 管線內部 | Firehose → S3 raw、OpenSearch | role 只能寫 raw 的 `raw/`、`errors/`、讀單一 stream、對單一 domain 的 `es:ESHttpPost`／`Put`／`Get`；domain access policy 只列 Firehose role；FGAC 只給 `firehose_writer`（index 前綴）；trust 帶 `aws:SourceAccount` |
| 事件 | S3 → EventBridge → Glue workflow | rule 只比對 raw bucket 的 `raw/` 前綴；EventBridge role 只能對單一 workflow `glue:notifyEvent`，trust 限單一 rule |
| ETL | Glue → raw 讀、curated 寫、catalog | crawler 與 job 分兩個 role；catalog 只到兩個 database |
| 倉儲 | Redshift → curated、catalog | 只讀 |
| BI | QuickSight → Athena、Redshift | Athena 用 data source 專用 role；Redshift 走 VPC connection 與唯讀 DB user（D10） |
| 人 → OpenSearch | 工程師 → Dashboards（basic auth） | 不經過 access policy，只靠網路與 FGAC：SG 只放 Client VPN 與 VPC 內 runner 的 443；個人 internal user（K18）；`AUDIT_LOGS` 開 |
| 人 → VPC | 工程師 → VPC | Client VPN mutual TLS，authorization rule 只放 data subnet 的 CIDR；連線 log 必開 |
| 跨站 | 地端 → VPC | Site-to-Site VPN，只路由指定 CIDR；PSK 在 Secrets Manager |

執行 apply 的身分需要的特權操作（README 要列）：`iam:CreateServiceLinkedRole`（OpenSearch、Redshift、Client VPN 第一次建立時）、`iam:PassRole`（Firehose、Glue、Redshift、QuickSight、EventBridge 的 role）、`kms:CreateGrant`（Redshift、Firehose CMK）、`secretsmanager:GetSecretValue`（OpenSearch master secret：`search`、`search-config`；QuickSight 的 Redshift secret：`bi`）、`glue:PutDataCatalogEncryptionSettings`（`foundation`）、`events:PutRule`／`PutTargets`（`pipeline`）。

### 4.1 安全例外：OpenSearch master 帳密進 state（D2）

| 項目 | 內容 |
|---|---|
| 例外 | master user 用 internal user database，密碼以明文出現在 `search` stack 的 state：`aws_opensearch_domain` 的 `master_user_password` 一份，`opensearch-domain` module 讀 secret 的 data source 一份，共兩份。plan 輸出標 sensitive |
| 風險 | 讀得到 `search` state 的人等於拿到 `all_access` 與 `security_manager`。basic auth 不經 access policy，只要網路連得到（VPC 內或 Client VPN）就能用。FGAC 開了不能關 |
| 影響範圍 | 每個環境一個 domain；只有 `search` 的 state 物件與它的舊版本；`search-config` 用 ephemeral 讀，state 裡零份；其他 stack 不碰這個 secret |
| 密碼怎麼產生 | `foundation` 建 secret 容器（`aws_secretsmanager_secret`，CMK，S8 已允許），值由人用 `aws secretsmanager get-random-password` 產生後 `put-secret-value`，JSON `{"username","password"}`；`opensearch-domain` 收 `master_user_secret_arn`，在 module 裡讀。比較過：`random_password` 放在 stack 會有三份（產生器結果、domain 屬性，寫回 Secrets Manager 還要 `aws_secretsmanager_secret_version`，S8 不准），module 裡用也違反 S7；`TF_VAR_` 從 CI 傳入雖然 state 只剩一份，但密碼經過 CI 環境與 plan 檔；ephemeral 讀取接不到 domain 屬性（§2 第 4 點） |
| 補償控制 | 1. module 沒有 password 變數，S7 擴充到 `opensearch-domain`；2. state bucket 強化（D15、§4.2）；3. SG 只放 Client VPN 與 VPC 內 runner 的 443，Dashboards 只能走 VPN；4. master 不給日常使用（K18）；5. `AUDIT_LOGS` 開，log 用 CMK；6. secret 用 CMK，只有 deploy role 與 break-glass role 能讀 |
| 輪替 | 每 90 天或有人離職時：`put-secret-value` 新密碼 → apply `search`（domain 更新 master 密碼）→ apply `search-config`（ephemeral 重新讀）→ 確認 state bucket 裡含舊密碼的舊版本在 30 天後過期 |
| owner | `search` stack 的擁有者（搜尋／觀測團隊）；範本寫佔位，複製出去填人名。platform team 追蹤例外 |
| 移除例外的 checkpoint | 1. aws provider 加了 `master_user_password_wo`（每次升 aws provider 的 MINOR 時看 CHANGELOG）：改用 ephemeral 讀 secret 餵 write-only 屬性；2. 組織有 IdP：接 SAML 取代 Dashboards 的 basic auth，master 換成 IAM role；3. 最晚 2027-04-24 重新審查 |
| 記錄在哪裡 | 這一節、example4 REFERENCE〈安全例外：OpenSearch master 帳密進 state〉、`opensearch-domain` README〈注意〉 |

### 4.2 state bucket 的強化（D15）

state bucket 由 platform team 或帳號開通流程在範本外建立（§2 第 18 點），範本不建也不改它。example4 REFERENCE〈前置作業的細節〉第 1 項要求 bucket 擁有者落地下列控制，§4.1 的補償控制引用這份清單：

| 控制 | 落地的地方 | 範本這邊做什麼 |
|---|---|---|
| 專用 CMK | bucket 預設加密用一把只給 state 用的 key；key policy 只允許 deploy role、break-glass role | `.tfbackend` 加 `kms_key_id = "<state-kms-key-arn>"` 佔位（K24），複製出去時換掉 |
| bucket policy | 只允許 deploy role 與 break-glass role 讀寫；拒絕非 TLS、拒絕不是用該 CMK 的上傳 | 無；README 給 policy 範例 |
| 舊版本過期 | versioning 開、noncurrent version 30 天過期（含舊密碼的 state 版本最多留 30 天） | 無 |
| CloudTrail | 對 state bucket 開 data event，記錄 `GetObject` | 無 |
| Block Public Access、versioning、SSE | v1 design §5.5 已要求 | 無 |

## 5. module 清單

共同慣例：`name`、`tags`（`Name` 由 module 加）、`kms_key_arn`、中文 description、aws `>= 6.0, < 7.0`、README 有〈注意〉〈刻意不做〉與 terraform-docs marker。

### 5.1 `opensearch-domain`

- 責任：VPC 內的 OpenSearch managed domain，含 hot／UltraWarm／cold 與 log publishing。
- resource：`aws_opensearch_domain`、`aws_cloudwatch_log_group`、`aws_cloudwatch_log_resource_policy`；data `aws_secretsmanager_secret_version`。
- 輸入：`engine_version`（必填）；`hot = { instance_type, instance_count, ebs = { volume_size, volume_type = "gp3", iops, throughput } }`；`dedicated_master = { instance_type, count }`；`warm = { instance_type, count }`；`cold_storage`；`availability_zone_count`；`multi_az_with_standby`；`subnet_ids`、`security_group_ids`；`kms_key_arn`；`master_user_secret_arn`（secret JSON 有 `username`、`password`）；`access_principal_arns`（不收 `*`）；`log_types`（預設 `ES_APPLICATION_LOGS`、`AUDIT_LOGS`）；`log_retention_days`；`auto_tune`、`off_peak_window_start`；`automated_snapshot_start_hour`。
- 固定：加密、node-to-node、HTTPS、TLS 1.2 PFS、FGAC、`internal_user_database_enabled = true`、`anonymous_auth_enabled = false`。
- validation：`warm` 要有 `dedicated_master`、hot 不能是 `t2.`／`t3.`；`cold_storage` 要有 `warm`；master 3 或 5 以上且不是 4；`hot.instance_count >= availability_zone_count` 且 > 1；standby 時 warm 是 AZ 數的倍數；warm type 限 `ultrawarm1.(medium|large|xlarge).search`；instance type 以 `.search` 結尾；secret ARN 格式；access principal 不含 `*`。
- 輸出：`domain_arn`、`domain_name`、`endpoint`、`dashboard_endpoint`、`log_group_arns`。
- 刻意不做：public domain、IAM master user、Cognito、SAML、custom endpoint、cross-cluster、package、Serverless、ISM、自己產生密碼。

### 5.2 `opensearch-config`

- 責任：domain 內部的設定：ISM policy、FGAC role 與 mapping、index template。
- resource：`opensearch_ism_policy`、`opensearch_role`、`opensearch_roles_mapping`、`opensearch_composable_index_template`。
- 輸入：`ism_policies`（policy id → `{ index_patterns, warm_days, cold_days, delete_days, timestamp_field }`，天數都是 index 的累計年齡（ISM 只有「年齡到 N 天進下一階段」的轉換，hot 停留到 `warm_days`），module 產生 hot → `warm_migration` → `cold_migration`（帶 `timestamp_field`）→ `cold_delete`）；`writer_roles`（FGAC role 名稱 → `{ index_patterns, backend_role_arns }`，權限固定為 §2 第 5 點那組）；`role_mappings`（內建 role，如 `ultrawarm_manager`、`cold_manager` → `{ users, backend_role_arns }`）；`index_templates`。
- validation：天數遞增；`delete_days` 必填；有 `cold_days` 就要 `warm_days` 與 `timestamp_field`；backend role 是 IAM role ARN；不准 mapping `all_access`、`security_manager`。
- 輸出：`ism_policy_ids`、`writer_role_names`。
- 刻意不做：`opensearch_user`、snapshot repository、Dashboards saved object、自訂 action group。provider 設定在 stack。

### 5.3 `dynamodb-table`

- resource：`aws_dynamodb_table`、`aws_dynamodb_contributor_insights`（選填）。
- 輸入：`hash_key`、`range_key`、`attributes`、`billing_mode`（預設 `PAY_PER_REQUEST`）、容量、`global_secondary_indexes`（`key_schema`）、`ttl_attribute`、`stream_view_type`、`point_in_time_recovery_days`（預設 35）、`deletion_protection`（預設 true）、`table_class`、`kms_key_arn`、`contributor_insights`。
- validation：屬性不缺不多；容量跟 billing mode 一致；stream view type；PITR 1–35。
- 輸出：`table_name`、`arn`、`stream_arn`。
- 刻意不做：global table、resource policy、import、autoscaling、Kinesis streaming destination、資料項目。

### 5.4 `kinesis-stream`

- 輸入：`mode`、`shard_count`、`retention_hours`（24–8760）、`kms_key_arn`（`encryption_type = "KMS"` 寫死）、`shard_level_metrics`。輸出：`name`、`arn`。
- 刻意不做：enhanced fan-out、resource policy、不加密。

### 5.5 `firehose-stream`

- resource：`aws_kinesis_firehose_delivery_stream`、`aws_cloudwatch_log_group`。
- 輸入：`role_arn`；`source_stream_arn`（`null` 為 Direct PUT，這時開 SSE）；`s3 = { bucket_arn, prefix, error_output_prefix, buffering_size, buffering_interval, compression = "GZIP" }`；`opensearch = { domain_arn, index_name, index_rotation_period, subnet_ids, security_group_ids, retry_seconds }`；`kms_key_arn`；`log_retention_days`。
- validation：timestamp prefix 時 `error_output_prefix` 要有 `!{firehose:error-output-type}`；OpenSearch 必須有 VPC 設定；`buffering_interval` 範圍（上限實作時核對）。
- 輸出：`name`、`arn`、`log_group_name`。
- 刻意不做：Redshift 目的地、Parquet 轉換、dynamic partitioning、Lambda、HTTP、Splunk、Snowflake、Iceberg、OpenSearch Serverless、MSK。

### 5.6 `glue-catalog`

- 輸入：`databases`（名稱 → `{ description, location_uri }`）。輸出：`database_names`、`database_arns`。
- 刻意不做：table、帳號層加密、Lake Formation、resource policy、federated database。

### 5.7 `glue-catalog-encryption`（帳號層）

- resource：`aws_glue_data_catalog_encryption_settings`。
- 輸入：`kms_key_arn`（catalog metadata 用 `SSE-KMS`；connection 密碼也用同一把，`return_connection_password_encrypted = true`）。輸出：`catalog_id`。
- README 開頭粗體（比照 `xray-transaction-search`）：**每個帳號、每個 region 只能由一處呼叫**，後 apply 的會蓋掉前面的設定；開啟後所有讀寫 catalog 的身分都要有這把 key 的 `kms:Decrypt`、`kms:GenerateDataKey`，包括同帳號其他專案；destroy 時 provider 會不會改回未加密，未確認。
- 怎麼提醒（D13）：module README 開頭、module 變數 description、example4 `foundation` 的 `glue_catalog_encryption` 變數 description（「同帳號第二個專案設 `null`」）、tfvars 註解、example4 README〈前置作業〉。
- 刻意不做：`catalog_encryption_service_role`、跨帳號 catalog。

### 5.8 `glue-etl`

- 責任：security configuration、crawler、job、trigger、workflow；可選的 S3 事件觸發（D14）。
- resource：`aws_glue_security_configuration`、`aws_glue_crawler`、`aws_glue_job`、`aws_glue_trigger`、`aws_glue_workflow`、`aws_cloudwatch_log_group`；`event_trigger` 有給時加 `aws_cloudwatch_event_rule`、`aws_cloudwatch_event_target`。
- 輸入：`kms_key_arn`；`crawlers`；`jobs`；`triggers`（`SCHEDULED`／`CONDITIONAL`，可帶 `workflow`）；`workflow`（`null` 不建）；`event_trigger = { bucket_name, key_prefix, role_arn, actions, batch_size, batch_window_seconds }`（`null` 不建）。
- `event_trigger` 的行為：建 `type = "EVENT"` 的 trigger 當 `workflow` 的起始 trigger，`event_batching_condition` 帶 batch 設定；建 EventBridge rule（default bus，pattern：`source = ["aws.s3"]`、`detail-type = ["Object Created"]`、`detail.bucket.name = [bucket_name]`、`detail.object.key = [{ prefix = key_prefix }]`）與 target（workflow ARN、`role_arn`）。
- validation：`script_location` 是 `s3://`；`worker_type` 列舉；timeout 1–2880；trigger 欄位一致；action 指到同一個 module 的 job／crawler；`event_trigger` 要有 `workflow`；`batch_size` 1–100、`batch_window_seconds` 1–900；`role_arn` 是 role ARN。
- 輸出：`crawler_names`、`job_names`、`workflow_name`、`workflow_arn`、`event_rule_arn`、`security_configuration_name`。
- 刻意不做：自訂 event bus、跨帳號事件、SQS 事件模式的 crawler、Glue connection、VPC 內的 job、streaming job、上傳腳本。

### 5.9 `athena-workgroup`

- 輸入：`results_bucket_name`、`results_prefix`、`kms_key_arn`、`bytes_scanned_cutoff_per_query`（預設 10 GiB）、`engine_version`、`named_queries`、`force_destroy`。固定：`enforce_workgroup_configuration`、CloudWatch 指標、`SSE_KMS`。輸出：`name`、`arn`。
- 刻意不做：代管查詢結果、Spark、capacity reservation、data catalog、Identity Center。

### 5.10 `redshift-serverless`

- 輸入：`db_name`、`admin_username`、`kms_key_arn`、`iam_role_arns`、`default_iam_role_arn`、`base_capacity`（4，或 8–512 每 8 一級）、`max_capacity`、`subnet_ids`、`security_group_ids`、`enhanced_vpc_routing`（預設 true）、`log_exports`、`usage_limit_rpu_hours`、`config_parameters`。固定：`manage_admin_password`、不公開、`require_ssl`。
- 輸出（跟 `redshift-cluster` 同名）：`endpoint_address`、`port`、`database_name`、`admin_secret_arn`，加 `namespace_name`、`workgroup_name`、`workgroup_arn`。
- 注意：namespace 沒有 final snapshot，刪除即丟資料。
- 刻意不做：snapshot 與還原、custom domain、endpoint access、resource policy、datashare。

### 5.11 `redshift-cluster`

- 輸入：`node_type`（`ra3.`）、`number_of_nodes`（1 只收 `ra3.large`、`ra3.xlplus`）、`database_name`、`master_username`、`kms_key_arn`、`iam_role_arns`、`default_iam_role_arn`、`subnet_ids`、`security_group_ids`、`enhanced_vpc_routing`、`automated_snapshot_retention_days`、`skip_final_snapshot`（預設 false）、`multi_az`、`parameters`。固定：加密、`manage_master_password`、不公開、`require_ssl`、log 寫 CloudWatch。
- 輸出：`endpoint_address`、`port`、`database_name`、`admin_secret_arn`，加 `cluster_identifier`、`arn`。
- 刻意不做：dc2、rg、snapshot copy、暫停排程、HSM、usage limit。

### 5.12 `quicksight-data`

- 輸入：`aws_account_id`；`athena_sources`（`{ workgroup, role_arn }`）；`redshift_sources`（`{ host, port, database, secret_arn }`）；`vpc_connection`；`datasets`（`{ source_key, import_mode = "DIRECT_QUERY", sql | table, columns }`）；`owner_principals`、`reader_principals`。
- validation：principal 是 QuickSight ARN；dataset 的來源存在；`sql` 與 `table` 擇一；有 Redshift 來源就要 `vpc_connection`。
- 輸出：`data_source_arns`、`data_set_arns`、`vpc_connection_arn`。
- 刻意不做：帳號訂閱、user、group、namespace、folder、analysis、dashboard、refresh schedule、RLS、`credential_pair`。

### 5.13 `vpn-site-to-site`

- 輸入：`vpc_id`＋`vpn_gateway = { amazon_side_asn }` 或 `transit_gateway_id`；`customer_gateway`；`routing`；`propagate_route_table_ids`；`tunnel_options`（只收強參數）；`log_retention_days`、`kms_key_arn`。固定：`preshared_key_storage = "SecretsManager"`、兩條 tunnel 的 log。
- 輸出：`vpn_connection_id`、`tunnel_addresses`、`preshared_key_secret_arn`、`vpn_gateway_id`。
- 刻意不做：PSK 輸入、accelerated VPN、Cloud WAN、IPv6、憑證型 customer gateway、TGW 本身。

### 5.14 `client-vpn`

- 輸入：`server_certificate_arn`；`authentication = { mutual_tls_root_certificate_arn, saml_provider_arn, self_service_saml_provider_arn }`；`client_cidr_block`；`vpc_id`、`subnet_ids`、`security_group_ids`；`authorization_rules`；`routes`；`split_tunnel`（預設 true）；`session_timeout_hours`；`dns_servers`；`log_retention_days`、`kms_key_arn`。固定：連線 log、UDP 443。
- validation：授權不收 `0.0.0.0/0`（除非 `split_tunnel = false` 並明確允許）；`access_group_id` 只在有 SAML 時能給；憑證是 ACM ARN（server 憑證 RSA 1024／2048）。
- 輸出：`endpoint_id`、`dns_name`、`log_group_name`。
- 刻意不做：AD、憑證產生、CRL、client connect handler、TGW 關聯。

## 6. `s3-bucket` 0.4.0

| 能力 | 0.3.1 | 0.4.0 |
|---|---|---|
| 封鎖公開、TLS only、SSE-KMS、BucketOwnerEnforced、過期、不過期、versioning、Lambda 通知 | 有 | 不變 |
| lifecycle transition | 沒有 | `transitions = list(object({ days, storage_class }))`，寫進「目前版本」rule；validation：天數遞增、小於過期天數、storage class 列舉 |
| EventBridge 通知 | 沒有 | `eventbridge`（bool，預設 `false`）；`aws_s3_bucket_notification` 在 `lambda_notifications` 非空或 `eventbridge = true` 時建立，兩者可並存 |
| 多 prefix 的 lifecycle、SQS／SNS、bucket policy 白名單、replication、object lock | 沒有 | 不做 |

不給新變數時 plan 跟 0.3.1 相同（既有測試不改就全過），所以是 MINOR。

example4 的 bucket（都 SSE-KMS）：`raw`（過期 365、30 天 `STANDARD_IA`、90 天 `GLACIER_IR`、`eventbridge = true`）、`curated`（never_expire、versioning）、`athena-results`（過期 30）、`glue-assets`（過期 90、versioning）；`flow-logs` 在 `foundation`。

## 7. example4 的 stack

### 7.1 stack 清單與 ORDER

| 順序 | stack | 放什麼 | 擁有者 | 變動頻率 | module |
|---|---|---|---|---|---|
| 1 | `foundation` | CMK、告警 SNS、flow log bucket、OpenSearch master secret 容器、Glue catalog 加密（D13） | platform | 低 | `kms-key`、`sns-alarm-topic`、`s3-bucket`、`glue-catalog-encryption`；`aws_secretsmanager_secret` |
| 2 | `network` | VPC、gateway endpoint、所有 SG | platform／網路 | 低 | `vpc`、`security-group` |
| 3 | `vpn` | Site-to-Site、Client VPN；預設零資源 | 網路 | 低 | `vpn-site-to-site`、`client-vpn` |
| 4 | `storage` | 資料湖 bucket、Glue database、Kinesis、DynamoDB、告警 | 資料平台 | 低 | `s3-bucket`、`glue-catalog`、`kinesis-stream`、`dynamodb-table`、`metric-alarm` |
| 5 | `iam-base` | 之後的資源一建立就要的 role（§8） | platform | 低 | `iam-role` |
| 6 | `search` | OpenSearch domain、告警 | 搜尋／觀測 | 低（apply 慢） | `opensearch-domain`、`metric-alarm` |
| 7 | `search-config` | ISM、FGAC role 與 mapping、index template | 搜尋／觀測 | 中 | `opensearch-config` |
| 8 | `analytics` | Athena workgroup、預存查詢 | 資料分析 | 中 | `athena-workgroup` |
| 9 | `iam-app` | 要具體 ARN 的 policy（§8） | platform | 低到中 | `iam-role`、`iam-role-policy` |
| 10 | `pipeline` | Firehose 兩條、Glue ETL 與事件觸發、告警 | 資料工程 | 高 | `firehose-stream`、`glue-etl`、`metric-alarm` |
| 11 | `warehouse` | Redshift（`warehouse_mode`）與防呆 | 資料平台 | 低 | `redshift-serverless`、`redshift-cluster`；`terraform_data` |
| 12 | `bi` | QuickSight | BI | 高 | `quicksight-data` |

排序的理由：`search` 在 `iam-base` 之後，因為 access policy 要列 Firehose role 的 ARN；`search-config` 緊接 `search`，Firehose 開始寫之前 FGAC mapping 要先存在；`analytics` 在 `iam-app` 之前，QuickSight Athena role 的 policy 要寫到 workgroup ARN；`iam-app` 在 `pipeline` 之前，Firehose 建立時會驗證 role 讀得到 stream。domain 本身不需要服務 role（master 是 internal user，service-linked role 自動建立）。`search-config` 要從 VPC 或連得到的網路執行，跟 example3 的 `eks-addons` 一樣。

### 7.2 SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../adr/0003-cross-stack-values-via-ssm-only.md)）。

| stack | key（Type） |
|---|---|
| `foundation` | `kms_key_arn`、`alarm_topic_arn`、`flow_log_bucket_arn`、`opensearch_master_secret_arn`（String） |
| `network` | `vpc_id`、`vpc_cidr`（String）；`azs`、`subnet_ids_app`、`subnet_ids_data`、`subnet_cidrs_data`、`route_table_ids_private`（StringList）；`sg_opensearch_id`、`sg_firehose_id`、`sg_redshift_id`、`sg_quicksight_id`、`sg_client_vpn_id`、`sg_search_admin_id`（String） |
| `vpn` | `client_vpn`、`site_to_site`（String，JSON；關閉時 `{"enabled":false}`） |
| `storage` | `raw_bucket_arn`、`raw_bucket_name`、`curated_bucket_arn`、`athena_results_bucket_arn`、`athena_results_bucket_name`、`glue_assets_bucket_arn`、`raw_database_name`、`curated_database_name`、`stream_arn`（String）；`table_${k}_arn`（樣式） |
| `iam-base` | `role_firehose_arn`、`role_firehose_name`、`role_glue_crawler_arn`、`role_glue_job_arn`、`role_glue_events_arn`、`role_redshift_arn`、`role_quicksight_vpc_arn`（String） |
| `search` | `opensearch_domain_arn`、`opensearch_domain_name`、`opensearch_endpoint`（String） |
| `search-config` | `firehose_writer_role`（String）；`ism_policy_ids`（StringList） |
| `analytics` | `athena_workgroup_name`、`athena_workgroup_arn`（String） |
| `iam-app` | `role_quicksight_athena_arn`（String） |
| `pipeline` | `firehose_s3_arn`、`firehose_opensearch_arn`、`glue_workflow_name`（String） |
| `warehouse` | `redshift_mode`、`redshift_host`、`redshift_port`、`redshift_database`、`redshift_admin_secret_arn`（String） |
| `bi` | 無 |

### 7.3 `warehouse` 的雙模式與防呆（D7、D16）

- 變數：`warehouse_mode`（string，必填，validation 只收 `serverless`、`provisioned`）；`serverless`、`provisioned`（object，預設 `null`）。交叉 validation：選了哪一種，對應物件必須非 `null`，另一個必須是 `null`（照 `rds` 的 `deployment`）。
- 呼叫：兩個 module 各自 `count = var.warehouse_mode == "<mode>" ? 1 : 0`；輸出用 `one(concat([for m in module.serverless : {...}], [for m in module.provisioned : {...}]))` 收成一個物件（兩個 module 的輸出型別不同，不能用三元運算子合併）。
- SSM：兩種都發布同名的 `redshift_host`、`redshift_port`、`redshift_database`、`redshift_admin_secret_arn`，另發布 `redshift_mode`。`bi` 只讀前三個，不分支。發布的 key 是寫死的，`check-ssm-contract.sh` 不用改。
- **防呆**：`guard.tf`：

  ```hcl
  # Switching warehouse_mode replaces this resource, and prevent_destroy rejects the plan.
  # See the README runbook before changing it; never commit prevent_destroy = false.
  resource "terraform_data" "warehouse_mode_guard" {
    triggers_replace = var.warehouse_mode

    lifecycle {
      prevent_destroy = true
    }
  }
  ```

  兩個 Redshift module 都加 `depends_on = [terraform_data.warehouse_mode_guard]`，讓防呆跟資料庫在同一個 plan 裡。S8 不擋 `terraform_data`，project-infra 規範也允許（放 precondition 的用途）。
- **擋得到什麼**：改 `warehouse_mode` → `triggers_replace` 變了 → 這個 resource 要 replace（先 destroy）→ `prevent_destroy` 讓整個 plan 失敗，兩個 module 都不會動。也擋 `terraform destroy`（含 `stacks.sh <env> all destroy` 走到 `warehouse` 時）。**擋不到**：直接在 `serverless`／`provisioned` 物件裡改會觸發 replace 的欄位（例如 `namespace_name`、`node_type` 從 single-node 換 multi-node 這類由 provider 決定的 ForceNew）；有人把 `guard.tf` 刪掉或把 `prevent_destroy` 改成 `false`（§2 第 19 點：拿掉設定就不再保護）。「replace 也會被擋」是依文件推論，未實測。
- **能驗證到哪裡**：
  1. `terraform test`（mock、plan）：斷言 `terraform_data.warehouse_mode_guard.triggers_replace == var.warehouse_mode`、兩個 module 各自的實例數、交叉 validation 的負向 run。
  2. `tests/check-warehouse-guard.sh`（`validate.sh` 的 Step 6b 會跑每個可執行的 `tests/check-*.sh`）：靜態確認 `guard.tf` 有 `prevent_destroy = true`、`triggers_replace = var.warehouse_mode`，兩個 module 都 `depends_on` 它。
  3. **`terraform test` 驗證不了 `prevent_destroy` 本身**：plan 的 run 沒有既有 state，觸發不了 replace；`expect_failures` 也抓不到這種錯誤（§2 第 19 點）。實際阻擋列為雲端驗證項目。
- **切換 runbook**（README）：
  1. 備份：provisioned → serverless 會留 final snapshot，仍建議先 UNLOAD 到 curated；**serverless → provisioned 不會留任何 snapshot**，一定要先 UNLOAD 或手動 snapshot 並確認完成。
  2. 在自己的工作目錄把 `guard.tf` 的 `prevent_destroy` 改成 `false`（本機暫時修改，不 commit，K23）。
  3. 改 tfvars 的 `warehouse_mode` 與對應物件（這個改動要 commit、走 PR）。
  4. `stacks.sh <env> warehouse plan`，確認只有預期的 destroy 與 create；apply。
  5. 還原 `guard.tf`（`git checkout -- guard.tf`），`stacks.sh <env> warehouse plan` 應該零差異。
  6. apply `bi`（host 變了，QuickSight 的 Redshift data source 會更新）；重新載入資料。
- **拆環境（dev）的影響**：`stacks.sh dev all destroy` 反向執行，`bi` 拆完後在 `warehouse` 停下，`warehouse` 之前的 10 個 stack 都還在。要繼續就照上面第 2 步在本機解除、只 destroy `warehouse`、還原 `guard.tf`，再從 `pipeline` 往回 destroy（或重跑 `all destroy`，已拆掉的 stack 沒有東西可刪）。README 的〈destroy 前要做的事〉列這一步。
- 預設：K16。

### 7.4 EventBridge 驅動 ETL（D14）

- **流程**：Firehose 寫 `raw/` → S3（raw bucket `eventbridge = true`）送 `Object Created` 到 default bus → `glue-etl` 建的 rule 比對 bucket 與 `raw/` 前綴 → target 是 workflow `<project>-<env>-raw-to-curated`，用 EventBridge role → workflow 的 EVENT 起始 trigger 依 batch 設定觸發 → job（bookmark 增量、轉 Parquet、更新 curated catalog）。raw 的 crawler 每日排程（K22）。
- **元件放哪裡**：
  - EventBridge rule、target、EVENT trigger、workflow：`glue-etl` module（K20）。S8 不准範本 stack 直接寫 `aws_cloudwatch_event_*`，所以不放 stack；module 建這些不違反 S4。不需要新 module。
  - EventBridge role（trust `events.amazonaws.com`，`source_arn` 是單一 rule ARN；權限只有對單一 workflow 的 `glue:notifyEvent`）：`iam-base`（K21）。
  - S3 的 EventBridge 開關：`storage` 的 raw bucket。
- **觸發次數**：EVENT trigger 是「`batch_size` 個事件或 `batch_window` 秒（從第一個事件起算）先到先觸發」。Firehose 一個 stream 每次 buffer 清空寫一個物件，所以物件數取決於 Firehose 的 `buffering_interval`。
  - 預設：Firehose S3 stream `buffering_interval = 900`（上限實作時核對）、`buffering_size = 64` MiB；Glue `batch_size = 100`、`batch_window_seconds = 900`（都是上限）。
  - 有資料持續流入時：每 900 秒最多 1 個物件，等滿 900 秒觸發一次，**一天最多 96 次 workflow**；這是事件觸發能壓到的下限，再低只能改排程。
  - dev：假設每天有資料 8 小時，約 32 次／天。sit：假設全天，約 96 次／天。
  - 成本（估計）：一次 job 用 G.1X × 2、Flex（0.29 美元／DPU-小時），以 3 分鐘計約 0.029 美元；dev 約 28 美元／月、sit 約 84 美元／月。Glue 的最低計費時間與實際執行時間未實測。
  - OpenSearch 那條 Firehose 的 S3 備份只寫 `errors/`，不在 rule 的前綴裡，不會觸發。
- **冪等**：Glue 不保證送達、不去重（§2 第 10 點），job 用 bookmark 處理「重複觸發」與「漏觸發」：漏掉的物件會在下一次觸發被撿到。

### 7.5 dev／sit 的預設規格

| 元件 | dev | sit |
|---|---|---|
| VPC | `10.30.0.0/20`、2 AZ、`nat_mode = "none"` | `10.31.0.0/20`、同 dev |
| Kinesis | provisioned 1 shard、保留 24 小時 | 同 dev |
| Firehose（S3） | buffer 64 MiB／900 秒、GZIP | 同 dev |
| Firehose（OpenSearch） | buffer 5 MiB／60 秒 | 同 dev |
| OpenSearch（D6、K17） | 2 × `m7g.large.search`（20 GiB gp3）、3 × `m7g.large.search` master、2 × `ultrawarm1.medium.search`、cold、2 AZ | 同 dev |
| ISM（index 年齡，累計） | 第 3 天進 warm、第 7 天進 cold、第 30 天刪除 | 第 7 天進 warm、第 30 天進 cold、第 90 天刪除 |
| Glue | 事件觸發 job（batch 100／900 秒）；raw crawler 每日 | 同 dev |
| Redshift（K16） | Serverless base 4、max 8、每月 100 RPU-小時 | base 4、max 16、200 RPU-小時 |
| Athena | 每查詢 10 GiB | 同 dev |
| DynamoDB | on-demand、PITR 7 天 | PITR 35 天 |
| Glue catalog 加密（D13） | 開 | 開 |
| VPN | 關 | 關（`envs/examples/vpn.tfvars` 示範開啟） |
| QuickSight | Athena 來源＋1 個 dataset；Redshift 來源有 secret ARN 才建 | 同 dev |

## 8. IAM：`iam-base` 與 `iam-app`

照 project-infra 的做法：`iam-base` 建之後的資源一建立就要的 role，policy 的 Resource 都是更早的 stack 發布的就直接帶上（project-infra 的 `ecs_execution`）；Resource 要等更晚的 stack 才有的，`iam-base` 只建 trust（project-infra 的 `rds_proxy`），policy 在 `iam-app` 用 `iam-role-policy` 附加；只在最後才用到的 role 直接建在 `iam-app`。全部 inline policy，trust 帶 `source_account`。

| role | 建在 | 誰一建立就要它 | policy 在哪 | 權限重點 |
|---|---|---|---|---|
| `firehose` | `iam-base`（只有 trust） | `search` 的 access policy、`pipeline` | `iam-app`（要 domain ARN） | 讀 stream；寫 raw 的 `raw/`、`errors/`；對 domain 的 `es:ESHttpPost`／`Put`／`Get`；VPC ENI 動作；KMS；log |
| `glue-crawler` | `iam-base`（完整） | `pipeline` | `iam-base` | 讀 raw、curated；兩個 database；log；KMS（含 catalog 加密的 key） |
| `glue-job` | `iam-base`（完整） | `pipeline` | `iam-base` | 讀 raw、寫 curated、讀 `glue-assets/scripts/`、寫 `glue-assets/tmp/`；兩個 database；log；KMS |
| `glue-events` | `iam-base`（完整） | `pipeline` 的 EventBridge target | `iam-base`（命名規則組出的單一 workflow ARN，K21） | `glue:notifyEvent`；trust `events.amazonaws.com`、`source_arn` 單一 rule |
| `redshift` | `iam-base`（完整） | `warehouse` | `iam-base` | 讀 curated；catalog 讀；KMS |
| `quicksight-vpc` | `iam-base`（完整） | `bi` 的 VPC connection | `iam-base` | VPC connection 要的 ENI 動作（實作時核對） |
| `quicksight-athena` | `iam-app` | `bi` 的 Athena data source | `iam-app`（要 workgroup ARN） | 單一 workgroup 的查詢動作；讀 curated；讀寫 `athena-results`；catalog 讀；KMS |

測試用 `jsondecode` 斷言 Resource 沒有 `*`（只能 `*` 的動作寫明白名單，例如 `ec2:Describe*`）。

## 9. 測試情境（TDD）

| module | 正向 | 負向（`expect_failures`） |
|---|---|---|
| `opensearch-domain` | hot only；完整冷熱；固定的加密、HTTPS、TLS、FGAC＋internal user database；master 帳密從 secret 接線（`mock_data` 回假 JSON）；log 與 resource policy；access policy 只含給定 principal | warm 沒 master；t3 開 warm；cold 沒 warm；master 2、4 台；instance_count 1；standby 時 warm 不是倍數；warm type；instance type 後綴；secret ARN 格式；principal 是 `*` |
| `opensearch-config` | ISM JSON 的狀態順序與 `timestamp_field`；只有 hot→delete；`firehose_writer` 的權限與 backend role；`ultrawarm_manager` mapping | 天數不遞增；有 cold 沒 `timestamp_field`；backend role 格式；mapping `all_access` |
| `dynamodb-table` | on-demand；provisioned；GSI `key_schema`；TTL、stream、PITR、deletion protection；KMS | 屬性缺漏或多餘；容量與 billing mode；stream view type；PITR |
| `kinesis-stream` | on-demand；provisioned；KMS | provisioned 沒 shard；on-demand 給 shard；保留時數 |
| `firehose-stream` | Kinesis → S3（無 SSE）；Direct PUT → S3（有 SSE）；OpenSearch 目的地 | prefix 規則；OpenSearch 沒 VPC；role 格式 |
| `glue-catalog` | 多個 database | 名稱不合法 |
| `glue-catalog-encryption` | SSE-KMS 與 connection 密碼加密都用給定的 key | key ARN 格式 |
| `glue-etl` | security configuration；crawler；job（Flex）；SCHEDULED、CONDITIONAL；`event_trigger`：EVENT trigger 在 workflow 裡、batch 設定、rule 的 pattern（`jsondecode` 斷言 source、detail-type、bucket、prefix）、target 的 ARN 與 role | script 不是 `s3://`；worker type；trigger 欄位；指到不存在的 job；`event_trigger` 沒 `workflow`；batch_size 0、101；window 0、901 |
| `athena-workgroup` | 強制設定、SSE_KMS、cutoff、named query | cutoff 太小；bucket 名稱 |
| `redshift-serverless` | 4 RPU；EVR；usage limit；密碼代管；不公開；輸出名稱與 `redshift-cluster` 相同 | base 6、520；subnet 不足；max 小於 base；usage limit 0 |
| `redshift-cluster` | single-node ra3.large；multi-node；log；require_ssl；加密；final snapshot | 非 ra3；single-node 用 ra3.4xlarge；保留天數 |
| `quicksight-data` | Athena 來源＋dataset；Redshift 來源＋VPC connection；權限 action | Redshift 沒 VPC connection；`sql` 與 `table` 都給；principal 格式；來源不存在 |
| `vpn-site-to-site` | VGW＋static；TGW＋BGP；PSK 在 Secrets Manager；tunnel log | VGW 與 TGW 都給或都沒給；弱 IKE 參數；CIDR |
| `client-vpn` | mutual TLS；SAML＋group；split tunnel；連線 log | 沒有驗證方式；`0.0.0.0/0`；有 group 沒 SAML；client CIDR 大小 |
| `s3-bucket` 0.4.0 | 既有測試全過；transition 寫進 rule；`eventbridge` 單獨開；與 Lambda 並存 | transition 天數不遞增、大於等於過期天數、storage class 不合法 |

範本 stack 的測試照 project-infra：讀與發布的 key 清單、`tests/tfvars/` 帶每份 tfvars、VPN 關閉時零資源、dev 與 sit 都有 warm 與 cold、`warehouse` 每份 tfvars 只建一個 module 且 guard 綁 `warehouse_mode`、`tests/check-warehouse-guard.sh`、`iam-base`／`iam-app` 的 Resource 斷言、`check-ssm-contract.sh` 通過。

## 10. 成本估計（Tokyo，on-demand，美元／月，730 小時）

**以下是估計**，單價取自 AWS 定價頁背後的公開價目 JSON（§13）；不含資料傳輸、儲存量、請求數。

| 元件 | 規格（單價） | dev | sit |
|---|---|---|---|
| OpenSearch | data 2 × m7g.large（0.175／時）＋master 3 × m7g.large（0.175）＋warm 2 × ultrawarm1.medium（0.279）＋40 GiB gp3（0.1464／GB-月） | 約 1,052 | 約 1,052 |
| OpenSearch warm／cold 儲存 | 依資料量 | 另計（單價未取得） | 另計 |
| Redshift Serverless | 0.494／RPU-小時，用量上限 100／200 | 最多約 49 | 最多約 99 |
| Kinesis | 1 shard（0.0195／shard-時） | 約 14 | 約 14 |
| Glue 事件觸發 job | 約 0.029／次（§7.4） | 約 28 | 約 84 |
| Firehose、Glue crawler（0.44／DPU-時）、Athena（5／TB）、DynamoDB | 小量 | 約 5–20 | 約 5–20 |
| KMS、CloudWatch Logs、SNS、Secrets Manager | | 約 6 | 約 6 |
| **小計（VPN 關）** | | **約 1,155–1,170** | **約 1,260–1,275** |
| 兩個環境合計 | | **約 2,415–2,445** | |
| 改用 provisioned（`ra3.large` single-node，0.639／時） | | 約 466（取代 Serverless 那列） | 同 |
| Client VPN（開啟時） | 1 association（0.15／時）＋2 人 × 160 小時（0.05／時） | ＋約 126 | ＋約 126 |
| Site-to-Site VPN（開啟時） | 1 條（0.048／時） | ＋約 35 | ＋約 35 |

OpenSearch 的 7 台節點佔每個環境約九成。範本 README 第一段寫「dev、sit 各約 1,150–1,300 美元／月起，主要是 OpenSearch 冷熱」。

## 11. 風險與 mock 驗不到的事

| 風險 | 影響 | 處理 |
|---|---|---|
| warm 最小台數、master 規格沒有文件 | apply 才失敗 | validation 只擋文件明寫的條件；K17 用保守值；雲端驗證 |
| UltraWarm 啟用後要幾小時才能用 | ISM 搬移失敗 | runbook：等 warm 可用再 apply `search-config` |
| cold 需要 `timestamp_field` | 搬移失敗 | `opensearch-config` 必填；README 要求文件帶這個欄位 |
| §4.1 的例外 | master 帳密在 state | 補償控制、輪替、checkpoint、§4.2 |
| basic auth 繞過 access policy | 網路連得到就能嘗試登入 | SG 只放 VPN 與 runner；個人帳號；`AUDIT_LOGS` |
| ephemeral 在 `terraform test` 的 mock 下能不能跑 | `search-config` 的測試寫不出來 | G10 先驗證；不行就改用 `override_module` 只測 module 輸入，記錄限制（未確認） |
| `search-config` 要連 VPC 內的 domain | CI 跑不了 apply | 同 example3；mock 測試不需要連線 |
| opensearch provider 的 lock | S10 | 使用者產生 |
| `glue-catalog-encryption` 被同帳號第二個專案呼叫 | 設定互蓋；其他專案的 Glue／Athena 因 KMS 權限失敗 | D13 的選填輸入與四處提醒 |
| state bucket 的強化沒做 | §4.1 的補償控制不成立 | README 前置作業列成第一項；`.tfbackend` 的 `kms_key_id` 佔位沒換掉時 init 會失敗 |
| 事件觸發的次數與成本 | Glue 費用高於排程 | batch 設到上限、job 不跑 crawler（K22）；README 寫估計與改回排程的方法 |
| EventBridge 重複或遺漏事件 | 重跑或延遲 | job bookmark |
| `warehouse_mode` 的防呆 | replace 被擋是推論；解除步驟靠人 | runbook、`check-warehouse-guard.sh`、雲端驗證 |
| dev 拆環境卡在 `warehouse` | 前面的 stack 沒拆 | README 的 destroy 步驟 |
| QuickSight 主控台步驟 | 自動化不完整 | README 前置作業；Redshift 來源預設不建 |
| Firehose ENI 權限能否收窄 | role 偏寬 | 照 AWS 文件；能加條件的實作時核對 |
| Site-to-Site 的 `customer_gateway_configuration` 是否含 PSK | PSK 仍可能進 state | 雲端驗證 |
| 14 個新 module＋1 個 MINOR 連續發版 | Actions 額度、release PR 衝突 | 每個 Phase 1–3 個，release PR 一次合併一個 |
| HCP 登記漏掉 | 範本 init 失敗 | 每發一個新 module 就登記並從消費端抓一次 |
| Lake Formation 模式 | IAM 權限不夠 | README 前提：帳號用 IAM 存取模式 |
| 成本（D6） | 兩個環境合計每月約 2,400 美元 | README 第一段寫明；destroy `search` 前先處理 warm／cold index |

## 12. Phase

見 [`implement-process.md`](./implement-process.md)。摘要：

| Phase | 內容 |
|---|---|
| G0 | 設計與實作流程 |
| G1 | `s3-bucket` 0.4.0（`transitions`、`eventbridge`）、`kinesis-stream`、`dynamodb-table`；發版、HCP |
| G2 | `glue-catalog`、`glue-catalog-encryption`、`glue-etl`（含事件觸發）；發版、HCP |
| G3 | `opensearch-domain`、`opensearch-config`；發版、HCP |
| G4 | `firehose-stream`、`athena-workgroup`；發版、HCP |
| G5 | `redshift-serverless`、`redshift-cluster`；發版、HCP |
| G6 | `quicksight-data`；發版、HCP |
| G7 | `vpn-site-to-site`、`client-vpn`；發版、HCP |
| G8 | example4 骨架、`foundation`、`network` |
| G9 | `vpn`、`storage`、`iam-base` |
| G10 | `search`、`search-config` |
| G11 | `analytics`、`iam-app`、`pipeline` |
| G12 | `warehouse`（雙模式與防呆）、`bi` |
| G13 | README、文件、全量驗證、驗證表 |

## 13. 來源

**怎麼查的**

- provider schema：在 repo 外的暫存目錄寫一個只有 `required_providers { aws = "6.70.0" }` 的設定，`terraform init -backend=false -plugin-dir=<repo>/.cache/plugins` 後跑 `terraform providers schema -json`，逐層列出 §2 提到的 resource；對 6.69.0（範本 lock 的版本）重跑，這批 resource 的欄位完全相同。沒有 AWS 憑證、沒有呼叫 AWS API。
- tflint：用 repo 的 [`.tflint.hcl`](../../../.tflint.hcl) 與 aws ruleset 0.49.0，在暫存目錄故意寫錯值探測（§2 第 16 點）。
- 價格：AWS 定價頁背後的公開價目 JSON（`https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/<service>/USD/current/<file>.json`），2026-10-24 下載；以 Asia Pacific (Tokyo) 的 on-demand 價為準。正式數字以各服務定價頁為準。

**AWS 文件**

- OpenSearch：UltraWarm <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ultrawarm.html>；cold storage <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/cold-storage.html>；ClusterConfig <https://docs.aws.amazon.com/opensearch-service/latest/APIReference/API_ClusterConfig.html>；quotas <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/limits.html>；service-linked role <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/slr-aos.html>；fine-grained access control <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/fgac.html>；internal user database 教學 <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/fgac-http-auth.html>。
- Firehose：<https://docs.aws.amazon.com/firehose/latest/dev/controlling-access.html>、<https://docs.aws.amazon.com/firehose/latest/dev/encryption.html>。
- Glue：EventBridge 啟動 workflow <https://docs.aws.amazon.com/glue/latest/dg/starting-workflow-eventbridge.html>；`EventBatchingCondition` <https://docs.aws.amazon.com/glue/latest/webapi/API_EventBatchingCondition.html>。
- S3 EventBridge 事件格式：<https://docs.aws.amazon.com/AmazonS3/latest/userguide/ev-events.html>。
- Redshift：<https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-capacity.html>、<https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-known-issues.html>、<https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-clusters.html>。
- QuickSight：<https://docs.aws.amazon.com/quicksight/latest/user/accessing-data-sources.html>、<https://docs.aws.amazon.com/quicksight/latest/user/secrets-manager-integration.html>、<https://docs.aws.amazon.com/quicksight/latest/APIReference/API_AthenaParameters.html>、<https://docs.aws.amazon.com/quicksight/latest/APIReference/API_RedshiftParameters.html>。
- Client VPN：<https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html>、<https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/mutual.html>。
- 定價頁：<https://aws.amazon.com/opensearch-service/pricing/>、<https://aws.amazon.com/redshift/pricing/>、<https://aws.amazon.com/vpn/pricing/>、<https://aws.amazon.com/kinesis/data-streams/pricing/>、<https://aws.amazon.com/glue/pricing/>、<https://aws.amazon.com/athena/pricing/>、<https://aws.amazon.com/firehose/pricing/>、<https://aws.amazon.com/dynamodb/pricing/>。

**Terraform 與 provider**

- `prevent_destroy`：<https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle>；`terraform_data`：<https://developer.hashicorp.com/terraform/language/resources/terraform-data>；S3 backend：<https://developer.hashicorp.com/terraform/language/backend/s3>。
- `aws_vpn_connection` 的 PSK：<https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/vpn_connection.html.markdown>。
- opensearch provider：<https://registry.terraform.io/providers/opensearch-project/opensearch>、<https://github.com/opensearch-project/terraform-provider-opensearch>（`docs/index.md`、`docs/resources/`）。

**repo**

- [ADR-0002](../../adr/0002-split-state-by-owner-and-change-rate.md)、[ADR-0003](../../adr/0003-cross-stack-values-via-ssm-only.md)、[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)。
- [`releasing-modules.md`](../../guides/releasing-modules.md)、[`project-infra-standard.md`](../../guides/project-infra-standard.md)、[`hcp-registry-setup.md`](../../guides/hcp-registry-setup.md)。
- [v1 design §5.5](../v1/design-docs.md)（state bucket）、[v4 design](../v4/design-docs.md)（第二個 provider 與 lock 的前例）、[v6 design](../v6/design-docs.md)（`check-ssm-contract.sh`）。
- [`scripts/validate.sh`](../../../scripts/validate.sh)（S1–S11、Step 6b）；[`modules/s3-bucket`](../../../modules/s3-bucket/README.md)、[`modules/iam-role`](../../../modules/iam-role/README.md)、[`modules/xray-transaction-search`](../../../modules/xray-transaction-search/README.md)、[`modules/rds`](../../../modules/rds/README.md)；[`templates/project-infra/infra/README.md`](../../../templates/project-infra/infra/README.md)（`iam-base`、`iam-app`、`foundation/secrets.tf`）。

## 14. 實作後的變更

實作時跟上面的設計不同、或設計沒寫到的決定。標「使用者選擇」的是使用者拍板，其他照慣例判斷。

**module**

- **新 module 不先建 `CHANGELOG.md`**（改 K1）：先建 `# Changelog` 的話，release-please 第一次發版會在尾端留下被降級的 `## Changelog`，事後刪掉又會讓 module 目錄跟 tag 不一致（G1、G2 遇到）。
- **`glue-etl` 擋同一個 workflow 的第二個起始 trigger**：AWS 文件寫每個 workflow 只有一個 start trigger。有 `event_trigger` 時不准再有 `workflow = true` 的 SCHEDULED trigger，SCHEDULED 的起始 trigger 也最多一個。
- **`athena-workgroup` 的 cutoff 最小 10485760**：這是 provider 的下限（AWS API 文件寫 10000000），validation 照 provider。
- **`redshift-serverless` 的 `enhanced_vpc_routing`**：module 預設維持 §5.10 的 `true`，`warehouse` stack 傳 `false`（provisioned 也是），因為 Serverless 開 EVR 要 3 個 AZ，範本只有 2 個。`tests/check-output-parity.sh` 比對兩個 Redshift module 的輸出名稱，只 vendor 其中一個 module 時跳過。
- **VPN**：`vpn-site-to-site` 擋掉的弱演算法（SHA1、DH group 2、5）是依通行的密碼學建議，不是 AWS 明文規定。`client-vpn` 需要 `vpc_cidr_blocks`，範本傳 `network` 的 `vpc_cidr`。

**範本**

- **ISM 天數是 index 的累計年齡**（使用者選擇）：dev 第 3 天進 warm、第 7 天進 cold、第 30 天刪；sit 7／30／90（§7.5）。index pattern `<name_prefix>-events*`，Firehose 寫 `<name_prefix>-events`，`timestamp_field = "@timestamp"`；`search-config` 另建 index template 把 `@timestamp` 設成 `date`，cold 搬移才有欄位可用。
- **S1 放寬：`search-config` 用離線 aws provider 測試**（使用者選擇；取代 §11 的 `override_module` 備案）：Terraform 1.15 的 mock provider 不支援 ephemeral resource。測試檔用真的 aws provider，假帳密、三個 skip 全開、所有網址都是 `http://127.0.0.1:`；`validate.sh` 的 `offline_aws_provider` 只在 stack 有 `ephemeral "aws_...` 時接受這種寫法。`read_master_secret` 只為離線測試存在，`tests/check-read-master-secret.sh` 擋任何 tfvars 設它。ephemeral 本身與 provider 的帳密接線只有 `terraform validate` 與雲端驗證覆蓋。[`project-infra-standard.md`](../../guides/project-infra-standard.md)〈例外清單〉記了這兩個例外。
- **`warehouse` 的防呆檢查**：`tests/check-warehouse-guard.sh` 靜態確認 `prevent_destroy = true`、`triggers_replace = var.warehouse_mode`、兩個 module 都 `depends_on` guard；`terraform test` 驗不到 `prevent_destroy` 本身（§2 第 19 點），列為雲端驗證。
- **`foundation`**：`glue_catalog_encryption = {}` 用 `foundation` 自己的 CMK，物件裡給 `kms_key_arn` 才用別把 key。flow log bucket 用 SSE-KMS，CMK 的 key policy 給 `delivery.logs.amazonaws.com`（條件 `aws:SourceAccount`）。
- **`bi`**：VPC connection 用 data subnet（Redshift 在 data tier）；`datasets` 由 tfvars 給，表名與欄位要跟 Glue job 的輸出一致；dev、sit 只建 Athena 來源。人工步驟寫在 README〈前置作業〉：QuickSight 訂閱手動開（VPC connection 要 Enterprise 版）；給 `redshift_reader_secret_arn` 時 secret 在 repo 外建、QuickSight 管理者在主控台授權、執行 Terraform 的身分要 `secretsmanager:GetSecretValue`；secret 用 CMK 時 `aws-quicksight-secretsmanager-role-v0` 要 `kms:Decrypt`；QuickSight user 與 group 在 Terraform 外管理。
- **`network`：Redshift 沒有 S3 egress**。EVR 預設關閉，Spectrum 與 COPY 走 Redshift 自己的網路；開 EVR 時要加 S3 prefix list 的 443 egress，列為已知限制。
- **IAM 動作清單沒有對真實帳號驗證**（`iam-base`、`iam-app`）：Glue 可能還需要 `glue:GetSecurityConfiguration`；Glue 帶 security configuration 時實際的 log group 名稱未驗證（範圍是 `/aws-glue/*`）；Firehose 多給了 `es:DescribeDomain*`。
- **告警門檻是起始值**（`storage`、`search`、`pipeline`）：OpenSearch 告警的 `ClientId` dimension 用帳號 ID（未驗證）；JVM 告警用 180 秒 period 的 Maximum，取代「連續 3 分鐘」，避開 `evaluation_periods`：這個字含有 `uat`，會讓範本的環境名稱 `grep` 誤判。
- **`search-config` 的執行環境**（G13 發現）：VPC 沒有 NAT 與 interface endpoint，`search_admin` SG 也只有到 domain 的 egress，所以 VPC 內只掛這個 SG 的 runner 連不到 SSM、Secrets Manager、STS 與 registry。README 建議從 Client VPN（split tunnel）執行；要用 VPC 內的 runner，對外的路由專案自己補。
- **範例 Glue job**（K10）：`templates/example4/etl/raw_to_curated.py` 逐一讀 raw database 的 table，用 bookmark 增量處理，寫 Parquet 並以 `enableUpdateCatalog` 更新 curated catalog。crawler 把 `raw/` 建成 `raw` table 是推論，腳本把它改名成 `bi` 的 dataset 讀的 `events`，partition 欄位改名成 `year`、`month`、`day`、`hour`。沒有在 Glue 上跑過。

**加入雲端驗證清單的項目**：Site-to-Site 的 `customer_gateway_configuration` 在 SecretsManager 模式下是否含 PSK；VPN 與 Client VPN 的 log 用 CMK 能否寫入；`ra3.large` single-node 在 Tokyo 的可用性；flow log 用 CMK 寫 S3；QuickSight VPC connection 的 ENI 權限；IAM 動作清單；OpenSearch 告警的 `ClientId`；範例 Glue job；`search-config` 從 Client VPN 執行。完整清單在 example4 REFERENCE〈驗證〉。
