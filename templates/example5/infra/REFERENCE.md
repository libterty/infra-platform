# example5 參考資料

這份是 [`README.md`](./README.md) 的參考資料：README 只放第一次用範本需要的步驟，細節、合約、發布流程、runbook 與驗證紀錄都在這裡。

狀態：離線驗證通過，還沒在真實帳號 apply 過；第一次 apply 時逐項確認〈驗證〉的「雲端整合待驗證」與〈已知限制的細節〉。設計見 [`docs/design/v8/design-docs.md`](../../../docs/design/v8/design-docs.md)，實作紀錄見 [`implement-process.md`](../../../docs/design/v8/implement-process.md)。

## 成本（估計）

以 Tokyo on-demand 單價、730 小時、100 台裝置每台每 5 秒一則訊息估算，不含資料傳輸與儲存量。明細見 [design §10](../../../docs/design/v8/design-docs.md)。

| 項目 | dev | sit |
|---|---|---|
| OpenSearch 冷熱（7 台節點，同 example4） | 約 1,052 | 約 1,052 |
| IoT Core（連線、訊息、rule） | 約 83 | 約 83 |
| Kinesis 1 shard | 約 14 | 約 14 |
| Firehose、S3、SQS、EventBridge、Scheduler | 約 5–20 | 約 5–20 |
| KMS、CloudWatch Logs、SNS、Secrets Manager | 約 6 | 約 6 |
| Greengrass（每台 core device 0.18）、Device Defender audit（不到 1） | 依台數 | 依台數 |
| SageMaker 訓練 | 0（排程停用） | 依用量 |
| **小計（預設：VPN、PKI、endpoint、攝影機都關）** | **約 1,160–1,180** | **約 1,160–1,180＋訓練** |

兩個環境合計約 2,320–2,350 美元／月，另加訓練費。打開選配時每個環境再加：雲端推論 endpoint（1 台 `ml.m5.large`）約 109、ACM Private CA 約 400、Client VPN 約 126、每台攝影機的 KVS 約 4 加儲存；serverless 推論依用量；SiteWise 依 property 與訊息量，單價沒有取得。不用的環境請照〈destroy〉拆掉。

## 檔案

`infra/terraform/` 底下每個 stack 一個目錄，另有 `stacks.sh`（依序跑各 stack）與 `check-ssm-contract.sh`（靜態檢查 SSM 合約與 tfvars 一致性）。範本另有兩個 Terraform 讀的檔案目錄：

- `edge/components/<元件>/<版本>.json`：Greengrass 元件的 recipe，一個版本一個檔案。範例是 `com.example.Inference/1.0.0.json`。
- `ml/pipelines/training.json`：SageMaker 訓練 pipeline 的 definition。

每個 stack 的固定檔案跟 example4 相同（`versions.tf`、`providers.tf`、`common.tf`、`ssm-inputs.tf`、`ssm-outputs.tf`、`envs/<env>.tfvars`、`envs/<env>.tfbackend`、`tests/`、`.terraform.lock.hcl`），`common.tf` 15 個 stack 一字不差，`.tfbackend` 有 `kms_key_id = "<state-kms-key-arn>"`。`fleet`、`sitewise`、`edge` 另外有 `provider "awscc"`，region 與 role 跟 `provider "aws"` 用同一組變數；awscc 沒有 `allowed_account_ids`，帳號防呆靠同一個 stack 的 aws provider。`vpn`、`pki`、`inference` 有 `envs/examples/`，示範開 Client VPN、Private CA、推論 endpoint，這些檔案沒有 `.tfbackend`，不是環境。

## stack 的內容與依賴

apply 順序與 `ORDER` 見 README。下游只讀上游發布的 key。`<prefix>` 是 `<project>-<env>`。

| 順序 | stack | 建的東西 | 讀 |
|---|---|---|---|
| 1 | `foundation` | 共用 CMK（key policy 允許 CloudWatch Logs、log delivery、CloudWatch、SNS、EventBridge、Scheduler）、告警 SNS topic、flow log bucket（90 天過期）、OpenSearch master secret 容器 | 無 |
| 2 | `network` | VPC：`app`（private）、`data`（isolated）兩層、2 AZ、`nat_mode = "none"`；gateway endpoint `s3`；interface endpoint 只收 `sagemaker.runtime`（預設不建）；flow log；5 個 SG（`opensearch`、`firehose`、`sagemaker`、`client_vpn`、`search_admin`） | foundation |
| 3 | `vpn` | `client_vpn` 預設 `null`，零資源 | foundation、network |
| 4 | `pki` | `ca` 預設 `null`，零資源；開啟時建 ROOT 或 SUBORDINATE CA，不開 CRL 與 OCSP | 無 |
| 5 | `storage` | bucket `telemetry`（30 天 `STANDARD_IA`、90 天 `GLACIER_IR`、365 天過期）、`greengrass-artifacts`、`ota-artifacts`、`ml-artifacts`（三個都不過期、開 versioning、舊版本 30 天過期）；Kinesis（provisioned 1 shard、24 小時）；SQS `rule-errors`、`model-approved`（都有 DLQ、SSE-KMS）；Kinesis 與 SQS 告警 | foundation |
| 6 | `iam-base` | role `iot-rule`、`iot-provisioning`、`iot-logging`、`iot-audit`、`iot-mitigation`、`greengrass-tes`、`ota-presign`、`firehose`（只有 trust）、`sagemaker-pipeline`、`sagemaker-endpoint`、`scheduler` | foundation、network、storage |
| 7 | `search` | OpenSearch domain：2 × `m7g.large.search` hot、3 × master、2 × `ultrawarm1.medium.search`、cold；access policy 只列 Firehose role；告警 | foundation、network、iam-base |
| 8 | `search-config` | ISM policy、FGAC role `firehose_writer` 與 mapping、index template（`@timestamp` 是 `date`） | foundation、search、iam-base |
| 9 | `fleet` | thing type `<prefix>-device`；thing group `<prefix>-fleet`、`-unverified`、`-core`、`-quarantine`；IoT policy `<prefix>-device`、`-core`、`-claim`；role alias `<prefix>-greengrass-tes`（1 小時）；provisioning template `<prefix>-fleet`；pki 開啟時以 `SNI_ONLY` 註冊 CA；帳號層 IoT 設定（`account_settings`）；Device Defender 帳號 audit 設定（`device_defender_audit`）、每週一排程稽核、隔離用 mitigation action；Signer profile（`AWSIoTDeviceManagement-SHA256-ECDSA`）；IoT Jobs template `<prefix>-ota` | foundation、pki、storage、iam-base |
| 10 | `iam-app` | Firehose role 的 policy | foundation、network、storage、iam-base、search |
| 11 | `ingest` | IoT rule `<prefix 的 - 換成 _>_telemetry`、`_inference`（都送 Kinesis，失敗送 `rule-errors`）；Firehose `<prefix>-to-raw`（→ S3 `raw/`）、`<prefix>-to-search`（→ OpenSearch `<prefix>-events`）；Firehose 告警 | foundation、network、storage、iam-base、search |
| 12 | `sitewise` | `cameras`、`gateways` 都空時零資源；有攝影機時每台 core device 一個 hub model 與 asset、每台攝影機一個 camera model 與 asset | 無 |
| 13 | `edge` | 每個 recipe 檔一個元件版本；`deployments` 每個 thing group 一個部署；`cameras` 不空時每台攝影機一個 KVS stream、每台 core device 一個 thing 層級部署 | foundation、storage、fleet、sitewise |
| 14 | `ml` | model package group `<prefix>-models`；pipeline `<prefix>-training`；每週一 03:00（Asia/Taipei）的排程；EventBridge rule `<prefix>-model-approved` | foundation、storage、iam-base |
| 15 | `inference` | `model_package_arn = null` 時零資源；有值時建 endpoint `<prefix>-inference` 與兩個 rollback 告警 | foundation、network、storage、iam-base、ml |

「讀」欄看不出來的順序限制：

- `iam-base` 比 `fleet`、`ingest`、`edge`、`ml` 先 apply，拿不到它們的 ARN，所以照命名規則組（`iam-base/naming.tf`）：thing group `<prefix>-fleet` 等四個、thing／thing type／IoT policy `<prefix>-*`、IoT rule `<prefix 的 - 換成 _>_*`、KVS stream `<prefix>-cam-*`、model package group `<prefix>-models`、pipeline `<prefix>-training`。`storage` 的 `model-approved` queue policy 也照命名規則只放行 rule `<prefix>-model-approved`。改一邊的名稱，另一邊要一起改；兩邊的測試各自寫死同一組期望值。
- `search-config` 在 `ingest` 之前：Firehose 開始寫之前，FGAC mapping 要先存在。`iam-app` 在 `ingest` 之前：Firehose 建立時會驗證 role。
- `sitewise` 在 `edge` 之前：`edge` 的 precondition 檢查每台攝影機都已經在 `sitewise` 發布的 asset 裡。
- `inference` 的 precondition 檢查 `model_package_arn` 屬於 `ml` 的 model package group。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../../docs/adr/0003-cross-stack-values-via-ssm-only.md)）。下表照各 stack 的 `ssm-outputs.tf` 整理，不一致時以程式碼為準。

| stack | String | StringList |
|---|---|---|
| `foundation` | `kms_key_arn`、`alarm_topic_arn`、`flow_log_bucket_arn`、`opensearch_master_secret_arn` | — |
| `network` | `vpc_id`、`vpc_cidr`、`sg_opensearch_id`、`sg_firehose_id`、`sg_sagemaker_id`、`sg_client_vpn_id`、`sg_search_admin_id` | `azs`、`subnet_ids_app`、`subnet_ids_data`、`subnet_cidrs_data` |
| `vpn` | `client_vpn`：JSON。關閉時 `{"enabled":false}`；開啟時有 `endpoint_id`、`dns_name` | — |
| `pki` | `ca`：JSON。關閉時 `{"enabled":false}`；開啟時有 `arn`、`certificate_pem`（SUBORDINATE 還沒安裝憑證時是 `null`） | — |
| `storage` | `telemetry_bucket_arn`、`greengrass_artifacts_bucket_arn`、`greengrass_artifacts_bucket_name`、`ota_bucket_arn`、`ml_bucket_arn`、`ml_bucket_name`、`stream_arn`、`rule_errors_queue_arn`、`rule_errors_queue_url`、`model_approved_queue_arn` | — |
| `iam-base` | `role_iot_rule_arn`、`role_iot_provisioning_arn`、`role_iot_logging_arn`、`role_iot_audit_arn`、`role_iot_mitigation_arn`、`role_greengrass_tes_arn`、`role_ota_presign_arn`、`role_firehose_arn`、`role_firehose_name`、`role_sagemaker_pipeline_arn`、`role_sagemaker_endpoint_arn`、`role_scheduler_arn` | — |
| `search` | `opensearch_domain_arn`、`opensearch_domain_name`、`opensearch_endpoint` | — |
| `search-config` | `firehose_writer_role`（FGAC role 名稱） | `ism_policy_ids` |
| `fleet` | `thing_group_fleet_arn`、`thing_group_unverified_arn`、`thing_group_core_arn`、`role_alias_arn`、`provisioning_template_name`、`ota_signing_profile_name`、`ota_job_template_arn` | — |
| `iam-app` | 不發布 | — |
| `ingest` | `firehose_s3_arn`、`firehose_opensearch_arn` | `rule_names` |
| `sitewise` | `edge_connector_asset_ids`：JSON。沒有攝影機時 `{}`；有攝影機時是 `{"cameras":{<攝影機 id>:<asset id>},"hubs":{<core thing>:<asset id>}}` | — |
| `edge` | `kvs_stream_arns`：JSON，攝影機 id → stream ARN，沒有攝影機時 `{}` | `deployment_ids`（群組部署在前，攝影機的 thing 部署在後） |
| `ml` | `model_package_group_arn`、`model_package_group_name`、`pipeline_name` | — |
| `inference` | `endpoint`：JSON。沒有 endpoint 時 `{"enabled":false}`；有時有 `name`、`arn` | — |

`sitewise` 的 JSON 形狀跟 design §7.2 寫的不同（多了 `hubs`），因為 edge connector 的部署設定要的是 core device 的 hub asset。

`check-ssm-contract.sh` 檢查兩件事：每個讀取的 key 都由 `ORDER` 更早的 stack 發布、型別一致；同一個 env 各 stack tfvars 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名。

## 前置作業的細節

README〈前置作業〉每一項的完整做法，編號相同。

1. **state bucket 的強化**（第一次 `init` 之前；v7 design §4.2，design §4.2 沿用）。做法跟 [example4 REFERENCE〈前置作業的細節〉第 1 項](../../example4/infra/REFERENCE.md#前置作業的細節)相同：專用 CMK（key policy 只允許 deploy role 與 break-glass role），key ARN 填進 30 份 `envs/*.tfbackend` 的 `kms_key_id`，佔位 `<state-kms-key-arn>` 沒換掉時 `init` 會失敗；bucket policy 拒絕非 TLS、只允許 deploy role 與 break-glass role 讀寫這個專案的前綴、拒絕不是用該 CMK 的上傳（範例 policy 在 example4 那一節）；noncurrent version 30 天過期；對 state bucket 開 CloudTrail data event。`search` 的 state 含 OpenSearch master 密碼，這一步不能省。
2. **awscc provider 的 lock**（第一次 `init` 之前）。`fleet`、`sitewise`、`edge` 的 `.terraform.lock.hcl` 裡 awscc 1.107.0 目前只有一個 `h1:`（darwin），`validate.sh` 的 S10 要求 darwin 與 linux 各一個，所以現在全量驗證會在 S10 停下。在自己的終端機（要能連 registry，不需要 AWS 憑證）對三個 stack 各跑一次，再 commit 三份 lock：

   ```bash
   for s in fleet sitewise edge; do
     terraform -chdir=templates/example5/infra/terraform/$s providers lock -platform=darwin_arm64 -platform=linux_amd64
   done
   ```

3. **寫入 OpenSearch master secret 的值**（`foundation` apply 之後、`search` plan 之前）。secret 名稱是 `<project>-<env>/opensearch-master`，值是 JSON `{"username","password"}`，`opensearch-domain` 在 plan 時就讀，沒有值會失敗。指令跟 example4 相同，密碼不經過指令參數與 shell 變數：

   ```bash
   aws secretsmanager get-random-password --password-length 32 --require-each-included-type \
       --query RandomPassword --output text \
     | jq -Rc '{username: "master", password: .}' \
     | aws secretsmanager put-secret-value --secret-id <project>-<env>/opensearch-master --secret-string file:///dev/stdin
   ```

4. **韌體簽章憑證匯入 ACM**（`fleet` apply 之前；design K17）。Signer 對 IoT platform 不替你管 key，要自己準備 code signing 憑證與私鑰（例如 ECDSA P-256），匯入 ACM 後把 ARN 填進 `fleet` tfvars 的 `ota_signing_certificate_arn`（現在是佔位值）。私鑰只經過 `aws acm import-certificate`，不進 Terraform：

   ```bash
   aws acm import-certificate --certificate fileb://ota-signing.crt --private-key fileb://ota-signing.key \
     --certificate-chain fileb://ota-signing-chain.crt --query CertificateArn --output text
   ```

   裝置韌體要內建這張憑證（或它的公鑰）來驗簽。憑證要符合 Signer 對 code signing 憑證的要求，這一點沒有在真實帳號確認。
5. **帳號層設定：每個帳號、每個 region 只能一處**（`fleet` apply 之前；design K9）。`fleet` tfvars 的 `account_settings`（fleet indexing、IoT logging `WARN`、registry 事件）與 `device_defender_audit`（帳號 audit 設定）作用在整個帳號。**同帳號的第二個專案要把兩個都設 `null`**，否則後 apply 的會蓋掉前面的設定；每週排程稽核與隔離用的 mitigation action 不受影響，照樣建立。先用 `aws iot get-v2-logging-options`、`aws iot get-indexing-configuration`、`aws iot describe-account-audit-configuration` 確認帳號目前的設定。拿掉設定不會還原帳號的狀態（provider 刪除時不呼叫 AWS）。
6. **claim 憑證**（`fleet` apply 之後、裝置出廠之前；design §4.1）。在 Terraform 外用 CSR 建立，私鑰只在產線的環境：

   ```bash
   openssl ecparam -name prime256v1 -genkey -noout -out claim.key
   openssl req -new -key claim.key -subj "/CN=<project>-<env>-claim" -out claim.csr
   aws iot create-certificate-from-csr --certificate-signing-request file://claim.csr --set-as-active \
     --query certificateArn --output text
   aws iot attach-policy --policy-name <project>-<env>-claim --target <claim-certificate-arn>
   ```

   裝置用 claim 憑證連 IoT Core，呼叫 template `<project>-<env>-fleet`，參數 `SerialNumber`。開通後 thing 名稱是 `<project>-<env>-<序號>`、進 `<project>-<env>-unverified` 群組、拿到附加 `<project>-<env>-device` policy 的正式憑證。確認是自己的裝置後，人或 CI 把它搬進 `-fleet`（一般裝置）或 `-core`（core device）群組；Greengrass 部署只對 `-fleet`、`-core`。core device 另外要：序號以 `core-` 開頭（thing 名稱要符合 `<project>-<env>-core-*`，core policy 靠這個命名規則限縮），並在它的憑證附加 `<project>-<env>-core` policy，template 不會自動附加。每批生產結束就把 claim 憑證設成 `INACTIVE`（〈runbook：輪替 claim 憑證〉）。
7. **攝影機的 RTSP secret**（`sitewise`、`edge` 帶 `cameras` apply 之前；design K14）。每台攝影機一個 Secrets Manager secret，在 repo 外建立，**名稱必須是 `<project>-<env>/cameras/<攝影機 id>`**，值是 key 為 `RTSPStreamUrl` 的 JSON（網址含帳密）；ARN 填進 `cameras` 的 `rtsp_secret_arn`。core device 的 TES role（`iam-base` 的 `greengrass-tes`）只能讀這個命名規則底下的 secret，`sitewise`、`edge` 的 `cameras` validation 也會擋其他名稱。用共用 CMK 加密時 TES role 已經有 `kms:Decrypt`。RTSP 網址不進 tfvars、SSM 與 state。

   ```bash
   aws secretsmanager create-secret --name <project>-<env>/cameras/<攝影機 id> \
     --kms-key-id <foundation 的 kms_key_arn> \
     --secret-string '{"RTSPStreamUrl":"rtsp://<帳號>:<密碼>@<攝影機位址>/<路徑>"}'
   ```
8. **執行 apply 的身分要有的特權操作**（design §4）：

   | 操作 | 哪些 stack 用到 |
   |---|---|
   | `iam:CreateServiceLinkedRole` | `search`（OpenSearch）、`vpn`（Client VPN）、`inference`（SageMaker）、`fleet`（IoT），帳號第一次建立該服務時 |
   | `iam:PassRole` | `fleet`（provisioning、logging、audit、mitigation、role alias、presigned URL 的 role）、`ingest`（IoT rule、Firehose）、`ml`（SageMaker pipeline、Scheduler）、`inference`（SageMaker endpoint） |
   | `kms:CreateGrant` | `ingest`（Firehose）、`ml`、`inference`（SageMaker）、`edge`（KVS） |
   | `secretsmanager:GetSecretValue` | `search`、`search-config`（OpenSearch master secret） |
   | `iot:SetV2LoggingOptions`、`iot:UpdateIndexingConfiguration`、`iot:UpdateEventConfigurations`、`iot:UpdateAccountAuditConfiguration` | `fleet`（帳號層設定） |
   | `acm-pca:*` | `pki`（開啟時） |
   | `events:PutRule`、`events:PutTargets`、`scheduler:CreateSchedule` | `ml` |
   | Cloud Control API（`cloudformation:CreateResource`、`GetResource`、`UpdateResource`、`DeleteResource`、`GetResourceRequestStatus`） | `fleet`、`sitewise`、`edge`（awscc 透過 Cloud Control 建立資源）；完整清單沒有對真實帳號核對 |

## 安全取捨：fleet provisioning 不掛 pre-provisioning hook

`iot-fleet` 支援 `pre_provisioning_hook`，但範本傳 `null`（design K16）：`lambda-function` 只收 container image，掛 hook 就要把 ECR 與 image 建置帶進範本。下表摘自 design §4.1。

| 項目 | 內容 |
|---|---|
| 取捨 | example5 預設用 claim 憑證開通，沒有 Lambda hook 檢查裝置序號 |
| 風險 | claim 憑證外洩的人可以開通任意數量的裝置，拿到正式的裝置憑證與裝置 policy 的權限 |
| 影響範圍 | 每個環境一組 claim 憑證；開通出來的裝置只能用自己的 topic（`${iot:Connection.Thing.ThingName}`），碰不到其他裝置的資料、拿不到 AWS 憑證（一般裝置不是 core device，沒有 role alias 權限） |
| 補償控制 | 1. claim 憑證在 Terraform 外用 CSR 建立（`create-certificate-from-csr`），私鑰不經過 Terraform；2. claim policy 只有 `$aws/certificates/create/*` 與 `$aws/provisioning-templates/<template>/provision/*` 兩組 topic；3. provisioning template 要求 `SerialNumber` 參數、thing 名稱用序號組出（同序號第二次開通會失敗）；4. 開通出來的裝置先進 `unverified` thing group，人工或 CI 確認後再搬進正式群組（Greengrass 部署只對正式群組）；5. 每批生產結束就把 claim 憑證設成 `INACTIVE`；6. Device Defender audit 開、IoT logging 開 |
| 實作與設計的差異 | 第 3 點的「序號符合格式」沒有做到：provisioning template 的參數只能設 `Type` 與 `Default`，沒有格式檢查，只做到 thing 名稱由序號組出。「同序號第二次開通會失敗」也還沒在真實帳號確認 |
| 移除取捨的 checkpoint | 1. 範本有 Lambda image 建置流程時（或 `lambda-function` 支援 zip）：掛 hook 查 DynamoDB 的序號白名單；2. 改用 by trusted user 或 `acm-pca` 加 JITP；3. 最晚 2027-04-25 重新審查 |
| 記錄在哪裡 | design §4.1、這一節、`iot-fleet` README〈注意〉 |

## 安全例外：OpenSearch master 帳密進 state（沿用 v7）

`search`、`search-config` 從 example4 複製，v7 的例外原樣適用（design §4.2、K30）：master 密碼以明文出現在 `search` 的 state（`aws_opensearch_domain` 與 module 讀 secret 的 data source 各一份）；`search-config` 用 ephemeral 讀，state 裡零份。風險、補償控制（module 沒有 password 變數、state bucket 強化、SG 只放 Client VPN 與 `search_admin` 的 443、master 不給日常使用、`AUDIT_LOGS`、secret 用 CMK）、每 90 天的輪替步驟與 owner，見 [example4 REFERENCE〈安全例外〉](../../example4/infra/REFERENCE.md#安全例外opensearch-master-帳密進-state)。移除例外的 checkpoint 跟 example4 一起審查，最晚 2027-04-24。

## `search-config` 的執行環境

跟 example4 相同：domain 在 data subnet，沒有公開 endpoint；VPC 沒有 NAT，`search_admin` SG 也只開到 domain 的 egress。建議開 `vpn` 的 Client VPN（`envs/examples/vpn.tfvars`），從 VPN 上執行；或在 VPC 內的 runner 另外補對外的路。細節見 [example4 REFERENCE〈`search-config` 的執行環境〉](../../example4/infra/REFERENCE.md#search-config-的執行環境)。ISM 天數：dev 第 3／7／30 天進 UltraWarm／cold／刪除，sit 第 7／30／90 天，都是累計年齡；index 是 `<prefix>-events*`，**每筆資料都要帶 `@timestamp`**，否則搬不進 cold。

## Greengrass 元件與模型的發布流程

### 元件的新版本（design K10–K12、§7.3）

元件版本不可變：recipe 改了就是新版本，一個版本一個檔案。

1. 新增 `edge/components/<元件>/<新版本>.json`。`edge` 用 `templatefile` 讀 recipe，`${artifact_bucket}` 換成 `storage` 的 greengrass-artifacts bucket；recipe 裡要保留字面 `${` 時寫成 `$${`（Greengrass 自己的變數是 `{artifacts:...}` 這種沒有 `$` 的寫法，不受影響）。artifact 的 `Uri` 一定要在這個 bucket，`greengrass-component` 會擋。
2. CI 把 artifact 上傳到 `s3://<greengrass-artifacts>/artifacts/<元件>/<新版本>/`。**Terraform 不上傳物件**；沒上傳就 apply，元件版本建得起來，但裝置下載時部署會失敗。core device 經 TES role 只能讀 `artifacts/*`。
3. 改 `edge/envs/<env>.tfvars` 的 `deployments.<名稱>.components`。precondition 檢查每個自訂元件（名稱不是 `aws.` 開頭）的版本都有 recipe 檔，引用不存在的版本 plan 就失敗；所以舊版本的檔案要等沒有部署引用之後才能刪。`aws.greengrass.Nucleus` 必填並釘版本（K12），範本的 `2.14.3`、StreamManager `2.2.1` 是佔位，換成自己測過的版本。
4. PR 審查時看 `components` 的差異：**拿掉的元件會在裝置上解除安裝**。
5. apply `edge`。部署每次變更都是 replace（plan 會顯示刪除再建立，這是正常的）；失敗一律 `ROLLBACK`；rollout dev 每分鐘 10 台、失敗 10% 中止，sit 每分鐘 20 台、失敗 5% 中止，至少執行 10 台才判斷。自訂元件的設定會 merge `TopicPrefix = <prefix>`。

每個 thing group 只能有一個部署（validation 擋），一次 apply 不要超過 10 個部署在刪除中（AWS 的上限）。

### 模型核准到部署（design K22、§7.4）

```
Scheduler（每週一 03:00，dev 停用）→ SageMaker Pipeline <prefix>-training（前處理、訓練、註冊）
  → Model Registry <prefix>-models（新版本 PendingManualApproval）
  → 人在 Studio 或 CLI 核准（aws sagemaker update-model-package --model-package-arn <arn> --model-approval-status Approved）
  → EventBridge rule <prefix>-model-approved 比對 aws.sagemaker / SageMaker Model Package State Change /
    ModelPackageGroupName = <prefix>-models / ModelApprovalStatus = Approved
  → SQS <prefix>-model-approved（SSE-KMS，queue policy 只放行這條 rule）
  → CI（範本外）消費 → 開 PR → 合併後 apply edge 或 inference
```

- 訊息內容：EventBridge 不做 input transformer，SQS 收到的是完整事件 JSON；CI 從 `detail.ModelPackageArn`、`detail.ModelPackageGroupName`、`detail.ModelApprovalStatus` 取值。欄位名稱依 AWS 文件，沒有在真實帳號確認。
- CI 要做的事：讀 model package 的 `ModelDataUrl`、把模型轉成 ONNX、打包成元件 artifact 上傳（上一節第 2 步）、產生新版本的 recipe 檔、開 PR 改 `deployments` 的版本；要雲端推論時開 PR 改 `inference` 的 `model_package_arn`。處理成功才刪訊息；失敗 5 次進 DLQ。
- CI 的 IAM role 不在範本裡，至少要：`sqs:ReceiveMessage`、`sqs:DeleteMessage`（`model-approved` queue）、共用 CMK 的 `kms:Decrypt`、`sagemaker:DescribeModelPackage`、ml-artifacts 的 `s3:GetObject`、greengrass-artifacts `artifacts/*` 的 `s3:PutObject`。
- 告警：訊息等超過一天（CI 沒在跑）、DLQ 有訊息，都送告警 topic。
- 範例 pipeline 的 image 是佔位：`<account>.dkr.ecr.<region>.amazonaws.com/<prefix>-preprocess`、`-train`、`-inference`，iam-base 的 SageMaker role 只能拉 `<prefix>-*` 的 repository。換成自己的 pipeline 時，用 SageMaker Python SDK 匯出 `pipeline.definition()` 覆蓋 `ml/pipelines/training.json`，`${...}` 的值由 `ml` stack 填。

### 非 Greengrass 裝置的 OTA（design K7、K17）

1. CI 用 Signer profile（SSM `fleet/ota_signing_profile_name`）簽韌體，結果放到 ota-artifacts 的 `signed/current/firmware.bin`（bucket 有 versioning，舊版韌體找得回來）。
2. CI 從 job template 建 job：`aws iot create-job --job-id <id> --job-template-arn <fleet/ota_job_template_arn> --targets <thing group arn>`。job document 用 presigned URL（`ota-presign` role，只能讀 `signed/*`，1 小時過期）；rollout dev 每分鐘 10 台、sit 20 台，失敗比例超過 10%／5% 取消 job，timeout 60 分鐘。
3. 每次發布的 job 是執行期操作，不進 Terraform。job template 任何屬性改了都會 replace，不影響已經建立的 job。

## runbook：輪替 claim 憑證

每批生產結束、或懷疑外洩時做。

1. 照〈前置作業的細節〉第 6 項建新的 claim 憑證並附加 `<project>-<env>-claim` policy，交給產線。
2. 舊的設成 `INACTIVE`：`aws iot update-certificate --certificate-id <old-id> --new-status INACTIVE`。已經開通的裝置用自己的憑證，不受影響。
3. 懷疑外洩時：在 `<project>-<env>-unverified` 群組找出不認得的 thing，把它們的憑證設成 `REVOKED`，thing 搬進 `-quarantine` 或刪除；查 `AWSIotLogsV2` log group 的開通紀錄。
4. 確認不再需要舊憑證後：`aws iot detach-policy --policy-name <project>-<env>-claim --target <old-arn>`、`aws iot update-certificate --certificate-id <old-id> --new-status INACTIVE`（已是）、`aws iot delete-certificate --certificate-id <old-id>`。

## runbook：開啟 pki（自建 CA）

預設不開（design D4，一個 CA 約 400 美元／月）。範本只建 CA 並註冊到 IoT Core，不替裝置簽憑證、不開 auto-registration、不掛 JITP。

1. 把 `pki/envs/examples/pki.tfvars` 的 `ca` 物件抄進 `pki/envs/<env>.tfvars`，改 `subject`。`ROOT` 會自簽並安裝；`SUBORDINATE` 第一次 apply 只產生 CSR。
2. `./stacks.sh <env> pki apply`。`SUBORDINATE` 時拿 `terraform output ca_csr` 給上層 CA 簽，把憑證與 chain 填進 `ca.subordinate_certificate`，再 apply 一次；在那之前 `ca` 的 `certificate_pem` 是 `null`，不要 apply `fleet`。
3. `./stacks.sh <env> fleet apply`：讀到 `pki/ca` 的 `enabled = true`，以 `SNI_ONLY` 註冊 CA（不需要 verification certificate，裝置連線要送 SNI）。
4. 裝置憑證由你的簽發流程用這個 CA 簽，再用 `aws iot register-certificate` 註冊、附加 `<project>-<env>-device` policy。撤銷用 IoT registry 把憑證設成 `INACTIVE`／`REVOKED`（不開 CRL、OCSP，design K18）。
5. 關閉：`ca` 設回 `null`，依序 apply `pki`、`fleet`。CA 刪除後保留 `permanent_deletion_time_in_days`（預設 30）天可還原；IoT 上用這個 CA 簽的裝置憑證要先換掉。

## runbook：開啟雲端推論

預設不建（design K21）。

1. 模型在 `<prefix>-models` 核准後，CI 開 PR 在 `inference/envs/<env>.tfvars` 設 `model_package_arn`（含版本）；precondition 擋其他 group 的模型。
2. 預設是一台 `ml.m5.large` 的 instance variant：放在 data subnet、掛 `sagemaker` SG、network isolation、20% data capture 到 ml-artifacts 的 `capture/`、blue/green `ALL_AT_ONCE` 烘烤 600 秒，`Invocation5XXErrors` 或平均 `ModelLatency` 超過 1 秒就 rollback。改用 serverless 見 `envs/examples/inference-serverless.tfvars`（不能放 VPC、不能 data capture、不支援 network isolation）。
3. 呼叫端在 VPC 內時：先在 `network` tfvars 的 `interface_endpoint_services` 加 `"sagemaker.runtime"` 並 apply `network`（每個 AZ 按小時計費）。呼叫端的 role 不在範本，給 `sagemaker:InvokeEndpoint` 到 `arn:aws:sagemaker:<region>:<account>:endpoint/<prefix>-inference`。
4. `./stacks.sh <env> inference apply`。換模型版本也是改 `model_package_arn` 後 apply，走 blue/green。
5. 關閉：`model_package_arn` 拿掉，apply 會刪掉 endpoint 與告警。

## runbook：新增攝影機

影像不上雲、只在邊緣推論時不用做這些；只有用 Kinesis Video Streams 上傳影像才需要（design D6、K14）。

1. 確認 core device：Linux、名稱是 `<project>-<env>-core-*`、在 `-core` 群組、附加 `-core` policy。
2. 建 RTSP secret `<project>-<env>/cameras/<攝影機 id>`（〈前置作業的細節〉第 7 項）。TES role 已經能讀這個命名規則底下的 secret，也有 edge connector 要的 SiteWise 權限（asset 與 asset model 限縮到這個帳號與 region），不用改 `iam-base`。
3. 在 `sitewise/envs/<env>.tfvars` 與 `edge/envs/<env>.tfvars` 的 `cameras` 加**一模一樣**的一筆：`<攝影機 id> = { core_thing_name, rtsp_secret_arn, retention_hours }`。id 是 1–32 字元的小寫英數字與 `-`；`rtsp_secret_arn` 不是第 2 步那個名稱的 secret 時，plan 就失敗。
4. 依序 apply `sitewise`、`edge`。`edge` 的 precondition 確認攝影機已經在 `sitewise` 的 asset 裡。`edge` 建 KVS stream `<prefix>-cam-<id>`，並對 core device 建一個 thing 層級的部署 `<prefix>-kvs-<thing>`（Nucleus、StreamManager、`aws.iot.EdgeConnectorForKVS`，設定 `SiteWiseAssetIdForHub`）；edge connector 不能部署到 thing group。`camera_deployment.nucleus_version` 要跟群組部署的 Nucleus 一樣。

SiteWise 的限制：awscc 的 asset resource 不能設定屬性值，所以每台攝影機的設定（`KinesisVideoStreamName`、`RTSPStreamSecretARN`、本機保留 60 分鐘、直播與上傳的起訖）都寫成 asset model 的預設值，**一台攝影機一個 camera model、一台 core device 一個 hub model**（hub 對每台攝影機有一個 `ConnectedCameras-<id>` hierarchy）。後果：

- 改 RTSP secret 或攝影機數量會改 model，apply 是 in-place 更新還是 replace 沒有確認。
- 直播、上傳影片這類操作要在執行期用 `BatchPutAssetPropertyValue` 寫 asset 的屬性，Terraform 不管；寫了之後的值跟 model 預設值不同，Terraform 看不到這個差異。
- edge connector 能不能沿著多個 `ConnectedCameras-<id>` hierarchy 找到所有攝影機，沒有在真實帳號確認。

## destroy

`./stacks.sh <env> all destroy` 依反向順序跑。拆到 `search-config` 時要在〈`search-config` 的執行環境〉說的網路裡；那時 `vpn` 還沒拆，Client VPN 仍可用。

### destroy 前要做的事

| 資源 | 預設 | 要先做什麼 |
|---|---|---|
| 開通出來的 thing 與憑證、claim 憑證 | 在 Terraform 外建立 | 憑證要先 detach policy、設成 `INACTIVE` 再刪，thing 要先 detach principal 再刪；IoT policy 還附加在憑證上時，`fleet` 刪不掉 policy。thing group 裡還有 thing 時能不能刪，沒有確認 |
| Greengrass 部署（`edge`） | 刪除時先 cancel 再 delete | **裝置上的元件不會被移除**。要清掉裝置上的應用，先 apply 一個不含那些元件的部署，或重設裝置 |
| S3 bucket（`storage` 的四個、`foundation` 的 flow log bucket） | `force_destroy = false` | 不是空的會刪不掉。先清空（greengrass-artifacts、ota-artifacts、ml-artifacts 有 versioning，連舊版本與刪除標記一起清），確認資料不需要再刪。telemetry 的物件可能已轉到 `GLACIER_IR` |
| OpenSearch 的 warm／cold index（`search`） | ISM 依年齡搬移 | 先刪除或搬回 hot 所有 warm 與 cold 的 index，再 destroy `search` |
| model package（`ml`） | pipeline 註冊，不在 Terraform | 先刪掉 group 裡的所有版本；group 還有版本時能不能刪，沒有在真實帳號確認 |
| SageMaker endpoint（`inference`） | 刪除即停止計費 | data capture 的物件留在 ml-artifacts 的 `capture/` |
| KVS stream（`edge`） | 刪除即丟影片 | 要保留的影片先匯出 |
| SiteWise asset 與 model（`sitewise`） | awscc 刪除 | 有 hierarchy 關聯時刪除順序是否要先解除關聯，沒有確認 |
| 帳號層 IoT 設定（`fleet`） | 刪除時 provider 不呼叫 AWS | logging、fleet indexing、registry 事件會維持原狀；要關就自己用 CLI 改 |
| Device Defender 帳號 audit 設定（`fleet`） | awscc 刪除 | 刪除後帳號的 audit check 是否停用沒有確認；同帳號其他專案在用時先確認 |
| Signer profile（`fleet`） | 刪除是 cancel | 同名 profile 之後能不能再建立，沒有確認 |
| ACM Private CA（`pki`，開啟時） | 刪除後保留 30 天 | 期間可以還原；用它簽的裝置憑證要先換掉 |
| Secrets Manager secret（`foundation`） | 刪除後保留 30 天 | 期間不能用同名重建；值在 Terraform 外寫，刪了就沒有，要先備份 |
| CMK（`foundation`） | 刪除等待 30 天 | 其他 stack 都拆完再 destroy `foundation`，不然 bucket 與備份解不開 |

destroy 不會刪範本以外建的東西：state bucket、開通出來的 thing 與憑證、claim 憑證、ACM 的韌體簽章憑證、RTSP secret、ECR repository、CI 上傳的 artifact 與韌體（bucket 清空時一起刪）、IoT 的 `AWSIotLogsV2` 與 Greengrass、SageMaker 自己建的 log group。

## 複製出去之後要改什麼

| 項目 | 改什麼 |
|---|---|
| module 的 `source` | 從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，awscc module 也是 `/aws`，ADR-0004）；換 organization 或改 git 來源見 [`docs/guides/consuming-modules.md`](../../../docs/guides/consuming-modules.md) |
| 帳號表 | 15 個 stack 的 `common.tf` 的 `accounts_by_env`（`111111111111`、`222222222222`），同步改、保持一字不差 |
| state | 每份 `envs/*.tfbackend` 的 `bucket`、`kms_key_id`，`key` 的 `example-` 前綴換成自己的 `project` |
| tfvars 的佔位值 | `project`、`expected_account_id`；`foundation` 的 `alarm_emails`；`network` 的 `vpc_cidr`（`10.40.0.0/20`、`10.41.0.0/20`）、`azs`；`fleet` 的 `ota_signing_certificate_arn`、`ota_rollout`、`account_settings` 與 `device_defender_audit`（同帳號第二個專案設 `null`）；`edge` 的 `deployments` 與 `camera_deployment` 的元件版本；`search` 的規格；`search-config` 的 ISM 天數與維運 role；`ml` 的 `training_schedule_state` |
| topic | 裝置 publish `<project>-<env>/telemetry/<thing>`、subscribe `<project>-<env>/cmd/<thing>`；core device 的推論結果 publish 到 `<project>-<env>/inference/<thing>`。韌體照這個命名，IoT policy 與 rule 都依賴它 |
| 元件與 pipeline | 換掉 `edge/components/com.example.Inference/` 與 `ml/pipelines/training.json`；在 CI 加上傳 artifact、簽韌體、消費 `model-approved` 的步驟；建 `<project>-<env>-preprocess`、`-train`、`-inference` 的 ECR repository |

## 已知限制的細節

下面是 mock 驗不到或刻意不做的事，第一次 apply 時要逐項確認。

| 範圍 | 限制 |
|---|---|
| fleet provisioning | 沒有 pre-provisioning hook（〈安全取捨〉）；序號格式不檢查；claim policy 只放行 `$aws/certificates/create/*`，裝置要用 `CreateKeysAndCertificate`（金鑰由 AWS 產生），自己產生金鑰、送 CSR 的 `create-from-csr` 會被擋，要用的話在 `fleet/fleet.tf` 的 claim policy 加上 `$aws/certificates/create-from-csr/*`；開通出來的 thing 一律是 `-device` thing type、附加 `-device` policy，core device 要人工附加 `-core` policy 並搬群組 |
| core device policy | Greengrass data plane 的四個動作（`GetComponentVersionArtifact`、`ResolveComponentCandidates`、`GetDeploymentConfiguration`、`ListThingGroupsForCoreDevice`）用 Resource `*`，照 Greengrass 的最小 policy；其他動作用 `client/<prefix>-core-*` 命名規則 |
| IoT rule | 只送 Kinesis，再由 Firehose 進 S3 與 OpenSearch（IoT rule 的 OpenSearch action 送不進 VPC 內的 domain）。`iot-topic-rule` 的 action 由輸入型別限定，型別以外的 key（例如 `http`）會被 Terraform 丟掉而不是報錯 |
| Greengrass | 部署每次變更都 replace；拿掉的元件會在裝置上解除安裝；awscc 的 `inline_recipe` 在 plan 是否持續顯示變更未確認，有的話要加 `ignore_changes` |
| 範例元件與 pipeline | `com.example.Inference` 沒有在裝置上跑過（`main.py`、`requirements.txt` 也不在範本裡，由 CI 打包）；訓練 pipeline 沒有在 SageMaker 上跑過，image 是佔位 |
| 攝影機 | 見〈runbook：新增攝影機〉：RTSP secret 要照命名規則 `<prefix>/cameras/<id>` 建立、一台攝影機一個 SiteWise model、多個 hierarchy 未確認；TES role 的 `iotsitewise:ListAssets` 限縮到 asset model 是否可行未確認；edge connector 只支援 Linux、不能部署到 thing group |
| Device Defender | Detect 從 2026-08-31 起不開放新客戶，範本只做 audit（8 個 check、每週一）與隔離動作；沒有裝置行為的異常偵測，要靠 IoT logging 與自己加的 CloudWatch 告警 |
| PKI | 不開 CRL 與 OCSP，撤銷靠 IoT registry；IoT Core 連線時是否查 CRL 未確認 |
| SageMaker | endpoint 在沒有 NAT 的 VPC，模型從 S3 經 gateway endpoint 讀，能否正常啟動未確認；帶本機 NVMe 的 instance type 能否用 KMS 未確認（預設 `ml.m5.large` 沒有）；CI 與呼叫端的 role 不在範本 |
| awscc | 沒有 `default_tags`，tag 由 stack 傳給 module；Cloud Control 的錯誤訊息與 drift 偵測比 aws provider 少；lock 要補 linux hash（〈前置作業的細節〉第 2 項） |
| IAM 與 KMS | `iam-base`、`iam-app` 的動作清單與 `foundation` key policy 各服務的 condition key 都依文件寫，沒有對真實帳號驗證；TES role 的 trust 帶 `aws:SourceAccount`，credentials provider 會不會送這個 key 未確認 |
| 告警門檻 | `storage`、`search`、`ingest`、`inference` 的門檻是起始值，沒有用真實流量調過 |
| OpenSearch | 同 example4：warm 最小台數、`search-config` 的測試範圍（離線的 aws provider、`read_master_secret = false`）見 [example4 REFERENCE〈已知限制的細節〉](../../example4/infra/REFERENCE.md#已知限制的細節) |

## 驗證

```bash
scripts/validate.sh templates/example5
```

依序做 `fmt`、靜態規則（含 S1 mock provider、S8 stack 只呼叫 module、S10 lock 的 darwin 與 linux hash、S11 terraform-docs）、`check-ssm-contract.sh`；再對每個 stack 跑 `init -backend=false`、`validate`、`terraform test`，對 `dev`、`sit` 兩份 tfvars 與 `envs/examples/` 各跑一次測試，最後 tflint。全部離線，不需要 AWS 憑證，但需要 HCP registry token。

### 靜態驗證通過（2026-10-27）

| 項目 | 結果 |
|---|---|
| 每個 stack 的 `init -backend=false`、`validate`、`terraform test`、tflint | 15 個 stack、423 個 run 全過（含 dev、sit 兩份 tfvars 與 `envs/examples/` 的測試），tflint 對每份 tfvars 展開 module 也通過 |
| `scripts/validate.sh templates/example5` 全量 | **還沒通過**：靜態規則停在 S10（`fleet`、`sitewise`、`edge` 的 awscc lock 只有一個 `h1:`，等〈前置作業的細節〉第 2 項）；執行這次驗證的機器沒有 terraform-docs，S11 沒跑到。上一列是照 `validate.sh` 的步驟逐 stack 手動跑的結果 |
| `check-ssm-contract.sh` | 15 個 stack、72 個讀取、2 個 env 通過 |
| `search-config/tests/check-read-master-secret.sh` | 通過：沒有 tfvars 設 `read_master_secret` |
| `stacks.sh dev all plan --dry-run` | 依 ORDER 印出 15 個 stack 的指令，`destroy` 反向 |
| 環境名稱 | 對 `templates/example5` 做不分大小寫的 `grep`（排除 `*.svg`），`dev`、`sit` 以外的環境名稱都沒有出現 |

### 雲端整合待驗證

需要真實帳號，這個里程碑沒有做。

| 項目 | 怎麼確認 |
|---|---|
| fleet provisioning by claim | claim 憑證只碰得到兩組 provisioning topic；開通後 thing 名稱、thing type、`unverified` 群組、`-device` policy 正確；同序號第二次開通失敗 |
| 裝置 policy | 一般裝置只能用自己的 client id 與 topic；core device 的命名規則與 Greengrass data plane 動作夠用 |
| core device 拿 AWS 憑證 | role alias 換得到 TES 憑證（trust 的 `aws:SourceAccount`）；讀得到 SSE-KMS 的 artifact；寫得到 `/aws/greengrass/*` log |
| Greengrass 部署 | replace 的行為、`ROLLBACK`、abort 條件；awscc `inline_recipe` 在 plan 是否持續顯示變更；拿掉元件時裝置解除安裝 |
| 範例推論元件 | ONNX Runtime 在裝置上跑得起來，結果 publish 到 `<prefix>/inference/<thing>` |
| IoT rule → Kinesis → Firehose | 兩條 rule 寫入 SSE-KMS 的 stream；失敗時 error action 寫進 SSE-KMS 的 `rule-errors`；Firehose 寫進 S3 與 VPC 內的 OpenSearch（SigV4、FGAC `firehose_writer`） |
| OpenSearch | 同 example4：ISM 搬移（含 `@timestamp`）、2 台 warm、Dashboards 只能從 VPN 連、master 密碼輪替 |
| 帳號層 IoT 設定 | logging 寫進 `AWSIotLogsV2`、fleet indexing、registry 事件；同帳號第二個專案設 `null` 時不互蓋 |
| Device Defender | 帳號 audit 設定的 check 名稱對照（排程稽核的大寫名稱與 awscc 的 snake_case）；每週稽核結果送到 SSE-KMS 的告警 topic；mitigation 把 thing 加進 `quarantine` |
| OTA | Signer 用匯入 ACM 的憑證與 `AWSIoTDeviceManagement-SHA256-ECDSA` 簽章；job template 的 presigned URL 用 `ota-presign` role 讀得到 `signed/current/firmware.bin`；rollout 與 abort |
| KVS edge connector | SiteWise asset model 的欄位與預設值；多個 `ConnectedCameras-<id>` hierarchy；TES role 讀得到 `<prefix>/cameras/*` 的 RTSP secret、SiteWise 權限限縮到 `asset/*` 與 `asset-model/*` 後仍夠用（AWS 範例是 `*`）；影像寫進 SSE-KMS 的 stream |
| SiteWise gateway | 在 Greengrass core device 上建立與連線 |
| 訓練與核准 | pipeline 用佔位以外的 image 跑完、以 `PendingManualApproval` 註冊；Scheduler 用 CMK 加密並觸發 pipeline；EventBridge 寫進 SSE-KMS 的 SQS（queue policy 的 `aws:SourceArn`）；SQS 訊息的欄位 |
| 雲端推論 | 從 model package 建 endpoint、VPC 內沒有 NAT 能啟動、network isolation、data capture；blue/green 由告警自動 rollback；serverless 範例 |
| pki | ROOT 與 SUBORDINATE 的建立流程；`SNI_ONLY` 註冊；IoT Core 連線時是否查 CRL |
| IAM 動作清單與 key policy | `iam-base`、`iam-app` 的 role 夠用且沒有多給；`foundation` key policy 各服務的 condition key 被接受 |
| 特權操作 | 執行 apply 的身分要的 Cloud Control API 動作清單 |
| destroy | 帳號層設定與 audit 設定刪除後的狀態；Signer profile cancel 後能否同名重建；model package group、SiteWise 的刪除順序 |
| 告警 | Kinesis、SQS、Firehose、OpenSearch、SageMaker 告警的 dimension 對得上指標 |
| Client VPN | mutual TLS 連線、授權只到 data subnet；連線 log 用 CMK 能寫入 |
| flow log 與 state | 用 CMK 加密的 flow log bucket 收得到 flow log；`.tfbackend` 的 `kms_key_id` 與 bucket policy 下 `init`、`plan`、lock 檔寫入都正常 |
