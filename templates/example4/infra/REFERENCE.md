# example4 參考資料

這份是 [`README.md`](./README.md) 的參考資料：README 只放第一次用範本需要的步驟，細節、合約、runbook 與驗證紀錄都在這裡。

狀態：離線驗證通過，還沒在真實帳號 apply 過；第一次 apply 時逐項確認〈驗證〉的「雲端整合待驗證」與〈已知限制的細節〉。設計見 [`docs/design/v7/design-docs.md`](../../../docs/design/v7/design-docs.md)，實作紀錄見 [`implement-process.md`](../../../docs/design/v7/implement-process.md)。

## 成本（估計）

dev、sit 各約 1,150–1,300 美元／月起，合計約 2,400–2,450 美元／月，大部分是 OpenSearch 冷熱架構（每個環境 7 台節點約 1,052 美元）。以 Tokyo on-demand 單價、730 小時估算，不含資料傳輸、儲存量與請求數。VPN 預設關閉；打開 Client VPN 每個環境再加約 126 美元，Site-to-Site 約 35 美元。明細見 [design §10](../../../docs/design/v7/design-docs.md)。不用的環境請照〈destroy〉拆掉。

## 檔案

`infra/terraform/` 底下每個 stack 一個目錄，另有 `stacks.sh`（依序跑各 stack）與 `check-ssm-contract.sh`（靜態檢查 SSM 合約與 tfvars 一致性）。範例 Glue job 在 `etl/raw_to_curated.py`，由 CI 上傳，Terraform 不上傳。

每個 stack 的固定檔案跟 example3 相同（`versions.tf`、`providers.tf`、`common.tf`、`ssm-inputs.tf`、`ssm-outputs.tf`、`envs/<env>.tfvars`、`envs/<env>.tfbackend`、`tests/`、`.terraform.lock.hcl`），`common.tf` 12 個 stack 一字不差。不同的地方：`.tfbackend` 多一行 `kms_key_id = "<state-kms-key-arn>"`（state 專用 CMK，見〈前置作業的細節〉第 1 項）；`vpn`、`warehouse`、`bi` 另有 `envs/examples/`，示範開 VPN、provisioned Redshift、Redshift 資料來源，這些檔案沒有 `.tfbackend`，不是環境。

## stack 的內容與依賴

apply 順序與 `ORDER` 見 README。下游只讀上游發布的 key。

| 順序 | stack | 建的東西 | 讀 |
|---|---|---|---|
| 1 | `foundation` | 共用 CMK（`kms-key`）、告警 SNS topic、flow log bucket（SSE-KMS）、OpenSearch master secret 容器（值在 Terraform 外寫）、帳號層 Glue Data Catalog 加密（`glue_catalog_encryption = {}` 時用這把 CMK） | 無 |
| 2 | `network` | VPC：`app`（private）、`data`（isolated）兩層、2 AZ、`nat_mode = "none"`；gateway endpoint `s3`、`dynamodb`；flow log；6 個 SG（`opensearch`、`firehose`、`redshift`、`quicksight`、`client_vpn`、`search_admin`） | foundation |
| 3 | `vpn` | `client_vpn`、`site_to_site` 預設 `null`，零資源 | foundation、network |
| 4 | `storage` | bucket `raw`（30 天 `STANDARD_IA`、90 天 `GLACIER_IR`、365 天過期、開 EventBridge）、`curated`（不過期、versioning）、`athena-results`（30 天過期）、`glue-assets`（90 天過期、versioning）；Glue database `<project>_<env>_raw`、`_curated`；Kinesis（provisioned 1 shard、24 小時）；DynamoDB（tfvars `tables`）；Kinesis 與 DynamoDB 告警 | foundation |
| 5 | `iam-base` | role `firehose`（只有 trust）、`glue-crawler`、`glue-job`、`glue-events`、`redshift`、`quicksight-vpc` | foundation、network、storage |
| 6 | `search` | OpenSearch domain：2 × `m7g.large.search` hot、3 × `m7g.large.search` master、2 × `ultrawarm1.medium.search`、cold；access policy 只列 Firehose role；告警 | foundation、network、iam-base |
| 7 | `search-config` | ISM policy、FGAC role `firehose_writer` 與 mapping、index template。要從連得到 domain 的網路執行（〈`search-config` 的執行環境〉） | foundation、iam-base、search |
| 8 | `analytics` | Athena workgroup（每查詢 10 GiB 上限、SSE_KMS）、範例預存查詢 | foundation、storage |
| 9 | `iam-app` | Firehose role 的 policy、QuickSight 的 Athena 資料來源 role | foundation、network、storage、iam-base、search、analytics |
| 10 | `pipeline` | Firehose `to-raw`（Kinesis → S3 raw）、`to-search`（Kinesis → OpenSearch）；Glue workflow、job、raw crawler、EventBridge 觸發；Firehose 告警 | foundation、network、storage、iam-base、search |
| 11 | `warehouse` | Redshift Serverless 或 provisioned（`warehouse_mode`），加上 `terraform_data` 防呆 | foundation、network、iam-base |
| 12 | `bi` | QuickSight Athena 資料來源與 dataset；有 `redshift_reader_secret_arn` 才建 Redshift 資料來源與 VPC connection | network、storage、iam-base、analytics、iam-app、warehouse |

「讀」欄看不出來的順序限制：

- `search-config` 在 `pipeline` 之前：Firehose 開始寫之前，FGAC mapping 要先存在。
- `iam-app` 在 `pipeline` 之前：Firehose 建立時會驗證 role 讀得到 stream。
- `iam-base` 比 `pipeline` 先 apply，拿不到 workflow 與 EventBridge rule 的 ARN，所以照命名規則組：workflow `<project>-<env>-raw-to-curated`，rule 與 EVENT trigger `<workflow>-s3-event`，Glue job 名稱以 `<project>-<env>-` 開頭（bookmark 權限的範圍）。改一邊的名稱，另一邊要一起改；兩個 stack 的測試各自寫死同一組期望值。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../../docs/adr/0003-cross-stack-values-via-ssm-only.md)）。下表照各 stack 的 `ssm-outputs.tf` 整理，不一致時以程式碼為準。

| stack | String | StringList |
|---|---|---|
| `foundation` | `kms_key_arn`、`alarm_topic_arn`、`flow_log_bucket_arn`、`opensearch_master_secret_arn` | — |
| `network` | `vpc_id`、`vpc_cidr`、`sg_opensearch_id`、`sg_firehose_id`、`sg_redshift_id`、`sg_quicksight_id`、`sg_client_vpn_id`、`sg_search_admin_id` | `azs`、`subnet_ids_app`、`subnet_ids_data`、`subnet_cidrs_data`、`route_table_ids_private`（兩層的 route table 都算） |
| `vpn` | `client_vpn`、`site_to_site`：JSON。關閉時 `{"enabled":false}`；開啟時 `client_vpn` 有 `endpoint_id`、`dns_name`，`site_to_site` 有 `vpn_connection_id`、`tunnel_addresses`、`preshared_key_secret_arn` | — |
| `storage` | `raw_bucket_arn`、`raw_bucket_name`、`curated_bucket_arn`、`athena_results_bucket_arn`、`athena_results_bucket_name`、`glue_assets_bucket_arn`、`raw_database_name`、`curated_database_name`、`stream_arn`、`table_<key>_arn`（每個 `tables` 一個，範本是 `table_ingest_state_arn`） | — |
| `iam-base` | `role_firehose_arn`、`role_firehose_name`、`role_glue_crawler_arn`、`role_glue_job_arn`、`role_glue_events_arn`、`role_redshift_arn`、`role_quicksight_vpc_arn` | — |
| `search` | `opensearch_domain_arn`、`opensearch_domain_name`、`opensearch_endpoint` | — |
| `search-config` | `firehose_writer_role`（FGAC role 名稱） | `ism_policy_ids` |
| `analytics` | `athena_workgroup_name`、`athena_workgroup_arn` | — |
| `iam-app` | `role_quicksight_athena_arn` | — |
| `pipeline` | `firehose_s3_arn`、`firehose_opensearch_arn`、`glue_workflow_name` | — |
| `warehouse` | `redshift_mode`、`redshift_host`、`redshift_port`、`redshift_database`、`redshift_admin_secret_arn`（兩種模式都發布同名的 5 個 key） | — |
| `bi` | 不發布 | — |

`bi` 只讀 `warehouse` 的 host、port、database，不讀 `redshift_mode`，所以切換模式時 `bi` 不用改程式碼。

`check-ssm-contract.sh` 檢查兩件事：每個讀取的 key 都由 `ORDER` 更早的 stack 發布、型別一致；同一個 env 各 stack tfvars 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名。寫法見 [`templates/project-infra/infra/README.md`](../../project-infra/infra/README.md)〈合約檢查〉。

## 前置作業的細節

README〈前置作業〉每一項的完整做法，編號相同。

1. **state bucket 的強化**（第一次 `init` 之前；design §4.2）。state bucket 由 platform team 或帳號開通流程建立，範本不管（Block Public Access、versioning、SSE 是基本要求）。`search` 的 state 含 OpenSearch master 密碼（〈安全例外〉），bucket 擁有者要先做到：
   - 專用 CMK：bucket 預設加密用一把只給 state 用的 key，key policy 只允許 deploy role 與 break-glass role。把 key ARN 填進 24 份 `envs/*.tfbackend` 的 `kms_key_id`；佔位 `<state-kms-key-arn>` 沒換掉時 `init` 會失敗。
   - bucket policy：只允許 deploy role 與 break-glass role 讀寫這個專案的 state，拒絕非 TLS、拒絕不是用該 CMK 的上傳。範例如下，未在真實帳號驗證。同一個 bucket 放多個專案時，Resource 只寫自己專案的前綴，不要把別的專案鎖在外面：

     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Sid": "DenyNonTls",
           "Effect": "Deny",
           "Principal": "*",
           "Action": "s3:*",
           "Resource": ["arn:aws:s3:::<state-bucket>", "arn:aws:s3:::<state-bucket>/*"],
           "Condition": { "Bool": { "aws:SecureTransport": "false" } }
         },
         {
           "Sid": "OnlyDeployAndBreakGlass",
           "Effect": "Deny",
           "Principal": "*",
           "Action": "s3:*",
           "Resource": "arn:aws:s3:::<state-bucket>/<project>-*",
           "Condition": {
             "ArnNotLike": {
               "aws:PrincipalArn": [
                 "arn:aws:iam::<account>:role/<deploy-role>",
                 "arn:aws:iam::<account>:role/<break-glass-role>"
               ]
             }
           }
         },
         {
           "Sid": "OnlyStateKey",
           "Effect": "Deny",
           "Principal": "*",
           "Action": "s3:PutObject",
           "Resource": "arn:aws:s3:::<state-bucket>/<project>-*",
           "Condition": {
             "StringNotEqualsIfExists": { "s3:x-amz-server-side-encryption-aws-kms-key-id": "<state-kms-key-arn>" }
           }
         }
       ]
     }
     ```

   - 舊版本 30 天過期：noncurrent version 30 天過期，含舊密碼的 state 版本最多留 30 天。
   - CloudTrail：對 state bucket 開 data event，記錄 `GetObject`。
2. **寫入 OpenSearch master secret 的值**（`foundation` apply 之後、`search` plan 之前）。`opensearch-domain` 在 plan 時就讀 secret，沒有值會失敗。secret 名稱是 `<project>-<env>/opensearch-master`，值是 JSON `{"username","password"}`。用管線串起來，密碼不經過指令參數與 shell 變數：

   ```bash
   aws secretsmanager get-random-password --password-length 32 --require-each-included-type \
       --query RandomPassword --output text \
     | jq -Rc '{username: "master", password: .}' \
     | aws secretsmanager put-secret-value --secret-id <project>-<env>/opensearch-master --secret-string file:///dev/stdin
   ```

3. **Glue Data Catalog 加密：每個帳號、每個 region 只能一處設定**（`foundation` apply 之前）。`foundation` 的 tfvars `glue_catalog_encryption = {}` 會用這個 stack 的 CMK 加密整個帳號的 catalog。**同帳號的第二個專案要設 `null`**，否則後 apply 的會蓋掉前面的設定。開啟後，所有讀寫 catalog 的身分（包括同帳號其他專案的 Glue、Athena、Redshift、QuickSight）都要有這把 key 的 `kms:Decrypt`、`kms:GenerateDataKey`。先用 `aws glue get-data-catalog-encryption-settings` 確認帳號目前的設定。
4. **QuickSight 訂閱與 secret 授權**（`bi` apply 之前）：
   - QuickSight 帳號訂閱在主控台手動開；VPC connection 要 Enterprise 版。
   - QuickSight user 與 group 在 Terraform 外管理；把 `bi` tfvars 的 `owner_principals`、`reader_principals` 換成真實的 group ARN。
   - 要接 Redshift 時（給 `redshift_reader_secret_arn`）：secret 在 repo 外建立；QuickSight 管理者要在主控台把這個 secret 授權給 QuickSight；執行 Terraform 的身分要有它的 `secretsmanager:GetSecretValue`（QuickSight 依呼叫者的 IAM policy 授權）；secret 用 CMK 時，`aws-quicksight-secretsmanager-role-v0` 要有那把 key 的 `kms:Decrypt`。
5. **Redshift 唯讀 DB user 與 secret**（`warehouse` apply 之後、`bi` 帶 `redshift_reader_secret_arn` apply 之前）：用 `redshift_admin_secret_arn` 的帳密登入，建一個只有 SELECT 的 user，例如：

   ```sql
   CREATE USER quicksight_reader PASSWORD '<產生的密碼>';
   GRANT USAGE ON SCHEMA public TO quicksight_reader;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO quicksight_reader;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO quicksight_reader;
   ```

   把它的 `username`、`password` 存進一個 repo 外建立的 secret，ARN 填進 `bi` 的 tfvars（範例 `envs/examples/redshift.tfvars`）。沒做這一步，`bi` 只建 Athena 資料來源。
6. **Lake Formation 用 IAM 模式**（`storage` apply 之前）。範本的權限全部靠 IAM，帳號的 Data Catalog 設定要維持「新 database、table 只用 IAM 存取控制」。帳號開了 Lake Formation 權限模式時，Glue、Athena、Redshift、QuickSight 的 role 光有 IAM 權限不夠。
7. **執行 apply 的身分要有的特權操作**（design §4）：

   | 操作 | 哪些 stack 用到 |
   |---|---|
   | `iam:CreateServiceLinkedRole` | `search`（OpenSearch）、`warehouse`（Redshift）、`vpn`（Client VPN），帳號第一次建立該服務時 |
   | `iam:PassRole` | `pipeline`（Firehose、Glue、EventBridge 的 role）、`warehouse`（Redshift）、`bi`（QuickSight） |
   | `kms:CreateGrant` | `warehouse`（Redshift）、`pipeline`（Firehose） |
   | `secretsmanager:GetSecretValue` | `search`、`search-config`（OpenSearch master secret）、`bi`（QuickSight 的 Redshift secret） |
   | `glue:PutDataCatalogEncryptionSettings` | `foundation` |
   | `events:PutRule`、`events:PutTargets` | `pipeline` |

## 安全例外：OpenSearch master 帳密進 state

設計時選擇讓 OpenSearch 用 internal user database 的 master 帳密（design D2），Dashboards 立即可用，代價是密碼會進 `search` 的 state。下表摘自 design §4.1。

| 項目 | 內容 |
|---|---|
| 例外 | master user 用 internal user database，密碼以明文出現在 `search` stack 的 state：`aws_opensearch_domain` 的 `master_user_password` 一份，`opensearch-domain` module 讀 secret 的 data source 一份，共兩份。plan 輸出標 sensitive |
| 風險 | 讀得到 `search` state 的人等於拿到 `all_access` 與 `security_manager`。basic auth 不經 access policy，只要網路連得到（VPC 內或 Client VPN）就能用。FGAC 開了不能關 |
| 影響範圍 | 每個環境一個 domain；只有 `search` 的 state 物件與它的舊版本；`search-config` 用 ephemeral 讀，state 裡零份；其他 stack 不碰這個 secret |
| 密碼怎麼產生 | `foundation` 用 `secrets-manager-secret` 建 secret 容器（CMK），值由人用 `aws secretsmanager get-random-password` 產生後 `put-secret-value`，JSON `{"username","password"}`；`opensearch-domain` 收 `master_user_secret_arn`，在 module 裡讀。`random_password`、`TF_VAR_`、ephemeral 三種做法為什麼不用，見 design §4.1 |
| 補償控制 | 1. module 沒有 password 變數，S7 擴充到 `opensearch-domain`；2. state bucket 強化（〈前置作業的細節〉第 1 項）；3. SG 只放 Client VPN 與 VPC 內 runner 的 443，Dashboards 只能走 VPN；4. master 不給日常使用：只給 `search-config` 與緊急使用，人員帳號由 master 在 Dashboards 建，不經 Terraform（design K18）；5. `AUDIT_LOGS` 開，log 用 CMK；6. secret 用 CMK，只有 deploy role 與 break-glass role 能讀 |
| 輪替 | 每 90 天或有人離職時：`put-secret-value` 新密碼 → apply `search`（domain 更新 master 密碼）→ apply `search-config`（ephemeral 重新讀）→ 確認 state bucket 裡含舊密碼的舊版本在 30 天後過期 |
| owner | `search` stack 的擁有者（搜尋／觀測團隊）；範本寫佔位，複製出去填人名。platform team 追蹤例外 |
| 移除例外的 checkpoint | 1. aws provider 加了 `master_user_password_wo`（每次升 aws provider 的 MINOR 時看 CHANGELOG）：改用 ephemeral 讀 secret 餵 write-only 屬性；2. 組織有 IdP：接 SAML 取代 Dashboards 的 basic auth，master 換成 IAM role；3. 最晚 2027-04-24 重新審查 |
| 記錄在哪裡 | design §4.1、這一節、`opensearch-domain` README〈注意〉 |

## `search-config` 的執行環境

domain 在 VPC 的 data subnet，沒有公開 endpoint。`search-config` 的 opensearch provider 用 master 帳密做 basic auth（`sign_aws_requests = false`），連 `https://<opensearch_endpoint>`；帳密由 `ephemeral "aws_secretsmanager_secret_version"` 讀，不進 state 與 plan 檔。範本不建 runner。

執行的地方要連得到三個地方：

| 目的地 | 為什麼 |
|---|---|
| domain 的 443 | `opensearch` SG 只收 `firehose`、`client_vpn`、`search_admin` 三個 SG 的 443。從 Client VPN 連進來，或在 VPC 內的 runner 掛 `search_admin` SG（`sg_search_admin_id`） |
| AWS API | 讀 SSM（`foundation`、`search`、`iam-base` 的 key）、Secrets Manager（master secret，加上 `foundation` CMK 的 `kms:Decrypt`）、STS |
| Terraform registry 與 HCP | `init` 要下載 provider 與 module |

VPC 沒有 NAT 也沒有 interface endpoint，`search_admin` SG 也只開了到 domain 的 egress，所以**只掛 `search_admin` SG、放在這個 VPC 裡的 runner 連不到 AWS API 與 registry**。可行的做法：

1. Client VPN（建議）：開 `vpn` stack 的 `client_vpn`（預設 split tunnel），筆電或 CI runner 連上 VPN 後執行。到 domain 走 VPN，AWS API 與 registry 走原本的網路。
2. VPC 內的 runner：除了 `search_admin` SG，另外掛一個自己管理、允許對外 443 的 SG，並在範本以外補上對外的路（NAT，或 `ssm`、`secretsmanager`、`sts`、`kms` 的 interface endpoint 加 registry 的 mirror）。

另外：

- UltraWarm 啟用後可能要幾小時才能用。`search` apply 完，等 warm 可用再 apply `search-config`，否則 ISM 的搬移會失敗。
- `read_master_secret` 只為離線測試存在（測試設 `false`），任何 tfvars 都不准設它；`tests/check-read-master-secret.sh` 會擋。
- 人員登入 Dashboards 也走 Client VPN 加 basic auth，用 master 在 Dashboards 建的個人帳號，不共用 master。

### ISM 與 index

| 項目 | dev | sit |
|---|---|---|
| 進 UltraWarm | 第 3 天 | 第 7 天 |
| 進 cold | 第 7 天 | 第 30 天 |
| 刪除 | 第 30 天 | 第 90 天 |

天數是 index 從建立算起的**累計年齡**，不是在各階段停留的天數。

- ISM policy 套在 `<project>-<env>-events*`。Firehose 寫 `<project>-<env>-events`，`firehose-stream` 預設每天輪替，實際 index 名稱帶日期後綴。
- 搬進 cold 要靠時間欄位 `@timestamp`。`search-config` 另建 index template 把 `@timestamp` 設成 `date`，**寫進 Kinesis 的每筆資料都要帶 `@timestamp`**。
- FGAC role `firehose_writer` 只能寫這個 index 前綴，backend role 是 `iam-base` 的 Firehose role。`ultrawarm_manager`、`cold_manager` 只在 tfvars 給了維運 role 時才建 mapping。

## EventBridge 觸發

```
Firehose 寫 raw/ → S3（raw bucket eventbridge = true）送 Object Created 到 default bus
  → rule <workflow>-s3-event 比對 raw bucket 與 raw/ 前綴
  → target 是 workflow <project>-<env>-raw-to-curated，用 iam-base 的 glue-events role
  → workflow 的 EVENT 起始 trigger 依 batch 設定觸發 → job（bookmark 增量、轉 Parquet、更新 curated catalog）
```

| 項目 | 說明 |
|---|---|
| batch 設定 | `batch_size = 100`、`batch_window_seconds = 900`，都是 Glue 允許的上限。事件數或視窗（從第一個事件起算）先到先觸發 |
| 觸發次數 | Firehose 的 S3 stream `buffering_interval = 900`、`buffering_size = 64`（MiB），資料持續流入時每 900 秒最多寫 1 個物件，所以一天最多 96 次 workflow，這是事件觸發壓得到的下限。dev 假設每天有資料 8 小時，約 32 次；sit 假設全天，約 96 次 |
| 成本（估計） | 一次 job 用 G.1X × 2、Flex（0.29 美元／DPU-小時），以 3 分鐘計約 0.029 美元；dev 約 28 美元／月、sit 約 84 美元／月。Glue 的最低計費時間與實際執行時間未實測 |
| crawler | 不跟著事件跑。raw crawler 每天 18:00 UTC（台北 02:00）跑一次，因為 crawler 每次執行有最低計費時間，跟著事件跑會放大成本（design K22）。新的欄位或 partition 要等隔天 crawler 跑過，job 才讀得到 |
| 不會誤觸發的路徑 | OpenSearch 那條 Firehose 的 S3 備份與兩條 Firehose 的錯誤輸出都寫 `errors/`，不在 rule 的前綴裡 |
| 冪等 | Glue 不保證送達、也不去重。job 用 bookmark：重複觸發時已處理的檔案會略過，漏掉的檔案下一次觸發會撿到 |
| 起始 trigger | 一個 workflow 只能有一個起始 trigger（AWS 文件）。`glue-etl` 有 `event_trigger` 時，不准再有 `workflow = true` 的 SCHEDULED trigger，plan 時就擋 |

改回排程：

1. `storage/buckets.tf`：raw bucket 的 `eventbridge` 改成 `false`。
2. `pipeline/glue.tf`：拿掉 `event_trigger`，改給 `triggers`，例如 `{ "<workflow>-daily" = { type = "SCHEDULED", schedule = "cron(0 19 * * ? *)", workflow = true, actions = [{ job = local.job_name }] } }`。
3. `iam-base` 的 `glue_events` role 不再用到，可以連同 `role_glue_events_arn` 的發布與 `pipeline` 的讀取一起拿掉（`check-ssm-contract.sh` 會檢查兩邊一致）。
4. 依序 apply `storage`、`iam-base`、`pipeline`。

### 範例 Glue job

[`etl/raw_to_curated.py`](../etl/raw_to_curated.py) 是 PySpark 範例。它逐一讀 raw database 裡 crawler 建的 table（GZIP JSON），用 job bookmark（`transformation_ctx`）只處理新資料，把 Parquet 寫到 curated bucket 的 `<table>/`，再用 `enableUpdateCatalog` 建立或更新 curated database 的同名 table。crawler 把 `raw/` 建成名為 `raw` 的 table（推論，未驗證），腳本把它改名為 `events`，跟 `bi` 的 dataset 一致；Firehose 時間前綴產生的 `partition_0`–`partition_3` 改名成 `year`、`month`、`day`、`hour` 並當 partition。

- **CI 把它上傳到 glue-assets bucket 的 `scripts/`，Terraform 不上傳物件**（design K10）。job 讀 `s3://<glue-assets>/scripts/raw_to_curated.py`，還沒上傳時 job 會失敗。
- 參數來自 `pipeline/glue.tf` 的 `default_arguments`：`--raw_database`、`--curated_database`、`--curated_path`（另有 `--raw_path`、`--TempDir`，範例沒有用到）。
- 欄位轉換只是範例。`bi` 的 dataset 欄位（`event_id`、`event_time`、`payload`）要跟 job 的實際輸出一致，換成自己的資料時一起改。
- `transformation_ctx` 是 bookmark 的 key，改了就會重新處理全部資料。

## `warehouse_mode` 切換

`warehouse` 依 `warehouse_mode` 只建 `redshift-serverless` 或 `redshift-cluster` 其中一個，兩種都發布同名的 host、port、database。dev、sit 預設 `serverless`（base 4 RPU；dev max 8、每月 100 RPU-小時，sit max 16、200 RPU-小時）。Serverless 的 `enhanced_vpc_routing` 預設 `false`，因為開了要 3 個 AZ，範本只有 2 個。

防呆：`guard.tf` 的 `terraform_data.warehouse_mode_guard` 帶 `triggers_replace = var.warehouse_mode` 與 `prevent_destroy = true`，兩個 module 都 `depends_on` 它。改 `warehouse_mode` 會讓它要 replace，`prevent_destroy` 就讓整個 plan 失敗，兩個 module 都不會動；`terraform destroy` 也會被擋。「replace 也會被擋」是依 Terraform 文件推論，未實測。擋不到的情況：

- 直接在 `serverless`／`provisioned` 物件裡改會觸發 replace 的欄位。
- 有人刪掉 `guard.tf` 或把 `prevent_destroy` 改成 `false` 並 commit（`tests/check-warehouse-guard.sh` 在 CI 擋這種 commit）。

切換步驟：

1. **備份**。provisioned → serverless 會留 final snapshot（`<project>-<env>-warehouse-final`）。**serverless → provisioned 不會留任何 snapshot**（namespace 沒有 final snapshot，刪除即丟資料），一定要先做手動 snapshot 並確認完成。範本的 `redshift` role 只能讀 curated，沒有寫入權限，所以不能直接 UNLOAD 到 curated；要 UNLOAD 的話，先另外給這個 role curated 某個 prefix 的 `s3:PutObject` 與共用 key 的 `kms:GenerateDataKey`，用完拿掉。
2. 在自己的工作目錄把 `guard.tf` 的 `prevent_destroy` 改成 `false`。**這是本機暫時修改，不 commit**（design K23）。
3. 改 tfvars 的 `warehouse_mode` 與對應物件（另一個設 `null`；範例 `envs/examples/provisioned.tfvars`）。這個改動要 commit、走 PR。
4. `./stacks.sh <env> warehouse plan`，確認只有預期的 destroy 與 create，再 apply。
5. 還原 `guard.tf`（`git checkout -- guard.tf`），`./stacks.sh <env> warehouse plan` 應該零差異。
6. apply `bi`（host 變了，QuickSight 的 Redshift 資料來源會更新），重新載入資料；有 Redshift 唯讀 user 的話要在新的 warehouse 重建（〈前置作業的細節〉第 5 項）。

## destroy

`./stacks.sh <env> all destroy` 依反向順序跑，拆完 `bi` 後**會在 `warehouse` 停下**（`prevent_destroy`），前面 10 個 stack 都還在。完整拆一個環境：

1. 先做下面〈destroy 前要做的事〉。
2. `./stacks.sh <env> all destroy`，在 `warehouse` 停下。
3. 本機把 `guard.tf` 的 `prevent_destroy` 改成 `false`（不 commit），`./stacks.sh <env> warehouse destroy`，再 `git checkout -- guard.tf`。
4. 從 `pipeline` 往回 destroy，或重跑 `./stacks.sh <env> all destroy`（已拆掉的 stack 沒有東西可刪）。拆到 `search-config` 時要在〈`search-config` 的執行環境〉說的網路裡；那時 `vpn` 還沒拆，Client VPN 仍可用。

### destroy 前要做的事

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| S3 bucket（`storage` 的四個、`foundation` 的 flow log bucket） | `force_destroy = false` | 不是空的會刪不掉。先清空（含舊版本與刪除標記），確認資料不需要再刪。raw 的物件可能已轉到 `GLACIER_IR`，清空前先確認不用取回 |
| OpenSearch 的 warm／cold index（`search`） | ISM 依年齡搬移 | 先刪除或搬回 hot 所有 warm 與 cold 的 index，再 destroy `search`；停用 warm／cold 也要先做這一步 |
| DynamoDB table（`storage`） | `deletion_protection = true`，stack 沒有開關 | 本機在 `storage/tables.tf` 的 module 呼叫加 `deletion_protection = false`，apply 之後再 destroy；要保留資料先匯出 |
| Redshift（`warehouse`） | Serverless 沒有 final snapshot；provisioned `skip_final_snapshot = false` | Serverless 先做手動 snapshot（UNLOAD 要另外給寫入權限，見〈`warehouse_mode` 切換〉第 1 步）；provisioned 會留 `<project>-<env>-warehouse-final`，不需要就事後刪掉。兩種都要照上面第 3 步解除防呆 |
| Athena workgroup（`analytics`） | `force_destroy = false` | 在 Terraform 外建的 named query 要先刪掉 |
| Secrets Manager secret（`foundation`） | 刪除後保留 30 天 | 期間不能用同名重建；值在 Terraform 外寫，刪了就沒有，要先備份 |
| CMK（`foundation`） | 刪除等待 30 天 | 等待期間 key 不能用、可以取消刪除。其他 stack 都拆完再 destroy `foundation`，不然 snapshot、備份檔解不開 |
| Glue Data Catalog 加密（`foundation`） | 帳號層設定 | destroy 時 provider 會不會改回未加密未確認；同帳號其他專案還在用 catalog 時，先確認 key 刪除不會影響它們 |
| Glue job、crawler、Firehose、VPN 的 log group | module 建立，跟著刪 | Glue 實際寫 log 的 log group 名稱未驗證，服務自己建的 log group 要自己刪 |

destroy 不會刪範本以外建的東西：state bucket、QuickSight 帳號與 user、Redshift 唯讀 user 的 secret、CI 上傳的 Glue 腳本（glue-assets bucket 清空時一起刪）。

## 複製出去之後要改什麼

| 項目 | 改什麼 |
|---|---|
| module 的 `source` | 從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）；換 organization 或改 git 來源見 [`docs/guides/consuming-modules.md`](../../../docs/guides/consuming-modules.md) |
| 帳號表 | 12 個 stack 的 `common.tf` 的 `accounts_by_env`（`111111111111`、`222222222222`），同步改、保持一字不差 |
| state | 每份 `envs/*.tfbackend` 的 `bucket`、`kms_key_id`，`key` 的 `example-` 前綴換成自己的 `project` |
| tfvars 的佔位值 | `project`、`expected_account_id`；`foundation` 的 `alarm_emails`、`glue_catalog_encryption`（同帳號第二個專案設 `null`）；`network` 的 `vpc_cidr`（`10.30.0.0/20`、`10.31.0.0/20`）、`azs`；`storage` 的 `tables`；`search` 的規格；`search-config` 的 ISM 天數與維運 role；`bi` 的 principal 與 `datasets` |
| Glue job | 照自己的資料改 `etl/raw_to_curated.py`，在 CI 加上傳到 glue-assets 的 `scripts/` 的步驟 |

## 已知限制的細節

下面是 mock 驗不到或刻意不做的事，第一次 apply 時要逐項確認。

| 範圍 | 限制 |
|---|---|
| IAM 動作清單（`iam-base`、`iam-app`） | 沒有對真實帳號驗證。Glue job 與 crawler 可能還需要 `glue:GetSecurityConfiguration`；Glue 帶 security configuration 時實際寫 log 的 log group 名稱未驗證（權限範圍是 `/aws-glue/*`）；Firehose 的 policy 多給了 `es:DescribeDomain*`；Firehose 的 ENI 權限能否再收窄未確認 |
| 告警門檻 | `storage`、`search`、`pipeline` 的門檻是起始值，沒有用真實流量調過。OpenSearch 告警的 `ClientId` dimension 用帳號 ID（未驗證）；JVM 記憶體告警用 180 秒的 Maximum，取代 AWS 建議的「連續 3 分鐘」 |
| Redshift 沒有 S3 egress | `redshift` SG 只收 Client VPN 與 QuickSight 的 5439，沒有對外規則。EVR 預設關閉，Spectrum 與 COPY 走 Redshift 自己的網路；開 EVR 時要在 `network` 加 S3 prefix list 的 443 egress，而且 Serverless 開 EVR 要 3 個 AZ |
| `search-config` 的測試範圍 | Terraform 1.15 的 mock provider 不支援 ephemeral resource，`search-config` 的測試改用離線的 aws provider（假帳密、所有 endpoint 指向 `http://127.0.0.1:`、啟動檢查全關），並以 `read_master_secret = false` 跳過 ephemeral 讀取。ephemeral 本身與 provider 的帳密接線只有 `terraform validate` 與雲端驗證覆蓋 |
| `prevent_destroy` | `terraform test` 驗不到：plan 的 run 沒有既有 state，觸發不了 replace。`tests/check-warehouse-guard.sh` 只做靜態檢查（`prevent_destroy = true`、`triggers_replace = var.warehouse_mode`、兩個 module 都 `depends_on` guard） |
| VPN | `vpn-site-to-site` 擋掉的弱演算法（SHA1、DH group 2、5）是依通行的密碼學建議，不是 AWS 明文規定。`client-vpn` 需要 `vpc_cidr_blocks`，範本傳 `network` 發布的 `vpc_cidr` |
| QuickSight | VPC connection 用 data subnet；dev、sit 只建 Athena 來源；`datasets` 的表名與欄位要跟 Glue job 的輸出一致，沒有東西檢查 |
| Athena | 每查詢掃描上限最小 10485760 位元組（provider 的下限，AWS API 文件寫 10000000） |
| 範例 Glue job | 沒有在 Glue 上跑過：crawler 建的 table 名稱、partition 欄位名稱、Glue 5.1 上 bookmark 與 `enableUpdateCatalog` 的行為都是依文件推論 |
| OpenSearch 規格 | warm 最小台數、T3 master 能不能搭 UltraWarm，AWS 文件沒寫；範本用 2 台 warm、`m7g.large.search` master 的保守值 |

## 驗證

```bash
scripts/validate.sh templates/example4
```

依序做 `fmt`、靜態規則（含 S1 mock provider、S8 stack 只呼叫 module、S10 lock 的 darwin 與 linux hash）、`check-ssm-contract.sh`、`bash -n` 與 shellcheck；再對每個 stack 跑 `init -backend=false`、`validate`、`terraform test`，對 `dev`、`sit` 兩份 tfvars 各跑一次 `tests/tfvars`；最後跑 `tests/check-*.sh`。全部離線，不需要 AWS 憑證，但 stack 從 HCP private registry 抓 module，需要 registry token。

### 靜態驗證通過（2026-10-24）

| 項目 | 結果 |
|---|---|
| `scripts/validate.sh templates/example4` | 12 個 stack、305 個 `terraform test` run 全過（含 dev、sit 兩份 tfvars 與 `envs/examples/` 的測試）；fmt、靜態規則、S10 通過 |
| `check-ssm-contract.sh` | 12 個 stack、71 個讀取、2 個 env 通過 |
| `warehouse/tests/check-warehouse-guard.sh` | 通過；突變：`prevent_destroy` 改 `false`、`triggers_replace` 改綁 `var.serverless`、`provisioned` 拿掉 `depends_on`，三種都會失敗 |
| `search-config/tests/check-read-master-secret.sh` | 通過：沒有 tfvars 設 `read_master_secret` |
| `stacks.sh dev all plan --dry-run` | 依 ORDER 印出 12 個 stack 的指令，`destroy` 反向 |
| 環境名稱 | 對 `templates/example4` 做不分大小寫的 `grep`（排除 `*.svg`：SVG 內嵌的 base64 會誤中），`dev`、`sit` 以外的環境名稱都沒有出現 |

### 雲端整合待驗證

需要真實帳號，這個里程碑沒有做。

| 項目 | 怎麼確認 |
|---|---|
| 冷熱搬移（ISM） | index 依累計年齡進 UltraWarm、cold、刪除；cold 搬移用 `@timestamp` |
| warm 最小台數 | 2 台 `ultrawarm1.medium.search` 能建立並承接搬移 |
| Firehose 寫進 VPC 內的 OpenSearch | SigV4 通過 access policy，FGAC `firehose_writer` mapping 生效，index 依日期輪替並套上 ISM |
| Dashboards 只能從 VPN 連 | basic auth 從 Client VPN 可以登入；VPC 外與其他 SG 連不到；VPN 用戶端解析得到 domain endpoint |
| master 密碼輪替 | 照〈安全例外〉的輪替步驟，`search`、`search-config` 都換到新密碼 |
| S3 → EventBridge → Glue workflow | 批次觸發的實際次數與 batch 行為；漏觸發或重複觸發時 bookmark 的表現 |
| Glue job 成本 | Flex G.1X × 2 的實際執行時間與最低計費時間 |
| 範例 Glue job | crawler 建的 table 名稱與 partition 欄位；bookmark、`enableUpdateCatalog` 建立 curated table |
| catalog 加密後的 KMS 權限 | Glue、Athena、Redshift、QuickSight 各角色讀寫 catalog 都有 key 權限；同帳號其他專案的影響 |
| IAM 動作清單 | `iam-base`、`iam-app` 的 role 夠用；是否要 `glue:GetSecurityConfiguration`；Glue log group 的實際名稱 |
| Redshift Spectrum | EVR 關閉時從 curated 讀得到；開 EVR 時補上 S3 egress 的效果 |
| `ra3.large` single-node | Tokyo 可以建立 |
| `warehouse_mode` 切換 | 改模式時 plan 被 `prevent_destroy` 擋下；照 runbook 解除、切換、還原後 plan 零差異 |
| QuickSight 兩種來源 | Athena 來源與 dataset；Redshift 來源、secret 授權、VPC connection 的 ENI 權限 |
| Client VPN | mutual TLS 連線、授權只到 data subnet；連線 log 用 CMK 能寫入 |
| Site-to-Site VPN | PSK 只在 Secrets Manager；`customer_gateway_configuration` 在 SecretsManager 模式下是否含 PSK（含的話 PSK 會出現在 state）；tunnel log 用 CMK 能寫入 |
| log group 層的 resource policy | OpenSearch 的 log publishing 接受掛在 log group 上的 policy |
| flow log | 用 CMK 加密的 flow log bucket 能收到 flow log |
| OpenSearch 告警 | `ClientId` 用帳號 ID 時指標對得上 |
| `.tfbackend` 的 `kms_key_id` 與 bucket policy | state 用專用 CMK 加密；套上範例 policy 後 `init`、`plan`、lock 檔寫入都正常 |
| `search-config` 的執行環境 | 從 Client VPN 執行 `search-config` 的 plan 與 apply |
