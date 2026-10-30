# example5 雲端驗證 runbook

## 結論

這份 runbook 列出 `templates/example5` 第一次在真實 AWS 帳號 apply 時要逐項確認的事。照做完，REFERENCE〈雲端整合待驗證〉表、〈已知限制的細節〉與 design v8 §4.1、§11、§14 裡的「未確認」「未驗證」「推論」都會變成有證據的通過或不通過。

- 範圍：REFERENCE 表上的 21 項（本文第 1–21 項），加上表上沒涵蓋的 3 項（本文 S1–S3）。對照見〈範圍〉。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、名稱怎麼來的、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的標【寫入】，只在 `dev` 執行。要在測試裝置或 core device 上跑的標【裝置端】，其餘在操作者的終端機跑。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的預設命名、SDK 的範例名稱、裝置上的路徑），執行時以實際輸出為準。
- 費用：OpenSearch 冷熱每個環境每月約 1,052 美元，整份 runbook 建議只在 `dev` 做。第 14 項（endpoint 每月約 109）、第 15 項（Private CA 每月約 400，region 第一個 CA 有 30 天試用）、第 20 項（Client VPN 每月約 126）做完就關。core device 用一台 EC2 或 VM。

從程式碼就看得出來、第一次驗證很可能不通過的事，先講：

1. **同序號第二次開通很可能會成功**（第 1 項）。design §4.1 補償控制 3 說「同序號第二次開通會失敗」，§14 已標成推論。provisioning template 的 thing resource 遇到同名 thing 時，AWS 的行為是更新既有 thing、再附加一張新憑證（推測，依 AWS 文件的 `OverrideSettings` 說明），也就是同一個 thing 會有兩張有效憑證。不通過的話，補償控制 3 要改寫，風險表要重新評估。
2. **claim policy 擋掉 `CreateCertificateFromCsr`**（第 1 項）。claim policy 只放行 `$aws/certificates/create/*`（`fleet/fleet.tf:78`、`:86`），用 CSR 換憑證的 topic 是 `$aws/certificates/create-from-csr/json`（AWS 的命名），`create/*` 比對不到。裝置自己產生私鑰、送 CSR 的開通流程會被拒；只有讓 AWS 產生金鑰的 `CreateKeysAndCertificate` 會通。
3. **TES role 沒有 `s3:GetBucketLocation`**（第 3、4 項）。`iam-base/policies.tf:73` 只給 `artifacts/*` 的 `s3:GetObject`。AWS 文件的預設 token exchange policy 有 `s3:GetBucketLocation`，Greengrass 下載 artifact 時是否需要它沒有確認（推測）。如果需要，core device 下載 `com.example.Inference` 的 artifact 會 `AccessDenied`。
4. **endpoint role 寫不進 data capture**（第 14 項）。`inference/endpoint.tf:42` 把 20% 的請求 capture 到 ml-artifacts 的 `capture/`，但 endpoint role 只有 `models/*` 的 `s3:GetObject`（`iam-base/policies.tf:169`），沒有 `capture/*` 的 `s3:PutObject`。data capture 用的是 endpoint 的 execution role（推測，依 AWS 文件），所以 capture 很可能寫不進去。
5. **Greengrass 的 log 不會上雲**（第 3 項）。REFERENCE 要驗「寫得到 `/aws/greengrass/*` log」，但部署的元件沒有 `aws.greengrass.LogManager`（`edge/envs/dev.tfvars:13-15`），nucleus 不會自己把 log 送進 CloudWatch。要驗這一點得暫時把 LogManager 加進 dev 的部署。
6. **WARN 等級的 IoT logging 記不到成功的開通**（S1）。REFERENCE〈runbook：輪替 claim 憑證〉第 3 步說「查 `AWSIotLogsV2` 的開通紀錄」，但帳號層 logging 是 `WARN`（`fleet/envs/dev.tfvars:8`），成功的事件是 INFO 等級，不會寫進去（推測，依 AWS IoT logging 的等級定義）。懷疑外洩時，要靠 fleet indexing 查 `unverified` 群組。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 1–21 | fleet provisioning、裝置 policy、core device 憑證、Greengrass 部署、範例推論元件、IoT rule、OpenSearch、帳號層設定、Device Defender、OTA、KVS edge connector、SiteWise gateway、訓練與核准、雲端推論、pki、IAM、特權操作、destroy、告警、Client VPN、flow log 與 state | `templates/example5/infra/REFERENCE.md:333-355`〈雲端整合待驗證〉 |
| S1 | claim 憑證設成 `INACTIVE`、開通的追查 | design §4.1 補償控制 5、6；REFERENCE〈runbook：輪替 claim 憑證〉 |
| S2 | core device 的開通：序號、`-core` policy、群組 | REFERENCE〈前置作業的細節〉第 6 項；design §4.1 補償控制 4；§14 `fleet` |
| S3 | awscc 的 drift 與錯誤訊息 | design §11 第 11 點；REFERENCE〈已知限制的細節〉awscc 列 |

design §4.1 補償控制與 §11、§14 各點的去處（行號是 `docs/design/v8/design-docs.md`）：

| 出處 | 內容 | 在本文 |
|---|---|---|
| §4.1 控制 1（:147） | claim 憑證在 Terraform 外用 CSR 建立 | 第 1 項前提 |
| §4.1 控制 2 | claim policy 只有兩組 provisioning topic | 第 1 項 |
| §4.1 控制 3 | 序號格式、thing 名稱由序號組出、同序號第二次開通會失敗 | 第 1 項（格式檢查沒有做到，見 REFERENCE:160） |
| §4.1 控制 4 | 開通的裝置先進 `unverified`，部署只對正式群組 | 第 1 項、S2 |
| §4.1 控制 5 | 每批生產結束 claim 憑證設成 `INACTIVE` | S1 |
| §4.1 控制 6 | Device Defender audit 與 IoT logging | 第 8、9 項 |
| §11（:492） | awscc `inline_recipe` 在 plan 是否持續顯示變更 | 第 4 項 |
| §11（:493） | 部署每次變更都 replace、同時最多 10 個在刪除中 | 第 4 項（10 個的上限不實測） |
| §11（:494） | 拿掉元件在裝置上解除安裝 | 第 4 項 |
| §11（:495） | 刪掉還在部署的元件版本 | 不在本文：`edge` 的 precondition 離線就擋（`edge/outputs.tf:8-11`） |
| §11（:496） | claim 憑證外洩 | 第 1 項、S1 |
| §11（:497） | 帳號層設定被第二個專案呼叫 | 第 8 項 |
| §11（:498） | Device Defender Detect 不能用 | 不在本文：設計決定，不是待驗證的行為 |
| §11（:499） | KVS edge connector 依賴 SiteWise asset 的結構 | 第 11 項 |
| §11（:500–501） | SiteWise Monitor 維護模式、Neo／DLR 淘汰 | 不在本文：服務公告，不是部署行為 |
| §11（:502） | awscc 的 drift 偵測與錯誤訊息 | S3 |
| §11（:503–506） | awscc lock、版本下限、發版、HCP 登記 | 不在本文：離線與 CI 的事；lock 是〈前置作業〉第 2 項，HCP 登記漏掉時第一次 `init` 就會失敗 |
| §11（:507） | 範例元件與訓練 pipeline 沒在真實環境跑過 | 第 5、13 項 |
| §11（:508） | IAM 動作清單 | 第 16 項（各項的 CloudTrail 檢查一起看） |
| §11（:509） | 成本 | 不在本文：跑完一個月後看帳單 |
| §14（:570） | IoT Core 連線時是否查 CRL | 第 15 項 |
| §14（:574） | `inline_recipe` 是 optional＋computed | 第 4 項 |
| §14（:577） | audit check 名稱對照 | 第 9 項 |
| §14（:578） | asset 不能設屬性值 | 第 11 項 |
| §14（:579） | FIFO 的 content-based deduplication | 不在本文：範本只用標準 queue |
| §14（:582） | 帶 NVMe 的 instance type 用 KMS | 不在本文：預設 `ml.m5.large` 沒有 NVMe；換 type 時再驗 |
| §14（:592） | credentials provider 搭配 `source_account`；provisioning 與 audit 的動作清單 | 第 3、1、9、16 項 |
| §14（:593） | 同序號第二次開通、core device 要另外附加 `-core` policy | 第 1 項、S2 |
| §14（:595） | edge connector 跟多個 hierarchy | 第 11 項 |
| §14（:597） | `iotsitewise:ListAssets` 能否限縮 | 第 11 項 |
| §14（:596） | Nucleus 2.14.3、StreamManager 2.2.1 是佔位 | 第 4 項前提 |
| REFERENCE:117 | Signer 對 code signing 憑證的要求 | 第 10 項 |
| REFERENCE:198 | SQS 訊息的欄位名稱 | 第 13 項 |
| REFERENCE:262–272 | destroy 的各項「沒有確認」 | 第 18 項 |

不涵蓋：沿用 example4 的 OpenSearch 細節（warm 最小台數、master 密碼輪替的完整步驟）只在第 7 項做最小確認，完整做法在 [example4 REFERENCE〈已知限制的細節〉](../../templates/example4/infra/REFERENCE.md#已知限制的細節)。

## 需要的權限與工具

操作者的終端機：

- AWS CLI v2（要有 `greengrassv2`、`iotsitewise`、`iot-jobs-data`、`cloudcontrol`、`scheduler` 子指令）、`jq`、`openssl`、`curl`、Terraform（apply 用）。
- `mosquitto_pub`、`mosquitto_sub`（Mosquitto 的 client）。第 2、15 項用它扮演裝置。
- Python 3 與 AWS IoT Device SDK v2（`awsiotsdk`），用 SDK 附的 fleet provisioning 範例。範例的檔名與參數每個版本不同（推測），以你用的版本的 README 為準。
- Amazon Root CA 1（`AmazonRootCA1.pem`，AWS 公開的 CA 憑證，下面寫成 `AmazonRootCA1.pem`）。
- Docker：第 13 項要建 `<project>-<env>-preprocess`、`-train`、`-inference` 三個 image 推上 ECR，repo 沒有提供。

測試機器：

| 用途 | 機器 | 條件 |
|---|---|---|
| 一般裝置（第 1、2、10 項、S1） | 操作者的筆電或任何 Linux | 能連 IoT Core 的 8883 port |
| core device（第 3–5、11、12 項、S2） | 一台 EC2（Amazon Linux 2023 或 Ubuntu）或 VM，Linux、Java 11 以上、Python 3 與 pip | 要能對外連 443、8883。**不能放在範本的 VPC**：那裡沒有 NAT、沒有 public subnet（`network/vpc.tf:7`），放在另一個有對外路由的 VPC。不需要 instance profile，AWS 憑證走 TES |
| 攝影機（第 11 項） | 真實的 RTSP 攝影機，或在 core device 上用 RTSP server 加 `ffmpeg` 循環播放測試影片（推測可行，repo 沒有提供） | core device 連得到 RTSP |
| OpenSearch、`search-config`（第 7、20 項） | Client VPN 上的機器，或 VPC 內的 runner | REFERENCE〈`search-config` 的執行環境〉 |

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 15 個 stack | deploy role（tfvars 的 `deploy_role_arn`，空字串用呼叫者自己）；要有 REFERENCE〈前置作業的細節〉第 8 項的特權操作 | `fleet/providers.tf:1-35`、REFERENCE:137-148 |
| 執行本文的唯讀指令 | 驗證用的 IAM 身分，權限見下 | 無 |
| 一般裝置 | fleet provisioning 換到的裝置憑證 | 第 1 項 |
| core device | 附加 `-core` policy 的裝置憑證，經 role alias 換到 TES role | S2、第 3 項 |
| 消費 `model-approved` queue | 範本外的 CI role；沒有的話用驗證身分代替 | REFERENCE:200 |

驗證身分要的 AWS 權限（唯讀）：`iot:Describe*`、`iot:List*`、`iot:Get*`、`iot:SearchIndex`、`iotjobsdata:DescribeJobExecution`、`greengrass:Get*`、`greengrass:List*`、`greengrass:Describe*`、`iotsitewise:Describe*`、`iotsitewise:List*`、`iotsitewise:GetAssetPropertyValue`、`kinesisvideo:Describe*`、`kinesisvideo:GetDataEndpoint`、`kinesisvideo:ListFragments`、`kinesis:DescribeStreamSummary`、`firehose:DescribeDeliveryStream`、`sqs:GetQueueUrl`、`sqs:GetQueueAttributes`、`sagemaker:Describe*`、`sagemaker:List*`、`scheduler:GetSchedule`、`events:DescribeRule`、`events:ListTargetsByRule`、`signer:GetSigningProfile`、`signer:DescribeSigningJob`、`acm:DescribeCertificate`、`acm-pca:DescribeCertificateAuthority`、`es:DescribeDomain`、`ec2:Describe*`、`s3:ListBucket`、`s3:GetObject`（只看 metadata 與測試物件）、`ssm:GetParameter`、`logs:Describe*`、`logs:FilterLogEvents`、`cloudwatch:DescribeAlarms`、`cloudwatch:ListMetrics`、`cloudwatch:GetMetricStatistics`、`cloudtrail:LookupEvents`、`iam:GetRole`、`iam:GetRolePolicy`、`iam:ListRolePolicies`、`iam:SimulatePrincipalPolicy`、`kms:GetKeyPolicy`、`kms:DescribeKey`、`sns:ListSubscriptionsByTopic`、`cloudformation:GetResource`（Cloud Control）。

【寫入】要另外的權限：`iot:CreateCertificateFromCsr`、`iot:RegisterCertificate`、`iot:RegisterCertificateWithoutCA`、`iot:UpdateCertificate`、`iot:AttachPolicy`、`iot:DetachPolicy`、`iot:CreateThing`、`iot:AttachThingPrincipal`、`iot:AddThingToThingGroup`、`iot:RemoveThingFromThingGroup`、`iot:Publish`（`iot-data publish`）、`iot:CreateJob`、`iot:CancelJob`、`iot:StartOnDemandAuditTask`、`iot:StartAuditMitigationActionsTask`、`signer:StartSigningJob`、`s3:PutObject`、`secretsmanager:CreateSecret`、`iotsitewise:BatchPutAssetPropertyValue`、`sagemaker:StartPipelineExecution`、`sagemaker:UpdateModelPackage`、`sagemaker:InvokeEndpoint`、`scheduler:CreateSchedule`、`sqs:ReceiveMessage`、`sqs:DeleteMessage`、`cloudwatch:SetAlarmState`、`iam:PutRolePolicy`、`iam:DeleteRolePolicy`（只在第 6 項）、`acm-pca:IssueCertificate`、`acm-pca:GetCertificate`、`acm-pca:RevokeCertificate`。

網路：裝置與 core device 經公網連 IoT Core（design K33），不經範本的 VPC。OpenSearch 只能從 VPC 內或 Client VPN 連（第 7、20 項）。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
PFX="$P-$E"                               # name_prefix
RULE_PFX="${PFX//-/_}"                    # IoT rule 名稱的前綴
ssm() { aws ssm get-parameter --name "/$P/$E/$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
KMS_KEY=$(ssm foundation/kms_key_arn)
TOPIC=$(ssm foundation/alarm_topic_arn)
STREAM_ARN=$(ssm storage/stream_arn)
GG_BUCKET=$(ssm storage/greengrass_artifacts_bucket_name)
OTA_BUCKET=$(ssm storage/ota_bucket_arn | sed 's|^arn:aws:s3:::||')
ML_BUCKET=$(ssm storage/ml_bucket_name)
TELEMETRY_BUCKET=$(ssm storage/telemetry_bucket_arn | sed 's|^arn:aws:s3:::||')
RULE_ERRORS_URL=$(ssm storage/rule_errors_queue_url)
MODEL_Q_URL=$(aws sqs get-queue-url --queue-name "$PFX-model-approved" --query QueueUrl --output text)
GROUP_FLEET_ARN=$(ssm fleet/thing_group_fleet_arn)
GROUP_UNVERIFIED_ARN=$(ssm fleet/thing_group_unverified_arn)
GROUP_CORE_ARN=$(ssm fleet/thing_group_core_arn)
ROLE_ALIAS_ARN=$(ssm fleet/role_alias_arn)
TEMPLATE=$(ssm fleet/provisioning_template_name)          # 應該等於 "$PFX-fleet"
SIGNING_PROFILE=$(ssm fleet/ota_signing_profile_name)     # 應該等於 "${RULE_PFX}_ota"
JOB_TEMPLATE_ARN=$(ssm fleet/ota_job_template_arn)
DOMAIN=$(ssm search/opensearch_domain_name)               # 應該等於 "$PFX-search"
OS_ENDPOINT=$(ssm search/opensearch_endpoint)
PIPELINE=$(ssm ml/pipeline_name)                          # 應該等於 "$PFX-training"
MPG=$(ssm ml/model_package_group_name)                    # 應該等於 "$PFX-models"

IOT_DATA=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)
IOT_CRED=$(aws iot describe-endpoint --endpoint-type iot:CredentialProvider --query endpointAddress --output text)
```

名稱怎麼來的：

- `name_prefix = "${var.project}-${var.env}"`、`ssm_prefix = "/${var.project}/${var.env}"`（`fleet/common.tf:44-45`，15 個 stack 的 `common.tf` 相同）；SSM key 是 `${ssm_prefix}/${stack}/${key}`（`modules/ssm-publish/main.tf:4`）。
- key 名稱：`foundation/ssm-outputs.tf:3-6`、`storage/ssm-outputs.tf:3-12`、`fleet/ssm-outputs.tf:3-9`、`search/ssm-outputs.tf:3-5`、`ml/ssm-outputs.tf:3-5`。
- `model-approved` queue 沒有發布 URL，名稱是 `"${local.name_prefix}-model-approved"`（`storage/queues.tf:16`）。
- provisioning template `"${local.name_prefix}-fleet"`（`fleet/fleet.tf:16`）；Signer profile 把連字號換成底線再加 `_ota`（`fleet/ota.tf:6`）；domain `"${local.name_prefix}-search"`（`search/domain.tf:3`）；pipeline `"${local.name_prefix}-training"`（`ml/pipeline.tf:8`）；model package group `"${local.name_prefix}-models"`（`ml/registry.tf:7`）。
- IoT rule 名稱不能有連字號，前綴是 `replace(local.name_prefix, "-", "_")`（`ingest/rules.tf:3`）。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER` 與 README〈前置作業〉。每個 stack 第一次先 `./stacks.sh <env> <stack> init`，apply 前先 `--dry-run` 看一次指令。

| 階段 | 做什麼 | 在哪裡跑 | 做完接著驗 |
|---|---|---|---|
| 0 | 照 REFERENCE〈複製出去之後要改什麼〉換掉佔位值（`accounts_by_env`、`.tfbackend`、tfvars 的 `project`、`expected_account_id`；`foundation` 的 `alarm_emails` 換成會收信的地址，`foundation/envs/dev.tfvars:5`）；REFERENCE〈前置作業的細節〉第 1、2、4、5 項；先記下帳號層 IoT 設定的現況（第 8 項）；建好 core device 用的 EC2；準備 `com.example.Inference` 的 artifact（第 5 項）與三個 ECR image（第 13 項） | 自己的終端機 | 第 8 項的「apply 前」快照 |
| A | `foundation` → 寫入 OpenSearch master secret（〈前置作業〉第 3 項）→ `network`、`vpn`（要做第 7、20 項時帶 Client VPN）、`pki`（預設零資源）、`storage`、`iam-base`、`search` | 能呼叫 AWS API 的地方 | 收到 SNS 訂閱確認信就點 |
| B | `search-config` | Client VPN 或 VPC 內 | 無 |
| C | `fleet`、`iam-app`、`ingest`、`sitewise`（`cameras = {}`）、`edge`、`ml`、`inference`（`model_package_arn = null`） | 能呼叫 AWS API 的地方 | 第 8、9 項的設定部分、第 17、19、21 項、S3 |
| D | 〈前置作業〉第 6 項：建 claim 憑證 | 自己的終端機 | 無 |
| E | 【裝置端】一般裝置開通與連線 | 測試裝置 | 第 1、2 項、S1 |
| F | 【裝置端】core device 開通、附加 `-core` policy、搬進 `-core`、安裝 Greengrass；上傳 artifact | core device 與自己的終端機 | S2、第 3–6 項 |
| G | 資料進 OpenSearch 之後 | Client VPN | 第 7、20 項（ISM 搬移要等 dev 的第 3、7 天） |
| H | 跑訓練 pipeline、核准；再開 `inference` | 自己的終端機 | 第 13、14 項 |
| I | OTA：Signer 簽章、建 job | 自己的終端機與測試裝置 | 第 10 項 |
| J | 選配：攝影機（RTSP secret、`sitewise`、`edge` 帶 `cameras`）、SiteWise gateway | 混合 | 第 11、12 項 |
| K | 選配：開 `pki`，再 apply `fleet` | 自己的終端機與測試裝置 | 第 15 項 |
| L | 全部做完、最後才做：destroy | 自己的終端機 | 第 18 項 |

第 16 項（IAM）不是獨立的階段：每一項做完都跑一次第 16 項的 CloudTrail 查詢，收集 `AccessDenied`。

---

## 1. fleet provisioning by claim

**前提**

- 階段 C、D 完成。claim 憑證照 REFERENCE:121-127 用 CSR 建立，附加 `$PFX-claim` policy（design §4.1 控制 1）。下面用 `CLAIM_CERT_ARN`、`CLAIM_CERT_ID` 代表它。
- 測試裝置上有 `claim.crt`（`create-certificate-from-csr` 回的 PEM 存成檔案）、`claim.key`、`AmazonRootCA1.pem`。
- 序號用 `test-0001` 這類一看就知道是測試的值。

**指令**

```bash
# template 內容、role、沒有 hook
aws iot describe-provisioning-template --template-name "$TEMPLATE" \
  --query '{enabled:enabled,type:type,role:provisioningRoleArn,hook:preProvisioningHook}'
aws iot describe-provisioning-template --template-name "$TEMPLATE" --query templateBody --output text | jq .

# claim policy 只有兩組 topic
aws iot get-policy --policy-name "$PFX-claim" --query policyDocument --output text | jq .
aws iot list-targets-for-policy --policy-name "$PFX-claim"
```

【裝置端】開通（第一次）。用 SDK 的 fleet provisioning 範例，參數是 IoT data endpoint、claim 憑證與私鑰、`AmazonRootCA1.pem`、template 名稱、template 參數 `{"SerialNumber":"test-0001"}`。範例的 key 產生方式選 `CreateKeysAndCertificate`。成功時把範例回的裝置憑證與私鑰存成 `dev.crt`、`dev.key`。

```bash
# 開通後（操作者的終端機）
THING="$PFX-test-0001"
aws iot describe-thing --thing-name "$THING" --query '{type:thingTypeName,attrs:attributes,version:version}'
aws iot list-thing-groups-for-thing --thing-name "$THING" --query 'thingGroups[].groupName'
aws iot list-thing-principals --thing-name "$THING"
for c in $(aws iot list-thing-principals --thing-name "$THING" --query 'principals[]' --output text); do
  aws iot list-attached-policies --target "$c" --query 'policies[].policyName' --output text
  aws iot describe-certificate --certificate-id "${c##*/}" --query 'certificateDescription.status' --output text
done
```

【裝置端】接著做三個負面測試：

1. claim 憑證 publish 到 provisioning 以外的 topic（應該被斷線）：

   ```bash
   mosquitto_pub --cafile AmazonRootCA1.pem --cert claim.crt --key claim.key -h "$IOT_DATA" -p 8883 \
     -i claim-test -t "$PFX/telemetry/$PFX-test-0001" -m '{}' -d
   ```

2. 用 SDK 範例改走 `CreateCertificateFromCsr`（裝置自己產生私鑰）。依〈結論〉第 2 點，預期這一步被拒。
3. 同序號第二次開通：用 `{"SerialNumber":"test-0001"}` 再跑一次範例，然後重跑上面的 `list-thing-principals`。

【寫入】收尾：把測試 thing 的憑證停用並刪除（REFERENCE:217 的順序：detach policy、`INACTIVE`、detach principal、刪憑證、刪 thing）。

名稱怎麼來的：template 的 thing 名稱是 `Fn::Join` 出的 `"${local.name_prefix}-<SerialNumber>"`、thing type `"${local.name_prefix}-device"`、群組只有 `-unverified`、附加 `-device` policy（`fleet/fleet.tf:118-120`、`:130`）；thing type 的 searchable attribute `serial`（`fleet/fleet.tf:5`、`:121`）；claim policy（`fleet/fleet.tf:69-91`）；provisioning role `"${local.name_prefix}-iot-provisioning"`（`iam-base/roles.tf:12`）。`$aws/certificates/create-from-csr/json` 是 AWS 的 topic 命名，不在 repo 裡。

**預期結果**

- template `enabled` 是 `true`、`type` 是 `FLEET_PROVISIONING`、`hook` 沒有值、role 是 `arn:aws:iam::<account>:role/<project>-<env>-iot-provisioning`；`templateBody` 的參數只有 `SerialNumber` 與 `AWS::IoT::Certificate::Id`。
- claim policy 的 Publish／Receive／Subscribe 只有 `$aws/certificates/create/*` 與 `$aws/provisioning-templates/<project>-<env>-fleet/provision/*`；`list-targets-for-policy` 只有 claim 憑證。
- 開通後：thing `<project>-<env>-test-0001` 存在，type `<project>-<env>-device`、`attributes.serial = test-0001`；群組只有 `<project>-<env>-unverified`；principal 是一張 `ACTIVE` 的憑證，只附加 `<project>-<env>-device`。
- 負面測試 1：client 被斷線（`mosquitto_pub -d` 看到連線關閉），訊息沒有進 Kinesis（第 6 項的 rule 沒有觸發）。
- 負面測試 2：記下結果。被拒時，備註「claim policy 不支援 CSR 開通」，給 platform team 開 issue 決定要不要加 `create-from-csr/*`。
- 負面測試 3：design 的期望是失敗、thing 只有一張憑證。若第二次成功、thing 有兩張 `ACTIVE` 憑證，記成**不通過**，design §4.1 控制 3 與 REFERENCE〈安全取捨〉要改寫。
- CloudTrail（第 16 項的查詢）沒有 provisioning role 的 `AccessDenied`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／CSR 開通 ______ ／同序號第二次開通 ______

## 2. 裝置 policy

**前提**：第 1 項開通出來的 `dev.crt`、`dev.key`，thing `$PFX-test-0001`（重做時先別刪）。core device 的部分在 S2 與第 3、4 項驗。

**指令**

```bash
aws iot get-policy --policy-name "$PFX-device" --query policyDocument --output text | jq .
aws iot get-policy --policy-name "$PFX-core" --query policyDocument --output text | jq .
```

【裝置端】正面與負面測試（`-d` 看連線狀態）：

```bash
T="$PFX-test-0001"
COMMON=(--cafile AmazonRootCA1.pem --cert dev.crt --key dev.key -h "$IOT_DATA" -p 8883 -d)

# 1. 自己的 client id、自己的 telemetry topic（應該成功）
mosquitto_pub "${COMMON[@]}" -i "$T" -t "$PFX/telemetry/$T" \
  -m "{\"@timestamp\":\"$(date -u +%FT%TZ)\",\"temp\":21.5}"

# 2. 自己的 cmd topic 與 jobs topic（應該成功，Ctrl-C 結束）
mosquitto_sub "${COMMON[@]}" -i "$T" -t "$PFX/cmd/$T" -t "\$aws/things/$T/jobs/notify-next"

# 3. 別人的 client id（應該連不上）
mosquitto_pub "${COMMON[@]}" -i "$PFX-other" -t "$PFX/telemetry/$PFX-other" -m '{}'

# 4. 自己的 client id、別人的 topic（應該被斷線）
mosquitto_pub "${COMMON[@]}" -i "$T" -t "$PFX/telemetry/$PFX-other" -m '{}'

# 5. 推論 topic 只給 core device（應該被斷線）
mosquitto_pub "${COMMON[@]}" -i "$T" -t "$PFX/inference/$T" -m '{}'
```

【寫入】在另一個終端機發一則 cmd 給它，確認測試 2 收得到：

```bash
aws iot-data publish --endpoint-url "https://$IOT_DATA" --topic "$PFX/cmd/$PFX-test-0001" \
  --cli-binary-format raw-in-base64-out --payload '{"cmd":"ping"}'
```

失敗的連線與 publish 應該留在 IoT logging（ERROR 等級，`WARN` 會記到）：

```bash
aws logs filter-log-events --log-group-name AWSIotLogsV2 --start-time $(( ($(date +%s) - 900) * 1000 )) \
  --filter-pattern '{ $.status = "Failure" }' --query 'events[].message' --output text | head -20
```

名稱怎麼來的：裝置 policy（`fleet/fleet.tf:23-41`），`${iot:Connection.Thing.ThingName}` 是 `fleet/fleet.tf:18`；topic 命名 `<project>-<env>/telemetry/<thing>`、`/cmd/<thing>`、`/inference/<thing>`（REFERENCE:287）；log group `AWSIotLogsV2`（`iam-base/policies.tf:49`）。log 的 JSON 欄位 `status` 是 AWS IoT logging 的格式（推測）。

**預期結果**

- 測試 1 成功（`PUBACK` 或沒有斷線），第 6 項的 S3 `raw/` 之後看得到這筆。
- 測試 2 訂閱成功，`iot-data publish` 的訊息收得到。
- 測試 3 連線被拒；測試 4、5 被斷線。
- `AWSIotLogsV2` 有對應的 `Failure` 事件（如果沒有，記在第 8 項）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 3. core device 拿 AWS 憑證

**前提**

- S2 完成：`$PFX-core-001` 存在，憑證附加 `-device` 與 `-core` policy，`core.crt`、`core.key` 在 core device 上。
- `com.example.Inference` 的 artifact 已上傳到 `s3://$GG_BUCKET/artifacts/com.example.Inference/1.0.0/inference.zip`（第 5 項）。
- 要驗 log：【寫入】暫時在 `edge/envs/dev.tfvars` 的 `deployments.core.components` 加 `"aws.greengrass.LogManager" = "<版本>"` 再 apply `edge`（`aws.` 開頭的元件不需要 recipe 檔，`edge/deployments.tf:15`、`:25`）。驗完拿掉。

**指令**

```bash
aws iot describe-role-alias --role-alias "$PFX-greengrass-tes" \
  --query 'roleAliasDescription.{role:roleArn,duration:credentialDurationSeconds}'
aws iam get-role --role-name "$PFX-greengrass-tes" --query 'Role.AssumeRolePolicyDocument' | jq .
```

【裝置端】不經 Greengrass，直接用憑證換 TES 憑證（credentials provider 的 URL 格式是 AWS 的慣例，推測）：

```bash
curl -s --cert core.crt --key core.key --cacert AmazonRootCA1.pem \
  -H "x-amzn-iot-thingname: $PFX-core-001" \
  "https://$IOT_CRED/role-aliases/$PFX-greengrass-tes/credentials" > tes.json
jq '.credentials | {expiration, has_key: (.accessKeyId != null)}' tes.json

export AWS_ACCESS_KEY_ID=$(jq -r .credentials.accessKeyId tes.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r .credentials.secretAccessKey tes.json)
export AWS_SESSION_TOKEN=$(jq -r .credentials.sessionToken tes.json)
aws sts get-caller-identity
aws s3 cp "s3://$GG_BUCKET/artifacts/com.example.Inference/1.0.0/inference.zip" /tmp/inference.zip   # 應該成功
aws s3api get-bucket-location --bucket "$GG_BUCKET"                                                    # 記下結果（〈結論〉第 3 點）
aws s3 ls "s3://$GG_BUCKET/"                                                                           # 應該 AccessDenied
aws s3 cp "s3://$OTA_BUCKET/signed/current/firmware.bin" /tmp/fw.bin                                    # 應該 AccessDenied
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

一般裝置的憑證也試一次（應該被拒，因為 `-device` policy 沒有 `iot:AssumeRoleWithCertificate`）：

```bash
curl -s -o /dev/null -w '%{http_code}\n' --cert dev.crt --key dev.key --cacert AmazonRootCA1.pem \
  -H "x-amzn-iot-thingname: $PFX-test-0001" "https://$IOT_CRED/role-aliases/$PFX-greengrass-tes/credentials"
```

log（LogManager 部署後）：

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/greengrass/ --query 'logGroups[].[logGroupName,kmsKeyId]' --output text
```

CloudTrail 看 credentials provider 的呼叫與 `aws:SourceAccount`：

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | select(.requestParameters.roleArn // "" | endswith("-greengrass-tes"))
  | "\(.eventTime) \(.userIdentity.invokedBy // .userIdentity.type) \(.errorCode // "OK")"'
```

名稱怎麼來的：role alias `"${local.name_prefix}-greengrass-tes"`、`credential_duration = 3600`（`fleet/fleet.tf:17`、`:97`）；core policy 的 `iot:AssumeRoleWithCertificate`（`fleet/fleet.tf:59`）；TES role 名稱、trust `credentials.iot.amazonaws.com` 加 `aws:SourceAccount`（`iam-base/roles.tf:34-35`、`modules/iam-role/main.tf:33`）；權限（`iam-base/policies.tf:72-104`）；artifact 路徑（`edge/components/com.example.Inference/1.0.0.json:31`，REFERENCE 說的是 `templates/example5/edge/components/...`）。LogManager 建的 log group 名稱（`/aws/greengrass/GreengrassSystemComponent/<region>/System`、`/aws/greengrass/UserComponent/<region>/<component>`）是 AWS 的慣例（推測）。

**預期結果**

- role alias 指向 `<project>-<env>-greengrass-tes`，`duration` 是 3600。trust 有 `StringEquals aws:SourceAccount = <account>`。
- core 憑證的 `curl` 拿到憑證，`get-caller-identity` 是 `assumed-role/<project>-<env>-greengrass-tes/...`。**這一步成功就表示 credentials provider 有送 `aws:SourceAccount`**（或不檢查）；失敗是 `403`，訊息記在備註，`source_account` 的條件要拿掉或改。
- artifact 下載成功（SSE-KMS 的 `kms:Decrypt` 夠用）；`ls` 與 OTA bucket 都是 `AccessDenied`。
- `get-bucket-location` 的結果記下；如果第 4 項 Greengrass 下載 artifact 失敗、錯誤是 `GetBucketLocation`，就是〈結論〉第 3 點成立。
- 一般裝置的 `curl` 回 `403`。
- LogManager 部署後，`/aws/greengrass/` 底下有 log group，而且有新的 log。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`source_account` ______ ／`GetBucketLocation` ______

## 4. Greengrass 部署

**前提**

- 階段 F：S2 完成、Greengrass 已在 core device 上執行、`$PFX-core-001` 在 `-core` 群組；第 5 項的 artifact 已上傳。
- `edge` 的 `deployments.core` 用 Nucleus `2.14.3`、StreamManager `2.2.1`、`com.example.Inference 1.0.0`（`edge/envs/dev.tfvars:13-15`）。這兩個 AWS 元件版本是佔位（design §14:596），安裝 Greengrass 時 nucleus 版本要跟這裡一樣，否則部署會升級或降級 nucleus。
- dev 的 rollout 每分鐘 10 台、失敗 10% 中止，sit 每分鐘 20 台、5%；`min_number_of_executed_things` 預設 10（`edge/variables.tf:11`）。只有一台 core device 時，abort 條件不會觸發。

**指令**

```bash
# 元件版本
COMP_ARN="arn:aws:greengrass:$AWS_REGION:$ACCOUNT:components:com.example.Inference:versions:1.0.0"
aws greengrassv2 describe-component --arn "$COMP_ARN" --query '{status:status.componentState,msg:status.message,errors:status.errors}'
aws greengrassv2 get-component --arn "$COMP_ARN" --recipe-output-format JSON --query recipe --output text | base64 --decode | jq '.ComponentConfiguration, .Manifests[0].Artifacts'

# 部署
aws greengrassv2 list-deployments --target-arn "$GROUP_CORE_ARN" --history-filter ALL \
  --query 'deployments[].[deploymentName,deploymentId,deploymentStatus,creationTimestamp]' --output table
DEP_ID=$(aws ssm get-parameter --name "/$P/$E/edge/deployment_ids" --query Parameter.Value --output text | cut -d, -f1)
aws greengrassv2 get-deployment --deployment-id "$DEP_ID" \
  --query '{name:deploymentName,status:deploymentStatus,policies:deploymentPolicies,job:iotJobConfiguration,components:components}' | jq .

# 裝置端的狀態
aws greengrassv2 get-core-device --core-device-thing-name "$PFX-core-001" --query '{status:status,platform:platform,arch:architecture,nucleus:coreVersion}'
aws greengrassv2 list-effective-deployments --core-device-thing-name "$PFX-core-001" \
  --query 'effectiveDeployments[].[deploymentName,coreDeviceExecutionStatus,reason]' --output table
aws greengrassv2 list-installed-components --core-device-thing-name "$PFX-core-001" \
  --query 'installedComponents[].[componentName,componentVersion,lifecycleState]' --output table

# unverified 的裝置不該收到部署（S2 也會看）
aws greengrassv2 list-deployments --target-arn "$GROUP_UNVERIFIED_ARN" --query 'deployments[].deploymentName'
```

**`inline_recipe` 的 plan drift**（design §11:492、§14:574）：

```bash
cd templates/example5/infra/terraform
./stacks.sh "$E" edge plan -- -detailed-exitcode; echo "exit=$?"     # 0 沒有變更、2 有變更
./stacks.sh "$E" edge plan -- -refresh-only -detailed-exitcode; echo "exit=$?"
```

有變更時，把 plan 裡 `module.component[...]` 的差異（哪個屬性從什麼變成什麼）貼在備註。

【寫入】replace 的行為：把 `edge/envs/dev.tfvars` 的 `rollout.maximum_per_minute` 從 10 改成 11，plan、apply，再跑上面的 `list-deployments` 與 SSM 的 `deployment_ids`；做完改回 10。

【寫入】`ROLLBACK`：新增 `edge/components/com.example.Inference/1.0.1.json`（複製 1.0.0，`ComponentVersion` 改 `1.0.1`、`Run` 改成 `exit 1`、artifact 路徑改 `1.0.1`，並上傳同一個 zip 到 `artifacts/com.example.Inference/1.0.1/`），把部署改成 `1.0.1` 後 apply。觀察：

```bash
aws greengrassv2 list-effective-deployments --core-device-thing-name "$PFX-core-001" \
  --query 'effectiveDeployments[0].[deploymentName,coreDeviceExecutionStatus,reason]' --output text
aws greengrassv2 list-installed-components --core-device-thing-name "$PFX-core-001" \
  --query 'installedComponents[?componentName==`com.example.Inference`].[componentVersion,lifecycleState]' --output text
```

復原：部署改回 `1.0.0` 並 apply；部署不再引用 1.0.1 之後才刪檔案（REFERENCE:180）。

【寫入】abort：只有一台 core device 時，暫時把 `abort.min_number_of_executed_things` 設成 `1`、再部署一次壞掉的 1.0.1，看 IoT job 是否被取消：

```bash
JOB_ID=$(aws greengrassv2 get-deployment --deployment-id "<新的部署 id>" --query iotJobId --output text)
aws iot describe-job --job-id "$JOB_ID" --query 'job.{status:status,reason:reasonCode,abort:abortConfig}'
```

【寫入】拿掉元件：把 `aws.greengrass.StreamManager` 從 `components` 拿掉、apply，看 `list-installed-components` 是否少了它；驗完加回去。

【裝置端】device 上的 log（路徑是 Greengrass 的預設，推測）：

```bash
sudo tail -n 50 /greengrass/v2/logs/greengrass.log
```

名稱怎麼來的：部署名稱 `"${local.name_prefix}-${k}"`，`k` 是 `core`，所以是 `<project>-<env>-core`；target 是 `fleet/thing_group_core_arn`（`edge/deployments.tf:2-5`、`:11-12`）；自訂元件加 `TopicPrefix`（`edge/deployments.tf:15`）；rollout 與 abort（`edge/deployments.tf:18-19`）；`failure_handling` 預設 `ROLLBACK`、`component_update.action` 預設 `NOTIFY_COMPONENTS`（`modules/greengrass-deployment/variables.tf:83`、`:95`）；abort 的 action 固定 `CANCEL`（`modules/greengrass-deployment/main.tf:47`）；`inline_recipe = jsonencode(local.recipe)`（`modules/greengrass-component/main.tf:14`）；recipe 用 `templatefile` 帶入 bucket（`edge/components.tf:7-9`）；`deployment_ids` 群組部署在前（`edge/ssm-outputs.tf:8`）。元件 ARN 的格式是 AWS 的慣例（推測）。

**預期結果**

- 元件狀態 `DEPLOYABLE`；recipe 裡 artifact 的 `Uri` 是 `s3://<project>-<env>-greengrass-artifacts-<account>/artifacts/com.example.Inference/1.0.0/inference.zip`。
- 部署 `<project>-<env>-core`：`failureHandlingPolicy = ROLLBACK`、`componentUpdatePolicy.action = NOTIFY_COMPONENTS`、rollout `maximumPerMinute` 等於 tfvars、abort 是 `CANCEL`／`FAILED`／threshold 等於 tfvars／`minNumberOfExecutedThings = 10`；`com.example.Inference` 的 `configurationUpdate.merge` 是 `{"TopicPrefix":"<project>-<env>"}`，AWS 元件沒有 merge。
- core device `HEALTHY`，nucleus 版本等於 tfvars；effective deployment `SUCCEEDED`；三個元件 `RUNNING`（Nucleus 是 `FINISHED` 或 `RUNNING`）。
- `unverified` 群組沒有部署。
- drift：兩次 plan 都是 `exit=0`。`exit=2` 而且是 `inline_recipe` 的差異時記成**不通過**：module 要加 `lifecycle { ignore_changes = [inline_recipe] }`（design §11:492 的處理）。
- replace：plan 顯示部署 `must be replaced`；apply 後 `list-deployments` 有新的 id，舊的變 `CANCELED` 或查不到；`deployment_ids` 換成新的 id；裝置上的元件不受影響。
- `ROLLBACK`：effective deployment `FAILED`，`com.example.Inference` 回到 `1.0.0`、`RUNNING`。
- abort：job `CANCELED`，`reasonCode` 跟 abort 有關。
- 拿掉 StreamManager 後裝置上的 StreamManager 被解除安裝。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／drift ______ ／abort 有沒有實測 ______

## 5. 範例推論元件

**前提**

- 範本只有 recipe（`edge/components/com.example.Inference/1.0.0.json`），`main.py`、`requirements.txt`、模型都不在 repo（REFERENCE:300）。執行人要自己寫一個最小的 `main.py`：用 Greengrass IPC 訂閱 `<TopicPrefix>/telemetry/+`、用 ONNX Runtime 跑 `model.onnx`、把結果 publish 到 `<TopicPrefix>/inference/<thing name>`；`requirements.txt` 至少有 `onnxruntime`、`awsiotsdk`。
- 訂閱要用 `<TopicPrefix>/telemetry/+`，**不要用** `+/telemetry/+`：core policy 的 Subscribe 只放行 `topicfilter/<project>-<env>/telemetry/*`（`fleet/fleet.tf:56`），以 `+` 開頭的 topic filter 比對不到（推測，依 IoT policy 對 topic filter 的比對方式）。recipe 的 IPC 授權寫 `+/telemetry/+`（`1.0.0.json:16`），這是授權範圍，不是訂閱的 filter。
- zip 的根目錄放 `main.py`、`requirements.txt`、`model.onnx`。recipe 用 `{artifacts:decompressedPath}/inference/...`（`1.0.0.json:26-27`），Greengrass 會把 `inference.zip` 解到同名的 `inference/` 目錄（推測，Greengrass 的慣例）。

【寫入】上傳：

```bash
aws s3 cp inference.zip "s3://$GG_BUCKET/artifacts/com.example.Inference/1.0.0/inference.zip"
```

**指令**

【裝置端】元件的 log（路徑是 Greengrass 的預設，推測）：

```bash
sudo tail -n 50 /greengrass/v2/logs/com.example.Inference.log
```

【寫入】送一筆假的 telemetry，看推論結果有沒有出來（推論結果經第 6 項的 `_inference` rule 進 Kinesis 與 S3）：

```bash
aws iot-data publish --endpoint-url "https://$IOT_DATA" --topic "$PFX/telemetry/$PFX-test-0001" \
  --cli-binary-format raw-in-base64-out --payload "{\"@timestamp\":\"$(date -u +%FT%TZ)\",\"temp\":21.5}"

# 15 分鐘內（Firehose S3 的 buffering_interval 是 900 秒）
aws s3 ls "s3://$TELEMETRY_BUCKET/raw/" --recursive | tail -5
# 下載最新一個物件，找 kind = inference
KEY=$(aws s3 ls "s3://$TELEMETRY_BUCKET/raw/" --recursive | sort | tail -1 | awk '{print $4}')
aws s3 cp "s3://$TELEMETRY_BUCKET/$KEY" - | gunzip | grep '"kind":"inference"' | head -3
```

名稱怎麼來的：recipe（`edge/components/com.example.Inference/1.0.0.json:8-33`）；`TopicPrefix` 由部署 merge（`edge/deployments.tf:15`）；core policy 的推論 topic（`fleet/fleet.tf:56-58`）；rule 加的 `kind`（`ingest/rules.tf:23`）；Firehose 的 `raw/` 與 900 秒（`ingest/firehose.tf:9`、`:12`）。

**預期結果**

- 元件 `RUNNING`，`Install` 的 `pip install` 成功（core device 要能連 PyPI）；log 有收到 telemetry 與 publish 的紀錄，沒有 IPC 授權錯誤。
- S3 `raw/` 有 `kind: inference`、`thing_name: <project>-<env>-core-001` 的紀錄。
- 不通過時記下是哪一段：`pip`、ONNX Runtime 載入、IPC 授權、IoT policy（`AWSIotLogsV2` 有 core device 的 `Failure`）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／core device 的 OS 與架構 ______

## 6. IoT rule → Kinesis → Firehose

**前提**：階段 C 完成；第 2 項的 telemetry 或第 5 項的 `iot-data publish` 已經送過資料。OpenSearch 的部分要在 Client VPN 上看（第 7 項）。

**指令**

```bash
for r in "${RULE_PFX}_telemetry" "${RULE_PFX}_inference"; do
  aws iot get-topic-rule --rule-name "$r" \
    --query 'rule.{sql:sql,ver:awsIotSqlVersion,actions:actions,error:errorAction,disabled:ruleDisabled}' | jq -c .
done

aws kinesis describe-stream-summary --stream-name "$PFX-telemetry" \
  --query 'StreamDescriptionSummary.{status:StreamStatus,enc:EncryptionType,key:KeyId,shards:OpenShardCount}'

for f in "$PFX-to-raw" "$PFX-to-search"; do
  aws firehose describe-delivery-stream --delivery-stream-name "$f" \
    --query 'DeliveryStreamDescription.{status:DeliveryStreamStatus,source:Source.KinesisStreamSourceDescription.KinesisStreamARN,enc:DeliveryStreamEncryptionConfiguration}' | jq -c .
done

# 有資料進 stream、Firehose 有送出
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords \
  --dimensions Name=StreamName,Value="$PFX-telemetry" --statistics Sum --period 300 \
  --start-time "$(date -u -v-1H +%FT%TZ 2>/dev/null || date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)"
aws s3 ls "s3://$TELEMETRY_BUCKET/raw/" --recursive | tail -3
aws s3 ls "s3://$TELEMETRY_BUCKET/errors/" --recursive | tail -3
aws logs filter-log-events --log-group-name "/aws/kinesisfirehose/$PFX-to-search" --limit 10 --query 'events[].message' --output text
```

【寫入】error action：暫時讓 rule role 寫不進 Kinesis，確認失敗的訊息進 SSE-KMS 的 `rule-errors`。做完一定要刪掉這條 deny（它不在 Terraform 裡）。

```bash
aws iam put-role-policy --role-name "$PFX-iot-rule" --policy-name runbook-deny-kinesis \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":[\"kinesis:PutRecord\",\"kinesis:PutRecords\"],\"Resource\":\"$STREAM_ARN\"}]}"
sleep 30
aws iot-data publish --endpoint-url "https://$IOT_DATA" --topic "$PFX/telemetry/$PFX-test-0001" \
  --cli-binary-format raw-in-base64-out --payload '{"runbook":"error-action"}'
sleep 30
aws sqs receive-message --queue-url "$RULE_ERRORS_URL" --max-number-of-messages 1 --wait-time-seconds 10 \
  --query 'Messages[0].Body' --output text | jq .
aws iam delete-role-policy --role-name "$PFX-iot-rule" --policy-name runbook-deny-kinesis
```

收到的訊息看完就用 `delete-message` 刪掉，否則第 19 項的 `rule-errors-received` 告警會一直是 `ALARM`。

名稱怎麼來的：rule 名稱與 SQL（`ingest/rules.tf:17-26`）；Kinesis action 的 partition key `${topic(3)}`（`ingest/rules.tf:13`）；error action 寫 `rule-errors`（`ingest/rules.tf:30-36`）；stream `"${local.name_prefix}-telemetry"`（`storage/stream.tf:5`）；Firehose 名稱（`ingest/firehose.tf:4`、`:20`）與 log group `/aws/kinesisfirehose/<name>`（`modules/firehose-stream/main.tf:4`）；rule role `"${local.name_prefix}-iot-rule"`（`iam-base/roles.tf:7`），trust 用 `ArnLike aws:SourceArn` 限 `rule/<prefix 換底線>_*`（`iam-base/roles.tf:8`、`iam-base/naming.tf:32`）。

**預期結果**

- 兩條 rule：`awsIotSqlVersion = 2016-03-23`、一個 `kinesis` action（stream `<project>-<env>-telemetry`、partition key `${topic(3)}`）、`errorAction` 是 `sqs`；`ruleDisabled = false`。
- stream `ACTIVE`、`KMS`、key 是共用 CMK、1 個 shard。
- 兩條 Firehose `ACTIVE`，source 都是這個 stream。
- `IncomingRecords` 有值；`raw/` 有 GZIP 物件，內容有 `thing_name`、`kind`；`errors/` 沒有物件；`to-search` 的 log 沒有錯誤。
- error action：`rule-errors` 收到一則訊息（內容是失敗的 action 與原訊息，格式依 AWS），表示 rule role 寫得進 SSE-KMS 的 queue。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 7. OpenSearch

**前提**：階段 G。在 Client VPN 上（第 20 項）或 VPC 內執行。master 帳密在 `$PFX/opensearch-master`（`foundation/secrets.tf:4`）。完整的檢查清單與 master 密碼輪替跟 example4 相同，這裡只做 example5 特有的部分（index 名稱、`@timestamp`）與最小的健康檢查。

**指令**

```bash
aws opensearch describe-domain --domain-name "$DOMAIN" \
  --query 'DomainStatus.{ver:EngineVersion,hot:ClusterConfig.InstanceCount,warm:ClusterConfig.WarmCount,cold:ClusterConfig.ColdStorageOptions.Enabled,vpc:VPCOptions.SubnetIds}'

# 以下在 VPN 上；帳密不經過指令參數（從 secret 讀進 netrc 格式的暫存檔）
aws secretsmanager get-secret-value --secret-id "$PFX/opensearch-master" --query SecretString --output text \
  | jq -r --arg h "$OS_ENDPOINT" '"machine \($h) login \(.username) password \(.password)"' > /tmp/os.netrc
chmod 600 /tmp/os.netrc
curl -s --netrc-file /tmp/os.netrc "https://$OS_ENDPOINT/_cluster/health" | jq '{status, number_of_nodes}'
curl -s --netrc-file /tmp/os.netrc "https://$OS_ENDPOINT/_cat/indices/$PFX-events*?v"
curl -s --netrc-file /tmp/os.netrc "https://$OS_ENDPOINT/$PFX-events*/_search?size=1" | jq '.hits.hits[0]._source'
curl -s --netrc-file /tmp/os.netrc "https://$OS_ENDPOINT/_plugins/_ism/explain/$PFX-events*" | jq 'del(.total_managed_indices)'
rm -f /tmp/os.netrc
```

不在 VPN 上時，同一個 `curl` 應該連不到（DNS 解出私有 IP）。

名稱怎麼來的：domain `"${local.name_prefix}-search"`（`search/domain.tf:3`）；index `"${local.name_prefix}-events"`（`ingest/firehose.tf:25`）；ISM 與 index template 的 pattern `<prefix>-events*`、`@timestamp` 是 `date`（`search-config/config.tf:4`、`:31-36`）；dev 的天數 3／7／30（`search-config/envs/dev.tfvars:7-9`）；2 台 warm（`search/envs/dev.tfvars:19`）。

**預期結果**

- hot 2、warm 2、cold 開啟；domain 在 data subnet。
- cluster `green`；`<project>-<env>-events` 存在、有文件，`_source` 有 `@timestamp`、`thing_name`、`kind`。
- ISM explain：index 掛著 search-config 的 policy。dev 第 3 天後在 warm、第 7 天後在 cold（cold 要 `@timestamp`，REFERENCE:170）；沒有 `failed`。
- 第 19 項的 `hot-to-warm-migration-failed`、`warm-to-cold-migration-failed` 維持 `OK`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／進 warm、cold 的日期 ______

## 8. 帳號層 IoT 設定

**前提**

- 階段 0 先記下 apply 前的設定（帳號裡可能已經有別的專案的設定，REFERENCE:118）：

  ```bash
  mkdir -p runbook-snapshots
  aws iot get-v2-logging-options > runbook-snapshots/logging-before.json
  aws iot get-indexing-configuration > runbook-snapshots/indexing-before.json
  aws iot describe-event-configurations > runbook-snapshots/events-before.json
  aws iot describe-account-audit-configuration > runbook-snapshots/audit-before.json
  ```

  有任何一個不是預設值、而且不是這個專案設的，**先停下來**：這個帳號已經有別的專案管帳號層設定，`fleet` 的 `account_settings` 與 `device_defender_audit` 要設 `null`（REFERENCE:118）。
- 階段 C 完成。

**指令**

```bash
aws iot get-v2-logging-options
aws iot get-indexing-configuration \
  --query '{thing:thingIndexingConfiguration.{mode:thingIndexingMode,conn:thingConnectivityIndexingMode},group:thingGroupIndexingConfiguration.thingGroupIndexingMode}'
aws iot describe-event-configurations --query 'eventConfigurations'
aws logs describe-log-groups --log-group-name-prefix AWSIotLogsV2 --query 'logGroups[].[logGroupName,retentionInDays,kmsKeyId]' --output text

# fleet indexing 查得到 thing 與連線狀態
aws iot search-index --query-string "thingName:$PFX-*" --query 'things[].[thingName,connectivity.connected]' --output text
```

同帳號第二個專案不互蓋（只在要共用帳號時做，需要第二個專案的 `foundation`、`pki`、`storage`、`iam-base`）：【寫入】第二個專案的 `fleet` 設 `account_settings = null`、`device_defender_audit = null` 並 apply，之後重跑上面四個指令，跟第一個專案 apply 後的結果比對。

名稱怎麼來的：indexing、logging、event 的值（`fleet/account-settings.tf:4-19`）；`log_level = "WARN"`（`fleet/envs/dev.tfvars:8`）；logging role `"${local.name_prefix}-iot-logging"`（`iam-base/roles.tf:17`），只能寫 `AWSIotLogsV2`（`iam-base/policies.tf:45-50`）；provider 刪除時不呼叫 AWS（`modules/iot-account-settings/main.tf:1-2`）。

**預期結果**

- logging：`roleArn` 是 `<project>-<env>-iot-logging`、`defaultLogLevel = WARN`、`disableAllLogs = false`。
- indexing：thing `REGISTRY`、connectivity `STATUS`、group `ON`。
- event：`THING`、`THING_GROUP_MEMBERSHIP`、`JOB`、`JOB_EXECUTION`、`CERTIFICATE` 都是 `Enabled: true`。
- `AWSIotLogsV2` 存在，第 2 項的失敗事件有寫進去。記下 `retentionInDays` 與 `kmsKeyId`（log group 由 IoT 自己建，範本沒有設保留期與 CMK）。
- `search-index` 列出第 1 項、S2 的 thing，`connected` 反映目前連線狀態。
- 第二個專案（有做時）：apply 後四份設定跟第一個專案 apply 後一樣。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／apply 前帳號已有設定 □ 有 □ 無 ／`AWSIotLogsV2` 保留期 ______

## 9. Device Defender

**前提**：階段 C、E 完成；SNS 訂閱已確認。`device_defender_audit = {}`（`fleet/envs/dev.tfvars:13`）。

**指令**

```bash
# 帳號 audit 設定：8 個 check 開、其他 9 個關；通知送告警 topic
aws iot describe-account-audit-configuration --output json | jq '{
  role: .roleArn,
  sns: .auditNotificationTargetConfigurations,
  enabled: [.auditCheckConfigurations | to_entries[] | select(.value.enabled) | .key] | sort,
  disabled: [.auditCheckConfigurations | to_entries[] | select(.value.enabled | not) | .key] | sort }'

aws iot describe-scheduled-audit --scheduled-audit-name "$PFX-weekly"
aws iot describe-mitigation-action --action-name "$PFX-quarantine" --query '{role:roleArn,params:actionParams}'
```

【寫入】跑一次 on-demand audit，看 check 能不能跑、結果有沒有送到 SSE-KMS 的告警 topic：

```bash
TASK=$(aws iot start-on-demand-audit-task --target-check-names \
  LOGGING_DISABLED_CHECK CA_CERTIFICATE_EXPIRING_CHECK DEVICE_CERTIFICATE_EXPIRING_CHECK DEVICE_CERTIFICATE_SHARED_CHECK \
  CONFLICTING_CLIENT_IDS_CHECK IOT_POLICY_OVERLY_PERMISSIVE_CHECK IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK \
  REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK --query taskId --output text)
aws iot describe-audit-task --task-id "$TASK" --query '{status:taskStatus,stats:taskStatistics,checks:auditDetails}'
aws iot list-audit-findings --task-id "$TASK" \
  --query 'findings[].[checkName,severity,nonCompliantResource.resourceType,nonCompliantResource.resourceIdentifier]' --output json
```

【寫入】mitigation：做一個會被 `DEVICE_CERTIFICATE_EXPIRING_CHECK` 抓到的測試裝置（有效期 7 天的自簽憑證），再對 finding 套用 `$PFX-quarantine`：

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 7 \
  -subj "/CN=$PFX-dd-test" -keyout dd.key -out dd.crt
DD_CERT_ARN=$(aws iot register-certificate-without-ca --certificate-pem file://dd.crt --status ACTIVE --query certificateArn --output text)
aws iot create-thing --thing-name "$PFX-dd-test" --thing-type-name "$PFX-device"
aws iot attach-thing-principal --thing-name "$PFX-dd-test" --principal "$DD_CERT_ARN"

TASK=$(aws iot start-on-demand-audit-task --target-check-names DEVICE_CERTIFICATE_EXPIRING_CHECK --query taskId --output text)
# 等 taskStatus 變 COMPLETED
aws iot describe-audit-task --task-id "$TASK" --query taskStatus
aws iot start-audit-mitigation-actions-task --task-id "runbook-$(date +%s)" \
  --target auditTaskId="$TASK" \
  --audit-check-to-actions-mapping DEVICE_CERTIFICATE_EXPIRING_CHECK="$PFX-quarantine"
aws iot list-thing-groups-for-thing --thing-name "$PFX-dd-test" --query 'thingGroups[].groupName'
```

收尾：把 `$PFX-dd-test` 移出 quarantine、detach principal、憑證 `INACTIVE` 後刪除、刪 thing。

名稱怎麼來的：8 個 check（`fleet/device-defender.tf:5-14`）；排程 `"${local.name_prefix}-weekly"`、每週一（`fleet/device-defender.tf:26`）；mitigation `"${local.name_prefix}-quarantine"` 把 thing 加進 `<prefix>-quarantine`（`fleet/device-defender.tf:31-33`）；API 名稱對 awscc 屬性的對照，`audit.checks` 沒列的一律停用（`modules/iot-device-defender/main.tf:4-22`、`:36-38`）；audit role 與 mitigation role（`iam-base/roles.tf:22`、`:27`；權限 `iam-base/policies.tf:53-69`）。`ADD_THINGS_TO_THING_GROUP` 能用在 `DEVICE_CERTIFICATE_EXPIRING_CHECK` 的 finding 是 AWS 文件的說法（推測）。

**預期結果**

- `enabled` 剛好是上面 8 個，`disabled` 是其他 9 個（含 `IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK`，這個名稱對照最容易錯，design §14:577）；`role` 是 `<project>-<env>-iot-audit`；`sns.SNS.targetArn` 是告警 topic、`enabled = true`。
- 排程 `WEEKLY`、`MON`，check 清單一樣。mitigation 的 `addThingsToThingGroupParams.thingGroupNames` 是 `[<project>-<env>-quarantine]`。
- on-demand audit `COMPLETED`，每個 check 都不是 `FAILED`（`FAILED` 多半是 audit role 權限不夠，看 CloudTrail）；告警 email 收到 audit 結果（SSE-KMS topic 加 audit role 的 `kms:GenerateDataKey`）。
- 先講的預測：`IOT_POLICY_OVERLY_PERMISSIVE_CHECK` 很可能對 `<project>-<env>-claim` 報 finding（`iot:Connect` 的 Resource 是 `client/*`，`fleet/fleet.tf:73`），也可能對 `-core` 的 Greengrass `*` 報（`fleet/fleet.tf:62-64`）。這兩個是設計上的取捨，記在備註，不算不通過。
- mitigation：`$PFX-dd-test` 出現在 `<project>-<env>-quarantine`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／finding 清單 ______

## 10. OTA

**前提**

- 〈前置作業的細節〉第 4 項：code signing 憑證已匯入 ACM，ARN 填進 `fleet` 的 `ota_signing_certificate_arn`。
- 測試 thing 用第 1 項的 `$PFX-test-0001`（`-device` policy 有 jobs topic 的權限，`fleet/fleet.tf:31-39`）。
- 一台裝置時 abort（至少執行 10 台才判斷）不會觸發，只驗 job 建立、job document、presigned URL。

**指令**

```bash
aws signer get-signing-profile --profile-name "$SIGNING_PROFILE" \
  --query '{status:status,platform:platformId,cert:signingMaterial.certificateArn}'
CERT_ARN=$(aws signer get-signing-profile --profile-name "$SIGNING_PROFILE" --query signingMaterial.certificateArn --output text)
aws acm describe-certificate --certificate-arn "$CERT_ARN" \
  --query 'Certificate.{alg:KeyAlgorithm,eku:ExtendedKeyUsages[].Name,ku:KeyUsages[].Name,notAfter:NotAfter,status:Status}'

aws iot describe-job-template --job-template-id "$PFX-ota" \
  --query '{doc:document,presigned:presignedUrlConfig,rollout:jobExecutionsRolloutConfig,abort:abortConfig,timeout:timeoutConfig}' | jq .
```

【寫入】簽一個假韌體、建 job、取 job document：

```bash
head -c 1024 /dev/urandom > firmware.bin
aws s3 cp firmware.bin "s3://$OTA_BUCKET/unsigned/firmware.bin"
VID=$(aws s3api head-object --bucket "$OTA_BUCKET" --key unsigned/firmware.bin --query VersionId --output text)
SJ=$(aws signer start-signing-job --profile-name "$SIGNING_PROFILE" \
  --source "s3={bucketName=$OTA_BUCKET,key=unsigned/firmware.bin,version=$VID}" \
  --destination "s3={bucketName=$OTA_BUCKET,prefix=signed/}" --query jobId --output text)
aws signer describe-signing-job --job-id "$SJ" --query '{status:status,reason:statusReason,signed:signedObject}'
# 簽好的物件複製成 job template 下載的固定路徑
SIGNED_KEY=$(aws signer describe-signing-job --job-id "$SJ" --query signedObject.s3.key --output text)
aws s3 cp "s3://$OTA_BUCKET/$SIGNED_KEY" "s3://$OTA_BUCKET/signed/current/firmware.bin"

JOB=runbook-ota-$(date +%s)
aws iot create-job --job-id "$JOB" --job-template-arn "$JOB_TEMPLATE_ARN" \
  --targets "arn:aws:iot:$AWS_REGION:$ACCOUNT:thing/$PFX-test-0001"
aws iot describe-job --job-id "$JOB" --query 'job.{status:status,rollout:jobExecutionsRolloutConfig,abort:abortConfig,timeout:timeoutConfig}'

# job document 的 presigned URL 是否能下載（DescribeJobExecution 是否回解析後的 URL，推測）
URL=$(aws iot-jobs-data describe-job-execution --endpoint-url "https://$IOT_DATA" \
  --thing-name "$PFX-test-0001" --job-id "$JOB" --query 'execution.jobDocument' --output text | jq -r '.files[0].url')
echo "$URL" | cut -c1-120
curl -s -o downloaded.bin -w '%{http_code}\n' "$URL"
cmp downloaded.bin <(aws s3 cp "s3://$OTA_BUCKET/signed/current/firmware.bin" -) && echo "內容一致"

aws iot cancel-job --job-id "$JOB" --force
```

`unsigned/` 不在 `ota-presign` role 的範圍裡；CI 實際放未簽韌體的位置由 CI 決定，這裡只是測試用。

名稱怎麼來的：Signer profile 名稱與 platform（`fleet/ota.tf:5-9`）；job template `"${local.name_prefix}-ota"`、document 的 `${aws:iot:s3-presigned-url:https://s3.amazonaws.com/<bucket>/signed/current/firmware.bin}`、presigned 1 小時、rollout、abort、60 分鐘 timeout（`fleet/ota.tf:13-24`）；ota bucket `"${local.name_prefix}-ota-artifacts-${var.expected_account_id}"`（`storage/buckets.tf:25`）；`ota-presign` role 只能讀 `signed/*`（`iam-base/roles.tf:39`、`iam-base/policies.tf:107`）。Signer 輸出物件的 key 格式是 Signer 的慣例（推測），上面用 `describe-signing-job` 取。

**預期結果**

- profile `Active`、platform `AWSIoTDeviceManagement-SHA256-ECDSA`、憑證是匯入的那張。憑證 `KeyAlgorithm` 是 `EC_prime256v1`（或你選的），`ExtendedKeyUsages` 含 `CODE_SIGNING`，`Status` 是 `ISSUED`。REFERENCE:117「憑證要符合 Signer 的要求」以簽章 job 成功為準。
- job template：document 的 URL 是 `s3.amazonaws.com` 的 path-style；`presignedUrlConfig.roleArn` 是 `<project>-<env>-ota-presign`、`expiresInSec = 3600`；rollout 與 abort 等於 tfvars；timeout 60。
- 簽章 job `Succeeded`。
- job `IN_PROGRESS`；`describe-job-execution` 回的 URL 已經是 presigned（帶 `X-Amz-Signature`），`curl` 回 `200`、內容一致。
- 不通過時注意：bucket 在 Tokyo，URL 用全域的 `s3.amazonaws.com`，S3 可能回 `301`／`307` 或簽章錯誤（推測）。這時記下 HTTP 狀態與錯誤，job template 要改成 `s3.<region>.amazonaws.com`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／presigned URL 的 HTTP 狀態 ______

## 11. KVS edge connector

**前提**

- 階段 J。core device `$PFX-core-001` 是 Linux、在 `-core` 群組、附加 `-core` policy（REFERENCE:243）。
- 至少兩台攝影機接同一台 core device（驗「多個 `ConnectedCameras-<id>` hierarchy」），例如 id `cam-a`、`cam-b`。沒有真實攝影機時，在 core device 上用 RTSP server 加 `ffmpeg` 推兩路測試影片（推測可行）。
- 【寫入】照 REFERENCE:130-136 建兩個 RTSP secret `$PFX/cameras/cam-a`、`$PFX/cameras/cam-b`（`--kms-key-id "$KMS_KEY"`）。
- 【寫入】`sitewise/envs/dev.tfvars` 與 `edge/envs/dev.tfvars` 的 `cameras` 加一模一樣的兩筆（`core_thing_name = "<project>-dev-core-001"`、`rtsp_secret_arn`、`retention_hours = 24`），依序 apply `sitewise`、`edge`。

**指令**

```bash
ASSETS=$(ssm sitewise/edge_connector_asset_ids); echo "$ASSETS" | jq .
HUB_ID=$(jq -r --arg t "$PFX-core-001" '.hubs[$t]' <<<"$ASSETS")

# hub：HubName 屬性、兩個 hierarchy、兩個子 asset
aws iotsitewise describe-asset --asset-id "$HUB_ID" \
  --query '{name:assetName,status:assetStatus.state,props:assetProperties[].name,hier:assetHierarchies[].[name,id]}'
for h in $(aws iotsitewise describe-asset --asset-id "$HUB_ID" --query 'assetHierarchies[].id' --output text); do
  aws iotsitewise list-associated-assets --asset-id "$HUB_ID" --hierarchy-id "$h" --query 'assetSummaries[].name' --output text
done

# camera model 的屬性與預設值
for id in cam-a cam-b; do
  CAM_ID=$(jq -r --arg c "$id" '.cameras[$c]' <<<"$ASSETS")
  MODEL_ID=$(aws iotsitewise describe-asset --asset-id "$CAM_ID" --query assetModelId --output text)
  aws iotsitewise describe-asset-model --asset-model-id "$MODEL_ID" \
    --query 'assetModelProperties[].[name,dataType,type.attribute.defaultValue || `measurement`]' --output table
done

# KVS stream 與 CMK
for id in cam-a cam-b; do
  aws kinesisvideo describe-stream --stream-name "$PFX-cam-$id" \
    --query 'StreamInfo.{status:Status,kms:KmsKeyId,retention:DataRetentionInHours,device:DeviceName}'
done

# thing 層級的部署
aws greengrassv2 list-deployments --target-arn "arn:aws:iot:$AWS_REGION:$ACCOUNT:thing/$PFX-core-001" \
  --query 'deployments[].[deploymentName,deploymentStatus]' --output text
aws greengrassv2 list-installed-components --core-device-thing-name "$PFX-core-001" \
  --query 'installedComponents[].[componentName,componentVersion,lifecycleState]' --output table
```

【寫入】觸發直播（屬性名稱與 `NOW` 的用法依 AWS 的 edge connector 文件，推測）：

```bash
CAM_A=$(jq -r '.cameras["cam-a"]' <<<"$ASSETS")
NOW=$(date +%s)
aws iotsitewise batch-put-asset-property-value --entries "[
  {\"entryId\":\"1\",\"assetId\":\"$CAM_A\",\"propertyId\":\"<LiveStreamingStartTime 的 property id>\",
   \"propertyValues\":[{\"value\":{\"stringValue\":\"NOW\"},\"timestamp\":{\"timeInSeconds\":$NOW}}]},
  {\"entryId\":\"2\",\"assetId\":\"$CAM_A\",\"propertyId\":\"<LiveStreamingDurationInMinutes 的 property id>\",
   \"propertyValues\":[{\"value\":{\"integerValue\":5},\"timestamp\":{\"timeInSeconds\":$NOW}}]}]"

EP=$(aws kinesisvideo get-data-endpoint --stream-name "$PFX-cam-cam-a" --api-name LIST_FRAGMENTS --query DataEndpoint --output text)
aws kinesis-video-archived-media list-fragments --endpoint-url "$EP" --stream-name "$PFX-cam-cam-a" \
  --max-results 5 --query 'Fragments[].[FragmentNumber,ProducerTimestamp]' --output text
```

property id 用 `aws iotsitewise describe-asset --asset-id "$CAM_A" --query 'assetProperties[].[name,id]'` 查。cam-b 照做一次。

TES role 的權限夠不夠（含 `ListAssets` 能否限縮到 `asset-model/*`，design §14:597）：

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=iotsitewise.amazonaws.com \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | select(.userIdentity.arn // "" | contains("-greengrass-tes/"))
  | "\(.eventTime) \(.eventName) \(.errorCode // "OK")"'
```

【裝置端】edge connector 的 log（路徑推測）：`sudo tail -n 100 /greengrass/v2/logs/aws.iot.EdgeConnectorForKVS.log`。

名稱怎麼來的：hub 與 camera 的 model、asset 名稱 `<prefix>-hub-<thing>`、`<prefix>-cam-<id>`（`sitewise/sitewise.tf:10-11`）；camera model 的 11 個屬性與預設值（`sitewise/sitewise.tf:17-28`）；hub 的 `HubName` 與 `ConnectedCameras-<id>`（`sitewise/sitewise.tf:37-38`）；asset 的 parent（`sitewise/sitewise.tf:44-52`）；SSM 的 JSON（`sitewise/ssm-outputs.tf:5-8`）；KVS stream `"${local.name_prefix}-cam-${id}"`、`device_name` 是 core thing（`edge/kvs.tf:4`），用共用 CMK（`edge/kvs.tf:14`）；thing 部署 `"${local.name_prefix}-kvs-${t}"`、元件與 `SiteWiseAssetIdForHub`（`edge/deployments.tf:54-60`）；TES role 的 KVS、secret、SiteWise 權限（`iam-base/policies.tf:80-100`）。

**預期結果**

- SSM 的 JSON 有 `cameras.cam-a`、`cameras.cam-b`、`hubs.<project>-dev-core-001`。
- hub `ACTIVE`，有 `HubName` 與兩個 hierarchy，各自接到一台攝影機。
- camera model 有 7 個 attribute（預設值跟 `sitewise.tf` 一致，`KinesisVideoStreamName` 等於 stream 名稱、`RTSPStreamSecretARN` 等於 secret ARN）與 4 個 measurement。
- 兩個 stream `ACTIVE`、`KmsKeyId` 是共用 CMK、保留 24 小時。
- 部署 `<project>-dev-kvs-<project>-dev-core-001` 成功，裝置上 `aws.iot.EdgeConnectorForKVS` 是 `RUNNING`。
- 直播觸發後，**兩台**攝影機的 stream 都有 fragment。只有一台有，就是 edge connector 只認一個 hierarchy（design §14:595 不成立）。
- CloudTrail 沒有 TES role 的 `AccessDenied`。有 `ListAssets` 的 `AccessDenied` 時，§14:597 不成立，`iam-base` 要放寬這個動作的 Resource。
- 改 RTSP secret 或攝影機數量時 model 是 in-place 還是 replace（REFERENCE:250）：之後加第三台時看 plan，記在備註。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／兩台都有 fragment □ ／`ListAssets` ______

## 12. SiteWise gateway

**前提**

- 階段 J。core device 同第 11 項。
- 【寫入】`sitewise/envs/dev.tfvars` 加 `gateways = { gw = { core_device_thing_name = "<project>-dev-core-001" } }`，apply `sitewise`。
- 範本的部署沒有 SiteWise Edge 的元件。要讓 gateway 真的連上，【寫入】在 `edge` 的 `deployments.core.components` 加 SiteWise Edge 的元件（例如 `aws.iot.SiteWiseEdgePublisher`，版本自己核對），apply `edge`。沒有 OPC-UA 資料來源時，只驗 gateway 建立與 publisher 連線。

**指令**

```bash
aws iotsitewise list-gateways --query "gatewaySummaries[?gatewayName=='$PFX-gw'].[gatewayId,gatewayPlatform]" --output json
GW_ID=$(aws iotsitewise list-gateways --query "gatewaySummaries[?gatewayName=='$PFX-gw'].gatewayId | [0]" --output text)
aws iotsitewise describe-gateway --gateway-id "$GW_ID" \
  --query '{platform:gatewayPlatform,caps:gatewayCapabilitySummaries[].[capabilityNamespace,capabilitySyncStatus]}'
```

TES role 寫 SiteWise 的權限（gateway 用 TES）：用第 11 項的 CloudTrail 查詢，看 `BatchPutAssetPropertyValue` 有沒有 `AccessDenied`。

名稱怎麼來的：gateway 名稱 `"${local.name_prefix}-${k}"`（`sitewise/sitewise.tf:54`）；module 只在 `cameras` 或 `gateways` 不空時建立（`sitewise/sitewise.tf:61`）。SiteWise Edge 元件名稱取自 `modules/iotsitewise/README.md`〈注意〉。

**預期結果**

- gateway 存在，`gatewayPlatform.greengrassV2.coreDeviceThingName` 是 core device。
- 部署 SiteWise Edge 元件後，capability 的 `capabilitySyncStatus` 是 `IN_SYNC`。
- TES role 沒有 `AccessDenied`。有的話，記下動作與 Resource：TES 的 SiteWise 權限只到 `asset/*`、`asset-model/*`（`iam-base/policies.tf:100`），gateway 寫入用 alias 的資料流可能不在範圍內（推測）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 13. 訓練與核准

**前提**

- 階段 C 完成、`ml` 已 apply。dev 的排程是 `DISABLED`（`ml/envs/dev.tfvars:6`）。
- 【寫入】建三個 ECR repository `$PFX-preprocess`、`$PFX-train`、`$PFX-inference`，推 tag `1.0.0` 的 image（repo 沒有提供）。preprocess 的 entrypoint 是 `python3 /opt/program/preprocess.py`（`ml/pipelines/training.json:17`）；train 要能跑 SageMaker 的訓練合約；inference 要能跑 SageMaker 的 serving 合約（第 14 項用）。
- 【寫入】訓練資料放 `s3://$ML_BUCKET/training-data/`。

**指令**

```bash
aws sagemaker describe-pipeline --pipeline-name "$PIPELINE" --query '{status:PipelineStatus,role:RoleArn}'
aws sagemaker describe-pipeline --pipeline-name "$PIPELINE" --query PipelineDefinition --output text \
  | jq '.Parameters, [.Steps[] | {Name, Type, role: .Arguments.RoleArn}]'
aws scheduler get-schedule --name "$PFX-weekly-training" --group-name default \
  --query '{state:State,expr:ScheduleExpression,tz:ScheduleExpressionTimezone,kms:KmsKeyArn,target:Target.Arn,role:Target.RoleArn}'
aws events describe-rule --name "$PFX-model-approved" --query '{state:State,pattern:EventPattern}'
aws events list-targets-by-rule --rule "$PFX-model-approved" --query 'Targets[].[Id,Arn]' --output text
aws sqs get-queue-attributes --queue-url "$MODEL_Q_URL" --attribute-names KmsMasterKeyId Policy RedrivePolicy \
  --query Attributes | jq '.Policy |= fromjson'
```

【寫入】手動跑一次 pipeline：

```bash
EXEC=$(aws sagemaker start-pipeline-execution --pipeline-name "$PIPELINE" --query PipelineExecutionArn --output text)
aws sagemaker describe-pipeline-execution --pipeline-execution-arn "$EXEC" --query '{status:PipelineExecutionStatus,reason:FailureReason}'
aws sagemaker list-pipeline-execution-steps --pipeline-execution-arn "$EXEC" \
  --query 'PipelineExecutionSteps[].[StepName,StepStatus,FailureReason]' --output table
aws sagemaker list-model-packages --model-package-group-name "$MPG" \
  --query 'ModelPackageSummaryList[].[ModelPackageArn,ModelApprovalStatus]' --output text
```

【寫入】Scheduler 用 CMK 與 scheduler role 觸發 pipeline（不改 Terraform 的排程，另建一個 5 分鐘後觸發、跑完自動刪除的一次性排程）：

```bash
AT=$(date -u -v+5M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '+5 min' +%Y-%m-%dT%H:%M:%S)
aws scheduler create-schedule --name runbook-training-once --schedule-expression "at($AT)" \
  --flexible-time-window Mode=OFF --kms-key-arn "$KMS_KEY" --action-after-completion DELETE \
  --target "{\"Arn\":\"arn:aws:sagemaker:$AWS_REGION:$ACCOUNT:pipeline/$PIPELINE\",\"RoleArn\":\"$(ssm iam-base/role_scheduler_arn)\",\"SageMakerPipelineParameters\":{\"PipelineParameterList\":[]}}"
# 5 分鐘後
aws sagemaker list-pipeline-executions --pipeline-name "$PIPELINE" --max-results 3 \
  --query 'PipelineExecutionSummaries[].[StartTime,PipelineExecutionStatus,PipelineExecutionDisplayName]' --output text
```

【寫入】核准，看事件是否進 SSE-KMS 的 queue、欄位是否正確：

```bash
PKG=$(aws sagemaker list-model-packages --model-package-group-name "$MPG" --sort-by CreationTime --sort-order Descending \
  --query 'ModelPackageSummaryList[0].ModelPackageArn' --output text)
aws sagemaker update-model-package --model-package-arn "$PKG" --model-approval-status Approved
MSG=$(aws sqs receive-message --queue-url "$MODEL_Q_URL" --wait-time-seconds 20 --max-number-of-messages 1 --output json)
jq -r '.Messages[0].Body | fromjson | {source, "detail-type", arn: .detail.ModelPackageArn, group: .detail.ModelPackageGroupName, status: .detail.ModelApprovalStatus}' <<<"$MSG"
# 範本外沒有 CI 在消費：看完就刪，否則第 19 項的 oldest-message-age 告警一天後會響
aws sqs delete-message --queue-url "$MODEL_Q_URL" --receipt-handle "$(jq -r '.Messages[0].ReceiptHandle' <<<"$MSG")"
```

沒收到訊息時，看 rule 的 `FailedInvocations`：

```bash
aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations \
  --dimensions Name=RuleName,Value="$PFX-model-approved" --statistics Sum --period 300 \
  --start-time "$(date -u -v-1H +%FT%TZ 2>/dev/null || date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)"
```

名稱怎麼來的：pipeline 與 definition 的帶入值（`ml/pipeline.tf:8-17`）；image 佔位與 `models/training/` 輸出（`ml/pipelines/training.json:7-9`、`:54`）；排程名稱 `"${local.name_prefix}-weekly-training"`、`cron(0 3 ? * MON *)`、`Asia/Taipei`（`ml/schedule.tf:4-7`）、排程 group 預設 `default`（`modules/scheduler-schedule/main.tf:12`）；rule 名稱與 event pattern（`ml/approval.tf:5-12`）；queue policy 只放行這條 rule（`storage/queues.tf:5-6`、`:17`，`modules/sqs-queue/main.tf:54-60`）；scheduler role 只能 start 這個 pipeline、能 `kms:Decrypt`（`iam-base/policies.tf:190-194`）；KMS key policy 允許 `events.amazonaws.com`、`scheduler.amazonaws.com`（`foundation/kms.tf:23-37`）。

**預期結果**

- pipeline `Active`，role 是 `<project>-<env>-sagemaker-pipeline`；三個 step 的 `RoleArn` 都是同一個 role。
- 排程：dev `DISABLED`、sit `ENABLED`；`KmsKeyArn` 是共用 CMK；target 是 pipeline ARN、role 是 `<project>-<env>-scheduler`。
- rule `ENABLED`，pattern 跟 `approval.tf` 一致；target 是 `model-approved` queue；queue 用共用 CMK、有 redrive；policy 的 `aws:SourceArn` 是 `arn:aws:events:<region>:<account>:rule/<project>-<env>-model-approved`。
- pipeline 執行 `Succeeded`，三個 step 都成功；group 有一個 `PendingManualApproval` 的版本。失敗時記下哪個 step、`FailureReason`，並跑第 16 項的 CloudTrail 查詢（pipeline role 的動作清單是依文件寫的）。
- 一次性排程觸發了一次 pipeline 執行，之後排程自己刪掉。
- 核准後 queue 收到一則訊息：`source = aws.sagemaker`、`detail-type = SageMaker Model Package State Change`、`detail.ModelPackageArn`、`detail.ModelPackageGroupName`、`detail.ModelApprovalStatus = Approved`（REFERENCE:198 的欄位名稱）。欄位名稱不同時，把實際的 JSON 貼在備註，REFERENCE 那一段要改。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／pipeline 執行時間 ______ ／SQS 欄位 ______

## 14. 雲端推論

**前提**

- 第 13 項完成，group 裡有一個 `Approved` 的版本，`$PFX-inference:1.0.0` 是能 serving 的 image。
- 【寫入】`inference/envs/dev.tfvars` 設 `model_package_arn = "<第 13 項核准的 ARN>"`，apply `inference`。
- 費用：一台 `ml.m5.large` 每月約 109 美元，驗完設回 `null` 再 apply。

**指令**

```bash
aws sagemaker describe-endpoint --endpoint-name "$PFX-inference" \
  --query '{status:EndpointStatus,reason:FailureReason,config:EndpointConfigName,deploy:DeploymentConfig}'
CFG=$(aws sagemaker describe-endpoint --endpoint-name "$PFX-inference" --query EndpointConfigName --output text)
aws sagemaker describe-endpoint-config --endpoint-config-name "$CFG" \
  --query '{kms:KmsKeyId,variants:ProductionVariants[].[VariantName,InstanceType,ModelName],capture:DataCaptureConfig}'
MODEL=$(aws sagemaker describe-endpoint-config --endpoint-config-name "$CFG" --query 'ProductionVariants[0].ModelName' --output text)
aws sagemaker describe-model --model-name "$MODEL" \
  --query '{isolation:EnableNetworkIsolation,vpc:VpcConfig,role:ExecutionRoleArn,pkg:Containers[0].ModelPackageName}'
```

【寫入】呼叫與 data capture：

```bash
aws sagemaker-runtime invoke-endpoint --endpoint-name "$PFX-inference" \
  --content-type application/json --body '<你的模型吃的 JSON>' --cli-binary-format raw-in-base64-out out.json && cat out.json
# 多呼叫幾次（取樣 20%），幾分鐘後
aws s3 ls "s3://$ML_BUCKET/capture/" --recursive | tail -5
```

【寫入】blue/green 自動 rollback：註冊並核准第二個版本（第 13 項再跑一次），把 `model_package_arn` 改成新版本、apply；在烘烤的 600 秒內把其中一條 rollback 告警設成 `ALARM`：

```bash
aws cloudwatch set-alarm-state --alarm-name "$PFX-endpoint-5xx-errors" --state-value ALARM --state-reason "runbook rollback 測試"
aws sagemaker describe-endpoint --endpoint-name "$PFX-inference" \
  --query '{status:EndpointStatus,config:EndpointConfigName,last:LastDeploymentConfig}'
```

apply 的結果（成功、失敗、錯誤訊息）與 rollback 後 Terraform state 是否跟實際一致（再跑一次 `plan`），都記在備註。

【寫入】serverless 範例：先 `model_package_arn = null` apply（instance 不能直接轉 serverless，`modules/sagemaker-endpoint/README.md`〈注意〉），再：

```bash
./stacks.sh "$E" inference apply -- -var-file=envs/examples/inference-serverless.tfvars   # ARN 先換成核准的版本
aws sagemaker describe-endpoint-config --endpoint-config-name "$(aws sagemaker describe-endpoint --endpoint-name "$PFX-inference" --query EndpointConfigName --output text)" \
  --query 'ProductionVariants[0].ServerlessConfig'
```

名稱怎麼來的：endpoint `"${local.name_prefix}-inference"`、variant `primary`（`inference/endpoint.tf:6-7`）；告警名稱 `<prefix>-endpoint-5xx-errors`、`<prefix>-endpoint-model-latency`（`inference/endpoint.tf:13`、`:18`，底線換連字號：`modules/metric-alarm/main.tf:2`）；instance、VPC、network isolation、data capture、blue/green（`inference/endpoint.tf:34-46`）；endpoint role（`iam-base/roles.tf:55`、`iam-base/policies.tf:168-188`）；`sagemaker` SG 只開 VPC 網段的 443（`network/security-groups.tf:21-24`、`:56-59`）。

**預期結果**

- endpoint `InService`；config 有 KMS key、一個 `primary` variant（`ml.m5.large`）；model `EnableNetworkIsolation = true`、VPC 是 data subnet 與 `sagemaker` SG、role 是 `<project>-<env>-sagemaker-endpoint`。
- `Creating` 卡住或 `Failed` 時，記下 `FailureReason`。從程式碼看得到的兩個可能：`sagemaker` SG 的 egress 只到 VPC 網段（`network/security-groups.tf:58`），S3 gateway endpoint 的目的地是 S3 的 prefix list，不在 VPC 網段裡；如果模型是經 VPC 的 ENI 下載，會被 SG 擋（推測）。
- `invoke-endpoint` 回結果。
- data capture：依〈結論〉第 4 點，預期 `capture/` 沒有物件、CloudTrail 有 endpoint role 對 `capture/` 的 `PutObject` `AccessDenied`。有物件就是推測錯了，記下來。
- rollback：endpoint 回到原本的 config。
- serverless：`ServerlessConfig` 是 2048 MB、並發 5。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／data capture ______ ／rollback 時 Terraform 的行為 ______

## 15. pki

**前提**

- 階段 K。費用：general-purpose CA 每月約 400 美元，region 第一個 CA 有 30 天試用（REFERENCE:22）。在一天內做完並關閉。
- 【寫入】照 REFERENCE〈runbook：開啟 pki〉第 1–3 步：把 `pki/envs/examples/pki.tfvars` 的 `ca` 抄進 `pki/envs/dev.tfvars`（`ROOT`），apply `pki`，再 apply `fleet`。
- `SUBORDINATE` 要有上層 CA，沒有的話只驗 `ROOT`，`SUBORDINATE` 在結果紀錄寫「沒驗」。

**指令**

```bash
CA_JSON=$(ssm pki/ca); jq '{enabled, arn, has_pem: (.certificate_pem != null)}' <<<"$CA_JSON"
CA_ARN=$(jq -r .arn <<<"$CA_JSON")
aws acm-pca describe-certificate-authority --certificate-authority-arn "$CA_ARN" \
  --query 'CertificateAuthority.{status:Status,type:Type,usage:UsageMode,key:CertificateAuthorityConfiguration.KeyAlgorithm,cn:CertificateAuthorityConfiguration.Subject.CommonName,crl:RevocationConfiguration}'
aws iot list-ca-certificates --query 'certificates[].[certificateId,status,certificateMode]' --output table
```

【寫入】【裝置端】用這個 CA 簽一張裝置憑證、註冊、連線：

```bash
openssl ecparam -name prime256v1 -genkey -noout -out pki-dev.key
openssl req -new -key pki-dev.key -subj "/CN=$PFX-pki-test" -out pki-dev.csr
CERT=$(aws acm-pca issue-certificate --certificate-authority-arn "$CA_ARN" --csr fileb://pki-dev.csr \
  --signing-algorithm SHA256WITHECDSA --validity Value=30,Type=DAYS --query CertificateArn --output text)
aws acm-pca get-certificate --certificate-authority-arn "$CA_ARN" --certificate-arn "$CERT" --query Certificate --output text > pki-dev.crt
jq -r .certificate_pem <<<"$CA_JSON" > ca.pem

# SNI_ONLY 的 CA 下要怎麼註冊裝置憑證，以 AWS 回應為準（推測先試這個，失敗再試 register-certificate-without-ca）
PKI_CERT_ARN=$(aws iot register-certificate --certificate-pem file://pki-dev.crt --ca-certificate-pem file://ca.pem \
  --set-as-active --query certificateArn --output text)
aws iot create-thing --thing-name "$PFX-pki-test" --thing-type-name "$PFX-device"
aws iot attach-thing-principal --thing-name "$PFX-pki-test" --principal "$PKI_CERT_ARN"
aws iot attach-policy --policy-name "$PFX-device" --target "$PKI_CERT_ARN"

# mosquitto 連 hostname 時會送 SNI
mosquitto_pub --cafile AmazonRootCA1.pem --cert pki-dev.crt --key pki-dev.key -h "$IOT_DATA" -p 8883 -d \
  -i "$PFX-pki-test" -t "$PFX/telemetry/$PFX-pki-test" -m "{\"@timestamp\":\"$(date -u +%FT%TZ)\"}"
```

【寫入】撤銷：

```bash
# 1. 只在 ACM PCA 撤銷（沒有 CRL、OCSP），IoT Core 是否還接受
SERIAL=$(openssl x509 -in pki-dev.crt -noout -serial | cut -d= -f2)
aws acm-pca revoke-certificate --certificate-authority-arn "$CA_ARN" --certificate-serial "$SERIAL" --revocation-reason KEY_COMPROMISE
#    再跑一次上面的 mosquitto_pub

# 2. 在 IoT registry 設成 REVOKED（範本的撤銷方式）
aws iot update-certificate --certificate-id "${PKI_CERT_ARN##*/}" --new-status REVOKED
#    再跑一次上面的 mosquitto_pub
```

收尾：刪測試 thing 與憑證；`ca = null`，依序 apply `pki`、`fleet`（REFERENCE:227）。

名稱怎麼來的：CA 的 common name `"${local.name_prefix}-device-ca"`（`pki/ca.tf:8`），不開 CRL、OCSP（`pki/ca.tf:2`）；SSM 的 JSON（`pki/ssm-outputs.tf:5-9`）；`fleet` 讀到 `enabled` 就以 `SNI_ONLY` 註冊（`fleet/fleet.tf:137-138`、`modules/iot-fleet/main.tf:160-166`）。

**預期結果**

- CA `ACTIVE`、`ROOT`、`GENERAL_PURPOSE`、`EC_prime256v1`、CN 是 `<project>-dev-device-ca`、沒有 CRL 與 OCSP。
- IoT 的 CA 清單有一張 `ACTIVE`、`certificateMode = SNI_ONLY`。
- 裝置憑證註冊成功（記下用的是哪個指令），連線與 publish 成功。
- 撤銷 1：連線**仍然成功**，表示 IoT Core 不查 CA 的撤銷狀態（沒有 CRL 可查，design §14:570 的答案記在這裡）。
- 撤銷 2：連線失敗。
- 關閉後 IoT 的 CA 清單沒有這張 CA，ACM PCA 的狀態是 `DELETED`（保留期內可還原）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`SUBORDINATE` 有沒有驗 ______ ／註冊用的指令 ______

## 16. IAM 動作清單與 key policy

**前提**：其他項目做的同時跑。這一項的目標是收集「權限不夠」與「給太多」的證據，`iam-base`、`iam-app` 的動作清單與 `foundation` 的 key policy 都是照文件寫的（`iam-base/policies.tf:1-3`、`iam-app/firehose-policy.tf:1-3`、`foundation/kms.tf:2`）。

**指令**

每做完一項，查最近的 `AccessDenied`（CloudTrail 只回最近 90 天的管理事件，S3 物件層級的事件要另外開 data event 才看得到）：

```bash
aws cloudtrail lookup-events --start-time "$(date -u -v-3H +%FT%TZ 2>/dev/null || date -u -d '-3 hour' +%FT%TZ)" \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | select(.errorCode // "" | test("AccessDenied|Unauthorized|KMS"))
  | select(.userIdentity.arn // "" | contains("'"$PFX"'-"))
  | "\(.eventTime) \(.userIdentity.arn | split("/")[1]) \(.eventSource) \(.eventName) \(.errorCode)"'
```

有 `NextToken` 時要翻頁，或改用 CloudTrail Lake／Athena。

給太多的反向檢查（唯讀的模擬）：

```bash
sim() { aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$ACCOUNT:role/$1" \
  --action-names "$2" --resource-arns "$3" --query 'EvaluationResults[0].EvalDecision' --output text; }

sim "$PFX-greengrass-tes"      s3:GetObject              "arn:aws:s3:::$GG_BUCKET/other/x"                                   # implicitDeny
sim "$PFX-greengrass-tes"      secretsmanager:GetSecretValue "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT:secret:$PFX/opensearch-master-AbCdEf"   # implicitDeny
sim "$PFX-iot-rule"            kinesis:PutRecord         "arn:aws:kinesis:$AWS_REGION:$ACCOUNT:stream/other"                  # implicitDeny
sim "$PFX-iot-provisioning"    iot:AddThingToThingGroup  "arn:aws:iot:$AWS_REGION:$ACCOUNT:thinggroup/$PFX-fleet"            # implicitDeny
sim "$PFX-iot-mitigation"      iot:AddThingToThingGroup  "arn:aws:iot:$AWS_REGION:$ACCOUNT:thinggroup/$PFX-fleet"            # implicitDeny
sim "$PFX-ota-presign"         s3:GetObject              "arn:aws:s3:::$OTA_BUCKET/unsigned/firmware.bin"                    # implicitDeny
sim "$PFX-sagemaker-endpoint"  s3:PutObject              "arn:aws:s3:::$ML_BUCKET/capture/x"                                 # 見第 14 項
sim "$PFX-scheduler"           sagemaker:StartPipelineExecution "arn:aws:sagemaker:$AWS_REGION:$ACCOUNT:pipeline/other"      # implicitDeny

aws kms get-key-policy --key-id "$KMS_KEY" --policy-name default --output text | jq '.Statement[] | {Sid, Principal, Condition}'
```

名稱怎麼來的：11 個 role 的名稱（`iam-base/roles.tf:7-60`）；`*` 只用在 EC2 Describe、`ecr:GetAuthorizationToken`、11 個 IoT audit 讀取動作（`iam-base/policies.tf:10-16`，design §14:592）；key policy 的 service principal 與 condition（`foundation/kms.tf:3-38`）。

**預期結果**

- 所有項目做完，CloudTrail 沒有範本 role 的 `AccessDenied`。有的話逐筆記下 role、動作、Resource，開 issue 給 platform team（module 或 `iam-base` 的修改）。已知可能出現的：TES 的 `s3:GetBucketLocation`（第 3 項）、endpoint role 的 `capture/` `PutObject`（第 14 項）、TES 的 `iotsitewise:ListAssets`（第 11 項）。
- 模擬的結果都是 `implicitDeny`（endpoint role 那一行依第 14 項的結論）。
- key policy 被 KMS 接受（`foundation` apply 成功就是證據）；CloudWatch Logs、log delivery、CloudWatch、SNS、EventBridge、Scheduler 的使用都沒有 KMS 錯誤（第 6、9、13、19、21 項）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`AccessDenied` 清單 ______

## 17. 特權操作

**前提**：階段 A、C 完成。apply 用的身分固定是 deploy role，方便在 CloudTrail 篩選。

**指令**

```bash
DEPLOY_ROLE=<deploy role 名稱>

# awscc 經 Cloud Control 建的資源（eventSource 是 Cloud Control 的命名，推測）
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=cloudcontrolapi.amazonaws.com \
  --max-results 50 --output json | jq -r '.Events[].CloudTrailEvent | fromjson
  | "\(.eventTime) \(.eventName) \(.requestParameters.typeName // "-") \(.errorCode // "OK")"' | sort | uniq -c

# deploy role 被拒的動作
aws cloudtrail lookup-events --start-time "$(date -u -v-1d +%FT%TZ 2>/dev/null || date -u -d '-1 day' +%FT%TZ)" \
  --max-results 50 --output json | jq -r --arg r "$DEPLOY_ROLE" '.Events[].CloudTrailEvent | fromjson
  | select(.userIdentity.arn // "" | contains("/" + $r + "/"))
  | select(.errorCode // "" | test("AccessDenied|Unauthorized"))
  | "\(.eventSource) \(.eventName) \(.errorCode)"' | sort | uniq -c

# 帳號第一次建立服務時的 service-linked role
aws iam list-roles --path-prefix /aws-service-role/ --query 'Roles[].RoleName' --output text | tr '\t' '\n' \
  | grep -iE 'opensearch|clientvpn|sagemaker|iot' || echo "沒有相關的 service-linked role"
```

名稱怎麼來的：特權操作清單（REFERENCE:137-148、design §4:138）；用 awscc 的 stack 是 `fleet`、`sitewise`、`edge`（`fleet/versions.tf:10-13`，另兩個同樣有 `provider "awscc"`）。

**預期結果**

- Cloud Control 的事件類型涵蓋 `AWS::GreengrassV2::ComponentVersion`、`AWS::GreengrassV2::Deployment`、`AWS::IoT::JobTemplate`、`AWS::IoT::AccountAuditConfiguration`、`AWS::IoT::ScheduledAudit`、`AWS::IoT::MitigationAction`，有攝影機或 gateway 時加 `AWS::IoTSiteWise::AssetModel`、`AWS::IoTSiteWise::Asset`、`AWS::IoTSiteWise::Gateway`（KVS stream 用 aws provider，不經 Cloud Control，`modules/kinesis-video-stream/main.tf:1`）。
- 把 deploy role 實際用到的 `cloudformation:*Resource*` 動作，以及 Cloud Control 底下代呼叫的服務動作（例如 `greengrass:CreateDeployment`、`iot:CreateJobTemplate`）整理成清單，補進 REFERENCE:148（現在寫「完整清單沒有對真實帳號核對」）。
- deploy role 沒有被拒的動作；有的話補進清單並記下 stack。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／補充的動作清單 ______

## 18. destroy

**前提**

- 最後才做，只在 `dev`、而且確定這個環境不要了；或另開一個可以丟棄的 env。
- 先照 REFERENCE〈destroy 前要做的事〉（REFERENCE:258-275）清掉 Terraform 外的東西：開通出來的 thing 與憑證、claim 憑證、bucket 內容、OpenSearch 的 warm／cold index、model package 的版本。
- 下面幾個「沒有確認」的行為要刻意觀察，所以有幾步**故意不先清**，標在指令裡。

**指令**

```bash
# destroy 前的快照
aws iot get-v2-logging-options > runbook-snapshots/logging-before-destroy.json
aws iot get-indexing-configuration > runbook-snapshots/indexing-before-destroy.json
aws iot describe-account-audit-configuration > runbook-snapshots/audit-before-destroy.json
```

【寫入】依序：

1. `./stacks.sh dev inference destroy`。
2. `ml`：**先不刪** model package 的版本，`./stacks.sh dev ml destroy`，記下 group 刪不刪得掉、錯誤訊息；刪不掉就用 `aws sagemaker delete-model-package` 刪掉所有版本再 destroy 一次。
3. `edge`：destroy 後在 core device 上看元件（REFERENCE:263：裝置上的元件不會被移除）：

   ```bash
   aws greengrassv2 list-installed-components --core-device-thing-name "$PFX-core-001" \
     --query 'installedComponents[].[componentName,lifecycleState]' --output text
   ```

4. `sitewise`（有攝影機時）：destroy，記下 hierarchy 關聯是否擋住刪除順序。
5. `fleet`：**thing 先留一個在 `-unverified`**（例如第 1 項的測試 thing，憑證先 detach `-device` policy），destroy，記下 thing group 刪不刪得掉。之後：

   ```bash
   aws iot get-v2-logging-options                     # 跟快照比
   aws iot get-indexing-configuration
   aws iot describe-account-audit-configuration --query 'auditCheckConfigurations' | jq 'map_values(.enabled)'
   aws signer get-signing-profile --profile-name "$SIGNING_PROFILE" --query status
   ```

6. 同名 Signer profile 能否重建：`./stacks.sh dev fleet apply`（重建整個 `fleet`），記下 Signer profile 的錯誤。能重建就再 destroy 一次。
7. 其餘 stack：`./stacks.sh dev all destroy` 會從 `inference` 往回跑，已經拆掉的 stack 沒有資源，不影響。拆到 `search-config` 時要在 Client VPN 上（REFERENCE:256）。

名稱怎麼來的：destroy 的順序是 `ORDER` 反過來（`stacks.sh:73-77`）；帳號層設定刪除時 provider 不呼叫 AWS（`modules/iot-account-settings/main.tf:1-2`）；audit 設定刪除會讓 check 全部停用（`modules/iot-device-defender/README.md`〈注意〉）；Signer profile `"${replace(local.name_prefix, "-", "_")}_ota"`（`fleet/ota.tf:6`）。

**預期結果**

- model package group：記下「有版本時能不能刪」（REFERENCE:266）。
- 刪掉 Greengrass 部署後，裝置上的元件還在（跟 REFERENCE:263 一致）。
- SiteWise：記下是否要先解除關聯（REFERENCE:269）。
- thing group 裡還有 thing 時：記下能不能刪（REFERENCE:262）。
- 帳號層設定：logging、indexing 跟 destroy 前一樣（provider 不呼叫 AWS）；audit 的 check 全部 `false`（REFERENCE:271）。同帳號有其他專案在用 audit 時，這一步會影響它們。
- Signer profile 是 `Canceled`。第 6 步：同名 profile 很可能**建不起來**（推測：Signer 取消的 profile 名稱不能重用）；如果是這樣，`fleet` destroy 後再 apply 會失敗，REFERENCE:272 要寫明，`ota-signing` 可能要讓名稱帶版本或後綴。
- 全部 destroy 完，帳號裡只剩 REFERENCE:277 列的「destroy 不會刪」的東西。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／group 有版本時 ______ ／thing group 有 thing 時 ______ ／Signer 重建 ______

## 19. 告警

**前提**：階段 C 完成；SNS 的 email 訂閱已確認。`inference` 的告警只在第 14 項開 endpoint 時存在。

**要確認的告警名稱**（`metric-alarm` 把 key 的底線換成連字號：`modules/metric-alarm/main.tf:2`）

| stack | 名稱 | 指標與維度 | 出處 |
|---|---|---|---|
| `storage`（7 條） | `<prefix>-stream-write-throughput-exceeded`、`-stream-read-throughput-exceeded`、`-stream-iterator-age` | `AWS/Kinesis`，`StreamName=<prefix>-telemetry` | `storage/alarms.tf:4-7`、`:15-29` |
| | `<prefix>-rule-errors-received`、`-rule-errors-dlq-not-empty`、`-model-approved-oldest-message-age`、`-model-approved-dlq-not-empty` | `AWS/SQS`，`QueueName=<prefix>-rule-errors`、`-rule-errors-dlq`、`-model-approved`、`-model-approved-dlq` | `storage/alarms.tf:10-11`、`:32-52`；DLQ 名稱 `modules/sqs-queue/main.tf:4` |
| `ingest`（2 條） | `<prefix>-firehose-s3-data-freshness`、`-firehose-opensearch-data-freshness` | `AWS/Firehose`，`DeliveryStreamName=<prefix>-to-raw`、`-to-search` | `ingest/alarms.tf:4-27` |
| `search`（6 條） | `<prefix>-cluster-status-red`、`-free-storage-space`、`-jvm-memory-pressure`、`-warm-jvm-memory-pressure`、`-hot-to-warm-migration-failed`、`-warm-to-cold-migration-failed` | `AWS/ES`，`DomainName=<prefix>-search`、`ClientId=<account>` | `search/alarms.tf:3`、`:8-47` |
| `inference`（2 條，選配） | `<prefix>-endpoint-5xx-errors`、`-endpoint-model-latency` | `AWS/SageMaker`，`EndpointName=<prefix>-inference`、`VariantName=primary` | `inference/endpoint.tf:9-23` |

SNS topic 是 `<prefix>-alarms`（`foundation/alarms.tf:3`）。

**指令**

```bash
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table
aws cloudwatch describe-alarms --alarm-name-prefix "$PFX-" --query 'MetricAlarms[].[AlarmName,StateValue,Namespace,MetricName]' --output table

# 每條告警的維度都對得到實際的指標
for a in $(aws cloudwatch describe-alarms --alarm-name-prefix "$PFX-" --query 'MetricAlarms[].AlarmName' --output text); do
  read -r ns mn <<<"$(aws cloudwatch describe-alarms --alarm-names "$a" --query 'MetricAlarms[0].[Namespace,MetricName]' --output text)"
  dims=$(aws cloudwatch describe-alarms --alarm-names "$a" --query 'MetricAlarms[0].Dimensions' --output json \
    | jq -r 'map("Name=\(.Name),Value=\(.Value)") | join(" ")')
  printf '%-55s %s\n' "$a" "$(aws cloudwatch list-metrics --namespace "$ns" --metric-name "$mn" --dimensions $dims --query 'length(Metrics)')"
done
```

【寫入】通知路徑（SSE-KMS 的 topic，`sns.amazonaws.com` 與 `cloudwatch.amazonaws.com` 要能用 key：`foundation/kms.tf:20-21`）：

```bash
aws cloudwatch set-alarm-state --alarm-name "$PFX-rule-errors-received" --state-value ALARM --state-reason "runbook 通知測試"
```

真實觸發：第 6 項的 error action 會讓 `rule-errors-received` 響；第 13 項的訊息不刪、等一天會讓 `model-approved-oldest-message-age` 響（只在需要時做）。

**預期結果**

- 訂閱是完整 ARN，不是 `PendingConfirmation`。
- 上表的 15 條（開 endpoint 時 17 條）都存在。穩定時大多是 `OK`；SQS、Firehose 的告警在沒有流量時可能是 `INSUFFICIENT_DATA`。
- 維度檢查回 `1` 以上。SQS 的 queue 一段時間沒有活動時 CloudWatch 不發指標，回 `0` 不一定是維度錯，先送一則訊息再查。
- `set-alarm-state` 收到 email，表示 SSE-KMS 的 topic 收得到 CloudWatch 的通知。
- 門檻是起始值（REFERENCE:307），這裡不調；跑一段時間真實流量後另外調。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／維度回 0 的告警 ______

## 20. Client VPN

**前提**

- 【寫入】照 `vpn/envs/examples/vpn.tfvars` 把 `client_vpn` 抄進 `vpn/envs/dev.tfvars`，server 與 client root 憑證在 Terraform 外匯入 ACM，apply `vpn`。費用每月約 126 美元。
- 用 mutual TLS 的 client 憑證建好 VPN 設定檔（AWS Client VPN 的下載設定加上 client 憑證與私鑰）。

**指令**

```bash
VPN=$(ssm vpn/client_vpn); jq . <<<"$VPN"
EP_ID=$(jq -r .endpoint_id <<<"$VPN")
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$EP_ID" \
  --query 'ClientVpnEndpoints[0].{status:Status.Code,auth:AuthenticationOptions[].Type,log:ConnectionLogOptions}'
aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id "$EP_ID" \
  --query 'AuthorizationRules[].[DestinationCidr,Status.Code]' --output text
aws ssm get-parameter --name "/$P/$E/network/subnet_cidrs_data" --query Parameter.Value --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/client-vpn/$PFX-client-vpn" --query 'logGroups[].[logGroupName,kmsKeyId]' --output text
```

連上 VPN 之後：

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://$OS_ENDPOINT/"           # 401（要帳密），表示 443 通
# 不該通：app subnet 的任一位址（沒有東西在聽時看 timeout 與 refused 的差別不大，改看授權規則）
aws logs filter-log-events --log-group-name "/aws/client-vpn/$PFX-client-vpn" --limit 5 --query 'events[].message' --output text
```

名稱怎麼來的：endpoint 名稱 `"${local.name_prefix}-client-vpn"`、授權規則只來自 data subnet CIDR、用共用 CMK（`vpn/client-vpn.tf:4-5`、`:13-15`）；log group `/aws/client-vpn/<name>`（`modules/client-vpn/main.tf:2`）；`client_vpn` SG 只到 OpenSearch 443（`network/security-groups.tf:16`）。

**預期結果**

- endpoint `available`，認證是 `certificate-authentication`，連線 log 開啟。
- 授權規則只有 data subnet 的 CIDR（跟 `subnet_cidrs_data` 一樣），`active`。
- log group 存在、`kmsKeyId` 是共用 CMK，連線後有 log。
- VPN 上連得到 OpenSearch 的 443。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 21. flow log 與 state

**前提**：階段 A 完成；〈前置作業的細節〉第 1 項的 state CMK 與 bucket policy 已設好。

**指令**

```bash
FLOW_BUCKET=$(ssm foundation/flow_log_bucket_arn | sed 's|^arn:aws:s3:::||')
aws ec2 describe-flow-logs --filter Name=resource-id,Values="$(ssm network/vpc_id)" \
  --query 'FlowLogs[].{status:FlowLogStatus,dest:LogDestination,err:DeliverLogsErrorMessage}'
aws s3 ls "s3://$FLOW_BUCKET/" --recursive | tail -3        # 前綴是 AWSLogs/<account>/vpcflowlogs/...（AWS 的慣例，推測）
KEY=$(aws s3 ls "s3://$FLOW_BUCKET/" --recursive | tail -1 | awk '{print $4}')
aws s3api head-object --bucket "$FLOW_BUCKET" --key "$KEY" --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'

# state
STATE_BUCKET=<state-bucket>
aws s3api head-object --bucket "$STATE_BUCKET" --key "$PFX/fleet/terraform.tfstate" --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'
aws s3api get-bucket-versioning --bucket "$STATE_BUCKET"
```

lock 檔：在一個終端機跑 `./stacks.sh dev fleet plan`，同時在另一個終端機跑同一個指令。

名稱怎麼來的：flow log bucket `"${local.name_prefix}-flow-logs-${var.expected_account_id}"`、SSE-KMS（`foundation/log-buckets.tf:5-7`）；key policy 允許 `delivery.logs.amazonaws.com`（`foundation/kms.tf:12-19`）；`network` 送 flow log（`network/vpc.tf:13`、`network/envs/dev.tfvars:9`）；state key `<project>-<env>/<stack>/terraform.tfstate`、`encrypt`、`use_lockfile`、`kms_key_id`（`fleet/envs/dev.tfbackend:2-7`）。

**預期結果**

- flow log `ACTIVE`、沒有錯誤；bucket 有物件，`ServerSideEncryption = aws:kms`、key 是共用 CMK。
- state 物件用 state 專用 CMK 加密；bucket 開了 versioning。
- 第二個 `plan` 等鎖或報 lock 錯誤；第一個結束後 `.tflock` 消失。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

---

## 表上沒涵蓋的項目

### S1. claim 憑證設成 `INACTIVE`、開通的追查（design §4.1 控制 5、6）

**前提**：第 1 項完成，claim 憑證是 `ACTIVE`。

**指令**

【寫入】停用 claim 憑證：

```bash
aws iot update-certificate --certificate-id "$CLAIM_CERT_ID" --new-status INACTIVE
aws iot describe-certificate --certificate-id "$CLAIM_CERT_ID" --query certificateDescription.status
```

【裝置端】用同一張 claim 憑證再跑一次 fleet provisioning 範例（序號 `test-0002`）。

追查開通出來的裝置（REFERENCE:216 的第 3 步）：

```bash
# fleet indexing：unverified 群組裡有哪些 thing
aws iot search-index --query-string "thingGroupNames:$PFX-unverified" --query 'things[].[thingName,attributes.serial]' --output text
# IoT logging 有沒有開通的紀錄（WARN 等級，預期只有失敗的）
aws logs filter-log-events --log-group-name AWSIotLogsV2 --start-time $(( ($(date +%s) - 3600) * 1000 )) \
  --filter-pattern '"rovision"' --query 'events[].message' --output text | head -10
```

已開通的裝置不受影響（REFERENCE:215）：用第 1 項的 `dev.crt` 再跑一次第 2 項的測試 1。

名稱怎麼來的：輪替步驟（REFERENCE:210-217）；`thingGroupNames` 能查是因為 `thing_group_indexing_mode = "ON"`、thing 是 `REGISTRY`（`fleet/account-settings.tf:5-7`）；log 等級 `WARN`（`fleet/envs/dev.tfvars:8`）。`thingGroupNames` 欄位名稱是 fleet indexing 的查詢語法（推測）。

**預期結果**

- claim 憑證 `INACTIVE` 之後，開通失敗（TLS 或連線被拒），`test-0002` 不存在。
- `search-index` 列得出 `unverified` 裡的 thing。
- `AWSIotLogsV2` 只有失敗的開通紀錄，成功的沒有。是這樣的話，REFERENCE:216 的「查 `AWSIotLogsV2` 的開通紀錄」要改成「用 fleet indexing 查 `unverified` 群組」。
- 已開通的裝置照常 publish。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／成功的開通有沒有 log ______

### S2. core device 的開通：序號、`-core` policy、群組（REFERENCE〈前置作業的細節〉第 6 項、design §4.1 控制 4）

**前提**：claim 憑證是 `ACTIVE`（S1 之後要先換一張新的，照 REFERENCE:214）；core device 的 EC2 已開好。

**指令**

【裝置端】在 core device 上用 fleet provisioning 範例開通，序號 `core-001`，憑證存成 `core.crt`、`core.key`。

開通後先確認它還收不到部署，也還不能拿 AWS 憑證：

```bash
THING="$PFX-core-001"
aws iot list-thing-groups-for-thing --thing-name "$THING" --query 'thingGroups[].groupName'
CORE_CERT_ARN=$(aws iot list-thing-principals --thing-name "$THING" --query 'principals[0]' --output text)
aws iot list-attached-policies --target "$CORE_CERT_ARN" --query 'policies[].policyName'
```

【裝置端】這時用 `core.crt` 跑第 3 項的 `curl`，預期 `403`。

【寫入】人工確認後附加 `-core` policy、搬進 `-core` 群組（REFERENCE:129）：

```bash
aws iot attach-policy --policy-name "$PFX-core" --target "$CORE_CERT_ARN"
aws iot add-thing-to-thing-group --thing-group-name "$PFX-core" --thing-name "$THING"
aws iot remove-thing-from-thing-group --thing-group-name "$PFX-unverified" --thing-name "$THING"
aws iot list-thing-groups-for-thing --thing-name "$THING" --query 'thingGroups[].groupName'
```

【裝置端】安裝 Greengrass，用手動佈建的方式帶入既有的憑證（`config.yaml` 填 thing 名稱、`core.crt`、`core.key`、`AmazonRootCA1.pem`、role alias `$PFX-greengrass-tes`、`$IOT_DATA`、`$IOT_CRED`、region；installer 的版本跟 `edge` 釘的 nucleus 一樣）。安裝參數與 `config.yaml` 欄位依 AWS 的 Greengrass 文件（推測）。

```bash
aws greengrassv2 get-core-device --core-device-thing-name "$THING" --query '{status:status,nucleus:coreVersion}'
aws greengrassv2 list-effective-deployments --core-device-thing-name "$THING" \
  --query 'effectiveDeployments[].[deploymentName,coreDeviceExecutionStatus]' --output text
```

【寫入】序號不是 `core-` 開頭的反例：拿第 1 項的 `$PFX-test-0001`，附加 `-core` policy 後用它的憑證跑第 3 項的 `curl` 與 `mosquitto_pub -i "$PFX-test-0001" -t "\$aws/things/$PFX-test-0001/shadow/get"`。做完 detach。

名稱怎麼來的：core policy 用 `client/<prefix>-core-*` 與 `$aws/things/<prefix>-core-*/*`（`fleet/fleet.tf:19`、`:44-67`）；template 只附加 `-device`、只進 `-unverified`（`fleet/fleet.tf:120`、`:130`）；部署只對 `fleet`、`core`（`edge/variables.tf:20-23`）。

**預期結果**

- 開通後只在 `-unverified`、只附加 `-device`；`curl` 回 `403`；`unverified` 沒有部署，Greengrass 就算裝了也收不到元件。
- 附加 `-core`、搬進 `-core` 之後，`-core` 群組的部署送到這台 core device，`get-core-device` 是 `HEALTHY`。
- 反例：名稱不符合 `<prefix>-core-*` 的 thing 附加了 `-core` policy 也連不上（client id 不符）、拿不到憑證。
- 記下 `-core` policy 的 Greengrass data plane 四個動作夠不夠：Greengrass 的 log 沒有 `AccessDenied`，部署能完成。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

### S3. awscc 的 drift 與錯誤訊息（design §11 第 11 點）

**前提**：階段 C 完成，`fleet`、`edge` 已 apply（`sitewise` 有資源時一起做）。這一項是記錄行為，不是比對規格；結果寫回 design §11 與 REFERENCE〈已知限制的細節〉awscc 那一列。

**指令**

```bash
cd templates/example5/infra/terraform

# 1. apply 後馬上 plan，沒有變更才算乾淨（每個用 awscc 的 stack）
for s in fleet edge sitewise; do
  ./stacks.sh "$E" "$s" plan -- -detailed-exitcode >/dev/null; echo "$s exit=$?"
done

# 2. Cloud Control 讀到的狀態（例：job template）
aws cloudcontrol get-resource --type-name AWS::IoT::JobTemplate --identifier "$PFX-ota" \
  --query 'ResourceDescription.Properties' --output text | jq 'keys'
```

【寫入】3. 在 console 或 CLI 外部改一個 awscc 管的資源，看 plan 偵不偵測得到。用排程稽核（改了不影響裝置）：

```bash
aws iot update-scheduled-audit --scheduled-audit-name "$PFX-weekly" --day-of-week TUE
./stacks.sh "$E" fleet plan      # 應該顯示 day_of_week TUE → MON
aws iot update-scheduled-audit --scheduled-audit-name "$PFX-weekly" --day-of-week MON
```

【寫入】4. 錯誤訊息：在 `edge/envs/dev.tfvars` 暫時加一個 `aws.` 開頭但不存在的元件版本（例如 `"aws.greengrass.StreamManager" = "9.9.9"`），apply，把錯誤訊息原樣貼在備註；復原後再 apply。

名稱怎麼來的：用 awscc 的 module 與 resource（`modules/greengrass-component/main.tf:12`、`modules/greengrass-deployment/main.tf:16`、`modules/iot-device-defender/main.tf:29`、`:49`、`:64`）；排程稽核名稱（`fleet/device-defender.tf:26`）；job template 名稱（`fleet/ota.tf:14`）。

**預期結果**

- 1：三個 stack 都是 `exit=0`。`exit=2` 時把差異貼在備註，判斷是 awscc 的 computed 屬性還是 `inline_recipe`（後者在第 4 項處理）。
- 3：plan 偵測得到外部的修改。偵測不到，就記成「awscc 的這種 resource 沒有 drift 偵測」。
- 4：記下錯誤訊息是否指得出哪個元件、哪個版本；只有 Cloud Control 的一般性錯誤時，REFERENCE 要提醒除錯時去看 `aws cloudcontrol get-resource-request-status` 或 CloudTrail。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

---

## 結果怎麼回寫

執行人是負責 apply 的專案 app team 成員；回寫分四處，都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/example5/infra/REFERENCE.md`〈雲端整合待驗證〉表與〈已知限制的細節〉 | 執行人 | 表格加一欄「結果」，寫 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`。21 項都通過時，比照〈靜態驗證通過（2026-10-27）〉另開一節〈雲端驗證通過（日期）〉把表搬過去；〈已知限制的細節〉、〈安全取捨〉、〈destroy 前要做的事〉、〈runbook：輪替 claim 憑證〉裡已經確認的條目改成實際行為；README 與 REFERENCE 開頭的狀態句改成實際狀態 | platform team ＋ 專案代表（`/templates/` 的 CODEOWNERS） |
| `docs/design/v8/design-docs.md` §4.1、§11、§14 | platform team | 每一點後面加 `→ 已確認（YYYY-MM-DD，runbook 第 <n> 項或 S<n>）`，或 `→ 不成立：<實際行為>，改法見 #issue`。§4.1 控制 3 若不成立，表格要改寫，並重新判斷取捨的 checkpoint | platform team |
| module README 的「還沒在真實帳號 apply 過」（`iot-fleet`、`iot-account-settings`、`iot-device-defender`、`greengrass-component`、`greengrass-deployment`、`iot-job-template`、`ota-signing`、`iotsitewise`、`kinesis-video-stream`、`acm-pca`、`sagemaker-*`、`eventbridge-rule`、`scheduler-schedule`、`sqs-queue`、`iot-topic-rule`） | platform team | 有驗到的 module 改成實際驗證的日期與帳號類型；`greengrass-component` README:37 依第 4 項的結果改 | platform team |

不通過的處理：

- 問題在 module（例如 `greengrass-component` 的 drift、`ota-signing` 的重建）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack（例如 `iam-base` 的動作清單、`fleet` 的 claim policy、`inference` 的 data capture 權限）：開 issue 並標 `templates/example5`，修正走一般的範本改版 PR。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
