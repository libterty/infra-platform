# example4 雲端驗證 runbook

## 結論

這份 runbook 列出 `templates/example4` 第一次在真實 AWS 帳號 apply 時要逐項確認的事。照做完，REFERENCE〈雲端整合待驗證〉表、〈已知限制的細節〉與 design v7 §11、§14 的「未驗證」「推論」都會變成有證據的通過或不通過。

- 範圍：REFERENCE〈雲端整合待驗證〉的 21 列，整理成本文第 1–21 項；design v7 裡表上沒有的未確認點併進對應的項目；另加一項寫這份文件時發現的風險（S1）。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、名稱怎麼來的、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。
- 這份文件的指令都**沒有實際跑過**。名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的預設命名或 API 行為），執行時以實際輸出為準。
- 從程式碼就看得出來、第一次驗證很可能不通過的事，先講（都沒有修，等驗證結果再決定）：
  1. **Glue 的 CloudWatch Logs 加密可能缺 `logs:AssociateKmsKey`**：`glue-etl` 的 security configuration 開了 `cloudwatch_encryption`（`modules/glue-etl/main.tf:15-18`），crawler 與 job 都掛它。AWS Glue 文件要求這時 role 要有 `logs:AssociateKmsKey`（推測，repo 裡沒有這個依據），`iam-base` 的 `WriteGlueLogs` 只有 `CreateLogGroup`、`CreateLogStream`、`PutLogEvents`（`iam-base/policies.tf:50-55`）。crawler 與 job 可能一跑就失敗。第 11、17 項會直接看到。
  2. **QuickSight VPC connection 的 SG 可能少一條 ingress**：AWS QuickSight 文件說 VPC connection 的 ENI 不是 stateful，它的 SG 要放行來自資料庫 SG 的回程流量（推測）。`network` 只給 `quicksight` 一條到 `redshift` 5439 的 egress（`network/security-groups.tf:19`），沒有從 `redshift` 進來的規則。Redshift 資料來源可能建不起來或連線逾時。第 16 項會看到。
  3. **REFERENCE 建議的「先 UNLOAD 到 curated」做不到**：`redshift` role 對 curated bucket 只有 `s3:GetObject`、`s3:ListBucket`、`s3:GetBucketLocation`（`iam-base/policies.tf:131-143`），沒有 `s3:PutObject`，所以 REFERENCE.md:251、:274 寫的 UNLOAD 會被拒。第 20 項改用手動 snapshot 備份。
  4. **data subnet 只有兩個 `/27`**：dev 是 `10.30.5.0/27`、`10.30.5.32/27`（`network/vpc.tf:10` 的 `newbits = 7`、`netnum_base = 40`），每個 27 個可用位址。OpenSearch 7 台節點、Firehose、Redshift、Client VPN、QuickSight 的 ENI 都放在這兩個 subnet。OpenSearch 的 VPC domain 在 blue/green 更新時要額外的 IP（推測，AWS 文件寫每台節點要預留約 3 個），位址可能不夠。S1 每個階段記一次剩餘位址。
  5. **寫進 Kinesis 的 `@timestamp` 會一路帶到 curated table**：REFERENCE.md:202 要求每筆資料都帶 `@timestamp`，範例 Glue job 不改欄位名稱就寫進 curated（`etl/raw_to_curated.py:63-74`）。Athena 文件說欄位名稱除了底線不支援特殊字元（推測），查 curated 的 `events` 時可能出錯。第 11 項會看到。

## 範圍

涵蓋：

| 編號 | 項目 | 來源（REFERENCE.md 行號） |
|---|---|---|
| 1 | `.tfbackend` 的 `kms_key_id` 與 bucket policy | :354 |
| 2 | flow log 用 CMK 寫進 S3 | :352 |
| 3 | Client VPN | :349 |
| 4 | Site-to-Site VPN | :350 |
| 5 | OpenSearch 規格：warm 最小台數、master | :336、:308 |
| 6 | OpenSearch log publishing 的 resource policy | :351 |
| 7 | `search-config` 從 Client VPN 執行 | :355 |
| 8 | Dashboards 只能從 VPN 連 | :338 |
| 9 | Firehose 寫進 VPC 內的 OpenSearch | :337 |
| 10 | S3 → EventBridge → Glue workflow | :340 |
| 11 | 範例 Glue job | :342、:307 |
| 12 | Glue job 成本 | :341 |
| 13 | catalog 加密後的 KMS 權限 | :343 |
| 14 | Redshift Spectrum | :345、:301 |
| 15 | `ra3.large` single-node | :346 |
| 16 | QuickSight 兩種來源 | :348、:305 |
| 17 | IAM 動作清單 | :344、:299 |
| 18 | OpenSearch 告警的 `ClientId` | :353、:300 |
| 19 | master 密碼輪替 | :339、:163 |
| 20 | `warehouse_mode` 防呆與切換 | :347、:303 |
| 21 | ISM 冷熱搬移 | :335 |
| S1 | data subnet 的 IP 預算 | 寫這份文件時發現，不在任何清單 |

design v7 各點的去處（`docs/design/v7/design-docs.md`）：

| design 位置 | 內容 | 在本文 |
|---|---|---|
| §2 第 3 點 | warm 最小台數、T3 master 能不能搭 UltraWarm、warm 要幾小時才能用 | 第 5 項。T3 master 不驗：範本用 `m7g.large.search`，要驗得另開 domain，費用不划算，維持未確認 |
| §2 第 5 點 | basic auth 不經 access policy | 第 8 項 |
| §2 第 13 點 | `customer_gateway_configuration` 是否含 PSK | 第 4 項 |
| §2 第 19 點 | `prevent_destroy` 擋 replace 是推論 | 第 20 項 |
| §3.2 K5 | Serverless 的 `require_ssl` config key | 第 14 項 |
| §3.2 K6 | log group 層的 resource policy | 第 6 項 |
| §5.7 | destroy 時 catalog 加密會不會改回 | 第 13 項最後一段（只在拆環境時） |
| §11 第 1 列 | warm 最小台數、master 規格 | 第 5 項 |
| §11 第 2 列 | UltraWarm 要幾小時才能用 | 第 5 項記時間，第 7 項的前提 |
| §11 第 3 列 | cold 需要 `timestamp_field` | 第 9 項（mapping）、第 21 項（搬移） |
| §11 第 4 列 | §4.1 的例外 | 第 1 項（state 保護）、第 19 項（輪替與 state 裡的份數） |
| §11 第 5 列 | basic auth 繞過 access policy | 第 8 項 |
| §11 第 6 列 | ephemeral 在 `terraform test` 能不能跑 | 不在本文：§14 已改用離線 aws provider。ephemeral 的實際接線在第 7 項 |
| §11 第 7 列 | `search-config` 要連 VPC 內的 domain | 第 7 項 |
| §11 第 8 列 | opensearch provider 的 lock | 不在本文：離線檢查（S10） |
| §11 第 9 列 | 同帳號第二個專案呼叫 `glue-catalog-encryption` | 第 13 項 |
| §11 第 10 列 | state bucket 的強化 | 第 1 項 |
| §11 第 11 列 | 事件觸發的次數與成本 | 第 10、12 項 |
| §11 第 12 列 | EventBridge 重複或遺漏事件 | 第 10 項 |
| §11 第 13 列 | `warehouse_mode` 的防呆 | 第 20 項 |
| §11 第 14 列 | dev 拆環境卡在 `warehouse` | 第 20 項（用 `plan -destroy` 驗，不用真的拆） |
| §11 第 15 列 | QuickSight 主控台步驟 | 第 16 項 |
| §11 第 16 列 | Firehose ENI 權限能否收窄 | 第 17 項 |
| §11 第 17 列 | `customer_gateway_configuration` 是否含 PSK | 第 4 項 |
| §11 第 18、19 列 | module 連續發版、HCP 登記 | 不在本文：發版流程，階段 0 的 `init` 失敗就代表漏登記 |
| §11 第 20 列 | Lake Formation 模式 | 第 13 項的前提檢查 |
| §11 第 21 列 | 成本 | 不在本文：看帳單。Glue 的部分在第 12 項 |
| §14〈加入雲端驗證清單的項目〉 | 9 項 | 第 4 項、第 3 與 4 項、第 15、2、16、17、18、11、7 項（依原文順序） |

不涵蓋：告警門檻是否合理（REFERENCE.md:300，要真實流量跑一段時間才能調）、Athena 掃描上限的下限值（REFERENCE.md:306，provider 行為，已在離線測試確認）。

## 需要的權限與工具

工具：

- AWS CLI v2（`--cli-binary-format raw-in-base64-out`、`redshift-data`、`redshift-serverless`、`quicksight` 子指令）、`jq`、`curl`（要支援 `-K -`）、`dig`、`nc`。
- Terraform：`versions.tf` 要求 `>= 1.10`（例如 `foundation/versions.tf:2`），離線測試用的是 1.15；`init` 要 HCP registry token（README.md:84）。
- OpenVPN 相容的用戶端（例如 AWS 提供的 VPN 用戶端）。第 3 項之後連 OpenSearch、Dashboards 都要先連上 Client VPN。
- 簽發 mutual TLS 憑證的工具（例如 easy-rsa）。server 憑證與 client root CA 要先匯入 ACM，repo 不管這一步。
- QuickSight 主控台的管理者帳號（第 16 項）。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 12 個 stack | 各 stack 的 deploy role（`deploy_role_arn`，空字串就用呼叫者自己），要有 README〈前置作業〉第 7 點的特權操作 | `foundation/providers.tf:1-10`、REFERENCE.md:141-150 |
| `search-config` 的 plan、apply，以及本文所有 `osq` 指令 | 同上，加上連上 Client VPN | REFERENCE.md:170-183 |
| state bucket 的設定 | bucket 擁有者（platform team） | REFERENCE.md:69 |
| QuickSight 訂閱、secret 授權、預覽 dataset | QuickSight 管理者 | REFERENCE.md:126-129 |
| 同帳號其他專案的 catalog 存取（第 13 項） | 該專案的 owner | REFERENCE.md:125 |

驗證身分要的 AWS 權限（唯讀）：`sts:GetCallerIdentity`、`ssm:GetParameter`、`ec2:Describe*`、`ec2:ExportClientVpnClientConfiguration`、`logs:Describe*`、`logs:FilterLogEvents`、`kms:DescribeKey`、`kms:GetKeyPolicy`、`s3:GetBucket*`、`s3:GetEncryptionConfiguration`、`s3:GetLifecycleConfiguration`、`s3:ListBucket`、`s3:ListBucketVersions`、`s3:GetObject`（`head-object` 用）、`cloudtrail:LookupEvents`、`cloudtrail:GetEventSelectors`、`es:DescribeDomain`、`es:DescribeDomainChangeProgress`、`firehose:DescribeDeliveryStream`、`cloudwatch:DescribeAlarms`、`cloudwatch:ListMetrics`、`cloudwatch:GetMetricStatistics`、`events:DescribeRule`、`events:ListTargetsByRule`、`glue:Get*`、`athena:GetQueryExecution`、`athena:GetQueryResults`、`redshift:Describe*`、`redshift-serverless:Get*`、`redshift-serverless:List*`、`redshift-data:DescribeStatement`、`redshift-data:GetStatementResult`、`quicksight:Describe*`、`secretsmanager:DescribeSecret`、`secretsmanager:ListSecretVersionIds`、`secretsmanager:GetSecretValue`（只對 OpenSearch master secret 與 Redshift 管理者 secret，加上 `foundation` CMK 的 `kms:Decrypt`）、`lakeformation:GetDataLakeSettings`、`iam:GenerateServiceLastAccessedDetails`、`iam:GetServiceLastAccessedDetails`、`ce:GetCostAndUsage`。

【寫入】要另外的權限：`kinesis:PutRecord`、`s3:PutObject`（glue-assets 的 `scripts/`）、`glue:StartCrawler`、`glue:StartWorkflowRun`、`events:DisableRule`、`events:EnableRule`、`athena:StartQueryExecution`、`redshift-data:ExecuteStatement`、`redshift-serverless:CreateSnapshot`、`secretsmanager:CreateSecret`、`secretsmanager:PutSecretValue`、`cloudwatch:SetAlarmState`。

網路：

- VPC 沒有 NAT 也沒有 interface endpoint（`network/vpc.tf:7`、`:12`）。OpenSearch 與 Redshift 只有 VPC 內與 Client VPN 連得到（`network/security-groups.tf:15-21`）。
- Client VPN 預設 split tunnel（`modules/client-vpn/variables.tf:222-224`），連上後 AWS API 與 registry 仍走原本的網路。
- Redshift 的 SQL 一律走 Data API（AWS API），不用連進 VPC。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。還沒 apply 的 stack 讀不到 key，會印 `ParameterNotFound`，該 stack apply 完再重跑一次。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project
E=<env>                                   # dev 或 sit
N="$P-$E"                                 # name_prefix
ssm() { aws ssm get-parameter --name "/$P/$E/$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
KMS_KEY=$(ssm foundation/kms_key_arn)
TOPIC=$(ssm foundation/alarm_topic_arn)
FLOW_BUCKET=$(ssm foundation/flow_log_bucket_arn); FLOW_BUCKET=${FLOW_BUCKET##*:::}
MASTER_SECRET=$(ssm foundation/opensearch_master_secret_arn)
VPC_ID=$(ssm network/vpc_id)
VPC_CIDR=$(ssm network/vpc_cidr)
SUBNETS_DATA=$(ssm network/subnet_ids_data)          # 逗號分隔
SG_OS=$(ssm network/sg_opensearch_id)
SG_FH=$(ssm network/sg_firehose_id)
SG_RS=$(ssm network/sg_redshift_id)
SG_QS=$(ssm network/sg_quicksight_id)
SG_VPN=$(ssm network/sg_client_vpn_id)
RAW_BUCKET=$(ssm storage/raw_bucket_name)
CURATED_BUCKET=$(ssm storage/curated_bucket_arn); CURATED_BUCKET=${CURATED_BUCKET##*:::}
GLUE_ASSETS=$(ssm storage/glue_assets_bucket_arn); GLUE_ASSETS=${GLUE_ASSETS##*:::}
RAW_DB=$(ssm storage/raw_database_name)               # <project>_<env>_raw
CURATED_DB=$(ssm storage/curated_database_name)       # <project>_<env>_curated
STREAM="$N-events"
DOMAIN=$(ssm search/opensearch_domain_name)           # 應該等於 "$N-search"
OS_ENDPOINT=$(ssm search/opensearch_endpoint)
WG=$(ssm analytics/athena_workgroup_name)             # 應該等於 "$N-analytics"
WORKFLOW=$(ssm pipeline/glue_workflow_name)           # 應該等於 "$N-raw-to-curated"
JOB="$WORKFLOW-job"
RS_MODE=$(ssm warehouse/redshift_mode)
RS_DB=$(ssm warehouse/redshift_database)
RS_ADMIN_SECRET=$(ssm warehouse/redshift_admin_secret_arn)

# 用 master 帳密打 OpenSearch API；只在 Client VPN 連上時能用。
# 帳密只經過管線，不進指令參數、shell 變數或 history。STAGE=AWSPREVIOUS osq ... 用上一版密碼（第 19 項）。
osq() {
  local path="$1"; shift
  aws secretsmanager get-secret-value --secret-id "$MASTER_SECRET" --version-stage "${STAGE:-AWSCURRENT}" \
      --query SecretString --output text \
    | jq -r '"user = " + ((.username + ":" + .password) | @json)' \
    | curl -sS --max-time 20 -K - "$@" "https://$OS_ENDPOINT$path"
}

# 用 Redshift 管理者 secret 經 Data API 跑一段 SQL，等結束後印狀態與結果。
rs() {
  local -a target; local id st
  if [ "$RS_MODE" = serverless ]; then target=(--workgroup-name "$N-warehouse"); else target=(--cluster-identifier "$N-warehouse"); fi
  id=$(aws redshift-data execute-statement "${target[@]}" --database "$RS_DB" --secret-arn "$RS_ADMIN_SECRET" \
         --sql "$1" --query Id --output text)
  while :; do
    st=$(aws redshift-data describe-statement --id "$id" --query Status --output text)
    case "$st" in FINISHED|FAILED|ABORTED) break ;; esac
    sleep 3
  done
  aws redshift-data describe-statement --id "$id" --query '{status:Status,error:Error,rows:ResultRows}'
  [ "$st" = FINISHED ] && aws redshift-data get-statement-result --id "$id" --query Records --output json 2>/dev/null
  return 0
}

# 【寫入】送一筆測試事件進 Kinesis；欄位對齊 REFERENCE.md:202 與 bi 的 dataset。
put_event() {
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  aws kinesis put-record --stream-name "$STREAM" --partition-key "$1" --cli-binary-format raw-in-base64-out \
    --data "{\"@timestamp\":\"$now\",\"event_id\":\"$1\",\"event_time\":\"$now\",\"payload\":\"runbook\"}" \
    --query SequenceNumber --output text >/dev/null
}
```

名稱怎麼來的：

- SSM 路徑：`common.tf:45` 的 `ssm_prefix = "/${var.project}/${var.env}"`，`modules/ssm-publish/main.tf:4` 組成 `<prefix>/<stack>/<key>`；key 名稱見各 stack 的 `ssm-outputs.tf`（例如 `foundation/ssm-outputs.tf:3-6`、`network/ssm-outputs.tf:3-19`、`storage/ssm-outputs.tf:4-12`、`search/ssm-outputs.tf:3-5`、`analytics/ssm-outputs.tf:3-4`、`pipeline/ssm-outputs.tf:3-5`、`warehouse/ssm-outputs.tf:4-8`）。
- `name_prefix`：`common.tf:44` 的 `"${var.project}-${var.env}"`。
- Kinesis stream：`storage/stream.tf:4` 的 `"${local.name_prefix}-events"`。
- OpenSearch domain：`search/domain.tf:3` 的 `"${local.name_prefix}-search"`。
- Athena workgroup：`analytics/workgroup.tf:24` 的 `"${local.name_prefix}-analytics"`。
- Glue workflow 與 job：`pipeline/glue.tf:4` 的 `"${local.name_prefix}-raw-to-curated"`、`:7` 的 `"${local.workflow_name}-job"`。
- Glue database：`storage/catalog.tf:3` 把 `-` 換成 `_`，`:6-7` 加 `_raw`、`_curated`。
- Redshift：`warehouse/redshift.tf:15`、`:36` 都是 `"${local.name_prefix}-warehouse"`；Serverless 的 namespace 與 workgroup 同名（`modules/redshift-serverless/main.tf:12`、`:34`）。
- master secret 的 JSON 欄位 `username`、`password`：REFERENCE.md:116。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER` 與 README〈前置作業〉。每個 stack 先跑 `--dry-run` 看一次指令。所有 `./stacks.sh` 指令都在複製出去的 `infra/terraform` 底下跑。

| 階段 | 做什麼 | 在哪裡跑 | 做完接著驗 |
|---|---|---|---|
| 0 | 照 REFERENCE〈複製出去之後要改什麼〉換掉佔位值；state bucket 的強化（README〈前置作業〉第 1 點）；Lake Formation 維持 IAM 模式；確認帳號的 Glue catalog 加密設定；開 QuickSight 訂閱（Enterprise）；簽發 Client VPN 憑證並匯入 ACM；`./stacks.sh <env> all init` | 任何能呼叫 AWS API 的地方 | 第 1 項、第 13 項的前提 |
| A | `foundation`（收到 SNS 訂閱確認信就點）→ 寫入 master secret 的值（REFERENCE.md:116-123）→ `network` | 同上 | 第 2 項的設定部分 |
| B | 在 `vpn/envs/dev.tfvars` 加上 `client_vpn`（照 `envs/examples/vpn.tfvars:9-16` 換掉 ARN），要驗 Site-to-Site 再加 `site_to_site`；apply `vpn` | 同上 | 第 3 項的設定部分、第 4 項 |
| C | `storage`、`iam-base`、`search`；等 UltraWarm 可用 | 同上 | 第 5、6 項、S1 |
| D | 連上 Client VPN，跑 `search-config` | Client VPN | 第 3 項的連線部分、第 7、8 項 |
| E | `analytics`、`iam-app`、`pipeline`；上傳 Glue 腳本；開始送測試資料 | 任何地方（送資料與 `osq` 要在 VPN 上） | 第 2 項的收 log 部分、第 9–13 項 |
| F | `warehouse` | 任何地方 | 第 14 項、第 15 項的唯讀部分 |
| G | `bi`（只有 Athena）→ 建 Redshift 唯讀 user 與 secret（REFERENCE.md:130-139）→ QuickSight 授權 secret → 帶 `redshift_reader_secret_arn` 再 apply `bi` | 任何地方 | 第 16 項 |
| H | 前面都跑過一輪之後的彙整 | 任何地方 | 第 17、18 項 |
| I | master 密碼輪替 | Client VPN | 第 19 項 |
| J | `warehouse_mode` 切換與還原 | 任何地方 | 第 20 項、第 15 項的建立部分 |
| K | 持續送資料，觀察 30 天（或照第 21 項的縮短做法 3–4 天） | Client VPN | 第 21 項 |

`all apply` 包含 `search-config`，所以要嘛整串在 VPN 上跑，要嘛照 README.md:63 分段。本文依上表分段跑。

---

## 1. `.tfbackend` 的 `kms_key_id` 與 bucket policy

**前提**

- state bucket 擁有者已做完 REFERENCE.md:69-115 的四件事：專用 CMK、bucket policy、舊版本 30 天過期、CloudTrail data event。
- 24 份 `envs/*.tfbackend` 的 `kms_key_id` 都換成那把 CMK 的 ARN，`key` 的 `example-` 前綴換成 `<project>-`（`foundation/envs/dev.tfbackend:2`、`:7`）。

**指令**

```bash
STATE_BUCKET=<state-bucket>
STATE_KEY=<state-kms-key-arn>

# 佔位值都換掉了（在 infra/terraform 底下跑；應該只剩一種 kms_key_id、沒有 example-）
grep -h '^kms_key_id' */envs/*.tfbackend | sort | uniq -c
grep -l 'example-\|<state-' */envs/*.tfbackend || echo "沒有佔位值"

# bucket 的基本設定
aws s3api get-bucket-encryption --bucket "$STATE_BUCKET"
aws s3api get-bucket-versioning --bucket "$STATE_BUCKET"
aws s3api get-public-access-block --bucket "$STATE_BUCKET"
aws s3api get-bucket-lifecycle-configuration --bucket "$STATE_BUCKET" \
  --query 'Rules[].{id:ID,status:Status,prefix:Filter,noncurrent:NoncurrentVersionExpiration}'
aws s3api get-bucket-policy --bucket "$STATE_BUCKET" --query Policy --output text | jq '.Statement[] | {Sid, Effect, Action, Resource}'
aws kms get-key-policy --key-id "$STATE_KEY" --policy-name default --output text | jq '.Statement[] | {Sid, Principal}'
aws cloudtrail get-event-selectors --trail-name <trail> \
  --query '{basic:EventSelectors[].DataResources, advanced:AdvancedEventSelectors}'

# 階段 A 之後：state 物件用專用 CMK 加密
for s in foundation network; do
  aws s3api head-object --bucket "$STATE_BUCKET" --key "$P-$E/$s/terraform.tfstate" \
    --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'
done
```

【寫入】反向確認 bucket policy 擋得住。物件名稱放在 `<project>-` 前綴下，才會落在 policy 的 Resource 裡：

```bash
# 不用專用 CMK 上傳：應該被拒
aws s3 cp /dev/null "s3://$STATE_BUCKET/$P-runbook-sse-check" --sse AES256
# 用另一個不是 deploy role、也不是 break-glass role 的身分讀 state：應該被拒
aws s3api head-object --bucket "$STATE_BUCKET" --key "$P-$E/foundation/terraform.tfstate"
```

`plan` 與 `apply` 成功本身就是 lock 檔寫入正常的證據：`use_lockfile = true`（`foundation/envs/dev.tfbackend:5`）會在 state 旁寫 `.tflock`，若寫入沒帶 CMK 會被 `OnlyStateKey` 擋下。

名稱怎麼來的：state key `"<project>-<env>/<stack>/terraform.tfstate"`（`foundation/envs/dev.tfbackend:2`，複製出去後換前綴）；policy 範例與 Sid（REFERENCE.md:73-112）。`<trail>` 是 bucket 擁有者的 trail，repo 裡沒有。

**預期結果**

- `kms_key_id` 只有一種值、24 份；沒有檔案含 `example-` 或 `<state-`。
- 預設加密是 `aws:kms`，key 是 `$STATE_KEY`；versioning `Enabled`；Block Public Access 四項都 `true`；有一條 `NoncurrentDays: 30` 的規則。
- policy 有 `DenyNonTls`、`OnlyDeployAndBreakGlass`、`OnlyStateKey`（或同義的 Sid）；key policy 只有 account root、deploy role、break-glass role（root 那條是讓 IAM 生效的必要條件）。
- trail 對 state bucket 有 S3 data event（至少 `GetObject`）。
- `head-object` 回 `aws:kms` 與 `$STATE_KEY`。
- 每個 stack 的 `init`、`plan`、`apply` 都沒有 `AccessDenied`。
- 兩個【寫入】都回 `AccessDenied`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 2. flow log 用 CMK 寫進 S3

**前提**

- 階段 A 完成；`network/envs/<env>.tfvars` 的 `flow_log = true`（`network/envs/dev.tfvars:9`）。
- VPC 要有流量才會有 log。階段 C 建了 OpenSearch 之後再看 S3。

**指令**

```bash
aws ec2 describe-flow-logs --filter Name=resource-id,Values="$VPC_ID" \
  --query 'FlowLogs[].{status:FlowLogStatus,deliver:DeliverLogsStatus,err:DeliverLogsErrorMessage,dest:LogDestination,type:LogDestinationType,traffic:TrafficType}'

aws s3api get-bucket-encryption --bucket "$FLOW_BUCKET"
aws s3api get-bucket-policy --bucket "$FLOW_BUCKET" --query Policy --output text | jq '.Statement[] | {Sid, Principal, Action}'
aws kms get-key-policy --key-id "$KMS_KEY" --policy-name default --output text \
  | jq '.Statement[] | select(.Principal.Service == "delivery.logs.amazonaws.com")'

# 階段 C 之後（flow log 約每 10 分鐘送一次）
aws s3api list-objects-v2 --bucket "$FLOW_BUCKET" --prefix "AWSLogs/$ACCOUNT/vpcflowlogs/$AWS_REGION/" \
  --query 'reverse(sort_by(Contents,&LastModified))[:3].[Key,LastModified]' --output text
aws s3api head-object --bucket "$FLOW_BUCKET" --key "<上一步列出的一個 Key>" --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'
```

名稱怎麼來的：bucket `"${local.name_prefix}-flow-logs-${var.expected_account_id}"`（`foundation/log-buckets.tf:5`），`log_delivery = ["vpc_flow_logs"]`（`:6`）；flow log 目的地型別 `s3`、`traffic_type` 預設 `ALL`（`modules/vpc/flow-log.tf:6-7`、`modules/vpc/variables.tf:92`）；key policy 的 `delivery.logs.amazonaws.com`（`foundation/kms.tf:12-19`）。S3 key 的 `AWSLogs/<account>/vpcflowlogs/<region>/` 前綴是 AWS 的命名（推測）。

**預期結果**

- flow log `ACTIVE`，`DeliverLogsStatus` 是 `SUCCESS`，沒有錯誤訊息；目的地是 flow log bucket，型別 `s3`，`ALL`。
- bucket 預設加密是 `aws:kms`，key 是 `$KMS_KEY`；bucket policy 有給 `delivery.logs.amazonaws.com` 的寫入。
- key policy 有 `delivery.logs.amazonaws.com` 的 `kms:Encrypt`、`kms:Decrypt`、`kms:ReEncrypt*`、`kms:GenerateDataKey*`、`kms:DescribeKey`，條件 `aws:SourceAccount`。
- 階段 C 之後有新的 `.log.gz` 物件，`head-object` 是 `aws:kms` 加 `$KMS_KEY`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 3. Client VPN

**前提**

- 階段 B 完成，`client_vpn` 用 mutual TLS（`server_certificate_arn`、`authentication.mutual_tls_root_certificate_arn` 是自己匯入 ACM 的憑證），`associated_subnet_count = 1`。
- `dns_servers` 不設（預設 `[]`，`vpn/variables.tf:13`）：split tunnel 下用戶端用自己的 DNS 解析 domain endpoint。
- 授權規則只放行 data subnet（`vpn/client-vpn.tf:13-15`）。VPC 的 DNS resolver（VPC 網段第一個位址加 2，dev 是 `10.30.0.2`）在 app subnet 裡，**不在授權範圍**，所以 `dns_servers` 設成 VPC resolver 會解析失敗（推測）。下面用它當「授權只到 data subnet」的反向測試。

**指令**

```bash
CVPN_ID=$(ssm vpn/client_vpn | jq -r .endpoint_id)

aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$CVPN_ID" \
  --query 'ClientVpnEndpoints[0].{status:Status.Code,split:SplitTunnel,auth:AuthenticationOptions[].Type,log:ConnectionLogOptions,sg:SecurityGroupIds,dns:DnsServers,transport:TransportProtocol,port:VpnPort,desc:Description}'
aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$CVPN_ID" \
  --query 'ClientVpnTargetNetworks[].[TargetNetworkId,Status.Code]' --output text
aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id "$CVPN_ID" \
  --query 'AuthorizationRules[].[DestinationCidr,AccessAll,Status.Code]' --output text
ssm network/subnet_cidrs_data
aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id "$CVPN_ID" \
  --query 'Routes[].[DestinationCidr,TargetSubnet,Origin,Status.Code]' --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/client-vpn/$N-client-vpn" \
  --query 'logGroups[].[logGroupName,kmsKeyId,retentionInDays]' --output text

# 用戶端設定檔（唯讀匯出），加上 client 憑證與私鑰後匯入 VPN 用戶端
aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id "$CVPN_ID" --output text > "$N-client-vpn.ovpn"
```

連上 VPN 之後（階段 D）：

```bash
aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id "$CVPN_ID" \
  --query 'Connections[?Status.Code==`active`].[ConnectionId,ClientIp,CommonName,ConnectionEstablishedTime]' --output text

# 到 data subnet 的 domain：通
dig +short "$OS_ENDPOINT"
nc -vz -w 5 "$OS_ENDPOINT" 443
# 到 app subnet 的 VPC resolver：不通（授權規則擋下）
dig +time=3 +tries=1 @10.30.0.2 "$OS_ENDPOINT"      # dev；sit 是 10.31.0.2

# 連線 log 用 CMK 寫得進去
aws logs describe-log-streams --log-group-name "/aws/client-vpn/$N-client-vpn" --order-by LastEventTime --descending \
  --max-items 3 --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output text
aws logs filter-log-events --log-group-name "/aws/client-vpn/$N-client-vpn" --max-items 5 --query 'events[].message' --output text
```

名稱怎麼來的：endpoint 的 description 與 `Name` tag 是 `"${local.name_prefix}-client-vpn"`（`vpn/client-vpn.tf:4`、`modules/client-vpn/main.tf:15`、`:56`）；log group `"/aws/client-vpn/${var.name}"`（`modules/client-vpn/main.tf:2`），用 `foundation` 的 CMK（`vpn/client-vpn.tf:5`、`modules/client-vpn/main.tf:9`）；UDP 443（`modules/client-vpn/main.tf:27-28`）；SSM 的 `endpoint_id`（`vpn/ssm-outputs.tf:4-8`）；dev 的 VPC 網段 `10.30.0.0/20`（`network/envs/dev.tfvars:5`），app subnet 從第 0 個 `/24` 開始（`network/vpc.tf:9`）。

**預期結果**

- endpoint `available`，`SplitTunnel` 是 `true`，`certificate-authentication`，connection log `Enabled: true` 指向 `/aws/client-vpn/<project>-<env>-client-vpn`，SG 是 `$SG_VPN`，`udp`／`443`。
- target network 一個，`associated`；授權規則兩條，等於兩個 data subnet 的 CIDR，`AccessAll` 是 `true`，`active`；路由有一條 VPC 網段、`Origin` 是 `associate`。
- log group 的 `kmsKeyId` 是 `$KMS_KEY`，保留 90 天。
- 連線後 `active` 有一筆；`dig` 回 data subnet 的私有位址；`nc` 成功；對 `10.30.0.2` 的 `dig` 逾時。
- log group 有 log stream，事件內容是連線紀錄（`connection-attempt` 之類，推測）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 4. Site-to-Site VPN

**前提**

- 階段 B 加了 `site_to_site`（照 `vpn/envs/examples/vpn.tfvars:19-25`），`customer_gateway.ip_address` 是一個真的公網位址。沒有地端設備也能驗 PSK 與 state 的部分；tunnel log 要有 IKE 協商才會有內容，沒有設備時那一段記「無法判定」。
- 驗完不需要就把 `site_to_site` 拿掉再 apply `vpn`【寫入】，避免每月約 35 美元（`vpn/envs/dev.tfvars:6-7`）。

**指令**

```bash
S2S=$(ssm vpn/site_to_site)
VPN_ID=$(jq -r .vpn_connection_id <<<"$S2S")
PSK_SECRET=$(jq -r .preshared_key_secret_arn <<<"$S2S")

aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
  --query 'VpnConnections[0].{state:State,pskArn:PreSharedKeyArn,tunnels:VgwTelemetry[].[OutsideIpAddress,Status,StatusMessage],ike:Options.TunnelOptions[].IkeVersions[].Value,log:Options.TunnelOptions[].LogOptions.CloudWatchLogOptions}'

# 設備設定檔裡的 PSK：只印長度與是否遮蔽，不印值
aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text \
  | sed -n 's:.*<pre_shared_key>\(.*\)</pre_shared_key>.*:\1:p' \
  | awk '{ print length($0), ($0 ~ /^\**$/ ? "masked-or-empty" : "NOT-MASKED") }'

# state 裡的 PSK：只印長度與布林值（在 infra/terraform 底下跑）
(cd vpn && TF_DATA_DIR=".terraform-$E" terraform state pull) \
  | jq '.resources[] | select(.type == "aws_vpn_connection") | .instances[0].attributes
        | { psk1_len: ((.tunnel1_preshared_key // "") | length),
            psk2_len: ((.tunnel2_preshared_key // "") | length),
            cgc_has_psk: ((.customer_gateway_configuration // "") | test("<pre_shared_key>[^<*]+</pre_shared_key>")),
            storage: .preshared_key_storage }'

# PSK 的 secret 由服務建立：記下用哪把 key
aws secretsmanager describe-secret --secret-id "$PSK_SECRET" --query '{name:Name,kms:KmsKeyId,owner:OwningService}'

# tunnel log
aws logs describe-log-groups --log-group-name-prefix "/aws/vendedlogs/vpn/$N-site-to-site" \
  --query 'logGroups[].[logGroupName,kmsKeyId,retentionInDays]' --output text
aws logs describe-log-streams --log-group-name "/aws/vendedlogs/vpn/$N-site-to-site" --max-items 5 \
  --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output text
aws logs describe-resource-policies --query 'resourcePolicies[].[policyName,lastUpdatedTime]' --output text
```

名稱怎麼來的：`"${local.name_prefix}-site-to-site"`（`vpn/site-to-site.tf:4`）；log group `"/aws/vendedlogs/vpn/${var.name}"`（`modules/vpn-site-to-site/main.tf:7`），用 CMK（`:14`）；`preshared_key_storage = "SecretsManager"`（`:49`）；兩條 tunnel 都開 log，BGP 時另開 BGP log（`:72-94`）；SSM 的三個欄位（`vpn/ssm-outputs.tf:9-14`）。vended log 會自動加一份 CloudWatch Logs resource policy，名稱是 AWS 決定的（推測，module 的 `/aws/vendedlogs/` 前綴就是為了這份 policy 的長度上限，`modules/vpn-site-to-site/main.tf:6`）；建立時 deploy role 可能要 `logs:PutResourcePolicy`（推測，README 的特權清單沒有列）。

**預期結果**

- 連線 `available`；`PreSharedKeyArn` 等於 SSM 的 `preshared_key_secret_arn`；兩條 tunnel 的 IKE 都只有 `ikev2`；兩條 tunnel 的 log 選項指向上面的 log group。
- 設備設定檔：兩行，都是 `masked-or-empty`。若出現 `NOT-MASKED`，表示 `customer_gateway_configuration` 含 PSK。
- state：`storage` 是 `SecretsManager`；`psk1_len`、`psk2_len` 是 0 或遮蔽字串的長度；`cgc_has_psk` 是 `false`。`true` 就是 PSK 進了 state，要回報（module README:69）。
- secret 的 `OwningService` 有值；記下 `KmsKeyId`（module README:70 列為未確認）。
- log group 的 `kmsKeyId` 是 `$KMS_KEY`。有地端設備時，tunnel 嘗試協商後出現 log stream；沒有設備就記「無法判定」。
- 執行時一起記下：apply 之後多了哪一份 resource policy、deploy role 有沒有因為 `logs:PutResourcePolicy` 失敗。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／`cgc_has_psk` ______ ／備註 ______

## 5. OpenSearch 規格：warm 最小台數與 master

**前提**

- 階段 C 完成。tfvars：hot 2 × `m7g.large.search`、master 3 × `m7g.large.search`、warm 2 × `ultrawarm1.medium.search`、cold 開啟、2 AZ（`search/envs/dev.tfvars:9-22`）。
- 記下 `search` apply 開始的時間。

**指令**

```bash
aws opensearch describe-domain --domain-name "$DOMAIN" \
  --query 'DomainStatus.{processing:Processing,state:DomainProcessingStatus,engine:EngineVersion,endpoint:Endpoints.vpc,cluster:ClusterConfig,fgac:AdvancedSecurityOptions,enc:EncryptionAtRestOptions.KmsKeyId,vpc:VPCOptions}'
aws opensearch describe-domain-change-progress --domain-name "$DOMAIN" \
  --query 'ChangeProgressStatus.{status:Status,stages:ChangeProgressStages[].[Name,Status]}'

# 連上 VPN 後：warm 節點真的加入叢集
osq "/_cat/nodes?v&h=name,node.role,heap.percent"
osq "/_cat/nodeattrs?v&h=node,attr,value" | grep -i box_type
osq "/_cat/indices/_warm?v"          # AWS 提供的篩選（推測），剛建好應該是空的
```

名稱怎麼來的：domain 名稱（`search/domain.tf:3`）；規格來自 tfvars 原樣傳進 module（`search/domain.tf:4-9`）；`zone_awareness_enabled = true`、`multi_az_with_standby` 預設 `false`（`modules/opensearch-domain/main.tf:84-85`、`modules/opensearch-domain/variables.tf:127-129`）。warm 節點的 `box_type` 屬性與 `_cat/indices/_warm` 是 AWS 的慣例（推測）。

**預期結果**

- apply 成功，沒有跟台數或 master 規格有關的錯誤。這就回答了「2 台 warm 能不能建立」。
- `ClusterConfig`：`InstanceCount: 2`、`DedicatedMasterCount: 3`、`WarmEnabled: true`、`WarmCount: 2`、`WarmType: ultrawarm1.medium.search`、`ColdStorageOptions.Enabled: true`、`ZoneAwarenessConfig.AvailabilityZoneCount: 2`。
- `processing` 變成 `false`、change progress `COMPLETED`。記下從 apply 開始到這時的時間，以及到 `_cat/nodes` 出現 warm 節點的時間（design §11 第 2 列）。
- `_cat/nodes` 看得到 7 台節點；`box_type` 有 `hot` 與 `warm` 兩種。

選做【寫入】（費時，只在 dev）：把 `warm.count` 改成 1 再 plan、apply，記下 API 接不接受。做完改回 2。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／domain 可用花了 ______ ／warm 可用花了 ______

## 6. OpenSearch log publishing 的 resource policy

**前提**

- 階段 C 完成。
- REFERENCE.md:351 寫的是「log group 層的 resource policy」，但 module 實際用的是**帳號層**的 policy，log group 層的寫法沒有採用（`modules/opensearch-domain/main.tf:43-46`、module README〈注意〉）。本項驗證的是實際部署的帳號層 policy；log group 層那個問題已經不適用，回寫時把 REFERENCE 那一列改掉。

**指令**

```bash
aws logs describe-resource-policies --query "resourcePolicies[?policyName=='OpenSearchService-$DOMAIN-logs'].policyDocument" \
  --output text | jq .
aws logs describe-resource-policies --query 'length(resourcePolicies)'      # 每個 region 上限 10 份

aws opensearch describe-domain --domain-name "$DOMAIN" --query 'DomainStatus.LogPublishingOptions'
aws logs describe-log-groups --log-group-name-prefix "/aws/OpenSearchService/domains/$DOMAIN/" \
  --query 'logGroups[].[logGroupName,kmsKeyId,retentionInDays]' --output text
for t in es-application-logs audit-logs; do
  echo "== $t"
  aws logs describe-log-streams --log-group-name "/aws/OpenSearchService/domains/$DOMAIN/$t" \
    --order-by LastEventTime --descending --max-items 2 --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output text
done
```

名稱怎麼來的：policy 名稱 `"OpenSearchService-${var.name}-logs"`（`modules/opensearch-domain/main.tf:46`）；log group `"/aws/OpenSearchService/domains/${var.name}/${lower(replace(t, "_", "-"))}"`（`:18`），`log_types` 預設 `ES_APPLICATION_LOGS`、`AUDIT_LOGS`（`modules/opensearch-domain/variables.tf:188`）；保留 30 天（`search/variables.tf:51`）。

**預期結果**

- policy 的 principal 是 `es.amazonaws.com`，action `logs:CreateLogStream`、`logs:PutLogEvents`，resource 是兩個 log group 的 `:*`，條件 `aws:SourceAccount` 等於帳號、`aws:SourceArn` 等於這個 domain（`modules/opensearch-domain/main.tf:47-60`）。
- 帳號裡的 resource policy 總數小於 10。
- `LogPublishingOptions` 有 `ES_APPLICATION_LOGS`、`AUDIT_LOGS`，都 `Enabled: true`。
- 兩個 log group 的 `kmsKeyId` 是 `$KMS_KEY`。
- `es-application-logs` 有 log stream。`audit-logs` 要等第 8 項在 Dashboards 開稽核之後才有內容（`modules/opensearch-domain/variables.tf:190`）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 7. `search-config` 從 Client VPN 執行

**前提**

- 第 3 項的 VPN 已連上；第 5 項的 warm 節點已出現（REFERENCE.md:187，不然 ISM 的搬移會失敗）。
- 本機能連 AWS API 與 HCP registry（split tunnel）；`search-config` 已 `init`。

**指令**

```bash
# 網路：沒帶帳密應該回 401
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 10 "https://$OS_ENDPOINT/"

# 在 infra/terraform 底下
./stacks.sh "$E" search-config plan
./stacks.sh "$E" search-config apply        # 【寫入】
./stacks.sh "$E" search-config plan         # 應該零差異

# ephemeral 讀的帳密沒有進 state：只數欄位，不印值
(cd search-config && TF_DATA_DIR=".terraform-$E" terraform state pull) \
  | jq '[paths | .[-1] | strings | select(. == "password" or . == "secret_string")] | length'

ssm search-config/firehose_writer_role
ssm search-config/ism_policy_ids

# 實際建出來的東西
osq "/_plugins/_ism/policies/logs" | jq '{states: [.policy.states[].name], template: .policy.ism_template}'
osq "/_plugins/_security/api/roles/firehose_writer" | jq .
osq "/_plugins/_security/api/rolesmapping/firehose_writer" | jq .
osq "/_index_template/firehose" | jq '.index_templates[0].index_template | {index_patterns, mappings: .template.mappings}'
```

名稱怎麼來的：provider 用 `https://<opensearch_endpoint>` 與 master 帳密、`sign_aws_requests = false`（`search-config/providers.tf:40`、`:46-51`）；帳密由 ephemeral 讀（`:33-37`）；ISM policy id 是 map key `logs`（`search-config/config.tf:7`、`modules/opensearch-config/main.tf:45`）；FGAC role `firehose_writer`（`search-config/config.tf:18`、`modules/opensearch-config/main.tf:63`）；index template `firehose`（`search-config/config.tf:32`、`modules/opensearch-config/main.tf:93`）；index pattern `"${local.name_prefix}-events*"`（`search-config/config.tf:4`）。

**預期結果**

- `curl` 回 `401`（網路通、FGAC 擋下匿名）。
- plan、apply 成功；第二次 plan `No changes`。沒有連線逾時或 TLS 錯誤。
- state 裡 `password`、`secret_string` 的欄位數是 `0`。
- SSM：`firehose_writer_role` 是 `firehose_writer`；`ism_policy_ids` 是 `logs`。
- ISM 的 states 是 `hot`、`warm`、`cold`、`delete`，`ism_template.index_patterns` 是 `<project>-<env>-events*`。
- `firehose_writer` 的 cluster 權限 `cluster_composite_ops`、`cluster_monitor`，index 權限 `create_index`、`manage`、`crud`（`modules/opensearch-config/main.tf:66-71`）；mapping 的 `backend_roles` 是 `arn:aws:iam::<account>:role/<project>-<env>-firehose`。
- index template 的 `@timestamp` 是 `date`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 8. Dashboards 只能從 VPN 連

**前提**

- 第 7 項完成，VPN 連著。

**指令**

```bash
# SG：只收三個 SG 的 443，沒有 egress
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$SG_OS" \
  --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,ReferencedGroupInfo.GroupId,CidrIpv4]' --output table
echo "firehose=$SG_FH client_vpn=$SG_VPN search_admin=$(ssm network/sg_search_admin_id)"

# access policy 只列 Firehose role
aws opensearch describe-domain --domain-name "$DOMAIN" --query 'DomainStatus.AccessPolicies' --output text | jq .

# basic auth 不經過 access policy：master 用帳密就能進來
osq "/_plugins/_security/authinfo" | jq '{user: .user_name, roles: .roles, backend_roles: .backend_roles}'
```

【寫入】用 master 在 Dashboards 建個人帳號（README 的補償控制第 4 點）：

1. 瀏覽器開 `https://<opensearch_endpoint>/_dashboards`，用 master 登入。
2. Security → Internal users 建一個個人帳號；Roles → `readall` 的 Mapped users 加上它。
3. Security → Audit logging 開啟（第 6 項的 `audit-logs` 才會有內容）。
4. 登出，用個人帳號登入，能看到 Discover。

離開 VPN 之後：

```bash
dig +short "$OS_ENDPOINT"                                                  # 仍解析得到私有位址
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 10 "https://$OS_ENDPOINT/_dashboards" || echo "連不到"
```

名稱怎麼來的：SG 規則（`network/security-groups.tf:16`、`:17`、`:20`）；access policy 只列 Firehose role（`search/domain.tf:15`、`modules/opensearch-domain/main.tf:22-30`）；匿名關閉（`modules/opensearch-domain/main.tf:118`）；Dashboards 路徑 `/_dashboards`（`modules/opensearch-domain/outputs.tf:17`）。

**預期結果**

- `$SG_OS` 只有三條 ingress（TCP 443，來源 `$SG_FH`、`$SG_VPN`、`search_admin`），沒有 egress、沒有 CIDR 來源。
- access policy 只有一個 statement，principal 是 Firehose role，action `es:ESHttp*`。
- `authinfo` 的 `user` 是 master 的名稱，`roles` 含 `all_access`：帳密請求沒有被 access policy 擋下。
- 個人帳號能登入 Dashboards。
- 離開 VPN 後 DNS 仍回私有位址，但 `curl` 逾時（`000` 或「連不到」）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 9. Firehose 寫進 VPC 內的 OpenSearch

**前提**

- 階段 E 完成（`analytics`、`iam-app`、`pipeline`）。
- 【寫入】送 20 筆測試事件（要在共用變數裡定義 `put_event`）：

  ```bash
  for i in $(seq 1 20); do put_event "verify-$i"; done
  ```

**指令**

```bash
aws firehose describe-delivery-stream --delivery-stream-name "$N-to-search" \
  --query 'DeliveryStreamDescription.{status:DeliveryStreamStatus,source:Source.KinesisStreamSourceDescription.KinesisStreamARN,os:Destinations[0].AmazonopensearchserviceDestinationDescription.{index:IndexName,rotation:IndexRotationPeriod,backup:S3BackupMode,vpc:VpcConfigurationDescription}}'

# Firehose 在 data subnet 建的 ENI
aws ec2 describe-network-interfaces --filters Name=group-id,Values="$SG_FH" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,SubnetId,Status,Description]' --output table

# 送達指標與錯誤 log（送完 5 分鐘後）
aws cloudwatch get-metric-statistics --namespace AWS/Firehose --metric-name DeliveryToAmazonOpenSearchService.Success \
  --dimensions Name=DeliveryStreamName,Value="$N-to-search" \
  --start-time "$(date -u -v-1H +%FT%TZ 2>/dev/null || date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 300 --statistics Average
aws logs filter-log-events --log-group-name "/aws/kinesisfirehose/$N-to-search" \
  --start-time $(( ($(date +%s) - 3600) * 1000 )) --query 'events[].message' --output text | tail -20
aws s3 ls "s3://$RAW_BUCKET/errors/" --recursive | tail -5

# index 依日期輪替、資料進得去、套上 ISM、@timestamp 是 date
osq "/_cat/indices/$N-events*?v&h=index,health,docs.count,creation.date.string"
osq "/$N-events*/_count?q=payload:runbook" | jq .count
osq "/_plugins/_ism/explain/$N-events*" \
  | jq -r 'to_entries[] | select(.key | startswith("'"$N"'-events")) | [.key, (.value["index.plugins.index_state_management.policy_id"] // .value.policy_id // "-")] | @tsv'
osq "/$N-events*/_mapping" | jq '[.[] | .mappings.properties["@timestamp"].type]'
```

名稱怎麼來的：stream `"${local.name_prefix}-to-search"`、index `"${local.name_prefix}-events"`、data subnet 與 `firehose` SG（`pipeline/firehose.tf:19`、`:24-26`）；輪替預設 `OneDay`（`modules/firehose-stream/variables.tf:101`），index 名稱加 `-YYYY-MM-DD` 是 Firehose 的命名（推測）；備份模式 `FailedDocumentsOnly`、備份與錯誤都在 `errors/`（`modules/firehose-stream/main.tf:82`、`pipeline/firehose.tf:30-31`）；log group `"/aws/kinesisfirehose/${var.name}"`（`modules/firehose-stream/main.tf:4`）。

**預期結果**

- stream `ACTIVE`，來源是 `$N-events`；index `<project>-<env>-events`、`OneDay`、`FailedDocumentsOnly`；VPC 設定的 subnet 是兩個 data subnet、SG 是 `$SG_FH`、role 是 `<project>-<env>-firehose`。
- ENI 在 data subnet、`in-use`。
- `Success` 的平均是 `1`；Firehose log 沒有 `403`、`AccessDenied`、`security_exception`；`errors/` 底下沒有新物件。
- `_cat/indices` 有一個 `<project>-<env>-events-<日期>`；`_count` 是 `20`（重送過就更多）；ISM explain 的 policy 是 `logs`；`@timestamp` 是 `date`。
- 這些合起來代表 SigV4 過了 access policy、FGAC `firehose_writer` 的 mapping 生效。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 10. S3 → EventBridge → Glue workflow

**前提**

- 第 9 項完成。
- 【寫入】上傳範例腳本（CI 還沒接上之前手動做，REFERENCE.md:235）：

  ```bash
  aws s3 cp etl/raw_to_curated.py "s3://$GLUE_ASSETS/scripts/raw_to_curated.py"     # 在範本根目錄跑
  ```

- 【寫入】持續送資料 2 小時，讓 `to-raw` 每 900 秒寫出一個物件：

  ```bash
  end=$(( $(date +%s) + 7200 )); while [ "$(date +%s)" -lt "$end" ]; do put_event "load-$(date +%s)"; sleep 10; done
  ```

**指令**

```bash
RULE="$WORKFLOW-s3-event"

aws s3api get-bucket-notification-configuration --bucket "$RAW_BUCKET"
aws events describe-rule --name "$RULE" --query '{state:State,pattern:EventPattern}'
aws events list-targets-by-rule --rule "$RULE" --query 'Targets[].[Id,Arn,RoleArn]' --output text
aws glue get-trigger --name "$RULE" --query 'Trigger.{type:Type,state:State,workflow:WorkflowName,batch:EventBatchingCondition,actions:Actions}'

# raw/ 底下的物件（每 900 秒一個）
aws s3 ls "s3://$RAW_BUCKET/raw/" --recursive | tail -10

# EventBridge 送出與失敗次數
for m in Invocations FailedInvocations; do
  aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name "$m" --dimensions Name=RuleName,Value="$RULE" \
    --start-time "$(date -u -v-3H +%FT%TZ 2>/dev/null || date -u -d '-3 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 900 --statistics Sum --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text
done

# workflow 每次執行的批次條件與結果
aws glue get-workflow-runs --name "$WORKFLOW" --max-results 50 \
  --query 'Runs[].[WorkflowRunId,Status,StartedOn,CompletedOn,StartingEventBatchCondition.BatchSize,StartingEventBatchCondition.BatchWindow,Statistics.SucceededActions,Statistics.FailedActions]' --output table
```

【寫入】冪等與漏觸發（REFERENCE.md:221）：

```bash
# 重複觸發：手動再跑一次 workflow，job 應該沒有新資料可處理
aws glue start-workflow-run --name "$WORKFLOW"

# 漏觸發：關掉 rule，等 to-raw 寫出一個物件（最多 15 分鐘），再打開，下一次觸發要把兩批都處理掉
aws events disable-rule --name "$RULE"
for i in $(seq 1 10); do put_event "missed-$i"; done
# 等 raw/ 出現新物件
aws events enable-rule --name "$RULE"
for i in $(seq 1 10); do put_event "after-$i"; done
```

處理結果用第 11 項的 Athena 查詢比對：`missed-*` 與 `after-*` 都要出現，`verify-*` 不能重複。

名稱怎麼來的：raw bucket 開 EventBridge（`storage/buckets.tf:14`）；rule 與 trigger 名稱 `"${var.workflow.name}-s3-event"`（`modules/glue-etl/main.tf:2`、`:152`、`:181`），事件樣式比對 raw bucket 與 `raw/` 前綴（`:184-191`、`pipeline/glue.tf:40-41`）；target id `glue-workflow`、role 是 `glue-events`（`modules/glue-etl/main.tf:202-204`、`pipeline/glue.tf:42`）；batch 100 筆或 900 秒（`pipeline/glue.tf:43-44`）；`to-raw` 的 900 秒、64 MiB buffer（`pipeline/firehose.tf:11-12`）。

**預期結果**

- notification 設定有 `EventBridgeConfiguration: {}`。
- rule `ENABLED`，樣式是 `aws.s3`／`Object Created`／raw bucket／`raw/` 前綴；target 是 workflow ARN，role 是 `<project>-<env>-glue-events`。
- trigger 是 `EVENT`、`ACTIVATED`，`BatchSize: 100`、`BatchWindow: 900`，action 是 `$JOB`。
- 2 小時內 `raw/` 約 8 個物件；`Invocations` 每 900 秒約 1；`FailedInvocations` 是 0。
- workflow run 次數約等於物件數，不超過每小時 4 次（REFERENCE.md:217 的上限推算）；`StartingEventBatchCondition` 的 `BatchSize` 小於 100（視窗先到）。記下實際的次數與每次間隔。
- 手動重跑那次成功，job 沒有寫出新的 Parquet（第 11 項的筆數不變）。
- rule 關掉期間沒有 workflow run；打開後的下一次 run 把 `missed-*` 與 `after-*` 一起處理。
- 有時 workflow 重疊時 job 會因 `max_concurrent_runs = 1`（`modules/glue-etl/variables.tf:77`）失敗，記下有沒有發生。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／2 小時的 run 次數 ______

## 11. 範例 Glue job

**前提**

- 第 10 項的資料已進 `raw/`、腳本已上傳。
- crawler 每天 18:00 UTC 才跑（`pipeline/glue.tf:15`），先手動跑一次：

  ```bash
  aws glue start-crawler --name raw          # 【寫入】
  ```

**指令**

```bash
aws glue get-crawler --name raw --query 'Crawler.{state:State,last:LastCrawl,secconf:CrawlerSecurityConfiguration,db:DatabaseName,targets:Targets.S3Targets[].Path}'
aws glue get-tables --database-name "$RAW_DB" \
  --query 'TableList[].{name:Name,partitions:PartitionKeys[].Name,location:StorageDescriptor.Location,classification:Parameters.classification,cols:StorageDescriptor.Columns[].Name}'

aws glue get-job --job-name "$JOB" --query 'Job.{glue:GlueVersion,worker:WorkerType,n:NumberOfWorkers,class:ExecutionClass,secconf:SecurityConfiguration,args:DefaultArguments}'
aws glue get-job-runs --job-name "$JOB" --max-results 10 \
  --query 'JobRuns[].[Id,JobRunState,StartedOn,ExecutionTime,DPUSeconds,ErrorMessage]' --output table
aws glue get-job-bookmark --job-name "$JOB" --query 'JobBookmarkEntry.{run:RunId,attempt:Attempt,version:Version}'

# Glue 實際寫 log 的 log group
aws logs describe-log-groups --log-group-name-prefix /aws-glue/ --query 'logGroups[].[logGroupName,kmsKeyId]' --output text
aws logs filter-log-events --log-group-name "/aws-glue/jobs/$N-etl/$JOB" --filter-pattern '?ERROR ?Exception ?AccessDenied' \
  --max-items 20 --query 'events[].message' --output text

# curated 的結果
aws glue get-tables --database-name "$CURATED_DB" \
  --query 'TableList[].{name:Name,partitions:PartitionKeys[].Name,location:StorageDescriptor.Location,cols:StorageDescriptor.Columns[].Name}'
aws s3 ls "s3://$CURATED_BUCKET/events/" --recursive | head
```

【寫入】用 Athena 比對筆數（會寫結果到 athena-results bucket）：

```bash
athena() {
  local q
  q=$(aws athena start-query-execution --work-group "$WG" --query-execution-context Database="$CURATED_DB" \
        --query-string "$1" --query QueryExecutionId --output text)
  while :; do
    s=$(aws athena get-query-execution --query-execution-id "$q" --query QueryExecution.Status.State --output text)
    case "$s" in SUCCEEDED|FAILED|CANCELLED) break ;; esac; sleep 2
  done
  aws athena get-query-execution --query-execution-id "$q" --query 'QueryExecution.Status.{state:State,reason:StateChangeReason}'
  [ "$s" = SUCCEEDED ] && aws athena get-query-results --query-execution-id "$q" --query 'ResultSet.Rows[].Data[].VarCharValue' --output text
  return 0
}
athena "SELECT count(*) FROM events"
athena "SELECT count(*), count(DISTINCT event_id) FROM events WHERE event_id LIKE 'verify-%'"
athena "SELECT event_id, event_time, payload, year, month, day, hour FROM events LIMIT 5"
```

名稱怎麼來的：crawler 名稱就是 map key `raw`（`pipeline/glue.tf:11`、`modules/glue-etl/main.tf:30`），目標 `s3://<raw bucket>/raw/`（`pipeline/glue.tf:14`）；security configuration `"${local.name_prefix}-etl"`（`pipeline/glue.tf:54`、`modules/glue-etl/main.tf:7`）；job log group `"/aws-glue/jobs/${var.name}/${each.key}"`（`modules/glue-etl/main.tf:53`）；Glue 5.1、G.1X × 2、FLEX（`pipeline/glue.tf:24-26`、`modules/glue-etl/variables.tf:71`）；腳本的表名改名與 partition 欄位（`etl/raw_to_curated.py:23`、`:26`），寫到 `<curated_path><target>/`（`:66`）。

**預期結果**

- crawler 成功，raw database 有一個 `raw` table（REFERENCE.md:233 的推論），partition 是 `partition_0`–`partition_3`，classification `json`。名稱不是 `raw` 時，腳本的 `TARGET_TABLES`（`etl/raw_to_curated.py:23`）要跟著改。
- job 成功，`ErrorMessage` 是空的；log 沒有 `AccessDenied`。失敗訊息含 `logs:AssociateKmsKey` 或 `glue:GetSecurityConfiguration` 時，記下來交給第 17 項。
- 記下 `/aws-glue/` 底下實際出現的 log group 名稱（REFERENCE.md:279 與 :299 列為未驗證）。
- curated database 有 `events` table，partition 是 `year`、`month`、`day`、`hour`，location 是 `s3://<curated bucket>/events/`；S3 有 Parquet 檔。
- Athena 的總筆數等於送進去的筆數；`verify-*` 的 `count` 等於 `count(DISTINCT)`（bookmark 沒有重複處理）。
- 可能不通過的兩點，請記下實際行為：
  - 欄位 `@timestamp` 讓 Athena 查詢失敗（推測，見〈結論〉第 5 點）。
  - Firehose 寫 S3 時記錄之間沒有換行（module 沒設 processing，`modules/firehose-stream/main.tf:52-71`），crawler 或 job 只讀到每個檔案的第一筆（推測）。筆數明顯少於送出數時就是這個原因。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／raw table 名稱 ______ ／備註 ______

## 12. Glue job 成本

**前提**

- 第 10、11 項跑過至少一天（dev 至少 10 次 job run）。

**指令**

```bash
# 每次 run 的時間與 DPU 秒數
aws glue get-job-runs --job-name "$JOB" --max-results 100 \
  --query 'JobRuns[?JobRunState==`SUCCEEDED`].[StartedOn,ExecutionTime,DPUSeconds,ExecutionClass]' --output table

# 平均每次的成本（Flex 0.29 美元／DPU-小時，REFERENCE.md:218）
aws glue get-job-runs --job-name "$JOB" --max-results 100 --query 'JobRuns[?JobRunState==`SUCCEEDED`].DPUSeconds' --output json \
  | jq '{runs: length, avg_dpu_seconds: (add / length), avg_usd: (add / length / 3600 * 0.29)}'

# crawler 每次的時間
aws glue get-crawler-metrics --crawler-name-list raw --query 'CrawlerMetricsList[].{last:LastRuntimeSeconds,median:MedianRuntimeSeconds}'

# 帳單上的 Glue（Cost Explorer 每次呼叫收費約 0.01 美元）
aws ce get-cost-and-usage --time-period Start=<YYYY-MM-DD>,End=<YYYY-MM-DD> --granularity DAILY --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["AWS Glue"]}}' \
  --query 'ResultsByTime[].[TimePeriod.Start,Total.UnblendedCost.Amount]' --output text
```

名稱怎麼來的：同第 11 項。Flex 與 G.1X × 2（`pipeline/glue.tf:24-26`）；最低計費 job 每次 1 分鐘、crawler 每次 10 分鐘（`modules/glue-etl/README.md`〈注意〉，引自 Glue 定價頁）。

**預期結果**

- `ExecutionTime` 與 `DPUSeconds` 有值；平均每次約 0.029 美元（3 分鐘、2 DPU 的估計）。
- 每月估計：平均每次成本 × 每天 run 次數 × 30。dev 約 28 美元、sit 約 84 美元（REFERENCE.md:218）。差距超過一倍就回寫實際數字。
- 帳單的 Glue 金額跟上面的估算同一個量級（帳單還含 crawler：每天 1 次、每次至少 10 分鐘）。
- 記下：Flex 從 `StartedOn` 到開始執行的等待時間（Flex 的啟動時間不固定）。

**結果紀錄**：日期 ______ ／執行人 ______ ／平均每次 ______ 秒、______ 美元 ／每月估計 ______ 美元

## 13. catalog 加密後的 KMS 權限

**前提**

- 階段 0：確認這個帳號、這個 region 沒有別的專案管 catalog 加密（README〈前置作業〉第 3 點）。第二個專案的 `foundation` tfvars 要設 `glue_catalog_encryption = null`。
- 階段 0：Lake Formation 維持 IAM 模式（REFERENCE.md:140）。
- 第 11、14、16 項各自代表一種身分讀寫 catalog；本項彙整。

**指令**

```bash
# 階段 0（apply foundation 之前）與階段 A 之後各跑一次
aws glue get-data-catalog-encryption-settings --query 'DataCatalogEncryptionSettings'
aws lakeformation get-data-lake-settings \
  --query 'DataLakeSettings.{admins:DataLakeAdmins,db:CreateDatabaseDefaultPermissions,table:CreateTableDefaultPermissions}'

# 帳號裡其他專案的 database
aws glue get-databases --query 'DatabaseList[].Name' --output text | tr '\t' '\n' | grep -v "^${P}_${E}_"

# 各角色的 KMS 呼叫有沒有被拒（最近 2 小時）
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=kms.amazonaws.com \
  --start-time "$(date -u -v-2H +%FT%TZ 2>/dev/null || date -u -d '-2 hour' +%FT%TZ)" --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | select(.errorCode != null)
           | "\(.userIdentity.sessionContext.sessionIssuer.userName // .userIdentity.arn) \(.eventName) \(.errorCode)"' \
  | sort | uniq -c
```

同帳號其他專案：請它們的 owner 在階段 A 之後跑一次自己的 Glue job 或 Athena 查詢，回報有沒有 `AccessDeniedException`（KMS）。

只在拆環境時（design §5.7、REFERENCE.md:278）：destroy `foundation` 前後各跑一次 `get-data-catalog-encryption-settings`，記下設定有沒有改回未加密。

名稱怎麼來的：`glue_catalog_encryption = {}` 時用 `foundation` 的共用 key（`foundation/glue-catalog-encryption.tf:3-5`、`foundation/envs/dev.tfvars:11`）；各角色的 key 權限：crawler 與 job `kms:Decrypt`、`kms:Encrypt`、`kms:GenerateDataKey`（`iam-base/policies.tf:43-48`）、Redshift 只有 `kms:Decrypt`（`:150-155`）、QuickSight Athena role 三個都有（`iam-app/quicksight-athena.tf:58-63`）。

**預期結果**

- 階段 0：`CatalogEncryptionMode` 是 `DISABLED`，或已由別處設定（那就把本專案設 `null`）。
- 階段 A 之後：`CatalogEncryptionMode: SSE-KMS`，`SseAwsKmsKeyId` 是 `$KMS_KEY`。
- Lake Formation：`CreateDatabaseDefaultPermissions`、`CreateTableDefaultPermissions` 都是 `IAM_ALLOWED_PRINCIPALS` 的 `ALL`。
- crawler、job（第 11 項）、Redshift（第 14 項）、QuickSight Athena role（第 16 項）讀寫 catalog 都成功；CloudTrail 沒有這些 role 的 KMS 錯誤。
- 其他專案回報沒有受影響；有影響時，它們的 role 要補這把 key 的權限（REFERENCE.md:125）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／其他專案 ______ ／destroy 後的設定 ______

## 14. Redshift Spectrum

**前提**

- 階段 F 完成，`warehouse_mode = "serverless"`（`warehouse/envs/dev.tfvars:6-11`）；第 11 項的 curated `events` 已有資料。
- 執行身分要能讀 `redshift_admin_secret_arn`（加上 `foundation` CMK 的 `kms:Decrypt`）。
- EVR 關閉（`warehouse/variables.tf:18`），Spectrum 走 Redshift 自己的網路；`redshift` SG 沒有 egress（REFERENCE.md:301）。

**指令**

```bash
aws redshift-serverless get-workgroup --workgroup-name "$N-warehouse" \
  --query 'workgroup.{status:status,evr:enhancedVpcRouting,public:publiclyAccessible,base:baseCapacity,max:maxCapacity,cfg:configParameters,subnets:subnetIds,sg:securityGroupIds,endpoint:endpoint.address}'
aws redshift-serverless get-namespace --namespace-name "$N-warehouse" \
  --query 'namespace.{status:status,kms:kmsKeyId,roles:iamRoles,default:defaultIamRoleArn,logs:logExports,admin:adminUsername}'
aws redshift-serverless list-usage-limits --resource-arn "$(aws redshift-serverless get-workgroup --workgroup-name "$N-warehouse" --query workgroup.workgroupArn --output text)"
```

【寫入】建 external schema 並查詢：

```bash
rs "CREATE EXTERNAL SCHEMA IF NOT EXISTS curated_ext FROM DATA CATALOG DATABASE '$CURATED_DB' IAM_ROLE default"
rs "SELECT count(*) FROM curated_ext.events"
rs "SELECT event_id, event_time FROM curated_ext.events LIMIT 5"
```

選做（只在第 20 項切到 provisioned 時）：把 `provisioned.enhanced_vpc_routing` 改成 `true` 再 apply【寫入】，重跑上面的 `SELECT`。預期會失敗或逾時（沒有 S3 egress）。要讓它成功得在 `network` 加 S3 prefix list 的 443 egress，那是程式碼修改，不在本文。做完改回 `false`。

名稱怎麼來的：workgroup 與 namespace 名稱（`warehouse/redshift.tf:15`、`modules/redshift-serverless/main.tf:12`、`:34`）；`require_ssl` 寫死在 config parameter（`modules/redshift-serverless/main.tf:5`）；預設 IAM role 是 `iam-base` 的 `redshift`（`warehouse/redshift.tf:4`、`:18-19`、`iam-base/roles.tf:33`）；usage limit 100 RPU-小時、`deactivate`（`warehouse/envs/dev.tfvars:10`、`modules/redshift-serverless/main.tf:56-64`）；管理者帳號預設 `dbadmin`（`modules/redshift-serverless/variables.tf:23`）。

**預期結果**

- workgroup `AVAILABLE`，`enhancedVpcRouting: false`、`publiclyAccessible: false`，base 4、max 8；`configParameters` 有 `require_ssl = true`（design K5 的「config key 未確認」，這裡確認），subnet 是兩個 data subnet、SG 是 `$SG_RS`。workgroup 用 2 個 AZ 建得起來，就確認了 design §2 第 14 點「沒開 EVR 時 2 AZ 可以」。
- namespace 的 `kmsKeyId` 是 `$KMS_KEY`，`iamRoles` 有 `<project>-<env>-redshift`，`logExports` 有三種。
- usage limit 一筆：`serverless-compute`、`monthly`、`deactivate`、100。
- `CREATE EXTERNAL SCHEMA` 成功；`count(*)` 等於第 11 項 Athena 的總筆數；`SELECT` 回 5 筆。
- 失敗時看 `error`：`AccessDenied`（catalog 或 S3）屬於第 13、17 項；`@timestamp` 欄位相關錯誤屬於〈結論〉第 5 點。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 15. `ra3.large` single-node

**前提**

- 唯讀部分隨時可做；實際建立在第 20 項切到 provisioned 時一起記錄。

**指令**

```bash
aws redshift describe-orderable-cluster-options --node-type ra3.large \
  --query 'OrderableClusterOptions[].{type:ClusterType,version:ClusterVersion,azs:AvailabilityZones[].Name}'
```

第 20 項 apply 之後：

```bash
aws redshift describe-clusters --cluster-identifier "$N-warehouse" \
  --query 'Clusters[0].{status:ClusterStatus,node:NodeType,type:NumberOfNodes,az:AvailabilityZone,evr:EnhancedVpcRouting,encrypted:Encrypted,kms:KmsKeyId,public:PubliclyAccessible}'
```

名稱怎麼來的：`node_type = "ra3.large"`、`number_of_nodes = 1`（`warehouse/envs/examples/provisioned.tfvars:11-12`）；`cluster_type` 在 1 台時是 `single-node`（`modules/redshift-cluster/main.tf:41`）；cluster id（`warehouse/redshift.tf:36`）。

**預期結果**

- `OrderableClusterOptions` 有 `single-node`，AZ 含 `ap-northeast-1a` 與 `ap-northeast-1c`（`network/envs/dev.tfvars:6`）。
- 第 20 項建出來的 cluster `available`，`ra3.large`、1 台，位在其中一個 data subnet 的 AZ，加密用 `$KMS_KEY`，不公開。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 16. QuickSight 兩種來源

**前提**

- 階段 0：QuickSight 訂閱是 Enterprise 版；`bi` tfvars 的 `owner_principals`、`reader_principals` 換成真實的 group ARN（`bi/envs/dev.tfvars:10-11`）。
- 第 11 項的 curated `events` 有資料。
- Redshift 的部分（階段 G 後半）：
  1. 【寫入】在 Redshift 建唯讀 user 與一張表（REFERENCE.md:130-137；表從 Spectrum 複製，給 `events_dw` dataset 用）：

     ```bash
     rs "CREATE TABLE public.events AS SELECT event_id, event_time FROM curated_ext.events"
     # 密碼由人產生，用 Query Editor 或 rs 執行 REFERENCE.md:133-136 的四行 SQL
     ```

  2. 【寫入】在 Secrets Manager 建 secret，內容 `{"username":"quicksight_reader","password":"..."}`，記下 ARN。
  3. QuickSight 管理者在主控台把這個 secret 授權給 QuickSight（REFERENCE.md:129）。
  4. 把 `bi/envs/examples/redshift.tfvars:11` 的 ARN 與 `:13-14` 的 principal 換成真的，`./stacks.sh dev bi apply -- -var-file=envs/examples/redshift.tfvars`【寫入】。之後只用 `dev.tfvars` apply 會把 Redshift 來源拿掉，驗完要不要保留由專案決定。

**指令**

```bash
aws quicksight describe-account-subscription --aws-account-id "$ACCOUNT" \
  --query 'AccountInfo.{edition:Edition,status:AccountSubscriptionStatus}'

# Athena 來源與 dataset
aws quicksight describe-data-source --aws-account-id "$ACCOUNT" --data-source-id athena \
  --query 'DataSource.{status:Status,error:ErrorInfo,params:DataSourceParameters}'
aws quicksight describe-data-set --aws-account-id "$ACCOUNT" --data-set-id events \
  --query 'DataSet.{mode:ImportMode,cols:OutputColumns[].[Name,Type]}'
aws quicksight describe-data-set-permissions --aws-account-id "$ACCOUNT" --data-set-id events \
  --query 'Permissions[].[Principal,length(Actions)]' --output text

# Athena 是用專用 role 查的
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StartQueryExecution --max-results 50 --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | "\(.eventTime) \(.userIdentity.arn) \(.requestParameters.workGroup) \(.errorCode // "OK")"'

# Redshift 來源與 VPC connection
aws quicksight describe-vpc-connection --aws-account-id "$ACCOUNT" --vpc-connection-id "$N-quicksight" \
  --query 'VPCConnection.{status:Status,availability:AvailabilityStatus,role:RoleArn,sg:SecurityGroupIds,enis:NetworkInterfaces[].[NetworkInterfaceId,SubnetId,Status,ErrorMessage]}'
aws quicksight describe-data-source --aws-account-id "$ACCOUNT" --data-source-id redshift \
  --query 'DataSource.{status:Status,error:ErrorInfo,params:DataSourceParameters,vpc:VpcConnectionProperties,ssl:SslProperties,secret:SecretArn}'
aws ec2 describe-network-interfaces --filters Name=group-id,Values="$SG_QS" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,SubnetId,Status,Description]' --output table
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$SG_QS" \
  --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,ReferencedGroupInfo.GroupId]' --output table
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateNetworkInterface --max-results 50 --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | select(.userIdentity.arn | test("quicksight-vpc")) | "\(.eventTime) \(.errorCode // "OK") \(.errorMessage // "")"'
```

主控台：用 owner 群組的帳號從 `events` 與 `events_dw` 各建一個 analysis，看得到資料列；用 reader 群組的帳號能開 dataset、不能改。

名稱怎麼來的：Athena 來源 id `athena`、Redshift 來源 id `redshift`（`bi/quicksight.tf:6`、`:14`、`modules/quicksight-data/main.tf:64`、`:93`）；Athena role `"${local.name_prefix}-quicksight-athena"`（`iam-app/quicksight-athena.tf:71`）；VPC connection id `"${local.name_prefix}-quicksight"`，用 data subnet 與 `quicksight` SG，role 是 `quicksight-vpc`（`bi/quicksight.tf:23-28`、`iam-base/roles.tf:40`）；dataset id `events`（`bi/envs/dev.tfvars:15`）與 `events_dw`（`bi/envs/examples/redshift.tfvars:25`），一律 `DIRECT_QUERY`（`bi/quicksight.tf:33`）。

**預期結果**

- 訂閱 `ENTERPRISE`、`ACCOUNT_CREATED`。
- `athena` 來源 `CREATION_SUCCESSFUL`，workgroup 是 `$WG`，role 是 `<project>-<env>-quicksight-athena`；`events` 是 `DIRECT_QUERY`，三個欄位；owner、reader 各一筆權限。
- CloudTrail 的 `StartQueryExecution` 由 `assumed-role/<project>-<env>-quicksight-athena/...` 發出，workgroup 是 `$WG`，`OK`。
- VPC connection `AVAILABLE`，兩個 ENI 在 data subnet、`AVAILABLE`、沒有 `ErrorMessage`；CloudTrail 的 `CreateNetworkInterface` 都 `OK`（`quicksight-vpc` role 的 ENI 權限夠用）。
- `redshift` 來源 `CREATION_SUCCESSFUL`，SSL 開著，用 VPC connection 與 secret。
- 主控台兩個 analysis 都有資料列；reader 不能編輯。
- 很可能不通過的一點（〈結論〉第 2 點）：`$SG_QS` 只有一條 egress。Redshift 來源 `CREATION_FAILED` 或預覽逾時時，先看這裡。

**結果紀錄**：日期 ______ ／執行人 ______ ／Athena 通過 □ 不通過 □ ／Redshift 通過 □ 不通過 □ ／備註 ______

## 17. IAM 動作清單

**前提**

- 第 9–16 項都跑過。記下階段 E 開始的時間 `<START>`（ISO 8601，UTC）。

**指令**

```bash
# 7 個 role 被拒的 API（CloudTrail 只有 management event；S3 物件層的拒絕看各服務的 log）
aws cloudtrail lookup-events --start-time "<START>" --output json \
  | jq -r --arg n "$N-" '.Events[].CloudTrailEvent | fromjson | select(.errorCode != null)
      | select((.userIdentity.sessionContext.sessionIssuer.userName // "") | startswith($n))
      | "\(.userIdentity.sessionContext.sessionIssuer.userName) \(.eventSource) \(.eventName) \(.errorCode)"' \
  | sort | uniq -c

# Glue、Firehose 的 log 裡的權限錯誤
aws logs filter-log-events --log-group-name "/aws-glue/jobs/$N-etl/$JOB" --filter-pattern '?AccessDenied ?"not authorized"' \
  --max-items 20 --query 'events[].message' --output text
for s in to-raw to-search; do
  aws logs filter-log-events --log-group-name "/aws/kinesisfirehose/$N-$s" --filter-pattern '?AccessDenied ?"not authorized"' \
    --max-items 20 --query 'events[].message' --output text
done
aws glue get-crawler --name raw --query 'Crawler.LastCrawl.{status:Status,error:ErrorMessage}'

# Firehose 建 ENI 時用到哪些 subnet（判斷能不能把 app subnet 從 policy 拿掉）
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateNetworkInterface --start-time "<START>" --output json \
  | jq -r '.Events[].CloudTrailEvent | fromjson | select(.userIdentity.arn | test("-firehose/"))
           | "\(.requestParameters.subnetId) \(.requestParameters.groupSet.items[0].groupId // "-") \(.errorCode // "OK")"' | sort | uniq -c
ssm network/subnet_ids_app

# 多給的權限：Firehose role 實際用過哪些服務（es 的動作層紀錄 AWS 可能不提供，推測）
JOBID=$(aws iam generate-service-last-accessed-details --arn "arn:aws:iam::$ACCOUNT:role/$N-firehose" --granularity ACTION_LEVEL --query JobId --output text)
aws iam get-service-last-accessed-details --job-id "$JOBID" \
  --query 'ServicesLastAccessed[].{svc:ServiceNamespace,last:LastAuthenticated,actions:TrackedActionsLastAccessed[].[ActionName,LastAccessedTime]}'
```

名稱怎麼來的：6 個 role 的名稱（`iam-base/roles.tf:5`、`:10`、`:17`、`:25`、`:33`、`:40`）與 `quicksight-athena`（`iam-app/quicksight-athena.tf:71`），都以 `<project>-<env>-` 開頭；Glue 的 log 權限範圍 `/aws-glue/*`（`iam-base/policies.tf:40`、`:50-55`）；Firehose 的 ENI 權限包含 app 與 data 兩層 subnet（`iam-app/firehose-policy.tf:19-21`、`:63-71`），`es:DescribeDomain*`（`:44-48`）；Firehose 的 log 權限只有 `logs:PutLogEvents`（`:85-90`）。

**預期結果**

- 第一段的輸出是空的。有輸出時，每一行就是一個要補的動作，記下 role、服務、動作。很可能出現的（〈結論〉第 1 點、REFERENCE.md:299）：`glue-crawler`、`glue-job` 的 `logs:AssociateKmsKey`、`glue:GetSecurityConfiguration`。
- Glue 與 Firehose 的 log 沒有權限錯誤；crawler `SUCCEEDED`。
- Firehose 建 ENI 時只用了 data subnet。這樣 `iam-app/firehose-policy.tf:19-21` 可以收窄成只有 data subnet（design §11 第 16 列）。
- last-accessed 的 `es` 有紀錄；`es:DescribeDomain*` 有沒有被用過，有紀錄就記下，沒有動作層紀錄就記「無法判定」。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／要補的動作 ______ ／可以拿掉的動作 ______

## 18. OpenSearch 告警的 `ClientId`

**前提**

- 階段 C 完成且 domain 跑了至少 15 分鐘；`foundation` 的 `alarm_emails` 換成會收信的地址並已確認訂閱。
- 告警的 `treat_missing_data` 預設是 `notBreaching`（`modules/metric-alarm/variables.tf:17`）：dimension 寫錯時告警會一直是 `OK`，所以**不能只看告警狀態**，要直接用告警的 dimension 查指標。

**指令**

```bash
# AWS/ES 實際發布的 dimension
aws cloudwatch list-metrics --namespace AWS/ES --metric-name FreeStorageSpace \
  --dimensions Name=DomainName,Value="$DOMAIN" --query 'Metrics[].Dimensions'

# 告警用的 dimension 與狀態
aws cloudwatch describe-alarms --alarm-name-prefix "$N-" \
  --query 'MetricAlarms[?Namespace==`AWS/ES`].[AlarmName,StateValue,MetricName,Dimensions[?Name==`ClientId`].Value|[0]]' --output table

# 用告警的 dimension 查得到資料點
for m in ClusterStatus.red FreeStorageSpace JVMMemoryPressure WarmJVMMemoryPressure; do
  echo "== $m"
  aws cloudwatch get-metric-statistics --namespace AWS/ES --metric-name "$m" \
    --dimensions Name=DomainName,Value="$DOMAIN" Name=ClientId,Value="$ACCOUNT" \
    --start-time "$(date -u -v-30M +%FT%TZ 2>/dev/null || date -u -d '-30 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 300 --statistics Maximum --query 'length(Datapoints)'
done
```

【寫入】確認告警會寄信：

```bash
aws cloudwatch set-alarm-state --alarm-name "$N-cluster-status-red" --state-value ALARM --state-reason "runbook test"
```

名稱怎麼來的：告警名稱 `"${var.name_prefix}-${replace(k, "_", "-")}"`（`modules/metric-alarm/main.tf:2`），key 是 `cluster_status_red`、`free_storage_space`、`jvm_memory_pressure`、`warm_jvm_memory_pressure`、`hot_to_warm_migration_failed`、`warm_to_cold_migration_failed`（`search/alarms.tf:9`、`:14`、`:21`、`:29`、`:34`、`:42`）；dimension `DomainName`、`ClientId = var.expected_account_id`（`search/alarms.tf:3`）；剩餘空間門檻 `20 * 1024 / 4 = 5120` MiB（`search/alarms.tf:18`、`search/envs/dev.tfvars:12`）。

**預期結果**

- `list-metrics` 的 dimension 是 `DomainName` 加 `ClientId`，`ClientId` 等於 `$ACCOUNT`。
- 6 個 `AWS/ES` 告警的 `ClientId` 都是 `$ACCOUNT`。
- 前三個指標的資料點數大於 0；`WarmJVMMemoryPressure` 在 warm 可用後大於 0。`HotToWarmMigrationFailureCount`、`WarmToColdMigrationFailureCount` 平常沒有資料，不檢查資料點。
- `set-alarm-state` 之後收到 email；下一次評估時告警回到 `OK`。
- `storage` 與 `pipeline` 的告警（例如 `$N-stream-iterator-age`、`$N-firehose-opensearch-data-freshness`）也用同樣的方式查一次資料點（`storage/alarms.tf:19-23`、`pipeline/alarms.tf:16-26`）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 19. master 密碼輪替

**前提**

- 第 7、8 項完成，VPN 連著。照 REFERENCE.md:163 的步驟做。
- REFERENCE.md:119-122 產生密碼的指令沒有排除 `"`、`\`，但 `opensearch-domain` README〈注意〉建議避開這兩個字元與空白。下面加了 `--exclude-characters`。

**指令**

```bash
# 0. 輪替前：secret 版本、state 裡密碼的份數、state 物件的版本
aws secretsmanager list-secret-version-ids --secret-id "$MASTER_SECRET" --query 'Versions[].[VersionId,VersionStages[0],CreatedDate]' --output table
(cd search && TF_DATA_DIR=".terraform-$E" terraform state pull) \
  | jq '[paths | .[-1] | strings | select(. == "master_user_password" or . == "secret_string")] | length'
aws s3api list-object-versions --bucket "<state-bucket>" --prefix "$P-$E/search/terraform.tfstate" \
  --query 'Versions[].[VersionId,IsLatest,LastModified]' --output table
```

【寫入】輪替：

```bash
# 1. 新密碼（管線，不經過指令參數與 shell 變數）
aws secretsmanager get-random-password --password-length 32 --require-each-included-type --exclude-characters '"\' \
    --query RandomPassword --output text \
  | jq -Rc '{username: "master", password: .}' \
  | aws secretsmanager put-secret-value --secret-id "$MASTER_SECRET" --secret-string file:///dev/stdin

# 2. search：只應該改 master_user_options
./stacks.sh "$E" search plan
./stacks.sh "$E" search apply

# 3. search-config：ephemeral 重新讀，零差異而且連得上
./stacks.sh "$E" search-config plan
```

輪替後：

```bash
osq "/_plugins/_security/authinfo" | jq .user_name                                         # 新密碼
STAGE=AWSPREVIOUS osq "/_plugins/_security/authinfo" -o /dev/null -w '%{http_code}\n'        # 舊密碼
aws opensearch describe-domain-change-progress --domain-name "$DOMAIN" --query 'ChangeProgressStatus.{status:Status,stages:ChangeProgressStages[].Name}'
```

30 天後：重跑步驟 0 的 `list-object-versions`，輪替前的 state 版本應該已經不在。

名稱怎麼來的：secret 名稱 `"${local.name_prefix}/opensearch-master"`（`foundation/secrets.tf:4`）；`username` 沿用 `master`（REFERENCE.md:121）；密碼在 state 的兩份：domain 屬性與讀 secret 的 data source（`modules/opensearch-domain/main.tf:7-9`、`:120-123`）；state key（第 1 項）。

**預期結果**

- 輪替前 state 裡的份數是 `2`（REFERENCE.md:158 的「共兩份」），輪替後仍是 `2`（換成新值）。
- `search` 的 plan 只有 `aws_opensearch_domain.this` 的 in-place 更新，內容是 sensitive 的 `master_user_options`；apply 成功。記下有沒有觸發 blue/green（change progress 的 stage 名稱）。
- `search-config` 的 plan 成功、`No changes`。
- 新密碼的 `authinfo` 回 master 名稱；舊密碼回 `401`。
- 30 天後舊的 state 版本已過期（第 1 項的 lifecycle 規則）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／是否 blue/green ______ ／30 天後確認日期 ______

## 20. `warehouse_mode` 防呆與切換

**前提**

- 階段 F、G 完成，目前是 `serverless`。
- 本項會刪掉 Serverless 的資料，只在 dev 做。
- `bash warehouse/tests/check-warehouse-guard.sh` 通過（REFERENCE.md:324）。

**指令**

先驗會被擋（都是 plan，唯讀）：

```bash
./stacks.sh dev warehouse plan                          # 1. 零差異
./stacks.sh dev warehouse plan -- -destroy              # 2. destroy 被擋（等於 dev 拆環境停在 warehouse）

# 3. 本機改 warehouse/envs/dev.tfvars：warehouse_mode = "provisioned"、serverless 拿掉、
#    provisioned = { node_type = "ra3.large", number_of_nodes = 1 }（照 envs/examples/provisioned.tfvars:8-15）
./stacks.sh dev warehouse plan                          # 預期失敗
aws redshift-serverless get-workgroup --workgroup-name "$N-warehouse" --query workgroup.status   # 仍是 AVAILABLE
```

【寫入】照 REFERENCE.md:249-256 解除、切換、還原：

```bash
# 備份：Redshift role 沒有 curated 的 PutObject，不能 UNLOAD 到 curated（〈結論〉第 3 點），改用手動 snapshot
aws redshift-serverless create-snapshot --namespace-name "$N-warehouse" --snapshot-name "$N-warehouse-before-switch"
aws redshift-serverless get-snapshot --snapshot-name "$N-warehouse-before-switch" --query 'snapshot.status'   # 等到 AVAILABLE

# 本機把 warehouse/guard.tf 的 prevent_destroy 改成 false（不 commit）
./stacks.sh dev warehouse plan          # 只應該有預期的 destroy 與 create
./stacks.sh dev warehouse apply

git checkout -- warehouse/guard.tf
./stacks.sh dev warehouse plan          # 零差異
bash warehouse/tests/check-warehouse-guard.sh

# SSM 換成 provisioned 的值；重跑共用變數讓 RS_MODE 等更新
ssm warehouse/redshift_mode; ssm warehouse/redshift_host
./stacks.sh dev bi plan                 # 有 Redshift 來源時應該只更新 host
```

接著做第 15 項的建立部分。切回 `serverless`（選做）時再走一次同樣的步驟，這次 provisioned 會留 final snapshot：

```bash
aws redshift describe-cluster-snapshots --snapshot-identifier "$N-warehouse-final" --query 'Snapshots[0].{status:Status,type:SnapshotType}'
```

最後 `git checkout -- warehouse/envs/dev.tfvars`，確認 `git status` 乾淨。

名稱怎麼來的：防呆 `terraform_data.warehouse_mode_guard`、`triggers_replace = var.warehouse_mode`、`prevent_destroy = true`（`warehouse/guard.tf:3-9`），兩個 module 都 `depends_on` 它（`warehouse/redshift.tf:27`、`:50`）；交叉 validation 要求另一個物件是 `null`（`warehouse/variables.tf:22-25`、`:41-44`），所以只加 `-var-file=envs/examples/provisioned.tfvars` 不夠，`dev.tfvars` 的 `serverless` 要拿掉；final snapshot `"${var.name}-final"`（`modules/redshift-cluster/main.tf:66`）；`stacks.sh` 把 `--` 之後的參數交給 `terraform plan`（`stacks.sh:124`）。手動 snapshot 名稱是本文自取的。

**預期結果**

- 步驟 1 零差異。
- 步驟 2 失敗，錯誤是 `Instance cannot be destroyed`，指向 `terraform_data.warehouse_mode_guard`（以及 Serverless 的資源，看實際輸出）。
- 步驟 3 失敗，錯誤同上，指向 `terraform_data.warehouse_mode_guard`：**replace 也會被 `prevent_destroy` 擋下**（design §2 第 19 點的推論成立）。workgroup 仍是 `AVAILABLE`。
- 解除後的 plan：`terraform_data.warehouse_mode_guard` 要 replace；`module.serverless[0]` 的 namespace、workgroup、usage limit 刪除；`module.provisioned[0]` 的 subnet group、parameter group、cluster、logging 新增。沒有其他資源。
- 還原 `guard.tf` 後 plan 零差異，`check-warehouse-guard.sh` 通過。
- SSM 的 `redshift_mode` 是 `provisioned`，host 換成 cluster endpoint。
- 切回時 final snapshot `available`、`manual`。
- `git status` 沒有殘留的修改。

**結果紀錄**：日期 ______ ／執行人 ______ ／防呆擋下 □ 沒擋下 □ ／切換通過 □ 不通過 □ ／備註 ______

## 21. ISM 冷熱搬移

**前提**

- 第 9 項之後持續有資料（每天至少一筆，才會每天有一個新 index）。
- 照 dev 的天數（第 3 天 warm、第 7 天 cold、第 30 天刪，`search-config/envs/dev.tfvars:6-11`）要觀察 30 天。
- 縮短做法【寫入】（只在 dev）：用最小天數覆寫，套到既有 index，觀察 3–4 天後還原。天數必須嚴格遞增、warm 至少 1（`modules/opensearch-config/variables.tf:25`）：

  ```bash
  ./stacks.sh dev search-config apply -- -var 'ism={warm_days=1,cold_days=2,delete_days=3,timestamp_field="@timestamp"}'
  osq "/_plugins/_ism/change_policy/$N-events*" -XPOST -H 'content-type: application/json' -d '{"policy_id":"logs"}'
  # 觀察完還原
  ./stacks.sh dev search-config apply
  osq "/_plugins/_ism/change_policy/$N-events*" -XPOST -H 'content-type: application/json' -d '{"policy_id":"logs"}'
  ```

  `warm_days = 1` 時，當天還在寫的 index 一過午夜就可能被搬進 warm（唯讀），晚到的資料會進 `errors/`。這是縮短做法造成的，不算不通過。

**指令**

每天跑一次：

```bash
# 每個 index 目前的 ISM 狀態
osq "/_plugins/_ism/explain/$N-events*" \
  | jq -r 'to_entries[] | select(.key | startswith("'"$N"'-events"))
           | [.key, (.value.state.name // "-"), (.value.action.name // "-"), ((.value.action.failed // false) | tostring), (.value.info.message // "")] | @tsv'

# hot、warm、cold 各有哪些 index（AWS 的 API，推測）
osq "/_cat/indices/_hot?v&h=index,docs.count,creation.date.string" | grep events
osq "/_cat/indices/_warm?v&h=index,docs.count,creation.date.string" | grep events
osq "/_cold/indices/_search" -XPOST -H 'content-type: application/json' -d '{}' | jq '[.indices[]?.index]'

# 搬移成功與失敗的指標
for m in HotToWarmMigrationSuccessCount HotToWarmMigrationFailureCount WarmToColdMigrationSuccessCount WarmToColdMigrationFailureCount; do
  echo "== $m"
  aws cloudwatch get-metric-statistics --namespace AWS/ES --metric-name "$m" \
    --dimensions Name=DomainName,Value="$DOMAIN" Name=ClientId,Value="$ACCOUNT" \
    --start-time "$(date -u -v-1d +%FT%TZ 2>/dev/null || date -u -d '-1 day' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 3600 --statistics Sum --query 'sum(Datapoints[].Sum)'
done
```

名稱怎麼來的：ISM policy 的 states、`warm_migration`（重試 5 次、間隔 1 小時）、`cold_migration` 帶 `timestamp_field`、經過 cold 的 index 用 `cold_delete`（`modules/opensearch-config/main.tf:4-39`）；天數是累計年齡（REFERENCE.md:199）；失敗指標名稱（`search/alarms.tf:37`、`:45`），成功指標名稱是 AWS 的命名（推測）。

**預期結果**

- 每個 index 依建立日起算：第 3 天前在 `hot`，第 3 天轉 `warm`、出現在 `_warm`，第 7 天轉 `cold`、出現在 `_cold/indices/_search`，第 30 天消失。縮短做法時是 1／2／3 天。
- explain 沒有 `failed: true`；`info.message` 沒有錯誤。cold 搬移成功代表 `@timestamp` 的 mapping 可用。
- 成功指標有數字，失敗指標是 0；`$N-hot-to-warm-migration-failed`、`$N-warm-to-cold-migration-failed` 沒有進 `ALARM`。
- 記下：ISM 從到期到實際搬完的延遲（ISM 的檢查週期加上搬移時間）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／用的天數 ______ ／延遲 ______

## S1. data subnet 的 IP 預算（寫這份文件時發現）

**前提**

- 每個 data subnet 是 `/27`（`network/vpc.tf:10`），扣掉 AWS 保留的 5 個，剩 27 個。
- 會放 ENI 在 data subnet 的：OpenSearch（`search/domain.tf:10`）、Firehose（`pipeline/firehose.tf:25`）、Redshift（`warehouse/redshift.tf:23`、`:43`）、Client VPN（`vpn/client-vpn.tf:11`）、QuickSight（`bi/quicksight.tf:26`）。

**指令**

階段 C、E、F、G 之後，以及第 19 項（若有 blue/green）、第 20 項之後各跑一次：

```bash
aws ec2 describe-subnets --subnet-ids $(tr ',' ' ' <<<"$SUBNETS_DATA") \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,AvailableIpAddressCount]' --output table
aws ec2 describe-network-interfaces --filters Name=subnet-id,Values="$SUBNETS_DATA" \
  --query 'NetworkInterfaces[].[SubnetId,InterfaceType,Description]' --output text | sort | uniq -c | sort -rn
```

**預期結果**

- 每個階段之後 `AvailableIpAddressCount` 都大於 0，並記下數字。
- OpenSearch 更新（第 5 項選做、第 19 項）時沒有出現 IP 不足的錯誤。
- 剩不到 5 個時回報：data tier 要加大（`network/vpc.tf:10` 的 `newbits`），這需要重建 subnet，越早決定越好。

**結果紀錄**：日期 ______ ／執行人 ______ ／C ______ E ______ F ______ G ______ 之後的最小剩餘數

---

## 結果怎麼回寫

執行人是負責 apply 的專案 app team 成員；回寫分四處，都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/example4/infra/REFERENCE.md`〈雲端整合待驗證〉表 | 執行人 | 表格加一欄「結果」，寫 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`；「log group 層的 resource policy」那一列照第 6 項改寫。21 列都通過時，比照〈靜態驗證通過（2026-10-24）〉另開一節〈雲端驗證通過（日期）〉把表搬過去；〈已知限制的細節〉與 README〈已知限制〉裡已經確認的條目刪掉；README.md:11 與 REFERENCE.md:5 的狀態句改成實際狀態 | platform team ＋ 專案代表（`/templates/` 的 CODEOWNERS） |
| `docs/design/v7/design-docs.md` §11 與 §2 第 3、13、19 點 | platform team | 每一點後面加 `→ 已確認（YYYY-MM-DD，runbook 第 <n> 項）`，或 `→ 不成立：<實際行為>，改法見 #issue` | platform team |
| module README 的「還沒在真實帳號 apply 過」與「未確認」（`opensearch-domain`、`opensearch-config`、`firehose-stream`、`glue-etl`、`glue-catalog-encryption`、`redshift-serverless`、`redshift-cluster`、`quicksight-data`、`client-vpn`、`vpn-site-to-site`） | platform team | 對應的項目通過後改成實際驗證的日期與帳號類型 | platform team |

不通過的處理：

- 問題在 module（例如 `glue-etl` 的 log 權限、`quicksight-data`）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack（例如 `iam-base` 的動作清單、`network` 的 SG 規則）：開 issue 並標 `templates/example4`，修正走一般的範本改版 PR。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
