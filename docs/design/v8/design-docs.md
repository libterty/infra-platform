# infra-platform v8 設計文件：IoT Edge AI module 與 templates/example5

> 狀態：使用者同意開始實作（2026-10-25），實作流程見 [`implement-process.md`](./implement-process.md)。§3.1 的 D1–D9 是使用者拍板的決策；§3.2 的 K 是照慣例的判斷，審閱時可以推翻。標「審閱重點」的是需要特別看的取捨。
> 範圍：新增 IoT Edge AI 用的 module（IoT Core fleet 與規則、Greengrass v2 元件與部署、IoT Jobs、OTA 簽章、Device Defender 稽核、ACM Private CA、SiteWise、Kinesis Video Streams、SageMaker 模型註冊／訓練 pipeline／雲端推論、SQS、EventBridge rule、EventBridge Scheduler），照 `templates/project-infra` 的標準新建獨立範本 `templates/example5`。不改 example2、example3、example4、project-infra 與既有 module。
> 文中路徑除非特別註明，都是 repo 內相對路徑。example5 的路徑都在 `templates/example5/infra/terraform/` 底下，下文省略這段前綴。
> provider schema、AWS 行為與價格是 2026-10-25 查證的結果，怎麼查與來源列在 §13。標「未確認」的要在實作或真實環境驗證。環境只有 `dev`、`sit`。

## 1. 結論

- **新 module 17 個**，每個發 0.1.0、在 HCP 登記。repo 的 module 從 56 個變成 73 個。
  - 必要（8）：`iot-fleet`、`iot-topic-rule`、`iot-account-settings`、`greengrass-component`、`greengrass-deployment`、`sagemaker-model-registry`、`ota-signing`、`sqs-queue`。
  - 選配（9）：`iot-job-template`、`sagemaker-endpoint`、`sagemaker-pipeline`、`iot-device-defender`、`kinesis-video-stream`、`acm-pca`、`eventbridge-rule`、`scheduler-schedule`、`iotsitewise`。
  - `timeseries-db` 不做：時序資料用既有的 `opensearch-domain`（2026-10-25 已決定）。另外 Timestream for LiveAnalytics 從 2025-06-20 起不開放新客戶（§2 第 9 點）。
- **第一次用 awscc provider**：aws provider 6.70.0 沒有 Greengrass v2、IoT Job template、Device Defender、SiteWise 的 resource，這 5 個 module 用 awscc 1.107.0，其他 12 個用 aws（§5 表）。`mock_provider "awscc"` 在 `terraform test` 的 plan 與 mock apply 都能跑（§2 第 1 點，實測）。
- **`validate.sh` 的 S4、S8 擴充到 `awscc_` 前綴**：目前只掃 `aws_`，module 寫 `awscc_iam_role` 或 stack 直接寫 `awscc_*` 都不會被擋（§2 第 2 點）。這是 v8 第一個 Phase 的內容。
- **資料路徑**：裝置 MQTT → IoT rule → Kinesis Data Streams → Firehose 兩條：S3 raw（GZIP JSON）與 VPC 內的 OpenSearch（冷熱跟 example4 一樣）。IoT rule 的 OpenSearch action 送不進 VPC 內的 domain（§2 第 7 點），所以中間經 Kinesis 與 Firehose。規則失敗送 SQS。
- **邊緣推論**：模型在 SageMaker Pipeline 訓練、註冊到 Model Registry；人工核准後 EventBridge 把事件送進 SQS，CI 消費、把模型（ONNX）打包成 Greengrass 元件的 artifact 上傳 S3，並開 PR 加元件 recipe、改部署版本；`edge` stack apply 後 Greengrass 部署到 thing group。邊緣只回傳推論結果時走同一條 MQTT 路徑。
- **雲端推論**：`sagemaker-endpoint` 從核准的 model package 建 endpoint（real-time 或 serverless），blue/green 加告警自動 rollback。`inference` stack 預設零資源，有核准的模型才填 ARN。
- **影像**：tfvars `cameras` 有值時才建 Kinesis Video Streams 與 Greengrass 的 KVS edge connector 部署。edge connector 的設定存在 SiteWise asset 裡、而且不能部署到 thing group（§2 第 6 點），所以每台 core device 一個 thing 層級的部署，SiteWise asset 由 `iotsitewise` 建。
- **OTA**：Greengrass 裝置靠 `greengrass-deployment` 換元件版本；非 Greengrass 裝置（MCU、FreeRTOS）用 IoT Jobs，job template 由 Terraform 管，每次發布的 job 是執行期操作，不進 Terraform（K7）。韌體用 AWS Signer 簽章（`ota-signing`）。
- **裝置憑證**：fleet provisioning by claim，由 AWS IoT 簽發裝置憑證。`acm-pca` module 照做，example5 的 `pki` stack 預設零資源（D4）。
- **Device Defender 只做稽核**：Detect（security profile）從 2026-08-31 起不開放新客戶（§2 第 8 點），`iot-device-defender` 只做 audit 設定、排程稽核與 mitigation action。
- **帳號層設定**（IoT fleet indexing、logging、event configuration、Device Defender audit 設定）每個帳號加 region 一份，照 v7 `glue-catalog-encryption` 的做法：選填物件，`null` 就不建，同帳號的第二個專案要設 `null`（K9）。
- **example5**：15 個 stack，ORDER `foundation network vpn pki storage iam-base search search-config fleet iam-app ingest sitewise edge ml inference`。`vpn`、`pki`、`inference` 預設零資源。
- **成本**：OpenSearch 冷熱每個環境約 1,052 美元／月，佔大部分。example5 預設（100 台裝置）每個環境約 1,160–1,180 美元／月，兩個環境合計約 2,320–2,350，另加訓練費（§10）。
- **Phase**：H0 文件；H1 驗證規則與通用 module；H2–H6 IoT 與 ML module；H7–H13 範本（§12）。
- **不碰 AWS**：只跑 [`scripts/validate.sh`](../../../scripts/validate.sh)。

## 2. 查證發現

1. **`mock_provider "awscc"` 可以用**：在 repo 外的暫存目錄用 awscc 1.107.0 寫 `awscc_greengrassv2_component_version`、`awscc_greengrassv2_deployment`（nested `components` map、`deployment_policies`）、`awscc_iot_job_template`，`terraform test` 的 `command = plan` 斷言 nested attribute、mock apply 斷言 computed `arn`，兩個 run 都通過（Terraform 1.15.8）。repo 的 `.tflint.hcl` 跑同一個目錄沒有錯誤；aws ruleset 不檢查 awscc resource。
2. **S4、S8 擋不到 awscc**：`validate.sh` 的 S4 比對 `resource "aws_iam_`、`resource "aws_security_group`，S8 只掃 `resource "aws_`。awscc 有 `awscc_iam_role`、`awscc_ec2_security_group` 這類 resource，不擴充的話 module 建 IAM 或 stack 直接宣告 awscc resource 都會通過。
3. **awscc provider 沒有 `default_tags`，也沒有 `allowed_account_ids`**（provider schema 只有 `region`、`assume_role`、`role_arn`、憑證相關設定）。tag 的形狀也不一致：`awscc_greengrassv2_*` 是 `map(string)`，`awscc_iot_*` 是 `set` of `{ key, value }`，`awscc_iotsitewise_*`、`awscc_kinesisvideo_stream` 是 `list` of `{ key, value }`。
4. **aws provider 6.70.0 的缺口**：沒有 Greengrass v2、IoT Job template、Device Defender、SiteWise、IoT software package 的 resource；`aws_iot_topic_rule` 沒有 `opensearch`、`iot_site_wise`、`location` action（只有舊的 `elasticsearch`）。awscc 1.107.0 都有。`aws_iot_topic_rule_destination` 只有 VPC 設定。
5. **Greengrass v2 部署的生命週期**：
   - 每個 target（thing 或 thing group）只有一個部署：「When you create a new deployment for a target that has an existing deployment, you replace the previous deployment.」新部署裡沒有的元件，core device 會解除安裝。
   - `CancelDeployment` 只影響還沒收到的裝置；`DeleteDeployment` 要先 cancel，而且「doesn't affect core devices that run that deployment」，裝置上的元件不會被移除。
   - 裝置被移出 thing group 時（nucleus 2.5.0 以上）會解除安裝該群組部署的元件。
   - `AWS::GreengrassV2::Deployment` 除了 Tags 全部是 create-only：改元件版本、部署政策、rollout 設定都會 replace。CloudFormation 刪除時先 cancel 再 delete，同時最多 10 個部署在刪除中，超過會 throttle。
6. **Greengrass 元件版本**：`InlineRecipe` 是 create-only 也是 write-only；artifact 上傳後不能改，要改就發新版本。刪除還在被部署引用的版本是允許的，但「deployments that refer to this component version will fail」。
7. **IoT rule 的 OpenSearch action 送不進 VPC 內的 domain**：「The OpenSearch (`openSearch`) action cannot be used to deliver data to VPC Elasticsearch clusters」；VPC destination 只用於 Kafka（HTTP 走 VPC destination 未確認）。Firehose 支援 VPC 內的 OpenSearch（v7 已實作）。
8. **Device Defender Detect 不開放新客戶**：「will no longer be available to new customers starting August 31, 2026… The audit feature continues to be fully available」，rules Detect 與 ML Detect 都包含在內。audit 設定是帳號層：`AccountId` 必填，「You can't disable a check if it's used by any scheduled audit」。
9. **停止支援或不開放新客戶的服務**：
   - SageMaker Edge Manager 2024-04-26 停止。AWS 建議「For a cross-platform edge runtime, use ONNX」「For edge deployments and monitoring use AWS IoT Greengrass V2」。
   - IoT Events 2026-05-20 停止支援；IoT Analytics 2025-12-15 停止支援；rule action 清單已經沒有這兩個。
   - Timestream for LiveAnalytics 2025-06-20 起不開放新客戶。
   - SiteWise Monitor（portal）與 SiteWise Edge Data Processing Pack 2025-11-07 起不開放新客戶，進入維護模式，AWS 建議改用 Amazon Managed Grafana；沒有公布停止日期。
   - SageMaker Neo、DLR、TensorFlow Lite 範例元件沒有找到停止公告（未確認）。
10. **KVS edge connector**（`aws.iot.EdgeConnectorForKVS` 1.0.5，Tokyo 有）：設定存在 SiteWise，每台 core device 與每台攝影機各要一個 SiteWise asset；RTSP 網址放在 Secrets Manager；「You can't deploy this component to groups of core devices」；只支援 Linux，依賴 token exchange service 與 stream manager。
11. **core device 的雲端前置**：
    - token exchange role 信任 `credentials.iot.amazonaws.com`，由 IoT role alias 指過去。預設 policy 只有 log 與 `s3:GetBucketLocation`，「This policy doesn't include access to files in S3 buckets」，artifact bucket 要另外給 `s3:GetObject`。
    - core device 的 IoT policy 要有 `iot:Connect`、health／jobs／shadow topic 的 publish／subscribe／receive、對 role alias 的 `iot:AssumeRoleWithCertificate`、`greengrass:GetComponentVersionArtifact`、`ResolveComponentCandidates`、`GetDeploymentConfiguration`、`ListThingGroupsForCoreDevice`。
    - 「Thing policy variables… aren't supported」for core devices；thing group 的 policy 不能授權 Greengrass data plane。
12. **fleet provisioning**：by claim 的 claim 憑證 policy 只能碰 `$aws/certificates/create/*` 與 `$aws/provisioning-templates/<name>/provision/*`；provisioning role 用 `AWSIoTThingsRegistration` 的權限。pre-provisioning hook 是 Lambda，回 `"allowProvisioning": True` 才繼續。by trusted user 是 IAM principal 呼叫 `iot:CreateProvisioningClaim`。
13. **CA 註冊**：`DEFAULT` 模式同 region 只能一個帳號；`SNI_ONLY`「We recommend… You don't need to provide a verification certificate or access to the private key」，裝置要送 SNI。`aws_iot_ca_certificate` 的 `verification_certificate_pem`「Required if `certificate_mode` is `DEFAULT`」。
14. **ACM Private CA 定價**：general-purpose 每個 CA 400 美元／月、short-lived 50 美元／月；憑證 general-purpose 前 1,000 張每張 0.75、short-lived 每張 0.058；每個 region 第一個 CA 有 30 天免費試用。
15. **AWS Signer**：IoT 用的 platform 有 `AWSIoTDeviceManagement-SHA256-ECDSA`、`AmazonFreeRTOS-Default`、`AmazonFreeRTOS-TI-CC3220SF`；「To sign code, you import a third-party code-signing certificate into ACM」。`aws_signer_signing_profile` 的參數改了都會 replace。Signer 搭配 IoT Device Management 不另外收費。Greengrass 元件不用 Signer，靠建立元件時算的 SHA digest 檢查完整性。
16. **IoT Job template**：`AWS::IoT::JobTemplate` 所有屬性（含 Tags、Document）改了都要 replace。
17. **SageMaker**：
    - Model Registry 新版本預設 `PendingManualApproval`，改成 `Approved`「initiates CI/CD deployment」；跨帳號共用靠 resource policy（`aws_sagemaker_model_package_group_policy`）。
    - Serverless inference 還在，記憶體 1–6 GB；不支援 GPU、VPC、network isolation、data capture、多個 production variant、Model Monitor；real-time endpoint 不能轉成 serverless。
    - deployment guardrails：blue/green（all at once、canary、linear）與 rolling，烘烤期間看 CloudWatch 告警自動 rollback；`aws_sagemaker_endpoint.deployment_config` 都有。
    - `aws_sagemaker_endpoint_configuration` 有 `name_prefix`，可以 `create_before_destroy`；`aws_sagemaker_model` 的 container 收 `model_package_name`。
18. **帳號層的 IoT 設定**：logging「applies to all your AWS IoT fleet」；`aws_iot_event_configurations`「Deleting this resource does not disable the event configurations」；fleet indexing 的 API 與 resource 都沒有名稱或 ID（推論每個帳號加 region 一份）。同帳號兩個 stack 都管就會互蓋（推論，AWS 沒有明寫）。
19. **S8 與 Secrets Manager**：stack 只能在 `foundation`、`agent` 宣告 `aws_secretsmanager_secret`。KVS edge connector 的 RTSP secret 若要放進範本，`foundation` 就要知道攝影機清單。
20. **既有 module 的限制**：`lambda-function` 只收 container image（`image_uri`），範本要 Lambda 就要有 ECR repository 與 image 建置流程；`sns-alarm-topic` 沒有讓 AWS 服務 publish 的 topic policy 輸入；`glue-etl` 的 EventBridge rule 寫在 module 裡（v7 K20），沒有通用的 EventBridge module。
21. **範本從 HCP 抓 module**：module 沒發版、HCP 沒登記之前，範本的 init 會失敗（[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)）。

## 3. 決策

### 3.1 使用者拍板（2026-10-25）

| # | 主題 | 決定 | 理由 |
|---|---|---|---|
| D1 | module 範圍 | **使用者選擇**：必要 8 個與選配 9 個全做；`timeseries-db` 不做 | 時序資料用既有 OpenSearch（2026-10-25 已決定） |
| D2 | 範本 | **使用者選擇**：照 v7 新建 `templates/example5` | 範本證明 module 接得起來 |
| D3 | 時序資料 | **使用者選擇**：OpenSearch 完整冷熱，跟 example4 一樣。規劃時建議的是只有 hot | 兩個環境行為一致；每個環境約 1,052 美元／月（§10） |
| D4 | 裝置憑證 | **使用者選擇**：fleet provisioning by claim，由 AWS IoT 簽發；`acm-pca` module 照做，example5 `pki` stack 預設零資源，`envs/examples/` 示範開啟 | 一個 CA 每月 400 美元（§2 第 14 點） |
| D5 | `iot-topic-rule` 的 provider | **使用者選擇**：aws；SiteWise 的資料走 Greengrass 上的 SiteWise gateway，不經 IoT rule | 跟其他 module 一致、tflint 檢查得到；aws 沒有 SiteWise action（§2 第 4 點） |
| D6 | 攝影機情境 | **使用者回答**：三種都要支援：只有感測器；影像不上雲、只在邊緣推論並回傳結果；用 Kinesis Video Streams 上傳影像 | example5 的 `cameras` 預設空，前兩種不需要另外的資源 |
| D7 | 雲端推論 | **使用者回答**：要 `sagemaker-model-registry`（模型來源）、`sagemaker-endpoint`、`sagemaker-pipeline` | |
| D8 | OTA | **使用者回答**：Greengrass 裝置走 `greengrass-deployment`；另外用 IoT Jobs 處理非 Greengrass 裝置 | |
| D9 | 其他選配 | **使用者回答**：`iot-device-defender`、`acm-pca`、EventBridge rule 與 Scheduler、`iotsitewise` 都做 | |

### 3.2 照慣例的判斷（審閱時可以推翻）

| # | 判斷 | 理由 |
|---|---|---|
| K1 | `greengrass-component`、`greengrass-deployment`、`iot-job-template`、`iot-device-defender`、`iotsitewise` 用 awscc，`required_providers` 寫 `awscc = { source = "hashicorp/awscc", version = ">= 1.107, < 2.0" }`；其他 12 個用 aws `>= 6.0, < 7.0`。一個 module 只用一個 provider | aws 沒有對應 resource（§2 第 4 點）；1.107.0 是查證過的版本，沒有往前查最低版本 |
| K2 | H1 先改 `validate.sh`：S4 的 IAM 與 SG 規則加上 `awscc_iam_`、`awscc_ec2_security_group` 前綴；S8 掃 `resource "awscc_`，awscc 一律不在例外清單；`tests/` 加正反案例 | §2 第 2 點；規則沒擴充之前不寫 awscc module |
| K3 | awscc module 收 `tags = map(string)`，在 module 裡轉成各 resource 要的形狀；aws module 照舊。範本呼叫 awscc module 時傳 `merge(local.common_tags, { Stack = "<stack>" })` | awscc 沒有 `default_tags`，tag 形狀不一致（§2 第 3 點） |
| K4 | 用到 awscc module 的 stack，`provider "awscc"` 的 `region` 與 `assume_role` 跟 `provider "aws"` 用同一組變數；stack 測試斷言兩者一致。帳號防呆靠 `provider "aws"` 的 `allowed_account_ids`（stack 一定有 aws，因為要 `ssm-read`） | awscc 沒有 `allowed_account_ids`（§2 第 3 點）；兩個 provider 用同一份憑證設定，aws 擋住就等於 awscc 也在同一個帳號 |
| K5 | awscc 的 lock 要 darwin＋linux 兩個 `h1:`（S10），由使用者在自己的終端機產生 | 同 v7 opensearch provider、v4 E13 |
| K6 | EventBridge 拆成兩個 module：`eventbridge-rule`（`aws_cloudwatch_event_rule`＋target）與 `scheduler-schedule`（`aws_scheduler_schedule`）；`glue-etl` 內建的 rule 不動 | resource 不重疊、用途不同；v7 不改 |
| K7 | 盤點時的 `iot-job` 改名 `iot-job-template`：Terraform 只管 job template（與選填的 software package catalog），每次發布的 job 由 CI 或操作者用 API 建立 | 一次 rollout 一個 job，是執行期操作；template 所有屬性都 replace（§2 第 16 點），放在 Terraform 剛好 |
| K8 | `iot-device-defender` 只做 audit 設定、排程稽核、mitigation action；security profile（Detect）刻意不做，README 寫原因 | Detect 不開放新客戶（§2 第 8 點） |
| K9 | 帳號層設定：`iot-account-settings`（fleet indexing、logging、event configuration）與 `iot-device-defender` 的 `audit`（帳號 audit 設定）都由 `fleet` stack 依選填物件呼叫，`null` 就不建；example5 的 dev、sit tfvars 都給值；README 寫「同帳號的第二個專案要設 `null`」 | 照 v7 D13；`fleet` 在 `iam-base` 之後，logging 與 audit 的 role 已經存在 |
| K10 | **審閱重點**：Greengrass 元件的 recipe 以檔案放在範本 `templates/example5/edge/components/<元件>/<版本>.json`，`edge` stack 用 `fileset` 對每個檔案呼叫 `greengrass-component`；artifact 由 CI 上傳到 `greengrass-artifacts` bucket，Terraform 不上傳物件。部署引用的版本由 tfvars 給，stack 的 precondition 檢查每個自訂元件版本都有對應的 recipe 檔 | 元件版本不可變（§2 第 6 點），一個版本一個檔案剛好對應；precondition 擋住刪掉還在部署的版本（刪了部署會失敗）；同 v7 K10（Glue 腳本由 CI 上傳） |
| K11 | `greengrass-deployment` 一次一個 target；target 是 thing group 或 thing 的 ARN；`failure_handling_policy` 預設 `ROLLBACK`、`component_update_policy` 預設 `NOTIFY_COMPONENTS`；rollout（`maximum_per_minute` 或 exponential）與 abort 條件必填 | 每個 target 只有一個部署（§2 第 5 點）；必填讓 apply 前就要決定失敗時怎麼停 |
| K12 | `aws.greengrass.Nucleus` 的版本在 tfvars 釘住，跟自訂元件一起放在部署的 `components` | 部署會 replace，沒釘住就可能在無關的變更時升級 nucleus |
| K13 | `iotsitewise` 做 asset model、asset、Greengrass v2 gateway；portal（SiteWise Monitor）與 Edge Data Processing Pack 刻意不做 | §2 第 9 點 |
| K14 | 攝影機：tfvars `cameras`（攝影機 id → `{ core_thing_name, rtsp_secret_arn, retention_hours }`）。空 map 就零資源。有值時 `sitewise` 建 edge connector 要的 asset，`edge` 建 KVS stream 與每台 core device 一個 thing 層級的部署。RTSP secret 在 repo 外建，ARN 從 tfvars 給 | §2 第 10、19 點；照 v7 D10 的 secret 做法，`foundation` 不必知道攝影機清單 |
| K15 | IoT rule 不直送 OpenSearch：rule → Kinesis → Firehose → OpenSearch 與 S3 | §2 第 7 點；`firehose-stream` 已支援 VPC 內 domain |
| K16 | **審閱重點**：example5 預設不掛 pre-provisioning hook（`iot-fleet` 支援 `pre_provisioning_hook`，範本傳 `null`）。取捨與補償控制見 §4.1 | `lambda-function` 只收 container image（§2 第 20 點），掛 hook 就要把 ECR 與 image 建置帶進範本 |
| K17 | `ota-signing` 的 code signing 憑證在 repo 外匯入 ACM，ARN 從 tfvars 給；platform 只收 §2 第 15 點的三種；簽章後的韌體放 `ota-artifacts` bucket | 私鑰不經過 Terraform |
| K18 | `acm-pca` 不開 CRL 與 OCSP；註冊到 IoT Core 用 `SNI_ONLY`；裝置憑證撤銷用 IoT registry 把憑證設成 `INACTIVE`／`REVOKED` | CRL 要 bucket policy 讓 ACM PCA 寫入，`s3-bucket` 刻意不做 bucket policy；IoT Core 連線時不查 CRL（未確認，H3 核對）；`SNI_ONLY` 不需要 verification certificate（§2 第 13 點） |
| K19 | `sagemaker-endpoint`：model 只從 model package ARN 建（不收任意 image）；endpoint config 用 `name_prefix`＋`create_before_destroy`；instance variant 必須在 VPC、`enable_network_isolation` 預設 `true`、`deployment_config` 必填（blue/green 加至少一個告警）；serverless variant 不能給 VPC 與 data capture | §2 第 17 點；只部署核准過的模型 |
| K20 | `sagemaker-pipeline` 的 definition 以檔案放在範本 `templates/example5/ml/pipelines/<名稱>.json`（SageMaker Python SDK 匯出後 commit），不從 S3 讀 | 定義跟著 PR 審查；範本附一個最小的訓練 pipeline 範例，沒有在 SageMaker 上跑過 |
| K21 | `inference` stack 預設零資源：`model_package_arn = null` 就不建 endpoint | endpoint 要有核准的模型才能建 |
| K22 | 模型核准流程：`ml` stack 用 `eventbridge-rule` 比對 `SageMaker Model Package State Change`（`ModelApprovalStatus = Approved`、單一 model package group）送進 `model-approved` SQS；CI 消費後打包元件、開 PR（K10）。Terraform 不在 apply 時自動改部署 | 部署的來源維持在 git；Lambda 直接改部署會跟 Terraform 的 state 互相覆蓋 |
| K23 | `sqs-queue` 有 DLQ（redrive）、SSE-KMS 必填；`allowed_source_arns` 產生只允許 `events.amazonaws.com` 且 `aws:SourceArn` 符合的 queue policy；IoT rule 用 role 寫入，不需要 queue policy | EventBridge 的 SQS target 只能靠 queue policy 授權 |
| K24 | `scheduler-schedule`：`ml` stack 用它每週觸發訓練 pipeline（target 是 SageMaker pipeline）；dev 的 `state = "DISABLED"` | 有排程才有重新訓練；dev 不必每週花訓練費 |
| K25 | core device 的 IoT policy 不用 thing policy variable，Resource 用命名規則 `client/${name_prefix}-core-*`；一般裝置的 policy 用 `${iot:Connection.Thing.ThingName}` 限縮到自己的 topic | §2 第 11 點 |
| K26 | `iot-topic-rule`：`sql_version` 寫死 `2016-03-23`；`error_action` 必填；action 只收 `kinesis`、`firehose`、`s3`、`sqs`、`lambda`、`dynamodbv2`、`republish`、`cloudwatch_logs`、`cloudwatch_metric`、`sns` | 2016-03-23 是 AWS 建議版本；`iot_analytics`、`iot_events` 已停止支援；`http`、`kafka`、`elasticsearch` 需要對外網路或 VPC destination，v8 不做 |
| K27 | 新 module 一律 0.1.0、`release-please-config.json` 加 `"initial-version": "0.1.0"`、不先建 `CHANGELOG.md` | v7 §14 |
| K28 | 每個 module 收 `kms_key_arn`，資料類資源必填 CMK；module 自己建的 log group 用同一把 key | 照 v7 K2 |
| K29 | 測試：用到的 provider 各一個 `mock_provider`、`command = plan`、每條 validation 正反各一個 run、至少一個 example；IAM policy 與 IoT policy 用 `jsondecode` 斷言 Resource 沒有 `*`（只能 `*` 的動作寫白名單） | S1 |
| K30 | `search`、`search-config`、`vpn` 從 example4 複製；`vpn` 只留 Client VPN；[`project-infra-standard.md`](../../guides/project-infra-standard.md)〈例外清單〉的 `search-config` 兩列加上 example5 | 兩份範本行為一致；example5 的 `search-config` 同樣用 ephemeral 讀 master 帳密 |
| K31 | `common.tf`、`providers.tf`、`versions.tf` 從 example4 複製；aws 的 lock 從既有 stack 複製；`check-ssm-contract.sh`、`stacks.sh` 從 example4 複製，只改 ORDER | S5、S10；範本操作一致 |
| K32 | 佔位值：帳號 `111111111111`（dev）、`222222222222`（sit）、網段 `10.40.0.0/20`、`10.41.0.0/20`、網域 `example.com` | 跟既有範本一致、網段不重疊 |
| K33 | VPC：`nat_mode = "none"`；gateway endpoint `s3`；interface endpoint 只建 SageMaker runtime（`inference` 有 endpoint 時才用得到，跟著 tfvars） | 成本；邊緣裝置走公網連 IoT Core，不經 VPC |

## 4. trust boundary 與特權操作

| 邊界 | 誰 → 誰 | 控制 |
|---|---|---|
| 裝置連線 | 裝置 → IoT Core（MQTT over TLS） | X.509 裝置憑證；一般裝置的 policy 只能用自己的 client id、publish／subscribe 自己的 topic（`${iot:Connection.Thing.ThingName}`）；core device policy 用命名規則（K25） |
| 裝置開通 | 出廠裝置 → fleet provisioning | claim 憑證只能碰兩組 provisioning topic；provisioning role 只能建 thing、憑證、把 thing 加進指定群組；hook 的取捨見 §4.1 |
| 裝置取得 AWS 憑證 | core device → token exchange service | role alias 指向 TES role；TES role 只能讀 `greengrass-artifacts` 的 `artifacts/` 前綴、寫自己的 log group、KVS 用命名規則 `stream/${name_prefix}-cam-*`；`credential_duration` 預設 3600 秒 |
| 規則 | IoT rule → Kinesis、SQS | rule role 只能 `kinesis:PutRecord(s)` 到單一 stream、`sqs:SendMessage` 到錯誤 queue；trust 帶 `aws:SourceAccount` 與 `aws:SourceArn` |
| 管線 | Firehose → S3、OpenSearch | 同 v7 §4 |
| 部署 | Terraform → Greengrass 部署 → 裝置 | 只有 `edge` stack 改部署；元件 artifact 只有 CI 能寫；部署必帶 abort 條件與 `ROLLBACK`（K11） |
| OTA（非 Greengrass） | CI → Signer → `ota-artifacts` → IoT Job → 裝置 | 韌體由 Signer 簽章、裝置驗簽；presigned URL 的 role 只能讀 `ota-artifacts` 的 `signed/` 前綴；job 用 template 的 abort、timeout、rollout 設定 |
| 模型 | SageMaker Pipeline → Model Registry → 人工核准 → SQS → CI | pipeline role 只能寫 `ml-artifacts`、註冊到單一 model package group；核准是人的動作；EventBridge 只能 `SendMessage` 到單一 queue（queue policy 帶 `aws:SourceArn`） |
| 雲端推論 | 呼叫端 → SageMaker endpoint | instance variant 在 VPC、network isolation；呼叫端要 `sagemaker:InvokeEndpoint` 到單一 endpoint（呼叫端的 role 不在範本） |
| 人 → OpenSearch、VPC | 同 v7 §4 | 同 v7 §4.1 的例外與補償控制（K30） |

執行 apply 的身分需要的特權操作（README 要列）：`iam:CreateServiceLinkedRole`（OpenSearch、Client VPN、SageMaker、IoT 第一次建立時）、`iam:PassRole`（IoT rule、provisioning、logging、audit、Firehose、SageMaker、Scheduler、IoT Job presigned URL 的 role）、`kms:CreateGrant`（Firehose、SageMaker、KVS 的 CMK）、`secretsmanager:GetSecretValue`（OpenSearch master secret：`search`、`search-config`）、`iot:SetV2LoggingOptions`、`iot:UpdateIndexingConfiguration`、`iot:UpdateEventConfigurations`、`iot:UpdateAccountAuditConfiguration`（`fleet`）、`acm-pca:*`（`pki` 開啟時）、awscc 透過 Cloud Control API 建立資源要的 `cloudformation:*Resource*` 動作（實作時核對清單）。

### 4.1 安全取捨：fleet provisioning 不掛 pre-provisioning hook（K16，審閱重點）

| 項目 | 內容 |
|---|---|
| 取捨 | example5 預設用 claim 憑證開通，沒有 Lambda hook 檢查裝置序號 |
| 風險 | claim 憑證外洩的人可以開通任意數量的裝置，拿到正式的裝置憑證與裝置 policy 的權限 |
| 影響範圍 | 每個環境一組 claim 憑證；開通出來的裝置只能用自己的 topic（K25），碰不到其他裝置的資料、拿不到 AWS 憑證（一般裝置不是 core device，沒有 role alias 權限） |
| 補償控制 | 1. claim 憑證在 Terraform 外用 CSR 建立（`create-certificate-from-csr`），私鑰不經過 Terraform；2. claim policy 只有兩組 provisioning topic；3. provisioning template 要求 `SerialNumber` 參數符合格式、thing 名稱用序號組出（同序號第二次開通會失敗）；4. 開通出來的裝置先進 `unverified` thing group，人工或 CI 確認後再搬進正式群組（Greengrass 部署只對正式群組）；5. 每批生產結束就把 claim 憑證設成 `INACTIVE`；6. Device Defender audit 開、IoT logging 開 |
| 移除取捨的 checkpoint | 1. 範本有 Lambda image 建置流程時（或 `lambda-function` 支援 zip）：掛 hook 查 DynamoDB 的序號白名單；2. 改用 by trusted user 或 `acm-pca` 加 JITP；3. 最晚 2027-04-25 重新審查 |
| 記錄在哪裡 | 這一節、example5 REFERENCE〈安全取捨〉、`iot-fleet` README〈注意〉 |

### 4.2 沿用 v7 的例外

OpenSearch master 帳密進 `search` stack 的 state（v7 §4.1）與 state bucket 的強化（v7 §4.2）原樣適用到 example5，checkpoint 一起審查。

## 5. module 清單

共同慣例：`name`、`tags`（`Name` 由 module 加）、`kms_key_arn`、中文 description、README 有〈注意〉〈刻意不做〉與 terraform-docs marker。

| module | provider | 必要／選配 | 用在哪個 stack |
|---|---|---|---|
| `iot-fleet` | aws | 必要 | `fleet` |
| `iot-topic-rule` | aws | 必要 | `ingest` |
| `iot-account-settings` | aws | 必要 | `fleet` |
| `greengrass-component` | awscc | 必要 | `edge` |
| `greengrass-deployment` | awscc | 必要 | `edge` |
| `sagemaker-model-registry` | aws | 必要 | `ml` |
| `ota-signing` | aws | 必要 | `fleet` |
| `sqs-queue` | aws | 必要 | `storage` |
| `iot-job-template` | awscc | 選配 | `fleet` |
| `sagemaker-endpoint` | aws | 選配 | `inference` |
| `sagemaker-pipeline` | aws | 選配 | `ml` |
| `iot-device-defender` | awscc | 選配 | `fleet` |
| `kinesis-video-stream` | aws | 選配 | `edge` |
| `acm-pca` | aws | 選配 | `pki` |
| `eventbridge-rule` | aws | 選配 | `ml` |
| `scheduler-schedule` | aws | 選配 | `ml` |
| `iotsitewise` | awscc | 選配 | `sitewise` |

### 5.1 `iot-fleet`

- 責任：一個裝置群的 IoT Core 設定：thing type、thing group 階層、IoT policy、role alias、fleet provisioning template、選填的 CA 註冊。
- resource：`aws_iot_thing_type`、`aws_iot_thing_group`、`aws_iot_policy`、`aws_iot_role_alias`、`aws_iot_provisioning_template`、`aws_iot_ca_certificate`。
- 輸入：`thing_types`（名稱 → `{ description, searchable_attributes }`）；`thing_groups`（名稱 → `{ parent, description, attributes }`）；`policies`（名稱 → policy 文件物件，module `jsonencode`）；`role_alias = { alias, role_arn, credential_duration }`；`provisioning_template = { template_body, provisioning_role_arn, enabled, pre_provisioning_hook = { target_arn } }`；`ca_certificate = { pem, mode = "SNI_ONLY", allow_auto_registration, registration_template }`。
- validation：thing group 的 parent 要在同一個 map 裡、不成環；policy 不准 `iot:*` 搭 Resource `*`；`credential_duration` 900–43200；role ARN 格式；`ca_certificate.mode` 只能 `SNI_ONLY`、`DEFAULT`，`DEFAULT` 時要有 verification certificate（module 不收，所以等於只准 `SNI_ONLY`）。
- 輸出：`thing_group_arns`、`thing_type_arns`、`policy_names`、`role_alias_arn`、`provisioning_template_name`、`ca_certificate_id`。
- 刻意不做：建 thing、建憑證（`aws_iot_certificate` 不給 CSR 時私鑰會進 state）、custom authorizer、domain configuration、billing group。

### 5.2 `iot-topic-rule`

- 責任：一組 IoT rule 與共用的 error action。
- resource：`aws_iot_topic_rule`。
- 輸入：`rules`（名稱 → `{ sql, description, enabled, actions = { kinesis, firehose, s3, sqs, lambda, dynamodbv2, republish, cloudwatch_logs, cloudwatch_metric, sns } }`，每種 action 是 list）；`error_action`（必填，同樣的 action 種類擇一）。
- 固定：`sql_version = "2016-03-23"`。
- validation：每條 rule 至少一個 action；`error_action` 剛好一個 action；rule 名稱只能英數與底線；SQL 以 `SELECT` 開頭；role ARN 格式；Lambda ARN 格式。
- 輸出：`rule_arns`、`rule_names`。
- 刻意不做：`http`、`kafka`、`elasticsearch`、`iot_analytics`、`iot_events`、`timestream`、`step_functions`、topic rule destination（K26）。Lambda 的 invoke permission 不在這裡（`lambda-function` 的 `permissions`）。

### 5.3 `iot-account-settings`（帳號層）

- 責任：每個帳號加 region 一份的 IoT 設定。
- resource：`aws_iot_indexing_configuration`、`aws_iot_logging_options`、`aws_iot_event_configurations`。
- 輸入：`indexing = { thing_indexing_mode, thing_connectivity_indexing_mode, named_shadow_indexing_mode, device_defender_indexing_mode, thing_group_indexing_mode, custom_fields }`（null 就不建）；`logging = { role_arn, default_log_level }`（預設 `WARN`）；`event_configurations`（事件 → bool，null 就不建）。
- validation：log level 限 `DEBUG`、`INFO`、`WARN`、`ERROR`、`DISABLED`；indexing mode 的值；`device_defender_indexing_mode = "VIOLATIONS"` 要搭 `thing_indexing_mode` 不是 `OFF`。
- 輸出：無（帳號層設定，沒有 ARN）。
- 注意：README 照 `xray-transaction-search` 寫「每個帳號、每個 region 只能由一處呼叫」；刪掉 `event_configurations` 不會關掉事件（§2 第 18 點）。
- 刻意不做：resource-specific logging、IoT Core 的 CMK 加密設定（`awscc_iot_encryption_configuration`，帳號層而且會影響同帳號所有裝置，要另外評估）。

### 5.4 `greengrass-component`

- 責任：一個 Greengrass 元件版本。
- resource：`awscc_greengrassv2_component_version`。
- 輸入：`recipe`（物件，module `jsonencode`；或 `recipe_json` 字串，兩者擇一）；`artifact_bucket_name`（recipe 裡的 artifact URI 只能在這個 bucket）；`tags`。
- validation：`ComponentName`、`ComponentVersion` 必填，版本是 semver；`RecipeFormatVersion = "2020-01-25"`；所有 artifact `Uri` 以 `s3://<artifact_bucket_name>/` 開頭；不准 `Lambda` 型元件（只收 inline recipe）。
- 輸出：`arn`、`component_name`、`component_version`。
- 注意：recipe 改了就是 replace（刪舊版本、建同版號）；刪掉還在部署的版本會讓部署失敗（§2 第 6 點）。範本靠 K10 的 precondition 擋。
- 刻意不做：Lambda 元件、上傳 artifact、公開元件。

### 5.5 `greengrass-deployment`

- 責任：對一個 target 的 Greengrass 部署。
- resource：`awscc_greengrassv2_deployment`。
- 輸入：`target_arn`（thing group 或 thing）；`components`（元件名稱 → `{ version, merge = object, reset = list(string), run_with = { posix_user } }`，module 把 `merge` `jsonencode`）；`failure_handling`（預設 `ROLLBACK`）；`component_update = { action = "NOTIFY_COMPONENTS", timeout_seconds = 60 }`；`configuration_validation_timeout_seconds`；`rollout`（必填，`maximum_per_minute` 或 `exponential = { base_rate_per_minute, increment_factor, number_of_succeeded_things }`）；`abort`（必填，list of `{ failure_type, action = "CANCEL", threshold_percentage, min_number_of_executed_things }`）；`in_progress_timeout_minutes`；`tags`。
- validation：target ARN 是 `thinggroup/` 或 `thing/`；至少一個元件；版本 semver；rollout 二擇一；abort 的百分比 0–100。
- 輸出：`deployment_id`。
- 注意：每次變更都是 replace（§2 第 5 點）；從 `components` 拿掉的元件會在裝置上解除安裝；刪掉這個 resource 不會移除裝置上的元件。
- 刻意不做：`parent_target_arn`（子部署）、Windows user。

### 5.6 `sagemaker-model-registry`

- resource：`aws_sagemaker_model_package_group`、`aws_sagemaker_model_package_group_policy`（選填）。
- 輸入：`description`；`cross_account_read_principals`（帳號 ID 或 role ARN 清單，產生唯讀的 resource policy；空就不建）。
- validation：principal 格式、不含 `*`。
- 輸出：`arn`、`name`。
- 刻意不做：model package 本身（由 pipeline 註冊）、核准（人的動作）、model card。

### 5.7 `ota-signing`

- resource：`aws_signer_signing_profile`、`aws_signer_signing_profile_permission`（選填）。
- 輸入：`platform_id`（三種之一，§2 第 15 點）；`certificate_arn`（ACM 匯入的 code signing 憑證，FreeRTOS platform 必填）；`signature_validity_days`（預設 365）；`signing_parameters`（例如 `certname`）；`start_job_principals`（可以開簽章 job 的 role ARN）。
- validation：platform 白名單；FreeRTOS platform 沒給 `certificate_arn` 就擋；ACM ARN 格式；有效天數 1–1095（上限未確認）。
- 輸出：`profile_name`、`profile_arn`、`profile_version_arn`。
- 注意：參數改了就 replace（§2 第 15 點），裝置端信任的是憑證，換 profile 不影響已簽的韌體。
- 刻意不做：簽章 job、Lambda／container image 簽章 platform。

### 5.8 `sqs-queue`

- resource：`aws_sqs_queue`（主 queue 與 DLQ）、`aws_sqs_queue_redrive_policy`、`aws_sqs_queue_redrive_allow_policy`、`aws_sqs_queue_policy`（選填）。
- 輸入：`fifo`（預設 `false`）；`visibility_timeout_seconds`；`message_retention_seconds`；`max_receive_count`（預設 5）；`dlq_retention_seconds`（預設 14 天）；`kms_key_arn`（必填）；`allowed_source_arns`（EventBridge rule ARN 清單）。
- validation：保留時間 60–1209600；`max_receive_count` 1–1000；source ARN 是 `arn:aws:events:`。
- 輸出：`queue_arn`、`queue_url`、`queue_name`、`dlq_arn`。
- 刻意不做：SNS 訂閱、跨帳號 policy、SQS 管理的 SSE（一律 CMK）。

### 5.9 `iot-job-template`

- resource：`awscc_iot_job_template`。
- 輸入：`job_template_id`；`description`；`document`（物件）或 `document_source`（`s3://` 網址）擇一；`presigned_url = { role_arn, expires_in_sec }`；`rollout`、`abort`、`timeout_minutes`、`retry`（list of `{ failure_type, number_of_retries }`）；`maintenance_windows`；`tags`。
- validation：document 二擇一；`expires_in_sec` 60–3600；retry 次數 0–10；abort 百分比。
- 輸出：`arn`、`job_template_id`。
- 注意：所有屬性改了都 replace（§2 第 16 點）；template 被 replace 不影響已經建立的 job。
- 刻意不做：job 本身（K7）、software package catalog（盤點時列入，範本用 S3 路徑就夠，有需要再加）。

### 5.10 `sagemaker-endpoint`

- resource：`aws_sagemaker_model`、`aws_sagemaker_endpoint_configuration`、`aws_sagemaker_endpoint`。
- 輸入：`model_package_arn`（必填，核准過的版本）；`execution_role_arn`；`variant`（`instance = { instance_type, initial_instance_count }` 或 `serverless = { memory_size_in_mb, max_concurrency, provisioned_concurrency }` 擇一）；`vpc = { subnet_ids, security_group_ids }`；`enable_network_isolation`（預設 `true`）；`data_capture = { destination_s3_uri, sampling_percentage }`；`deployment`（`blue_green = { traffic = "ALL_AT_ONCE" | "CANARY" | "LINEAR", ... }` 或 `rolling`，加 `rollback_alarm_names`）；`kms_key_arn`。
- validation：variant 二擇一；instance 要有 `vpc` 與 `deployment`、至少一個告警；serverless 不能給 `vpc`、`data_capture`、`enable_network_isolation = true`；記憶體 1024–6144 且是 1024 的倍數；instance type 以 `ml.` 開頭；model package ARN 格式（含版本）。
- 輸出：`endpoint_name`、`endpoint_arn`。
- 刻意不做：多個 variant、shadow variant、async inference、autoscaling（之後用 Application Auto Scaling 另外做）、任意 image。

### 5.11 `sagemaker-pipeline`

- resource：`aws_sagemaker_pipeline`。
- 輸入：`definition`（JSON 字串，範本用 `file()` 讀）；`role_arn`；`display_name`；`description`；`max_parallel_steps`。
- validation：definition 是合法 JSON 且有 `Version`、`Steps`；role ARN 格式。
- 輸出：`pipeline_arn`、`pipeline_name`。
- 刻意不做：從 S3 讀 definition（K20）、執行 pipeline（交給 `scheduler-schedule` 或人）。

### 5.12 `iot-device-defender`

- resource：`awscc_iot_account_audit_configuration`（選填）、`awscc_iot_scheduled_audit`、`awscc_iot_mitigation_action`。
- 輸入：`audit = { role_arn, checks = list(string), sns = { target_arn, role_arn } }`（null 就不建，帳號層，K9）；`scheduled_audits`（名稱 → `{ frequency, day_of_week, day_of_month, checks }`）；`mitigation_actions`（名稱 → `{ role_arn, add_things_to_thing_group | update_device_certificate | publish_finding_to_sns | enable_iot_logging }`）；`tags`。
- validation：frequency 是 `DAILY`、`WEEKLY`、`BIWEEKLY`、`MONTHLY`，搭配的 day 欄位；排程稽核用到的 check 都要在 `audit.checks` 裡（AWS 不准停用排程在用的 check）；mitigation action 剛好一種；ARN 格式。
- 輸出：`scheduled_audit_arns`、`mitigation_action_arns`。
- 刻意不做：security profile（K8）、custom metric、dimension。

### 5.13 `kinesis-video-stream`

- resource：`aws_kinesis_video_stream`。
- 輸入：`streams`（名稱 → `{ retention_hours, media_type, device_name }`）；`kms_key_arn`（必填）。
- validation：保留 0–87600 小時；名稱格式。
- 輸出：`stream_arns`、`stream_names`。
- 刻意不做：signaling channel（WebRTC）、儲存分層（`awscc_kinesisvideo_stream` 才有，需要時再評估）。

### 5.14 `acm-pca`

- resource：`aws_acmpca_certificate_authority`、`aws_acmpca_certificate`（root 自簽）、`aws_acmpca_certificate_authority_certificate`。
- 輸入：`type`（`ROOT` 或 `SUBORDINATE`；`SUBORDINATE` 要給上層 CA 簽好的憑證，module 只產生 CSR 並輸出）；`usage_mode`（`GENERAL_PURPOSE` 或 `SHORT_LIVED_CERTIFICATE`）；`key_algorithm`（預設 `EC_prime256v1`）；`subject`；`validity_years`；`permanent_deletion_time_in_days`（預設 30）。
- 固定：不開 CRL、OCSP（K18）。
- validation：algorithm 白名單、不准 RSA 2048 以下；`SUBORDINATE` 時沒給上層憑證就只輸出 CSR；保留天數 7–30。
- 輸出：`ca_arn`、`ca_certificate_pem`、`csr`。
- 刻意不做：CRL、OCSP、`aws_acmpca_permission`、跨帳號 RAM 共用、發裝置憑證。

### 5.15 `eventbridge-rule`

- resource：`aws_cloudwatch_event_rule`、`aws_cloudwatch_event_target`。
- 輸入：`event_bus_name`（預設 `default`）；`event_pattern`（物件，module `jsonencode`）或 `schedule_expression` 擇一；`targets`（id → `{ arn, role_arn, input_transformer, dead_letter_arn, retry = { maximum_event_age_seconds, maximum_retry_attempts }, sqs_message_group_id }`）；`state`。
- validation：pattern 與 schedule 二擇一；至少一個 target，最多 5 個；SQS、SNS、Lambda 以外的 target 要有 `role_arn`；retry 範圍。
- 輸出：`rule_arn`、`rule_name`。
- 刻意不做：自訂 event bus、archive、API destination、跨帳號 target。

### 5.16 `scheduler-schedule`

- resource：`aws_scheduler_schedule`、`aws_scheduler_schedule_group`（選填）。
- 輸入：`schedules`（名稱 → `{ expression, timezone = "Asia/Taipei", state, flexible_window_minutes, target = { arn, role_arn, input, sagemaker_pipeline_parameters, dead_letter_arn, retry } }`）；`group_name`；`kms_key_arn`。
- validation：expression 以 `cron(`、`rate(`、`at(` 開頭；`flexible_window_minutes` 1–1440 或 null（`OFF`）；role ARN 必填。
- 輸出：`schedule_arns`。
- 刻意不做：ECS 等其他特定 target 的參數（需要時再加）、一次性排程後自動刪除。

### 5.17 `iotsitewise`

- resource：`awscc_iotsitewise_asset_model`、`awscc_iotsitewise_asset`、`awscc_iotsitewise_gateway`。
- 輸入：`asset_models`（名稱 → `{ description, properties, hierarchies }`）；`assets`（名稱 → `{ model, parent, properties }`）；`gateways`（名稱 → `{ core_device_thing_name }`）；`tags`。
- validation：asset 引用的 model 與 parent 要在同一個 module 呼叫裡；property 的 `data_type`、`type`（`attribute`、`measurement`、`transform`、`metric`）；gateway 的 thing 名稱格式。
- 輸出：`asset_model_ids`、`asset_ids`、`gateway_ids`。
- 注意：KVS edge connector 要的 asset model 結構照 AWS 文件（§2 第 10 點），H5 實作時核對欄位。
- 刻意不做：portal、dashboard、project、access policy（SiteWise Monitor 不開放新客戶）、資料處理 pipeline、Siemens IE gateway。

## 6. 既有 module

v8 不改既有 module。example5 用到的既有 module：`kms-key`、`sns-alarm-topic`、`s3-bucket`、`vpc`、`security-group`、`vpc-interface-endpoints`、`client-vpn`、`iam-role`、`iam-role-policy`、`kinesis-stream`、`firehose-stream`、`opensearch-domain`、`opensearch-config`、`metric-alarm`、`ssm-publish`、`ssm-read`。

## 7. example5 的 stack

### 7.1 stack 清單與 ORDER

| 順序 | stack | 放什麼 | 擁有者 | 變動頻率 | module |
|---|---|---|---|---|---|
| 1 | `foundation` | CMK、告警 SNS、flow log bucket、OpenSearch master secret 容器 | platform | 低 | `kms-key`、`sns-alarm-topic`、`s3-bucket`；`aws_secretsmanager_secret` |
| 2 | `network` | VPC、endpoint、所有 SG | platform／網路 | 低 | `vpc`、`vpc-interface-endpoints`、`security-group` |
| 3 | `vpn` | Client VPN；預設零資源 | 網路 | 低 | `client-vpn` |
| 4 | `pki` | 自建 CA；預設零資源（D4） | 資安 | 低 | `acm-pca` |
| 5 | `storage` | 遙測 raw、Greengrass artifact、OTA、ML artifact bucket；Kinesis；SQS（rule 錯誤、模型核准）；告警 | IoT 平台 | 低 | `s3-bucket`、`kinesis-stream`、`sqs-queue`、`metric-alarm` |
| 6 | `iam-base` | 之後的資源一建立就要的 role（§8） | platform | 低 | `iam-role` |
| 7 | `search` | OpenSearch domain（冷熱）、告警 | 搜尋／觀測 | 低（apply 慢） | `opensearch-domain`、`metric-alarm` |
| 8 | `search-config` | ISM、FGAC、index template | 搜尋／觀測 | 中 | `opensearch-config` |
| 9 | `fleet` | thing type／group、IoT policy、role alias、provisioning template、帳號層設定、Device Defender、OTA 簽章、job template | IoT 平台 | 中 | `iot-fleet`、`iot-account-settings`、`iot-device-defender`、`ota-signing`、`iot-job-template` |
| 10 | `iam-app` | 要具體 ARN 的 policy（§8） | platform | 低到中 | `iam-role`、`iam-role-policy` |
| 11 | `ingest` | IoT rule、Firehose 兩條、告警 | 資料工程 | 高 | `iot-topic-rule`、`firehose-stream`、`metric-alarm` |
| 12 | `sitewise` | asset model、asset、gateway | 產線資料 | 中 | `iotsitewise` |
| 13 | `edge` | Greengrass 元件版本與部署、KVS stream | 邊緣應用 | 高 | `greengrass-component`、`greengrass-deployment`、`kinesis-video-stream` |
| 14 | `ml` | Model Registry、訓練 pipeline、每週排程、核准事件 | ML | 中 | `sagemaker-model-registry`、`sagemaker-pipeline`、`scheduler-schedule`、`eventbridge-rule` |
| 15 | `inference` | 雲端推論 endpoint 與 rollback 告警；預設零資源 | ML 服務 | 中 | `sagemaker-endpoint`、`metric-alarm` |

排序的理由：`pki` 在 `fleet` 之前，CA 憑證要先有才能註冊到 IoT；`fleet` 在 `iam-base` 之後，role alias、provisioning、logging、audit、presigned URL 的 role 都要先存在；`iam-app` 在 `search` 之後（Firehose 的 policy 要 domain ARN）；`ingest` 在 `iam-app` 之後（Firehose 建立時驗證 role）；`sitewise` 在 `edge` 之前，edge connector 的 asset 要先在；`ml` 的 model package group 在 `inference` 之前。`edge` 用到 awscc，`sitewise`、`fleet` 也是（K4、K5）。

### 7.2 SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../adr/0003-cross-stack-values-via-ssm-only.md)）。

| stack | key（Type） |
|---|---|
| `foundation` | `kms_key_arn`、`alarm_topic_arn`、`flow_log_bucket_arn`、`opensearch_master_secret_arn`（String） |
| `network` | `vpc_id`、`vpc_cidr`（String）；`azs`、`subnet_ids_app`、`subnet_ids_data`、`subnet_cidrs_data`（StringList）；`sg_opensearch_id`、`sg_firehose_id`、`sg_sagemaker_id`、`sg_client_vpn_id`、`sg_search_admin_id`（String） |
| `vpn` | `client_vpn`（String，JSON；關閉時 `{"enabled":false}`） |
| `pki` | `ca`（String，JSON；關閉時 `{"enabled":false}`，開啟時含 `arn`、`certificate_pem`） |
| `storage` | `telemetry_bucket_arn`、`greengrass_artifacts_bucket_arn`、`greengrass_artifacts_bucket_name`、`ota_bucket_arn`、`ml_bucket_arn`、`ml_bucket_name`、`stream_arn`、`rule_errors_queue_arn`、`rule_errors_queue_url`、`model_approved_queue_arn`（String） |
| `iam-base` | `role_iot_rule_arn`、`role_iot_provisioning_arn`、`role_iot_logging_arn`、`role_iot_audit_arn`、`role_iot_mitigation_arn`、`role_greengrass_tes_arn`、`role_ota_presign_arn`、`role_firehose_arn`、`role_firehose_name`、`role_sagemaker_pipeline_arn`、`role_sagemaker_endpoint_arn`、`role_scheduler_arn`（String） |
| `search` | `opensearch_domain_arn`、`opensearch_domain_name`、`opensearch_endpoint`（String） |
| `search-config` | `firehose_writer_role`（String）；`ism_policy_ids`（StringList） |
| `fleet` | `thing_group_fleet_arn`、`thing_group_unverified_arn`、`thing_group_core_arn`、`role_alias_arn`、`provisioning_template_name`、`ota_signing_profile_name`、`ota_job_template_arn`（String） |
| `iam-app` | 無（只附加 policy） |
| `ingest` | `firehose_s3_arn`、`firehose_opensearch_arn`（String）；`rule_names`（StringList） |
| `sitewise` | `edge_connector_asset_ids`（String，JSON：攝影機 id → asset id；空時 `{}`） |
| `edge` | `deployment_ids`（StringList）；`kvs_stream_arns`（String，JSON） |
| `ml` | `model_package_group_arn`、`model_package_group_name`、`pipeline_name`（String） |
| `inference` | `endpoint`（String，JSON；沒有 endpoint 時 `{"enabled":false}`） |

### 7.3 Greengrass 元件與部署（K10–K12）

```
templates/example5/edge/components/
  com.example.Inference/
    1.0.0.json        # recipe；artifact 指到 s3://<greengrass-artifacts>/artifacts/com.example.Inference/1.0.0/
```

- `edge` stack：`for_each = fileset("${path.module}/../../../edge/components", "*/*.json")`，key 是 `<元件>/<版本>`，每個檔案呼叫一次 `greengrass-component`。
- tfvars：`deployments`（名稱 → `{ thing_group = "fleet" | "core", components = { 元件 → 版本 }, rollout, abort }`），`aws.greengrass.Nucleus` 與公開元件（例如 `aws.greengrass.StreamManager`）也列在 `components`。
- precondition：`deployments` 裡不是 `aws.greengrass.` 開頭的元件版本，都要在 recipe 檔的 key 裡。刪掉還在部署的版本，plan 就失敗。
- 攝影機（K14）：`cameras` 不空時，每個 `core_thing_name` 一個 thing 層級的部署，元件是 `aws.iot.EdgeConnectorForKVS`，設定從 `sitewise` 的 SSM 讀 asset id。
- 範本附的 `com.example.Inference` 是最小的範例：從 MQTT 收感測器資料、用 ONNX Runtime 跑模型、把結果 publish 到 `${name_prefix}/inference/<thing>`。沒有在裝置上跑過。

### 7.4 模型的路徑（K22）

1. `scheduler-schedule` 每週觸發 SageMaker pipeline（dev 預設 `DISABLED`）。
2. pipeline 訓練、評估，把模型以 `PendingManualApproval` 註冊到 model package group。
3. 人在 SageMaker Studio 或 CLI 核准。
4. `eventbridge-rule` 比對 `{"source":["aws.sagemaker"],"detail-type":["SageMaker Model Package State Change"],"detail":{"ModelPackageGroupName":["<group>"],"ModelApprovalStatus":["Approved"]}}`，送進 `model-approved` queue。
5. CI 消費 queue：把模型轉成 ONNX、上傳 artifact、產生新版本的 recipe 檔、開 PR 改 `deployments` 的版本；雲端推論的話開 PR 改 `inference` 的 `model_package_arn`。
6. PR 合併後 apply `edge`（或 `inference`）。

CI 的部分（第 5 點）在範本外，README 寫流程與 queue 的訊息格式。

### 7.5 dev／sit 的預設規格

| 項目 | dev | sit |
|---|---|---|
| OpenSearch | 同 example4 | 同 example4 |
| ISM（累計年齡） | 3／7／30 天 | 7／30／90 天 |
| Kinesis | provisioned 1 shard | provisioned 1 shard |
| 訓練排程 | `DISABLED` | 每週一次 |
| `inference` | 零資源 | 零資源 |
| `cameras` | `{}` | `{}` |
| `pki`、`vpn` | 關 | 關 |
| IoT logging | `WARN` | `WARN` |
| Device Defender 排程稽核 | 每週 | 每週 |
| Greengrass rollout | 每分鐘 10 台、失敗 10% 中止 | 每分鐘 20 台、失敗 5% 中止 |

## 8. IAM：`iam-base` 與 `iam-app`

照 v7 §8：`iam-base` 建之後一建立就要的 role；Resource 要等更晚的 stack 才有的，用命名規則組出單一 ARN（v7 K21）或在 `iam-app` 附加。全部 inline policy，trust 帶 `source_account`。

| role | 建在 | 誰一建立就要它 | policy 在哪 | 權限重點 |
|---|---|---|---|---|
| `iot-rule` | `iam-base`（完整） | `ingest` | `iam-base` | `kinesis:PutRecord(s)` 單一 stream；`sqs:SendMessage` 錯誤 queue；KMS；trust `iot.amazonaws.com` |
| `iot-provisioning` | `iam-base`（完整） | `fleet` 的 provisioning template | `iam-base` | `AWSIoTThingsRegistration` 那組動作，thing group 用命名規則限縮 |
| `iot-logging` | `iam-base`（完整） | `fleet` 的 `iot-account-settings` | `iam-base` | 寫 `AWSIotLogsV2` log group |
| `iot-audit` | `iam-base`（完整） | `fleet` 的 Device Defender | `iam-base` | audit 要的讀取動作（AWS managed policy 的內容，實作時核對）；`sns:Publish` 告警 topic |
| `iot-mitigation` | `iam-base`（完整） | `fleet` 的 mitigation action | `iam-base` | 把 thing 加進 quarantine 群組、更新憑證狀態 |
| `greengrass-tes` | `iam-base`（完整） | `fleet` 的 role alias | `iam-base` | log；`s3:GetObject` `greengrass-artifacts/artifacts/*`；KVS `PutMedia` 等用命名規則 `stream/${name_prefix}-cam-*`；trust `credentials.iot.amazonaws.com` |
| `ota-presign` | `iam-base`（完整） | `fleet` 的 job template | `iam-base` | `s3:GetObject` `ota-artifacts/signed/*` |
| `firehose` | `iam-base`（只有 trust） | `search` 的 access policy | `iam-app` | 同 v7 |
| `sagemaker-pipeline` | `iam-base`（完整） | `ml` | `iam-base` | `ml-artifacts` 讀寫；註冊到命名規則組出的單一 model package group；訓練與處理 job 動作；`iam:PassRole` 給自己；KMS；log |
| `sagemaker-endpoint` | `iam-base`（完整） | `inference` | `iam-base` | 讀 `ml-artifacts/models/*`；ECR 拉 image；VPC ENI；KMS；log |
| `scheduler` | `iam-base`（完整） | `ml` 的排程 | `iam-base` | `sagemaker:StartPipelineExecution` 單一 pipeline（命名規則） |

測試用 `jsondecode` 斷言 Resource 沒有 `*`；只能 `*` 的動作寫白名單（例如 `ec2:Describe*`、IoT audit 的 `iot:List*`）。

## 9. 測試情境（TDD）

| module | 正向 | 負向（`expect_failures`） |
|---|---|---|
| `iot-fleet` | thing type、群組階層、policy JSON、role alias、provisioning template（含與不含 hook）、SNI_ONLY CA | parent 不存在；policy `iot:*`＋`*`；`credential_duration` 超出範圍；role ARN 格式；CA 模式 `DEFAULT` |
| `iot-topic-rule` | 多條 rule、各種 action、`sql_version` 固定、error action | 沒有 action；error action 零個或兩個；名稱有連字號；SQL 不是 SELECT |
| `iot-account-settings` | 三項都給；只給 logging；indexing 含 Device Defender | log level；indexing mode；`VIOLATIONS` 搭 `OFF` |
| `greengrass-component` | 物件 recipe；JSON 字串 recipe；artifact 在指定 bucket；tags 轉成 map | 兩種 recipe 都給或都沒給；版本不是 semver；artifact 在別的 bucket；Lambda 元件 |
| `greengrass-deployment` | thing group 與 thing target；merge 設定 `jsonencode`；固定的 ROLLBACK；exponential rollout；abort | target 格式；沒有元件；rollout 兩種都給；百分比超過 100 |
| `sagemaker-model-registry` | 只有 group；跨帳號唯讀 policy 的 JSON | principal 是 `*`；格式 |
| `ota-signing` | FreeRTOS 加憑證；DeviceManagement platform；start job permission | platform 不在白名單；FreeRTOS 沒憑證；天數 |
| `sqs-queue` | 標準與 FIFO；DLQ 與 redrive；queue policy 的 `aws:SourceArn` | 保留時間；receive count；source ARN 不是 events |
| `iot-job-template` | inline document；S3 document；presigned URL；rollout、abort、retry | document 兩種都給；`expires_in_sec`；retry 次數 |
| `sagemaker-endpoint` | instance＋VPC＋blue/green＋告警；serverless；data capture；`create_before_destroy` 的 name_prefix | 兩種 variant；instance 沒 VPC、沒告警；serverless 給 VPC 或 data capture；記憶體 |
| `sagemaker-pipeline` | definition、role、parallelism | definition 不是 JSON 或缺 `Steps` |
| `iot-device-defender` | audit＋排程＋mitigation；`audit = null` 時只有排程 | 排程的 check 不在 audit 裡；frequency 與 day 不搭；mitigation 兩種 |
| `kinesis-video-stream` | 多個 stream、KMS | 保留時數；名稱 |
| `acm-pca` | ROOT＋自簽安裝；SUBORDINATE 只輸出 CSR；short-lived | RSA 1024；保留天數 |
| `eventbridge-rule` | pattern＋SQS target；schedule＋需要 role 的 target；input transformer；DLQ | pattern 與 schedule 都給；沒有 target；超過 5 個；缺 role |
| `scheduler-schedule` | cron＋SageMaker pipeline 參數；flexible window | expression 格式；window 超出；缺 role |
| `iotsitewise` | model 階層、asset、gateway；tags 轉成 list | asset 的 model 不存在；property 型別；thing 名稱 |
| `validate.sh`（H1） | 既有範本與 module 全過 | module 裡寫 `awscc_iam_role`、`awscc_ec2_security_group` 被 S4 擋；stack 寫 `awscc_*` 被 S8 擋 |

範本 stack 的測試照 example4：讀與發布的 key 清單、`tests/tfvars/` 帶每份 tfvars、`vpn`／`pki`／`inference` 預設零資源、`cameras = {}` 時 `edge` 沒有 KVS 與 thing 層級部署、`edge` 的 precondition（引用不存在的版本會失敗）、awscc 與 aws provider 的 region 與 role 一致（K4）、`iam-base`／`iam-app` 的 Resource 斷言、`check-ssm-contract.sh` 通過。

## 10. 成本估計（Tokyo，on-demand，美元／月，730 小時）

**以下是估計**，單價取自 AWS Price List 公開檔案與定價頁（§13）；不含資料傳輸、儲存量。裝置相關的費用以 100 台、每台每 5 秒一則訊息估。

| 元件 | 規格（單價） | dev | sit |
|---|---|---|---|
| OpenSearch | 同 v7 §10 | 約 1,052 | 約 1,052 |
| IoT Core | 連線 0.096／百萬分鐘；訊息 1.20／百萬；rule 0.18／百萬觸發＋0.18／百萬 action（100 台約 5,256 萬則訊息） | 約 83（100 台） | 約 83（100 台） |
| Greengrass | 0.18／core device | 依台數 | 依台數 |
| Kinesis | 1 shard（0.0195／shard-時） | 約 14 | 約 14 |
| Firehose、S3、SQS、EventBridge、Scheduler | 小量 | 約 5–20 | 約 5–20 |
| Device Defender audit | 1.49／1,000 台 | 不到 1 | 不到 1 |
| SageMaker Pipeline 訓練 | 依 instance 與時數 | 0（排程關） | 依用量 |
| KMS、CloudWatch Logs、SNS、Secrets Manager | | 約 6 | 約 6 |
| **小計（預設：VPN、PKI、endpoint、攝影機都關）** | | **約 1,160–1,175** | **約 1,160–1,175＋訓練** |
| 兩個環境合計 | | **約 2,320–2,350＋訓練** | |
| 雲端推論 endpoint（開啟時） | ml.m5.large 1 台（0.149／時）；blue/green 期間短暫兩倍 | ＋約 109 | ＋約 109 |
| serverless 推論（取代上一列） | 0.00002／GB-秒 | 依用量 | 依用量 |
| KVS（每台攝影機） | 1 Mbps 約 329 GB／月 × 0.010965；儲存 0.025／GB-月 | ＋約 4＋儲存 | ＋約 4＋儲存 |
| SiteWise | 依 property 與訊息量 | 另計（單價未取得） | 另計 |
| ACM Private CA（開啟時） | 400／CA＋憑證 | ＋約 400 | ＋約 400 |
| Client VPN（開啟時） | 同 v7 | ＋約 126 | ＋約 126 |

OpenSearch 佔每個環境約九成。IoT Core 隨裝置數與訊息頻率線性成長，README 第一段寫「dev、sit 各約 1,150–1,200 美元／月起（100 台裝置），主要是 OpenSearch 冷熱」。

## 11. 風險與 mock 驗不到的事

| 風險 | 影響 | 處理 |
|---|---|---|
| awscc 的 write-only 屬性（`inline_recipe`）在 plan 是否一直顯示變更 | 每次 plan 都 replace 元件版本 | H4 用 mock 驗不出來，列入雲端驗證；有問題就改用 `lifecycle { ignore_changes }` 並在 README 說明 |
| Greengrass 部署每次變更都 replace | plan 看起來像刪掉再建；同時最多 10 個部署在刪除中 | README 說明 replace 是正常的；一次 apply 不超過 10 個部署 |
| 從部署拿掉元件會在裝置上解除安裝 | 裝置上的應用停止 | PR 審查看 `components` 的差異；README 寫明 |
| 刪掉還在部署的元件版本 | 部署失敗 | `edge` 的 precondition（K10） |
| claim 憑證外洩 | 有人開通假裝置 | §4.1 |
| 帳號層設定被同帳號第二個專案呼叫 | 設定互蓋 | K9 的選填輸入與 README 提醒 |
| Device Defender Detect 不能用 | 沒有行為異常偵測 | K8；README 寫替代做法（IoT logging＋CloudWatch 告警） |
| KVS edge connector 依賴 SiteWise asset 的結構 | 設定錯就連不上攝影機 | H5 照 AWS 文件核對；雲端驗證 |
| SiteWise Monitor、Edge Data Processing Pack 進入維護模式 | 之後可能停止 | `iotsitewise` 刻意不做這兩項 |
| SageMaker Neo、DLR 沒有找到停止公告 | 範例元件的 runtime 之後可能被淘汰 | 範例用 ONNX Runtime（AWS 的建議） |
| awscc 透過 Cloud Control API，部分 resource 的 drift 偵測與錯誤訊息比 aws 少 | 除錯比較慢 | README 說明；雲端驗證時記錄 |
| awscc 的 lock | S10 | 使用者產生（K5） |
| awscc 版本下限只查了 1.107.0 | 消費端用舊版會 init 失敗 | 下限寫 1.107 |
| 17 個新 module 連續發版 | Actions 額度、release PR 衝突 | 每個 Phase 2–3 個，release PR 一次合併一個 |
| HCP 登記漏掉 | 範本 init 失敗 | 每發一個新 module 就登記並從消費端抓一次 |
| 範例 Greengrass 元件、訓練 pipeline 沒有在真實環境跑過 | 複製出去不能直接用 | README 標明是骨架；列入雲端驗證 |
| IAM 動作清單沒有對真實帳號驗證 | apply 或執行時權限不足 | 列入雲端驗證 |
| 成本（D3） | 兩個環境合計每月約 2,300 美元起 | README 第一段寫明 |

## 12. Phase

實作流程在設計審過之後另寫 `implement-process.md`。Phase 代號用 H，接在 v7 的 G 之後。摘要：

| Phase | 內容 |
|---|---|
| H0 | 設計與實作流程 |
| H1 | `validate.sh` 的 S4、S8 擴充到 awscc（K2）；`sqs-queue`、`eventbridge-rule`、`scheduler-schedule`；發版、HCP |
| H2 | `iot-fleet`、`iot-account-settings`、`iot-topic-rule`；發版、HCP |
| H3 | `ota-signing`、`acm-pca`；發版、HCP |
| H4 | `greengrass-component`、`greengrass-deployment`、`iot-job-template`（第一批 awscc）；發版、HCP |
| H5 | `iot-device-defender`、`iotsitewise`、`kinesis-video-stream`；發版、HCP |
| H6 | `sagemaker-model-registry`、`sagemaker-pipeline`、`sagemaker-endpoint`；發版、HCP |
| H7 | example5 骨架、`foundation`、`network`、`vpn`、`pki` |
| H8 | `storage`、`iam-base` |
| H9 | `search`、`search-config` |
| H10 | `fleet`、`iam-app`、`ingest` |
| H11 | `sitewise`、`edge`（元件 recipe、precondition、攝影機） |
| H12 | `ml`、`inference` |
| H13 | README、架構圖、REFERENCE、全量驗證、驗證表 |

## 13. 來源

**怎麼查的**

- provider schema：在 repo 外的暫存目錄寫只有 `required_providers` 的設定（aws 6.70.0、awscc 1.107.0），`terraform init -backend=false -plugin-dir=<repo>/.cache/plugins` 後跑 `terraform providers schema -json`，逐層列出 §2 與 §5 提到的 resource。沒有 AWS 憑證、沒有呼叫 AWS API。
- `mock_provider "awscc"`：同一個暫存目錄寫 §2 第 1 點的 resource 與測試檔，`terraform test` 兩個 run 通過；用 repo 的 `.tflint.hcl` 跑 tflint 沒有錯誤。
- AWS 文件、CloudFormation resource 參考、停止支援公告：2026-10-25 讀取。
- 價格：AWS Price List 公開檔案（`pricing.us-east-1.amazonaws.com`）與定價頁，Asia Pacific (Tokyo) 的 on-demand 價。正式數字以各服務定價頁為準。

**AWS 文件**

- Greengrass：部署 <https://docs.aws.amazon.com/greengrass/v2/developerguide/create-deployments.html>；`CancelDeployment` <https://docs.aws.amazon.com/greengrass/v2/APIReference/API_CancelDeployment.html>；`DeleteDeployment` <https://docs.aws.amazon.com/greengrass/v2/APIReference/API_DeleteDeployment.html>；`DeleteComponent` <https://docs.aws.amazon.com/greengrass/v2/APIReference/API_DeleteComponent.html>；發布元件 <https://docs.aws.amazon.com/greengrass/v2/developerguide/publish-components.html>；recipe <https://docs.aws.amazon.com/greengrass/v2/developerguide/component-recipe-reference.html>；token exchange role <https://docs.aws.amazon.com/greengrass/v2/developerguide/device-service-role.html>；core device 的 IoT policy <https://docs.aws.amazon.com/greengrass/v2/developerguide/device-auth.html>；KVS edge connector <https://docs.aws.amazon.com/greengrass/v2/developerguide/kvs-edge-connector-component.html>；機器學習推論 <https://docs.aws.amazon.com/greengrass/v2/developerguide/perform-machine-learning-inference.html>。
- CloudFormation：`AWS::GreengrassV2::Deployment` <https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-greengrassv2-deployment.html>；`AWS::GreengrassV2::ComponentVersion` <https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-greengrassv2-componentversion.html>；`AWS::IoT::JobTemplate` <https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-iot-jobtemplate.html>；`AWS::IoT::AccountAuditConfiguration` <https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-iot-accountauditconfiguration.html>。
- IoT Core：rule action <https://docs.aws.amazon.com/iot/latest/developerguide/iot-rule-actions.html>；SQL 版本 <https://docs.aws.amazon.com/iot/latest/developerguide/iot-rule-sql-version.html>；OpenSearch action <https://docs.aws.amazon.com/iot/latest/developerguide/opensearch-rule-action.html>；Kafka VPC destination <https://docs.aws.amazon.com/iot/latest/developerguide/kafka-vpc-destination.html>；logging <https://docs.aws.amazon.com/iot/latest/developerguide/configure-logging.html>；fleet provisioning <https://docs.aws.amazon.com/iot/latest/developerguide/provision-wo-cert.html>；pre-provisioning hook <https://docs.aws.amazon.com/iot/latest/developerguide/pre-provisioning-hook.html>；CA 憑證 <https://docs.aws.amazon.com/iot/latest/developerguide/manage-your-CA-certs.html>；JITP <https://docs.aws.amazon.com/iot/latest/developerguide/jit-provisioning.html>。
- Device Defender Detect 的變更 <https://docs.aws.amazon.com/iot-device-defender/latest/devguide/dd-detect-availability-change.html>。
- 停止支援：SageMaker Edge Manager <https://docs.aws.amazon.com/sagemaker/latest/dg/edge-eol.html>；IoT Events <https://docs.aws.amazon.com/iotevents/latest/developerguide/iotevents-end-of-support.html>；IoT Analytics <https://docs.aws.amazon.com/iotanalytics/latest/userguide/iotanalytics-end-of-support.html>；Timestream for LiveAnalytics <https://docs.aws.amazon.com/timestream/latest/developerguide/AmazonTimestreamForLiveAnalytics-availability-change.html>；SiteWise Monitor <https://docs.aws.amazon.com/iot-sitewise/latest/appguide/iotsitewise-monitor-availability-change.html>；SiteWise Edge Data Processing Pack <https://docs.aws.amazon.com/iot-sitewise/latest/userguide/iotsitewise-dpp-availability-change.html>。
- AWS Signer <https://docs.aws.amazon.com/signer/latest/developerguide/Welcome.html>。
- SageMaker：核准 <https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry-approve.html>；跨帳號 <https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry-ram.html>；serverless <https://docs.aws.amazon.com/sagemaker/latest/dg/serverless-endpoints.html>；deployment guardrails <https://docs.aws.amazon.com/sagemaker/latest/dg/deployment-guardrails.html>。
- 定價頁：<https://aws.amazon.com/iot-core/pricing/>、<https://aws.amazon.com/greengrass/pricing/>、<https://aws.amazon.com/iot-device-defender/pricing/>、<https://aws.amazon.com/private-ca/pricing/>、<https://aws.amazon.com/kinesis/video-streams/pricing/>、<https://aws.amazon.com/sagemaker/pricing/>、<https://aws.amazon.com/eventbridge/pricing/>。

**Terraform 與 provider**

- awscc provider <https://registry.terraform.io/providers/hashicorp/awscc>；Cloud Control API 的 schema <https://github.com/hashicorp/terraform-provider-awscc/tree/main/internal/service/cloudformation/schemas>。
- aws provider：`aws_iot_topic_rule`、`aws_iot_event_configurations`、`aws_iot_ca_certificate`、`aws_signer_signing_profile` 的文件（hashicorp/terraform-provider-aws `website/docs/r/`）。

**repo**

- [v7 design](../v7/design-docs.md)（§4.1、§4.2 的例外、K10、K21、D13）、[ADR-0002](../../adr/0002-split-state-by-owner-and-change-rate.md)、[ADR-0003](../../adr/0003-cross-stack-values-via-ssm-only.md)、[ADR-0004](../../adr/0004-hcp-terraform-private-registry.md)。
- [`releasing-modules.md`](../../guides/releasing-modules.md)、[`project-infra-standard.md`](../../guides/project-infra-standard.md)。
- [`scripts/validate.sh`](../../../scripts/validate.sh)（S1、S4、S8、S10）；[`modules/lambda-function`](../../../modules/lambda-function/README.md)、[`modules/xray-transaction-search`](../../../modules/xray-transaction-search/README.md)、[`modules/glue-catalog-encryption`](../../../modules/glue-catalog-encryption/README.md)。

## 14. 實作後的變更

（實作時跟上面的設計不同、或設計沒寫到的決定記在這裡。）
