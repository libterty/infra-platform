# account-baseline 雲端驗證 runbook

## 結論

這份 runbook 列出 `templates/account-baseline` 第一次在真實 AWS 帳號 apply 時要逐項確認的事，照做完就能把 REFERENCE〈雲端整合待驗證〉表與 design v10 §11、§14 的「未確認」改成有證據的結論。

- 範圍：apply 前的盤點（本文第 0 項）、REFERENCE 表上的 8 項（第 1–8 項）、design §11 與 §14 裡表上沒涵蓋的 5 項（S1–S5）。
- 每一項都有：前提（要 apply 哪些 stack、tfvars 怎麼設）、指令、預期結果、結果紀錄。
- 指令預設都是唯讀。會改變狀態的指令標【寫入】，只在 `dev` 執行。
- 這份文件的指令都**沒有實際跑過**，名稱與數值都從程式碼推出來，出處寫在每段的「名稱怎麼來的」。標「推測」的是 repo 以外的慣例（AWS 的預設命名或行為），執行時以實際輸出為準。
- 這份範本改的是**整個帳號**，不是某個專案。apply 要帳號管理者等級的權限，有幾個動作會影響同帳號的其他專案，或做了就收不回來。哪些動作、怎麼復原，集中寫在〈帳號層的動作與復原〉，執行前一定要先看。
- 從程式碼就看得出來、第一次驗證很可能不通過或要調整的四件事，先講：
  1. **`destroy` 失敗後保護已經被拆掉**：`backup` 的 vault policy 與 lock、`foundation` 的 bucket policy、lifecycle、加密設定都依賴 vault 或 bucket，Terraform 會先刪它們，再去刪 vault 或 bucket，然後因為裡面有資料而失敗。結果是 vault 與 bucket 留著，保護卻沒了。REFERENCE〈destroy〉只寫「刪不掉是預期的」，沒寫這件事。第 8 項會確認，並寫了怎麼補回來。
  2. **`destroy` 不是復原**：`defaults` 的 destroy 是刪掉設定（public access block 被刪、密碼政策被刪），不是回到 apply 前的值（`modules/account-security-defaults/README.md:38`）。帳號原本就有密碼政策或 public access block 時，要靠第 0 項的快照手動恢復。
  3. **第一天會收到很多信**：Security Hub 的 rule 會把所有 `HIGH`、`CRITICAL` 而且 `ACTIVE` 的 finding 寄出來（`detect/findings.tf:14-26`），包括 FSBP、CIS 第一次評估時 `FAILED` 的 control；`UnauthorizedApiCalls` 告警門檻是 1 分鐘內 1 次（`modules/log-metric-alarm/variables.tf:32-37`），帳號裡任何 `AccessDenied` 都會觸發。第 2、5 項要記下第一週收到幾封，決定要不要調門檻。
  4. **EBS 的 recovery point 不一定用治理 CMK 加密**：REFERENCE〈Backup 的 tag 約定〉說「備份用治理 CMK 加密存進 vault」（`REFERENCE.md:74`）。EBS 這類沒有完整 AWS Backup 管理的資源，snapshot 可能沿用來源 volume 的 key（推測）。第 6 項會記下實際的 key。

## 範圍

涵蓋：

| 編號 | 項目 | 來源 |
|---|---|---|
| 0 | apply 前盤點帳號現況、留快照 | `templates/account-baseline/infra/README.md:44-60`〈第一次 apply〉 |
| 1–8 | CloudTrail、CloudTrail 告警、Config、Security Hub、finding 告警、Backup、Budgets、destroy | `templates/account-baseline/infra/REFERENCE.md:359-372`〈雲端整合待驗證〉 |
| S1–S5 | design §11、§14 與 REFERENCE〈已知限制的細節〉裡上表沒涵蓋的部分（對照見下表） | `docs/design/v10/design-docs.md` §11、§14；`REFERENCE.md:326-341` |

design §11、§14 與 REFERENCE〈已知限制的細節〉各點的去處：

| 來源 | 內容 | 在本文 |
|---|---|---|
| §11 第 1 點、REFERENCE 已知限制「只啟用主 region」 | 只有主 region 有偵測，FSBP 與 CIS 對其他 region 出 finding | S1 |
| §11 第 2 點 | Config 的 global resource 只在一個 region 記錄 | S1 |
| §11 第 3 點 | 帳號已經有 trail、recorder 或 detector | 第 0 項（盤點）、S2（import） |
| §11 第 4 點、§2 第 6 點、§14 查證結果第 1 點、REFERENCE「CIS v5.0.0」「Security Hub 的版本」 | 標準 ARN、CIS v5.0.0、CSPM | 第 4 項 |
| §11 第 5 點、REFERENCE「vault lock」 | governance 模式可被移除 | S3 |
| §11 第 6 點、§14 範本 `budget`、REFERENCE「Budgets 送 SNS」 | Budgets 送到 `ap-northeast-1` 的 topic、只用 `aws:SourceAccount` | 第 7 項 |
| §11 第 7 點 | destroy 的預期 | 第 8 項 |
| §11 第 8 點、REFERENCE「Organizations」 | Organizations 模式 | 不在本文：範本沒有對應的 stack，要有 organization 才能驗 |
| §14 查證結果第 2 點 | CloudTrail 的 log group ARN 要加 `:*` | 第 1 項 |
| §14 查證結果第 3 點、§14 module `organization-delegated-admin` | 委派管理的 API | 不在本文：Organizations |
| §14 module `config-recorder` | `all_supported` 由 `exclusion_types` 推導 | 第 3 項 |
| §14 module `guardduty`、`inspector` | 不收 `EKS_RUNTIME_MONITORING`、`LAMBDA_CODE` 要搭配 `LAMBDA` | S5 |
| §14 module `backup-plan`、`backup-vault` | selection tag 是「符合任一個」、vault policy 也 deny `PutBackupVaultAccessPolicy` | 第 6 項、S3 |
| §14 module `s3-bucket` 0.6.0、REFERENCE「CloudTrail、Config 的 bucket 與 key policy」 | `aws:SourceArn` 放寬成 `trail/*`、各服務實際送的 condition key | 第 1、3 項 |
| §14 module `sns-alarm-topic` 0.2.0 | 保留同帳號發佈的預設 statement | 第 2 項 |
| §14 module `iam-role` 0.5.0、REFERENCE「IAM 與 KMS」 | 三個 managed policy、`iam` 的動作清單、key policy | 第 1、3、6 項 |
| §14 範本 `defaults` | 不讀 `foundation`、EBS 用 `aws/ebs` | S4 |
| §14 範本治理 CMK | CloudTrail 用 `StringLikeIfExists`、開給 `cloudwatch.amazonaws.com` | 第 1、2 項 |
| §14 範本 `audit` | log group 保存天數、未授權呼叫的 pattern | 第 1、2 項 |
| §14 範本 `detect` | `RecordState = ACTIVE`、排除 GuardDuty 來源 | 第 5 項 |
| §14 範本 `backup` | `BACKUP_JOB_EXPIRED`、保留天數範圍 | 第 6 項 |
| REFERENCE「event pattern」 | 兩個 EventBridge rule 與兩個 metric filter 的 pattern | 第 2、5 項 |
| REFERENCE「log bucket」 | 沒有 S3 Object Lock | 不需要驗：刻意不做（design §4.1）。第 1 項會確認 versioning 與 lifecycle |
| REFERENCE〈帳號已經有 trail、recorder 或 detector〉最後一點 | GuardDuty feature 與 Inspector 掃描類型沒有 import，apply 直接改 | S2 |
| REFERENCE〈Backup 的 tag 約定〉最後一點 | 來源資源用自己的 CMK 時 Backup role 的權限 | 第 6 項（選做） |
| REFERENCE〈啟用其他 region〉 | 跨 region 寫 config bucket、finding aggregator 會不會觸發主 region 的 rule | 不在本文：範本沒有啟用其他 region |
| design §10 | Security Hub CSPM 的計價 | 不在本文：看帳單，不是功能驗證 |

## 需要的權限與工具

工具：

- AWS CLI v2（要有 `ec2 get-instance-metadata-defaults`、`inspector2`）、`jq`、Terraform（apply 用，版本 `>= 1.10`，`versions.tf:2`）。
- 一個收得到信的信箱，填進 `foundation` 的 `alert_emails` 與 `budget` 的 `budget_emails`（`foundation/envs/dev.tfvars:5`、`budget/envs/dev.tfvars:7`，範本的值是 `example.com`）。

身分：

| 用途 | 身分 | 依據 |
|---|---|---|
| apply 7 個 stack | 帳號管理者等級（實務上是 `AdministratorAccess`）。要能改 IAM 密碼政策、S3 account public access block、EBS 與 IMDS 的帳號預設、建 IAM role 與 service-linked role、啟用 GuardDuty、Security Hub、Inspector、Config、CloudTrail、Access Analyzer、Backup、Budgets、KMS。可以用 tfvars 的 `deploy_role_arn` 讓 provider 先 assume 一個 role | `providers.tf:1-27`（7 個 stack 相同）；`provider` 的 `allowed_account_ids` 只准 `expected_account_id`（`providers.tf:14`） |
| 執行本文的唯讀指令 | 只有下面唯讀權限的身分 | — |
| 本文的【寫入】指令 | apply 身分，或另給下面列的寫入權限 | — |
| 第 2 項 root 告警的真實觸發（選做） | root 帳號，要帳號擁有者同意 | — |

驗證身分要的 AWS 權限（唯讀）：`ssm:GetParameter`、`sts:GetCallerIdentity`、`cloudtrail:Describe*`、`cloudtrail:Get*`、`cloudtrail:LookupEvents`、`cloudtrail:ListPublicKeys`、`s3:ListBucket`、`s3:GetObject`（兩個 log bucket）、`s3:GetBucket*`、`s3:ListAllMyBuckets`、`s3:GetAccountPublicAccessBlock`、`kms:Decrypt`、`kms:DescribeKey`、`kms:GetKeyPolicy`、`kms:GetKeyRotationStatus`（治理 CMK）、`logs:Describe*`、`logs:TestMetricFilter`、`logs:FilterLogEvents`、`cloudwatch:DescribeAlarms`、`cloudwatch:GetMetricStatistics`、`config:Describe*`、`config:ListDiscoveredResources`、`guardduty:Get*`、`guardduty:List*`、`securityhub:Describe*`、`securityhub:Get*`、`securityhub:List*`、`inspector2:BatchGetAccountStatus`、`inspector2:ListCoverage`、`access-analyzer:Get*`、`access-analyzer:List*`、`events:DescribeRule`、`events:ListTargetsByRule`、`events:TestEventPattern`、`sns:GetTopicAttributes`、`sns:ListSubscriptionsByTopic`、`backup:Describe*`、`backup:Get*`、`backup:List*`、`budgets:ViewBudget`、`ec2:GetEbsEncryptionByDefault`、`ec2:GetEbsDefaultKmsKeyId`、`ec2:GetInstanceMetadataDefaults`、`ec2:DescribeVolumes`、`iam:GetAccountPasswordPolicy`、`iam:ListRoles`。

`validate-logs` 要讀 trail bucket 的物件，物件用治理 CMK 加密，所以要 `kms:Decrypt`。key policy 的第一條放行帳號 root（`modules/kms-key/main.tf:7-13`），用 IAM policy 給就好。

【寫入】要另外的權限：`cloudwatch:SetAlarmState`、`guardduty:CreateSampleFindings`、`guardduty:ArchiveFindings`、`securityhub:BatchImportFindings`、`config:DeliverConfigSnapshot`、`ec2:CreateVolume`、`ec2:DeleteVolume`、`ec2:CreateTags`、`backup:StartBackupJob`、`iam:PassRole`（`<project>-<env>-backup`）、`backup:DeleteRecoveryPoint`（用來確認被 deny）。

網路：全部是 AWS 的公開 API，不需要 VPC。Budgets 是全域服務，CLI 會自己找 endpoint。

### 帳號層的動作與復原

apply 這份範本會做下面這些事。影響範圍是整個帳號（或整個 region），不只這個 project。dev 帳號如果還有別的專案或別人在用，apply 前先通知。

| 動作 | stack | 影響 | 復原 |
|---|---|---|---|
| S3 account public access block 四項全開 | `defaults` | 帳號裡所有 bucket 立刻不能公開，包括靜態網站與用 public ACL 的 bucket（`modules/account-security-defaults/README.md:39`） | 【寫入】`aws s3control delete-public-access-block --account-id <account>`，或照第 0 項快照 `put-public-access-block`。之後 Terraform state 還認為它在，要 `terraform state rm` 或重 apply |
| EBS 預設加密（`aws/ebs`） | `defaults` | 這個 region 之後新建的 volume 都加密 | 【寫入】`aws ec2 disable-ebs-encryption-by-default`。期間建的 volume 維持加密，改不回來 |
| IMDSv2 預設、hop limit 2 | `defaults` | 這個 region 之後新開、沒自己設 metadata options 的 instance 只能用 IMDSv2；還在用 IMDSv1 的程式會拿不到憑證 | 【寫入】`aws ec2 modify-instance-metadata-defaults --http-tokens no-preference --http-put-response-hop-limit -1`（`-1` 代表不設定，推測）。期間開的 instance 不會跟著改 |
| IAM 密碼政策（14 字元、90 天到期、記 24 組） | `defaults` | 帳號所有 IAM 使用者的 console 密碼。密碼已經超過 90 天的使用者，下次登入可能被要求改密碼（推測） | 【寫入】照第 0 項快照 `aws iam update-account-password-policy ...`；原本沒有就 `aws iam delete-account-password-policy` |
| 第二條 multi-region trail | `audit` | 帳號已經有記 management event 的 trail 時，這條要計費（`README.md:48`） | `./stacks.sh <env> audit destroy` 刪 trail；已經寫進 bucket 的 log 留著 |
| Config recorder（所有類型、`CONTINUOUS`） | `audit` | 開始依 configuration item 計費 | destroy 會停掉 recorder；bucket 裡的資料留著 |
| 啟用 GuardDuty、Security Hub、Inspector | `detect` | 開始計費（GuardDuty、Security Hub 前 30 天試用，REFERENCE〈成本〉）；會建 service-linked role（推測） | **停用會刪掉既有 finding，收不回來**（`modules/guardduty/README.md:56`、`modules/securityhub/README.md:49`、`modules/inspector/README.md:44`）。要留紀錄先匯出。service-linked role 不會跟著刪（推測） |
| vault policy deny 刪除 recovery point | `backup` | 包括 root 在內，沒人能手動刪 recovery point（`modules/backup-vault/main.tf:10-30`） | 【寫入】`aws backup delete-backup-vault-access-policy --backup-vault-name <vault>` 拿掉，之後重 apply 會加回來 |
| vault lock（governance） | `backup` | 保留天數超出 dev 1–365、sit 7–365 的備份會被拒絕 | 【寫入】`aws backup delete-backup-vault-lock-configuration --backup-vault-name <vault>`。**不要**改成 compliance：冷卻期過後永遠移不掉（REFERENCE〈vault lock〉） |
| log bucket（versioning、365 天、`force_destroy = false`） | `foundation` | 稽核證據刪不掉 | 要刪只能清空所有版本；要留就 `terraform state rm`（REFERENCE〈destroy〉） |
| 治理 CMK | `foundation` | 排程刪除要等 30 天（`modules/kms-key/variables.tf:19`） | 等待期內 `aws kms cancel-key-deletion`。**刪掉之後 bucket 裡的 log 與 vault 裡的備份都解不開，收不回來** |
| Access Analyzer、Budgets、告警 topic | `defaults`、`budget`、`foundation` | 不影響其他資源 | destroy 即可 |

本文自己建的測試資源：1 GiB 的 EBS volume（第 6 項，做完刪）、recovery point（第 6 項，刪不掉，等到期）、GuardDuty sample finding 與一筆自訂 Security Hub finding（第 5 項，做完 archive）、暫時調低的預算（第 7 項，做完改回）。

## 共用變數

每次開新的 shell 先跑這段。`<project>`、`<env>` 換成 tfvars 的值（`dev` 或 `sit`）。還沒 apply 的 stack，對應的 `ssm` 會回 `ParameterNotFound`，先跳過。

```bash
export AWS_REGION=ap-northeast-1          # common.tf:24，aws_region 預設值；改過就跟著改
P=<project>                               # tfvars 的 project，範本是 baseline
E=<env>                                   # dev 或 sit
ssm() { aws ssm get-parameter --name "$1" --query Parameter.Value --output text; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)   # 應該等於 expected_account_id
PREFIX="$P-$E"

KMS_ARN=$(ssm "/$P/$E/foundation/kms_key_arn")
TRAIL_BUCKET=$(ssm "/$P/$E/foundation/trail_bucket_name")     # 應該等於 $PREFIX-trail-$ACCOUNT
CONFIG_BUCKET=$(ssm "/$P/$E/foundation/config_bucket_name")   # 應該等於 $PREFIX-config-$ACCOUNT
TOPIC_ARN=$(ssm "/$P/$E/foundation/alert_topic_arn")          # 結尾是 :$PREFIX-alerts
ANALYZER_ARN=$(ssm "/$P/$E/defaults/access_analyzer_arn")
CONFIG_ROLE=$(ssm "/$P/$E/iam/config_role_arn")
BACKUP_ROLE=$(ssm "/$P/$E/iam/backup_role_arn")
TRAIL_LOGS_ROLE=$(ssm "/$P/$E/iam/trail_logs_role_arn")
TRAIL_ARN=$(ssm "/$P/$E/audit/trail_arn")
RECORDER=$(ssm "/$P/$E/audit/config_recorder_name")           # 應該是 default
DETECTOR=$(ssm "/$P/$E/detect/guardduty_detector_id")
VAULT=$(ssm "/$P/$E/backup/vault_name")                       # 應該等於 $PREFIX-backup

TRAIL_LG="/aws/cloudtrail/$PREFIX"
```

名稱怎麼來的：

- `name_prefix = "${var.project}-${var.env}"`（`common.tf:44`），`ssm_prefix = "/${var.project}/${var.env}"`（`common.tf:45`）。7 個 stack 的 `common.tf` 一字不差。
- SSM key 是 `"${var.ssm_prefix}/${var.stack}/${each.key}"`（`modules/ssm-publish/main.tf:4`）；key 名稱見 `foundation/ssm-outputs.tf:3-6`、`defaults/ssm-outputs.tf:3`、`iam/ssm-outputs.tf:3-5`、`audit/ssm-outputs.tf:3-4`、`detect/ssm-outputs.tf:3`、`backup/ssm-outputs.tf:3`。`budget` 不發布 key。
- bucket 名稱 `"${local.name_prefix}-trail-${var.expected_account_id}"`、`"...-config-..."`（`foundation/buckets.tf:6`、`:10`）；topic `"${local.name_prefix}-alerts"`（`foundation/alerts.tf:3`）；vault `"${local.name_prefix}-backup"`（`backup/backup.tf:5`）；recorder `default`（`audit/config.tf:5`）。
- trail 的 log group `"/aws/cloudtrail/${local.name_prefix}"`（`audit/trail.tf:5`，`iam/naming.tf:4` 同一個規則）。

## 執行順序

順序照 `stacks.sh:8` 的 `ORDER`（`foundation defaults iam audit detect backup budget`）。每個 stack 第一次跑要先 `init`（`stacks.sh:119`），先 `--dry-run` 看一次指令：

```bash
cd templates/account-baseline/infra/terraform    # 複製出去之後是 infra/terraform
./stacks.sh "$E" foundation init
./stacks.sh "$E" foundation plan
./stacks.sh "$E" foundation apply
```

| 階段 | 做什麼 | 做完接著驗 |
|---|---|---|
| 0 | 照 README〈複製出去之後要改什麼〉換掉佔位值（`accounts_by_env`、tfbackend、`project`、`expected_account_id`、兩組 email）；跑第 0 項的盤點與快照；有既有服務的話先做 S2 | 第 0 項、S2 |
| A | `foundation` | 點 SNS 的訂閱確認信；第 1 項的 bucket 與 key 部分 |
| B | `defaults` | S4 |
| C | `iam` | — |
| D | `audit` | 第 1、2、3 項；S1 的 trail 與 Config 部分 |
| E | `detect` | 第 4、5 項；S1 的偵測服務部分；S5 |
| F | `backup` | 第 6 項的設定部分；S3 |
| G | `budget` | 第 7 項的設定部分 |
| H | 隔天以後 | 第 1 項的 `validate-logs`（digest 每小時一份）、第 3 項的 snapshot（每 24 小時）、第 6 項的排程備份（台北時間 03:00）、第 7 項的通知、第 2、5 項第一週的信件量 |
| I | 最後，而且只在可以拆掉的 dev 帳號 | 第 8 項 |

`iam` 一定要在 `audit` 之前：trail 與 recorder 要先有 role（REFERENCE〈stack 的內容〉）。`detect` 讀 `audit/config_recorder_name` 只是為了擋住順序（`detect/ssm-inputs.tf:4-6`）。

---

## 0. apply 前盤點與快照

**前提**

- 還沒 apply 任何 stack。
- 這一項全部唯讀。輸出存成檔案，〈帳號層的動作與復原〉要靠它恢復原值。

**指令**

```bash
OUT="baseline-before-$E-$(date +%Y%m%d).txt"
{
  echo "## trail";            aws cloudtrail describe-trails --include-shadow-trails
  echo "## config recorder";  aws configservice describe-configuration-recorders
  echo "## delivery channel"; aws configservice describe-delivery-channels
  echo "## guardduty";        aws guardduty list-detectors
  echo "## securityhub";      aws securityhub describe-hub 2>&1
  echo "## inspector";        aws inspector2 batch-get-account-status --account-ids "$ACCOUNT"
  echo "## access analyzer";  aws accessanalyzer list-analyzers
  echo "## s3 account pab";   aws s3control get-public-access-block --account-id "$ACCOUNT" 2>&1
  echo "## ebs encryption";   aws ec2 get-ebs-encryption-by-default; aws ec2 get-ebs-default-kms-key-id
  echo "## imds defaults";    aws ec2 get-instance-metadata-defaults
  echo "## password policy";  aws iam get-account-password-policy 2>&1
  echo "## backup";           aws backup list-backup-vaults; aws backup list-backup-plans
  echo "## budgets";          aws budgets describe-budgets --account-id "$ACCOUNT" 2>&1
  echo "## service-linked roles"; aws iam list-roles --path-prefix /aws-service-role/ --query 'Roles[].RoleName' --output text
} > "$OUT"

# 會被 S3 account public access block 擋掉的 bucket：policy 是公開的
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  s=$(aws s3api get-bucket-policy-status --bucket "$b" --query PolicyStatus.IsPublic --output text 2>/dev/null)
  [ "$s" = "True" ] && echo "public: $b"
done
```

名稱怎麼來的：要查的服務照 README〈第一次 apply〉第 1 點（`README.md:48-55`），加上 `defaults` 會改的四種帳號設定（`defaults/security.tf:5-18`）。

**預期結果**

- `describe-configuration-recorders`、`list-detectors` 是空的；`describe-hub` 回 `InvalidAccessException` 之類的「沒有啟用」錯誤（推測錯誤名稱）。有任何一個不是空的，先做 S2，不然 `audit`、`detect` 會 apply 失敗（`REFERENCE.md:76-78`）。
- `describe-trails` 有既有的 trail 時，記下名稱與是不是 multi-region；要留就照 S2 import，不留就跟帳號擁有者確認後刪。
- 沒有 `public:` 開頭的輸出。有的話，那些 bucket 在階段 B 之後會變成不能公開，先跟 bucket 的負責人確認。
- 檔案存好，記下密碼政策與三個 EBS／IMDS 設定的原值。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／既有服務與公開 bucket ______

## 1. CloudTrail

**前提**

- 階段 A–D 完成。
- trail 是 multi-region、只記 management event、log file validation 開、治理 CMK 加密（`audit/trail.tf:13-23`；`modules/cloudtrail/main.tf:10-12`）。
- CloudTrail 寫 CloudWatch Logs 用 `<prefix>-trail-logs` role，只能寫 `/aws/cloudtrail/<prefix>` 的 log stream（`iam/policies.tf:32-40`、`iam/naming.tf:4-5`）。
- bucket policy 的 `aws:SourceArn` 是本帳號的 `trail/*`（`modules/s3-bucket/main.tf:82-106`）；key policy 對 CloudTrail 用 `StringLikeIfExists` 加 `aws:SourceArn`（`foundation/kms.tf:8-22`）。這兩組條件是不是 CloudTrail 實際送的 key，第一次 apply 才知道。

**指令**

```bash
# trail 本身
aws cloudtrail get-trail --name "$TRAIL_ARN" \
  --query 'Trail.{name:Name,multi:IsMultiRegionTrail,home:HomeRegion,validation:LogFileValidationEnabled,kms:KmsKeyId,bucket:S3BucketName,cwl:CloudWatchLogsLogGroupArn,role:CloudWatchLogsRoleArn,global:IncludeGlobalServiceEvents}'
aws cloudtrail get-trail-status --name "$TRAIL_ARN" \
  --query '{logging:IsLogging,s3:LatestDeliveryTime,s3err:LatestDeliveryError,digest:LatestDigestDeliveryTime,digesterr:LatestDigestDeliveryError,cwl:LatestCloudWatchLogsDeliveryTime,cwlerr:LatestCloudWatchLogsDeliveryError}'
aws cloudtrail get-event-selectors --trail-name "$TRAIL_ARN"

# bucket 收到 log 與 digest，物件用治理 CMK 加密
aws s3api list-objects-v2 --bucket "$TRAIL_BUCKET" --prefix "AWSLogs/$ACCOUNT/CloudTrail/$AWS_REGION/" --max-items 3 --query 'Contents[].Key'
aws s3api list-objects-v2 --bucket "$TRAIL_BUCKET" --prefix "AWSLogs/$ACCOUNT/CloudTrail-Digest/" --max-items 3 --query 'Contents[].Key'
KEY=$(aws s3api list-objects-v2 --bucket "$TRAIL_BUCKET" --prefix "AWSLogs/$ACCOUNT/CloudTrail/$AWS_REGION/" --max-items 1 --query 'Contents[0].Key' --output text)
aws s3api head-object --bucket "$TRAIL_BUCKET" --key "$KEY" --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'

# bucket 的保護：versioning、lifecycle、ownership
aws s3api get-bucket-versioning --bucket "$TRAIL_BUCKET"
aws s3api get-bucket-lifecycle-configuration --bucket "$TRAIL_BUCKET" --query 'Rules[].[ID,Status,Expiration.Days,NoncurrentVersionExpiration.NoncurrentDays]' --output text
aws s3api get-bucket-ownership-controls --bucket "$TRAIL_BUCKET" --query 'OwnershipControls.Rules[0].ObjectOwnership'

# 治理 CMK
aws kms describe-key --key-id "alias/$PREFIX-governance" --query 'KeyMetadata.{arn:Arn,state:KeyState}'
aws kms get-key-rotation-status --key-id "$KMS_ARN"
aws kms get-key-policy --key-id "$KMS_ARN" --policy-name default --output text | jq -r '.Statement[].Sid'

# log group 收到 event
aws logs describe-log-groups --log-group-name-prefix "$TRAIL_LG" --query 'logGroups[].[logGroupName,retentionInDays,kmsKeyId]' --output text
aws logs describe-log-streams --log-group-name "$TRAIL_LG" --order-by LastEventTime --descending --max-items 3 \
  --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output text
```

trail 開始記錄超過 2 小時之後（digest 每小時一份），驗證 log 沒被改過：

```bash
aws cloudtrail validate-logs --trail-arn "$TRAIL_ARN" \
  --start-time "$(date -u -v-2H +%FT%TZ 2>/dev/null || date -u -d '-2 hour' +%FT%TZ)" --verbose | tail -5
```

名稱怎麼來的：trail `"${local.name_prefix}-trail"`（`audit/trail.tf:14`）；log group ARN 加 `:*`（`audit/trail.tf:20`）；key alias `alias/<name>`（`modules/kms-key/main.tf:70`），name 是 `"${local.name_prefix}-governance"`（`foundation/kms.tf:45`）；key policy 的 Sid 是 `EnableAccountRoot` 加 `AllowService<principal 去掉非英數字>`（`modules/kms-key/main.tf:8`、`:30`）；bucket 的 lifecycle rule ID `expire-objects`、`cleanup-noncurrent-versions`（`modules/s3-bucket/main.tf:226`、`:259`）；ownership `BucketOwnerEnforced`（`modules/s3-bucket/main.tf:194`）。log stream 名稱 `<account>_CloudTrail_<region>` 照 `modules/cloudtrail/README.md:41`；`AWSLogs/<account>/CloudTrail/<region>/` 與 `CloudTrail-Digest/` 的路徑是 CloudTrail 的慣例（推測）。

**預期結果**

- `multi` 是 `true`，`home` 是 `ap-northeast-1`，`validation` 是 `true`，`kms` 是治理 CMK，`global` 是 `true`，`cwl` 結尾是 `:*`。
- `logging` 是 `true`，三個 `*err` 都是空的。`s3err` 有值時多半是 bucket policy 的條件不對；`cwlerr` 有值時看 role 的 trust 與 `logs:CreateLogStream` 的範圍。
- event selector 只有 management event（`ReadWriteType: All`、`IncludeManagementEvents: true`、沒有 data resource）。
- log 與 digest 都有物件；`head-object` 的 `sse` 是 `aws:kms`，`key` 是 `$KMS_ARN`。
- versioning 是 `Enabled`；lifecycle 有兩條，`Expiration.Days` 是 365、`NoncurrentDays` 是 365；ownership 是 `BucketOwnerEnforced`。
- key `Enabled`、rotation `true`；Sid 有 `EnableAccountRoot` 與 7 個 `AllowService...`（cloudtrail、config、backup、budgets、events、cloudwatch、`logs.ap-northeast-1`）。
- log group 存在，`retentionInDays` dev 是 90、sit 是 365（`audit/envs/dev.tfvars:5`、`sit.tfvars:5`），`kmsKeyId` 是治理 CMK；log stream 最近幾分鐘內有 event。`audit` apply 時如果 log group 建不起來、錯誤跟 KMS 有關，記下來：key policy 給 `logs` 的只有 module 預設的三個動作（`modules/kms-key/variables.tf:41`），AWS 文件列的動作比較多（推測）。
- `validate-logs` 最後一行是 log 與 digest 都 `valid`，沒有 `INVALID`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 2. CloudTrail 告警

**前提**

- 階段 A、D 完成，告警 topic 的 email 訂閱已確認。
- 兩條告警：`Sum`、60 秒、1 個 period、門檻 `>= 1`、missing data 算 `notBreaching`，`alarm_actions` 與 `ok_actions` 都送告警 topic（`modules/log-metric-alarm/variables.tf:29-37`、`main.tf:40-41`）。
- 告警 topic 用治理 CMK 加密；CloudWatch alarm 靠 topic policy 保留的同帳號 statement 發佈（`modules/sns-alarm-topic/main.tf:20-45`），key policy 給了 `cloudwatch.amazonaws.com`（`foundation/kms.tf:28`）。

**要確認的名稱**

| 東西 | 名稱 | 出處 |
|---|---|---|
| alarm 與 metric filter | `<project>-<env>-trail-root-account-usage`、`<project>-<env>-trail-unauthorized-api-calls` | `modules/log-metric-alarm/main.tf:7` 是 `"${var.name_prefix}-${replace(k, "_", "-")}"`；`name_prefix = "${local.name_prefix}-trail"`（`audit/alarms.tf:25`）；key 見 `audit/alarms.tf:5`、`:10` |
| metric | `RootAccountUsage`、`UnauthorizedApiCalls`，namespace `<project>/<env>/cloudtrail` | `audit/alarms.tf:7`、`:12`、`:27` |

**指令**

```bash
aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" --query 'Attributes.{kms:KmsMasterKeyId,policy:Policy}' --output json \
  | jq '{kms, sids: (.policy | fromjson | [.Statement[] | {Sid, Principal, Condition}])}'
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table

aws cloudwatch describe-alarms --alarm-name-prefix "$PREFIX-trail-" \
  --query 'MetricAlarms[].[AlarmName,StateValue,Namespace,MetricName,Threshold,TreatMissingData]' --output table
aws logs describe-metric-filters --log-group-name "$TRAIL_LG" \
  --query 'metricFilters[].[filterName,metricTransformations[0].metricNamespace,metricTransformations[0].metricName]' --output table
```

用 filter 原樣測樣本 event（唯讀）。前兩筆應該命中，後三筆不應該：

```bash
ROOT_PATTERN=$(aws logs describe-metric-filters --log-group-name "$TRAIL_LG" --filter-name-prefix "$PREFIX-trail-root" --query 'metricFilters[0].filterPattern' --output text)
UNAUTH_PATTERN=$(aws logs describe-metric-filters --log-group-name "$TRAIL_LG" --filter-name-prefix "$PREFIX-trail-unauth" --query 'metricFilters[0].filterPattern' --output text)

aws logs test-metric-filter --filter-pattern "$ROOT_PATTERN" --log-event-messages \
  '{"eventVersion":"1.08","userIdentity":{"type":"Root","arn":"arn:aws:iam::111111111111:root"},"eventType":"AwsConsoleSignIn","eventName":"ConsoleLogin"}' \
  '{"eventVersion":"1.08","userIdentity":{"type":"Root","invokedBy":"support.amazonaws.com"},"eventType":"AwsApiCall","eventName":"DescribeTrails"}'

aws logs test-metric-filter --filter-pattern "$UNAUTH_PATTERN" --log-event-messages \
  '{"eventVersion":"1.08","errorCode":"AccessDenied","sourceIPAddress":"203.0.113.10","eventName":"ListUsers"}' \
  '{"eventVersion":"1.08","errorCode":"Client.UnauthorizedOperation","sourceIPAddress":"203.0.113.10","eventName":"DescribeInstances"}' \
  '{"eventVersion":"1.08","errorCode":"AccessDenied","sourceIPAddress":"delivery.logs.amazonaws.com","eventName":"PutObject"}' \
  '{"eventVersion":"1.08","errorCode":"AccessDenied","sourceIPAddress":"203.0.113.10","eventName":"HeadBucket"}'
```

`ROOT_PATTERN` 的第二筆有 `invokedBy`，不該命中。`UNAUTH_PATTERN` 的前兩筆該命中，後兩筆被排除。樣本 event 只放 pattern 用到的欄位，帳號 ID 是佔位。

【寫入】通知路徑：

```bash
aws cloudwatch set-alarm-state --alarm-name "$PREFIX-trail-unauthorized-api-calls" --state-value ALARM --state-reason "runbook 通知測試"
```

狀態會在下一次評估時回到 `OK`，`ok_actions` 會再寄一封。

真實觸發：

- 未授權：用**唯讀的驗證身分**呼叫一個它沒有權限的 API，例如 `aws iam list-users`（上面的唯讀清單沒有 `iam:ListUsers`）。應該回 `AccessDenied`。5–15 分鐘內 metric 有值、告警變 `ALARM`（CloudTrail 送到 CloudWatch Logs 的延遲，推測）。
- root（選做，要帳號擁有者同意）：用 root 登入 console 一次。也可以只靠上面的 `test-metric-filter`，備註寫「root 只驗了 pattern」。

```bash
aws cloudwatch get-metric-statistics --namespace "$P/$E/cloudtrail" --metric-name UnauthorizedApiCalls \
  --start-time "$(date -u -v-1H +%FT%TZ 2>/dev/null || date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Sum \
  --query 'Datapoints[?Sum>`0`]' --output table
```

**預期結果**

- topic 的 `kms` 是治理 CMK；policy 有 `OwnerAccountAccess`（條件 `AWS:SourceOwner`）與 `AllowServicePublish`（principal 是 `backup`、`budgets`、`events` 三個服務，條件 `aws:SourceAccount`）。
- 每個 email 訂閱的 `SubscriptionArn` 是完整 ARN，不是 `PendingConfirmation`。
- 兩條告警存在、`OK`，namespace 與 metric 跟上表一樣；metric filter 兩條。
- `test-metric-filter`：root 的 pattern 只命中第 1 筆，unauthorized 的只命中第 1、2 筆。
- `set-alarm-state` 之後收到 `ALARM` 與 `OK` 兩封信。收不到時，先看 `AWS/SNS` 的 `NumberOfNotificationsFailed`，再看 KMS（CloudWatch 對加密 topic 發佈失敗時，告警歷史會有 action 失敗的紀錄）。
- 真實的 `AccessDenied` 會讓 `UnauthorizedApiCalls` 有資料點，收到信。
- 第一週記下兩條告警各觸發幾次，作為要不要調門檻的依據。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／root 只驗 pattern □ ／第一週觸發次數 ______

## 3. Config

**前提**

- 階段 A、C、D 完成。
- recorder `default`：所有支援的類型加 global 類型、`CONTINUOUS`、保留 2557 天，送 config bucket，治理 CMK 加密（`audit/config.tf:4-12`）。沒有 `exclusion_types`，所以 `all_supported = true`、策略是 `ALL_SUPPORTED_RESOURCE_TYPES`（`modules/config-recorder/main.tf:1-3`、`:10-16`）。
- role `<prefix>-config-recorder` 掛 `AWS_ConfigRole`，加 inline policy：config bucket 的 `GetBucketAcl`、寫 `AWSLogs/<account>/Config/*`、治理 CMK 的 `Decrypt` 與 `GenerateDataKey`（`iam/roles.tf:5-9`、`iam/policies.tf:8-30`）。這份動作清單沒有在真實帳號驗過。
- snapshot 每 24 小時送一次（`modules/config-recorder/variables.tf:98`）。

**指令**

```bash
aws configservice describe-configuration-recorders \
  --query 'ConfigurationRecorders[].{name:name,role:roleARN,all:recordingGroup.allSupported,global:recordingGroup.includeGlobalResourceTypes,strategy:recordingGroup.recordingStrategy.useOnly,freq:recordingMode.recordingFrequency}'
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[].{name:name,recording:recording,last:lastStatus,err:lastErrorMessage}'
aws configservice describe-delivery-channels
aws configservice describe-delivery-channel-status \
  --query 'DeliveryChannelsStatus[].{history:configHistoryDeliveryInfo.lastStatus,snapshot:configSnapshotDeliveryInfo.lastStatus,stream:configStreamDeliveryInfo.lastStatus,err:configHistoryDeliveryInfo.lastErrorMessage}'
aws configservice describe-retention-configurations

# role 的內容
aws iam list-attached-role-policies --role-name "$PREFIX-config-recorder" --query 'AttachedPolicies[].PolicyArn'
aws iam get-role-policy --role-name "$PREFIX-config-recorder" --policy-name permissions --query 'PolicyDocument.Statement[].Sid'
aws iam get-role --role-name "$PREFIX-config-recorder" --query 'Role.AssumeRolePolicyDocument'

# bucket 收到資料，物件用治理 CMK 加密
aws s3api list-objects-v2 --bucket "$CONFIG_BUCKET" --prefix "AWSLogs/$ACCOUNT/Config/" --max-items 5 --query 'Contents[].Key'
KEY=$(aws s3api list-objects-v2 --bucket "$CONFIG_BUCKET" --prefix "AWSLogs/$ACCOUNT/Config/" --max-items 1 --query 'Contents[0].Key' --output text)
aws s3api head-object --bucket "$CONFIG_BUCKET" --key "$KEY" --query '{sse:ServerSideEncryption,key:SSEKMSKeyId}'

# 有記到資源（含 global 類型）
aws configservice list-discovered-resources --resource-type AWS::IAM::Role --limit 5 --query 'resourceIdentifiers[].resourceName'
aws configservice list-discovered-resources --resource-type AWS::S3::Bucket --limit 5 --query 'resourceIdentifiers[].resourceName'
```

【寫入】不想等 24 小時，手動送一份 snapshot（只是多寫一個物件）：

```bash
aws configservice deliver-config-snapshot --delivery-channel-name "$RECORDER"
```

名稱怎麼來的：role 名稱 `"${local.name_prefix}-config-recorder"`（`iam/roles.tf:6`）；inline policy 的名稱是 `iam-role-policy` 的 map key `permissions`（`iam/policies.tf:47`、`modules/iam-role-policy/main.tf:8`）；delivery channel 與 recorder 同名（`modules/config-recorder/main.tf:32`）；trust 的 `aws:SourceAccount`（`iam/roles.tf:33`、`modules/iam-role/main.tf:32-35`）。

**預期結果**

- recorder `default`，`all` 是 `true`、`global` 是 `true`、`strategy` 是 `ALL_SUPPORTED_RESOURCE_TYPES`、`freq` 是 `CONTINUOUS`，role 是 `$CONFIG_ROLE`。
- status 的 `recording` 是 `true`、`last` 是 `SUCCESS`。
- delivery channel 的 `s3BucketName` 是 `$CONFIG_BUCKET`、`s3KmsKeyArn` 是 `$KMS_ARN`；delivery 狀態 `history` 是 `SUCCESS`，`snapshot` 在第一份送出後是 `SUCCESS`。`err` 有值時，看 role 的 inline policy 與 bucket policy 的 `aws:SourceAccount`（`modules/s3-bucket/main.tf:127-143`）。
- retention 是 `2557`。
- managed policy 是 `arn:aws:iam::aws:policy/service-role/AWS_ConfigRole`；inline 的 Sid 是 `CheckBucketAcl`、`DeliverToConfigBucket`、`EncryptWithGovernanceKey`；trust 只有 `config.amazonaws.com`，條件 `aws:SourceAccount` 等於本帳號。
- bucket 有 `ConfigHistory`、`ConfigSnapshot` 之類的物件（路徑是 Config 的慣例，推測），`sse` 是 `aws:kms`、`key` 是治理 CMK。
- IAM role 與 S3 bucket 都查得到。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／備註 ______

## 4. Security Hub

**前提**

- 階段 D、E 完成。
- module 用 Security Hub CSPM（`aws_securityhub_account`），`enable_default_standards = false`，`control_finding_generator` 預設 `SECURITY_CONTROL`、`auto_enable_controls` 預設 `true`（`modules/securityhub/main.tf:14-19`、`variables.tf:15`、`:27`）。
- 訂閱 FSBP v1.0.0 與 CIS v5.0.0（`detect/detectors.tf:4`、`modules/securityhub/main.tf:8-11`、`:25`）。CIS v5.0.0 的 ARN 照 AWS 文件組，還沒在真實帳號訂閱過。
- 這一項的第一段（`describe-standards`）在 apply 前就能跑，可以先確認 ARN。

**指令**

```bash
# apply 前也能跑：這個 region 提供的標準
aws securityhub describe-standards --query 'Standards[].[StandardsArn,Name]' --output text \
  | grep -E 'aws-foundational-security-best-practices|cis-aws-foundations-benchmark'

# apply 後
aws securityhub describe-hub --query '{arn:HubArn,gen:ControlFindingGenerator,auto:AutoEnableControls}'
aws securityhub get-enabled-standards \
  --query 'StandardsSubscriptions[].[StandardsArn,StandardsStatus,StandardsStatusReason.StatusReasonCode]' --output text

# control 開始評估：Security Hub 自己產生的 finding，依合規狀態計數
aws securityhub get-findings --max-items 2000 \
  --filters '{"ProductName":[{"Value":"Security Hub","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --query 'Findings[].Compliance.Status' --output json | jq 'group_by(.) | map({(.[0]): length}) | add'

# 每個標準啟用了幾個 control
for s in $(aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].StandardsSubscriptionArn' --output text); do
  echo "$s $(aws securityhub describe-standards-controls --standards-subscription-arn "$s" --query 'length(Controls[?ControlStatus==`ENABLED`])')"
done
```

名稱怎麼來的：標準的路徑 `standards/aws-foundational-security-best-practices/v/1.0.0`、`standards/cis-aws-foundations-benchmark/v/5.0.0`（`modules/securityhub/main.tf:9-10`），ARN 是 `arn:<partition>:securityhub:<region>::<路徑>`（`:25`）。`ProductName = "Security Hub"` 是 Security Hub 自己的 finding 的慣例（推測）。

**預期結果**

- `describe-standards` 的輸出裡有 `arn:aws:securityhub:ap-northeast-1::standards/aws-foundational-security-best-practices/v/1.0.0` 與 `arn:aws:securityhub:ap-northeast-1::standards/cis-aws-foundations-benchmark/v/5.0.0`。沒有 v5.0.0 的話，`detect` 會 apply 失敗，記下這個 region 實際有的版本。
- `describe-hub` 的 `gen` 是 `SECURITY_CONTROL`、`auto` 是 `true`。
- `get-enabled-standards` 剛好兩個，都是 `READY`；沒有 CIS v1.2.0 或其他預設標準。
- apply 後幾小時內，finding 計數出現 `PASSED` 與 `FAILED`（不是全部 `NOT_AVAILABLE`）；全部是 `NOT_AVAILABLE` 表示 Config 沒在記錄，回頭看第 3 項。
- 兩個標準的 `ENABLED` control 數都大於 0。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／PASSED、FAILED 數 ______

## 5. finding 告警

**前提**

- 階段 A、E 完成，告警 topic 的 email 訂閱已確認。
- GuardDuty 的 rule：`source = aws.guardduty`、`detail.severity >= 7`（`detect/findings.tf:6-13`）。
- Security Hub 的 rule：`Severity.Label` 是 `HIGH` 或 `CRITICAL`、`RecordState = ACTIVE`、`ProductName` 不是 `GuardDuty`（`detect/findings.tf:14-26`），所以同一筆 GuardDuty finding 只會寄一次。
- 兩條 rule 的目標都是告警 topic（`detect/findings.tf:30-32`），topic policy 與 key policy 都放行 `events.amazonaws.com`（`foundation/alerts.tf:7`、`foundation/kms.tf:27`）。

**指令**

```bash
for r in guardduty securityhub; do
  aws events describe-rule --name "$PREFIX-$r-findings" --query '{state:State,pattern:EventPattern}'
  aws events list-targets-by-rule --rule "$PREFIX-$r-findings" --query 'Targets[].[Id,Arn]' --output text
done
```

用 rule 原樣測樣本 event（唯讀）：

```bash
GD_PATTERN=$(aws events describe-rule --name "$PREFIX-guardduty-findings" --query EventPattern --output text)
SH_PATTERN=$(aws events describe-rule --name "$PREFIX-securityhub-findings" --query EventPattern --output text)
ev() {  # $1 source, $2 detail-type, $3 detail
  printf '{"version":"0","id":"00000000-0000-0000-0000-000000000000","source":"%s","detail-type":"%s","account":"%s","time":"2026-01-01T00:00:00Z","region":"%s","resources":[],"detail":%s}' \
    "$1" "$2" "$ACCOUNT" "$AWS_REGION" "$3"
}

# GuardDuty：8 命中，5 不命中
aws events test-event-pattern --event-pattern "$GD_PATTERN" --event "$(ev aws.guardduty 'GuardDuty Finding' '{"severity":8}')"
aws events test-event-pattern --event-pattern "$GD_PATTERN" --event "$(ev aws.guardduty 'GuardDuty Finding' '{"severity":5}')"

# Security Hub：第一筆命中；GuardDuty 來源、ARCHIVED、MEDIUM 都不命中
shf() {  # $1 ProductName, $2 RecordState, $3 Severity.Label
  printf '%-30s ' "$1 $2 $3"
  aws events test-event-pattern --event-pattern "$SH_PATTERN" --query Result \
    --event "$(ev aws.securityhub 'Security Hub Findings - Imported' "{\"findings\":[{\"ProductName\":\"$1\",\"RecordState\":\"$2\",\"Severity\":{\"Label\":\"$3\"}}]}")"
}
shf "Security Hub" ACTIVE   HIGH
shf "GuardDuty"    ACTIVE   HIGH
shf "Security Hub" ARCHIVED CRITICAL
shf "Security Hub" ACTIVE   MEDIUM
```

【寫入】GuardDuty 的 sample finding：一個高嚴重度、一個低嚴重度。

```bash
aws guardduty create-sample-findings --detector-id "$DETECTOR" \
  --finding-types 'Backdoor:EC2/C&CActivity.B!DNS' 'Recon:EC2/PortProbeUnprotectedPort'
# 約 5 分鐘後
aws guardduty list-findings --detector-id "$DETECTOR" \
  --finding-criteria '{"Criterion":{"service.additionalInfo.sample":{"Eq":["true"]}}}' --query FindingIds --output text
```

兩個 finding type 的嚴重度（8 與 2）是 GuardDuty 的定義，不在 repo 裡（推測）；以 `get-findings` 看到的 `Severity` 為準。

【寫入】Security Hub 的 HIGH finding（不是 GuardDuty 來源）：匯入一筆自訂 finding，收信後再改成 `ARCHIVED`。

```bash
CREATED=$(date -u +%FT%TZ)
finding() {  # $1 RecordState
  jq -nc --arg acct "$ACCOUNT" --arg region "$AWS_REGION" --arg created "$CREATED" --arg now "$(date -u +%FT%TZ)" --arg state "$1" \
    '[{SchemaVersion:"2018-10-08", Id:"runbook-test-1",
       ProductArn:"arn:aws:securityhub:\($region):\($acct):product/\($acct)/default",
       GeneratorId:"runbook", AwsAccountId:$acct, Types:["Software and Configuration Checks"],
       CreatedAt:$created, UpdatedAt:$now, Severity:{Label:"HIGH"},
       Title:"runbook 通知測試", Description:"account-baseline runbook 第 5 項",
       Resources:[{Type:"Other", Id:"runbook-test"}], RecordState:$state}]'
}
aws securityhub batch-import-findings --findings "$(finding ACTIVE)"
# 收到信之後
aws securityhub batch-import-findings --findings "$(finding ARCHIVED)"
```

確認 rule 實際比對與轉送的次數：

```bash
for r in guardduty securityhub; do
  for m in MatchedEvents Invocations FailedInvocations; do
    printf '%-12s %-18s ' "$r" "$m"
    aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name "$m" --dimensions Name=RuleName,Value="$PREFIX-$r-findings" \
      --start-time "$(date -u -v-2H +%FT%TZ 2>/dev/null || date -u -d '-2 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 7200 --statistics Sum \
      --query 'Datapoints[0].Sum' --output text
  done
done
```

做完 archive sample finding：

```bash
aws guardduty archive-findings --detector-id "$DETECTOR" \
  --finding-ids $(aws guardduty list-findings --detector-id "$DETECTOR" --finding-criteria '{"Criterion":{"service.additionalInfo.sample":{"Eq":["true"]}}}' --query FindingIds --output text)
```

名稱怎麼來的：rule 名稱 `"${local.name_prefix}-guardduty-findings"`、`"...-securityhub-findings"`（`detect/findings.tf:7`、`:15`）；target ID `alerts`（`detect/findings.tf:31`，`modules/eventbridge-rule/main.tf:16`）；detector ID 從 `detect/guardduty_detector_id`（`detect/ssm-outputs.tf:3`）。自訂 finding 的 `ProductArn`（`product/<account>/default`）、`service.additionalInfo.sample` 的條件、`AWS/Events` 的 metric 名稱都是 AWS 的慣例（推測）。

**預期結果**

- 兩條 rule `ENABLED`，目標是 `$TOPIC_ARN`，ID `alerts`。
- `test-event-pattern`：GuardDuty 的 8 是 `true`、5 是 `false`；Security Hub 只有第一筆 `true`。
- sample finding：只收到高嚴重度那一筆的信（GuardDuty rule 寄的）。它也會出現在 Security Hub（`ProductName = GuardDuty`），但 Security Hub rule 不會再寄。
- 自訂 finding：收到一封信；改成 `ARCHIVED` 之後不再寄。
- `MatchedEvents` 與 `Invocations` 相等，`FailedInvocations` 是 `None` 或 0。`Invocations` 有值卻沒收到信，看 SNS 的 `NumberOfNotificationsFailed` 與 KMS；`FailedInvocations` 有值，多半是 topic policy 或 key policy 擋住 `events.amazonaws.com`。
- 第一週記下兩條 rule 各寄了幾封。Security Hub 那條在第一次評估後會寄出所有 `HIGH`、`CRITICAL` 的 `FAILED` control；GuardDuty 的 finding 每 15 分鐘更新一次（`modules/guardduty/variables.tf:42`），持續發生的 finding 可能重複寄信（推測）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／第一週信件數（GuardDuty、Security Hub）______

## 6. Backup

**前提**

- 階段 A、C、F 完成，告警 topic 的 email 訂閱已確認。
- vault `<prefix>-backup`：治理 CMK、vault policy deny 刪除、governance lock（dev 最短 1 天、sit 7 天，最長 365 天）、三種事件通知（`backup/backup.tf:4-18`、`backup/envs/dev.tfvars:6`、`sit.tfvars:6`）。
- plan `<prefix>-daily`：rule `daily`、`cron(0 19 * * ? *)`（台北時間 03:00）、保留 dev 7 天、sit 35 天，選 tag `backup = "daily"`（`backup/backup.tf:20-30`、`backup/envs/dev.tfvars:7`、`sit.tfvars:7`）。
- role `<prefix>-backup` 只掛兩個 AWS managed policy（`iam/roles.tf:10-17`）。
- 帳號裡要有一個帶 `backup = "daily"` 的資源。下面建一個 1 GiB 的測試 volume。

**指令**

```bash
aws backup describe-backup-vault --backup-vault-name "$VAULT" \
  --query '{key:EncryptionKeyArn,locked:Locked,min:MinRetentionDays,max:MaxRetentionDays,lockDate:LockDate,points:NumberOfRecoveryPoints}'
aws backup get-backup-vault-notifications --backup-vault-name "$VAULT" --query '{topic:SNSTopicArn,events:BackupVaultEvents}'

PLAN_ID=$(aws backup list-backup-plans --query "BackupPlansList[?BackupPlanName=='$PREFIX-daily'].BackupPlanId" --output text)
aws backup get-backup-plan --backup-plan-id "$PLAN_ID" \
  --query 'BackupPlan.Rules[].{rule:RuleName,vault:TargetBackupVaultName,cron:ScheduleExpression,delete:Lifecycle.DeleteAfterDays}'
SEL_ID=$(aws backup list-backup-selections --backup-plan-id "$PLAN_ID" --query 'BackupSelectionsList[0].SelectionId' --output text)
aws backup get-backup-selection --backup-plan-id "$PLAN_ID" --selection-id "$SEL_ID" \
  --query 'BackupSelection.{name:SelectionName,role:IamRoleArn,tags:ListOfTags}'
aws iam list-attached-role-policies --role-name "$PREFIX-backup" --query 'AttachedPolicies[].PolicyArn'
```

【寫入】建測試 volume（EBS 預設加密已開，會用 `aws/ebs`），馬上做一次備份：

```bash
VOL=$(aws ec2 create-volume --availability-zone "${AWS_REGION}a" --size 1 --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=backup,Value=daily},{Key=Name,Value=runbook-backup-test}]' \
  --query VolumeId --output text)
VOL_ARN="arn:aws:ec2:$AWS_REGION:$ACCOUNT:volume/$VOL"

# 保留天數一定要給，而且要在 lock 的範圍內；不給等於永久保留，會超過 365 天的上限
JOB=$(aws backup start-backup-job --backup-vault-name "$VAULT" --resource-arn "$VOL_ARN" --iam-role-arn "$BACKUP_ROLE" \
  --lifecycle DeleteAfterDays=7 --query BackupJobId --output text)
aws backup describe-backup-job --backup-job-id "$JOB" --query '{state:State,msg:StatusMessage,rp:RecoveryPointArn}'
```

工作完成後：

```bash
aws backup list-recovery-points-by-backup-vault --backup-vault-name "$VAULT" \
  --query 'RecoveryPoints[].{rp:RecoveryPointArn,res:ResourceArn,status:Status,key:EncryptionKeyArn,delete:Lifecycle.DeleteAfterDays}' --output table

# 【寫入】確認 vault policy 擋住手動刪除（預期 AccessDenied）
RP=$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "$VAULT" --query 'RecoveryPoints[0].RecoveryPointArn' --output text)
aws backup delete-recovery-point --backup-vault-name "$VAULT" --recovery-point-arn "$RP"
```

【寫入】失敗通知：保留天數超過 lock 的上限。

```bash
aws backup start-backup-job --backup-vault-name "$VAULT" --resource-arn "$VOL_ARN" --iam-role-arn "$BACKUP_ROLE" \
  --lifecycle DeleteAfterDays=400 --query BackupJobId --output text
```

這個請求可能直接被 API 拒絕，也可能建出一個之後 `FAILED` 的工作（推測）。直接拒絕就不會有通知；這時改用「先刪 volume、再對它的 ARN 開工作」再試一次（同樣是推測，記下實際行為）。`BACKUP_JOB_EXPIRED` 沒有簡單的觸發方式，只確認它在通知清單裡。

隔天（排程跑過一次之後）：

```bash
aws backup list-backup-jobs --by-backup-vault-name "$VAULT" --by-resource-arn "$VOL_ARN" \
  --query 'BackupJobs[].{created:CreationDate,state:State,plan:CreatedBy.BackupPlanId,rule:CreatedBy.BackupRuleId}' --output table
```

最後刪測試 volume（recovery point 刪不掉，等它到期）：

```bash
aws ec2 delete-volume --volume-id "$VOL"    # 【寫入】
```

選做：用應用範本的 CMK 加密的 volume 再做一次 `start-backup-job`，確認 `<prefix>-backup` 只靠兩個 managed policy 就能用那把 key（REFERENCE〈Backup 的 tag 約定〉最後一點）。

名稱怎麼來的：vault `"${local.name_prefix}-backup"`（`backup/backup.tf:5`）；plan `"${local.name_prefix}-daily"`（`backup/backup.tf:21`）；rule 名稱是 map key `daily`（`backup/backup.tf:26`、`modules/backup-plan/main.tf:8`）；selection 名稱跟 plan 一樣（`modules/backup-plan/main.tf:44`），tag 條件 `STRINGEQUALS`（`modules/backup-plan/main.tf:52`）；通知事件（`backup/backup.tf:16`）；role `"${local.name_prefix}-backup"`（`iam/roles.tf:11`）。

**預期結果**

- vault 的 `key` 是 `$KMS_ARN`；`locked` 是 `true`、`min` dev 1／sit 7、`max` 365、`lockDate` 是空的（governance 模式沒有鎖定日期，推測）。
- 通知的 topic 是 `$TOPIC_ARN`，事件是 `BACKUP_JOB_FAILED`、`BACKUP_JOB_EXPIRED`、`RESTORE_JOB_FAILED`。
- plan 一條 rule `daily`，vault 是 `$VAULT`，`cron(0 19 * * ? *)`，`delete` dev 7／sit 35；selection 的 role 是 `$BACKUP_ROLE`，tag 是 `backup` `STRINGEQUALS` `daily`。
- role 掛 `AWSBackupServiceRolePolicyForBackup` 與 `AWSBackupServiceRolePolicyForRestores`。
- 手動的工作 `COMPLETED`，vault 多一個 recovery point，`delete` 是 7。記下 recovery point 的 `key`：是治理 CMK，還是 `aws/ebs`（見〈結論〉第 4 點）。
- `delete-recovery-point` 回 `AccessDenied`，訊息提到 vault 的 access policy。
- 失敗的工作會寄一封 `BACKUP_JOB_FAILED` 的信；如果請求被直接拒絕，備註寫「失敗通知沒有驗到」與實際錯誤訊息。
- 隔天有一個由 plan 建立的工作（`plan` 等於 `$PLAN_ID`），狀態 `COMPLETED`。這證明 tag 選擇有效。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／recovery point 的 key ______ ／失敗通知 □ 有 □ 沒驗到

## 7. Budgets

**前提**

- 階段 A、G 完成，告警 topic 的 email 訂閱已確認，`budget_emails` 是收得到信的地址。
- 預算 `<prefix>-monthly`：每月 dev 100、sit 300 美元（佔位），三個通知：實際 80%、實際 100%、預測 100%，每個通知送告警 topic 與 `budget_emails`（`budget/budget.tf:3-22`）。
- topic policy 給 `budgets.amazonaws.com` 的條件只有 `aws:SourceAccount`（`modules/sns-alarm-topic/main.tf:47-54`），沒有 `aws:SourceArn`。Budgets 是全域服務，topic 在 `ap-northeast-1`，能不能送到還沒確認（design §11 第 6 點）。
- `FORECASTED` 要累積約 5 週的資料才會發（`modules/budgets/README.md:44`），新帳號這一條先不驗。

**指令**

```bash
aws budgets describe-budget --account-id "$ACCOUNT" --budget-name "$PREFIX-monthly" \
  --query 'Budget.{limit:BudgetLimit,unit:TimeUnit,type:BudgetType,actual:CalculatedSpend.ActualSpend,forecast:CalculatedSpend.ForecastedSpend}'
aws budgets describe-notifications-for-budget --account-id "$ACCOUNT" --budget-name "$PREFIX-monthly" \
  --query 'Notifications[].[NotificationType,ComparisonOperator,Threshold,ThresholdType,NotificationState]' --output table
aws budgets describe-subscribers-for-notification --account-id "$ACCOUNT" --budget-name "$PREFIX-monthly" \
  --notification NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=80,ThresholdType=PERCENTAGE \
  --query 'Subscribers[].[SubscriptionType,Address]' --output table
```

【寫入】把 dev 的預算暫時調低，讓實際花費超過門檻。本機改 `budget/envs/dev.tfvars` 的 `monthly_budget_usd`（不要 commit），值要小於這個月已經花的錢（看上面的 `actual`）：

```bash
# budget/envs/dev.tfvars：monthly_budget_usd = 0.01
./stacks.sh dev budget apply
```

等 Budgets 重新計算（一天幾次，推測），然後看 topic 有沒有收到 Budgets 的發佈：

```bash
for m in NumberOfMessagesPublished NumberOfNotificationsDelivered NumberOfNotificationsFailed; do
  printf '%-32s ' "$m"
  aws cloudwatch get-metric-statistics --namespace AWS/SNS --metric-name "$m" --dimensions Name=TopicName,Value="$PREFIX-alerts" \
    --start-time "$(date -u -v-24H +%FT%TZ 2>/dev/null || date -u -d '-24 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 86400 --statistics Sum \
    --query 'Datapoints[0].Sum' --output text
done
```

收到信之後把 tfvars 改回原值，再 `./stacks.sh dev budget apply`。

名稱怎麼來的：預算名稱是 map key `"${local.name_prefix}-monthly"`（`budget/budget.tf:10`、`modules/budgets/main.tf:4`）；門檻與類型（`budget/budget.tf:3-7`、`:14-16`）；topic 名稱（`foundation/alerts.tf:3`）。`AWS/SNS` 的 metric 名稱與 `TopicName` 維度是 SNS 的慣例（推測）。

**預期結果**

- `limit` 是 dev 100（或你改的值）`USD`，`MONTHLY`、`COST`。
- 三個通知：`ACTUAL` 80、`ACTUAL` 100、`FORECASTED` 100，都是 `GREATER_THAN`、`PERCENTAGE`。
- 80% 那個通知的訂閱者是 `SNS` `$TOPIC_ARN` 加每個 `budget_emails` 的 `EMAIL`。
- 調低之後：`budget_emails` 收到 Budgets 直接寄的信；告警 topic 的訂閱者也收到信，`NumberOfMessagesPublished` 有值。
- email 收到、topic 沒收到（`NumberOfMessagesPublished` 是 `None`）：表示 Budgets 發佈到 topic 被擋。先把 `budgets.amazonaws.com` 的條件加上 `aws:SourceArn`（`arn:aws:budgets::<account>:*`）或暫時拿掉條件再試，記下哪一種會通，開 issue 給 `sns-alarm-topic`。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／topic 有收到 □ email 有收到 □ ／tfvars 已改回 □

## 8. destroy

**前提**

- 其他項目都做完、結果已記下。
- 這一項分兩段：8a 全部唯讀，任何 dev 帳號都能做；8b 會真的刪東西，**只在可以拆掉的 dev 帳號做**。帳號裡還有其他專案在用時，只做 8a。
- `detect` 的 destroy 會刪掉所有 finding；要留就先匯出：

  ```bash
  aws securityhub get-findings --max-items 5000 > "securityhub-findings-$E.json"
  # get-findings 一次最多 50 筆，finding 多的話分批
  aws guardduty get-findings --detector-id "$DETECTOR" \
    --finding-ids $(aws guardduty list-findings --detector-id "$DETECTOR" --query 'FindingIds[:50]' --output text) > "guardduty-findings-$E.json"
  ```

**8a. 看 destroy 會做什麼（唯讀）**

`plan -destroy` 只讀 state 與 AWS，不改任何東西：

```bash
for s in budget backup detect audit iam defaults foundation; do
  echo "== $s"; ./stacks.sh "$E" "$s" plan -- -destroy -no-color | grep -E '^\s+# .* will be destroyed|^Plan:'
done
```

**8b. 【寫入】真的 destroy（可拆掉的 dev 帳號）**

順序照 `stacks.sh` 的反向（`stacks.sh:72-78`）。`all destroy` 遇到第一個失敗就停，所以一個一個跑：

```bash
./stacks.sh dev budget destroy
./stacks.sh dev backup destroy        # vault 裡有第 6 項的 recovery point，預期失敗
```

`backup` 失敗之後，看 vault 剩下什麼：

```bash
aws backup describe-backup-vault --backup-vault-name "$VAULT" --query '{locked:Locked,points:NumberOfRecoveryPoints}'
aws backup get-backup-vault-access-policy --backup-vault-name "$VAULT" 2>&1 | head -3
aws backup list-backup-plans --query "BackupPlansList[?BackupPlanName=='$PREFIX-daily']"
```

繼續（`detect` 會刪 finding，`defaults` 會刪帳號設定，見〈帳號層的動作與復原〉）：

```bash
./stacks.sh dev detect destroy
./stacks.sh dev audit destroy
./stacks.sh dev iam destroy           # backup 的 vault 還在，但 plan 與 selection 已經刪了，role 可以刪
./stacks.sh dev defaults destroy
./stacks.sh dev foundation destroy    # 兩個 log bucket 不是空的，預期失敗
```

`foundation` 失敗之後：

```bash
for b in "$TRAIL_BUCKET" "$CONFIG_BUCKET"; do
  echo "== $b"
  aws s3api get-bucket-policy --bucket "$b" --query Policy --output text 2>&1 | head -1
  aws s3api get-bucket-lifecycle-configuration --bucket "$b" --query 'Rules[].ID' --output text 2>&1 | head -1
  aws s3api get-bucket-versioning --bucket "$b"
  aws s3api get-bucket-encryption --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault' 2>&1 | head -3
done
aws kms describe-key --key-id "$KMS_ARN" --query 'KeyMetadata.KeyState'
aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" 2>&1 | head -1
aws iam list-roles --path-prefix /aws-service-role/ --query 'Roles[].RoleName' --output text
```

復原（要繼續用這個帳號時）：

- 重新 `./stacks.sh dev <stack> apply` 依 `ORDER` 跑一次，vault 與 bucket 還在 state 裡，policy、lock、lifecycle、加密設定會補回來。
- `defaults` 的四個帳號設定，apply 前的原值見第 0 項的快照；原本有值的要手動恢復（〈帳號層的動作與復原〉）。
- 真的要清掉 vault 與 bucket：vault 要等 recovery point 到期（dev 最後一次備份後 7 天）；bucket 要清空所有版本。key 要留到這兩者都不需要為止（REFERENCE〈destroy〉）。

名稱怎麼來的：destroy 的預期照 REFERENCE〈destroy〉（`REFERENCE.md:296-309`）；vault policy、lock、通知都引用 vault（`modules/backup-vault/main.tf:14`、`:36`、`:46`），bucket 的 policy、lifecycle、加密、versioning 都引用 bucket（`modules/s3-bucket/main.tf:182`、`:191` 與其後各 resource），所以 Terraform 會先刪它們再刪 vault 或 bucket。

**預期結果**

- 8a：每個 stack 的 `Plan:` 只有 `to destroy`，數量跟 apply 時建的一樣；`backup` 與 `foundation` 的清單包括 vault policy、lock、bucket policy、lifecycle（後面 8b 會被先刪掉的那些）。
- `budget`、`detect`、`audit`、`iam`、`defaults` destroy 成功。`detect` 之後 GuardDuty detector 與 Security Hub 都停用；`defaults` 之後 public access block 不存在、密碼政策不存在、EBS 預設加密 `false`。
- `backup` destroy 失敗，錯誤是 vault 裡還有 recovery point。失敗後 vault 還在、recovery point 還在；**記下 vault policy 與 lock 是不是已經不見了**（照 Terraform 的相依順序應該已經刪掉，這是〈結論〉第 1 點）。
- `foundation` destroy 失敗，錯誤是 bucket 不是空的（`BucketNotEmpty`）。bucket 還在；**記下 bucket policy、lifecycle、加密設定是不是已經不見了，versioning 是 `Enabled` 還是 `Suspended`**（推測 provider 刪 versioning resource 時會改成 `Suspended`）。key 應該還是 `Enabled`（bucket 沒刪成，key 不會被排進刪除）；topic 可能已經刪掉（topic 只依賴 key，不依賴 bucket）。
- service-linked role（GuardDuty、Security Hub、Inspector、Access Analyzer）還在（推測）。
- 如果上面兩個「保護已經不見」成立，在 REFERENCE〈destroy〉補一句：destroy 前先 `terraform state rm` vault 與 bucket，或失敗後立刻重 apply。

**結果紀錄**：日期 ______ ／執行人 ______ ／只做 8a □ 做了 8b □ ／通過 □ 不通過 □ ／失敗後 vault 與 bucket 剩下的設定 ______

---

## design §11、§14 的其他項目

### S1. 只啟用主 region、Config 的 global 類型（§11 第 1、2 點）

**前提**：階段 D、E 完成。

**指令**

```bash
# trail 涵蓋其他 region：在 us-east-1 打一個唯讀呼叫，15 分鐘後看 bucket
aws ec2 describe-availability-zones --region us-east-1 --query 'length(AvailabilityZones)'
aws s3api list-objects-v2 --bucket "$TRAIL_BUCKET" --prefix "AWSLogs/$ACCOUNT/CloudTrail/us-east-1/" --max-items 3 --query 'Contents[].Key'
aws cloudtrail get-trail --name "$TRAIL_ARN" --region us-east-1 --query 'Trail.{name:Name,home:HomeRegion}'

# 其他 region 沒有 regional 服務
for r in us-east-1 ap-northeast-3 ap-southeast-1; do
  printf '%-16s detector=%s recorder=%s analyzer=%s\n' "$r" \
    "$(aws guardduty list-detectors --region "$r" --query 'length(DetectorIds)')" \
    "$(aws configservice describe-configuration-recorders --region "$r" --query 'length(ConfigurationRecorders)')" \
    "$(aws accessanalyzer list-analyzers --region "$r" --query 'length(analyzers)')"
done

# Security Hub 的 FAILED control，看哪些跟其他 region 有關
aws securityhub get-findings --max-items 2000 \
  --filters '{"ProductName":[{"Value":"Security Hub","Comparison":"EQUALS"}],"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --query 'Findings[].[Compliance.SecurityControlId,Title]' --output text | sort | uniq -c | sort -rn | head -40
```

名稱怎麼來的：trail 是 multi-region（`audit/trail.tf:17`）；recorder 只在主 region、`include_global_resource_types = true`（`audit/config.tf:2`、`:9`）；其他服務的 module 呼叫都沒有給 `region`（`detect/detectors.tf:8-28`、`defaults/analyzer.tf:10-17`）。列的三個 region 只是例子，可以換成帳號實際會用的 region。

**預期結果**：`us-east-1` 路徑下有 log 物件；在 `us-east-1` 查 trail 看得到同一條，`home` 是 `ap-northeast-1`。三個 region 的 detector、recorder、analyzer 都是 0。第 3 項已經確認主 region 的 recorder 記錄 global 類型。FAILED control 清單整份貼在備註，標出哪些是因為其他 region 沒開服務（REFERENCE 說 FSBP 與 CIS 會對沒啟用的 region 出 finding，這句還沒驗證過；沒有這類 finding 就寫「不成立」）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／跟其他 region 有關的 control ______

### S2. 帳號已經有 trail、recorder 或 detector（§11 第 3 點）

**前提**：第 0 項發現帳號已經有 Config recorder、GuardDuty detector、Security Hub，或要留的 trail。沒有就跳過，結果紀錄寫「不適用」。

**指令**：照 REFERENCE〈帳號已經有 trail、recorder 或 detector〉的 import 指令（`REFERENCE.md:80-114`），把佔位帳號 `111111111111` 與 `baseline-dev` 換成實際值。import 只改 Terraform state，不改 AWS。import 完先 plan：

```bash
./stacks.sh dev audit plan
./stacks.sh dev detect plan
```

【寫入】plan 沒有 replace 再 apply。apply 之後：

```bash
aws configservice describe-delivery-channels --query 'DeliveryChannels[].s3BucketName'
aws guardduty get-detector --detector-id "$DETECTOR" --query 'Features[].[Name,Status]' --output text
aws inspector2 batch-get-account-status --account-ids "$ACCOUNT" --query 'accounts[0].resourceState'
```

名稱怎麼來的：import 的 resource 位址照 REFERENCE；recorder 與 delivery channel 名稱 `default`（`audit/config.tf:5`）。

**預期結果**：每個 stack 的 plan 沒有 `must be replaced`；trail 名稱不是 `<prefix>-trail` 時 plan 會出現 replace（REFERENCE 已寫），這時不要 apply，改成刪掉舊 trail。apply 後 delivery channel 改送 `$CONFIG_BUCKET`，舊 bucket 留著；GuardDuty 的 feature 與 Inspector 的掃描類型變成範本的設定（S5 的預期），這是 REFERENCE「沒有在真實帳號確認」的那一點（`REFERENCE.md:118`）。

**結果紀錄**：日期 ______ ／執行人 ______ ／不適用 □ 通過 □ 不通過 □ ／import 了哪些 ______

### S3. vault lock 與 vault policy（§11 第 5 點、§14 `backup-vault`）

**前提**：階段 F 完成；第 6 項做過（vault 裡有 recovery point）。

**指令**

```bash
aws backup get-backup-vault-access-policy --backup-vault-name "$VAULT" --query Policy --output text | jq '.Statement[] | {Sid, Effect, Action}'
aws backup describe-backup-vault --backup-vault-name "$VAULT" --query '{locked:Locked,min:MinRetentionDays,max:MaxRetentionDays,lockDate:LockDate}'

# Terraform 改不了 vault policy：plan 應該沒有 diff；有 diff 時 apply 會被 deny
./stacks.sh "$E" backup plan -- -detailed-exitcode; echo "exit=$?"
```

名稱怎麼來的：vault policy 的 Sid `DenyRecoveryPointDeletion` 與三個動作（`modules/backup-vault/main.tf:18-26`）；lock 沒有 `changeable_for_days`，所以是 governance（`backup/backup.tf:9-12`、`modules/backup-vault/main.tf:32-40`）。

**預期結果**：policy 只有一條 `Deny`，動作是 `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy`。lock 的 `min`、`max` 跟第 6 項一樣，`lockDate` 空的。plan 的 `exit=0`（沒有變更）。第 6 項的 recovery point 到期那天（建立後 7 天）再看一次 `list-recovery-points-by-backup-vault`，確認 AWS Backup 自己的到期刪除沒有被 deny 擋住（`modules/backup-vault/README.md:43` 的說法還沒驗證過）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／到期刪除有發生 □（日期 ______）

### S4. 帳號安全預設與 Access Analyzer（§14 範本 `defaults`）

**前提**：階段 B 完成；第 0 項的快照在手上。這一項的設定影響整個帳號，見〈帳號層的動作與復原〉。

**指令**

```bash
aws s3control get-public-access-block --account-id "$ACCOUNT"
aws ec2 get-ebs-encryption-by-default
aws ec2 get-ebs-default-kms-key-id
aws ec2 get-instance-metadata-defaults
aws iam get-account-password-policy

aws accessanalyzer get-analyzer --analyzer-name "$PREFIX-account" --query 'analyzer.{arn:arn,type:type,status:status}'
aws accessanalyzer list-findings --analyzer-arn "$ANALYZER_ARN" --filter '{"status":{"eq":["ACTIVE"]}}' \
  --query 'findings[].[resourceType,resource,isPublic]' --output text

# 第 6 項建的測試 volume 有沒有被預設加密（建之後、刪之前看）
aws ec2 describe-volumes --filters Name=tag:Name,Values=runbook-backup-test --query 'Volumes[].[VolumeId,Encrypted,KmsKeyId]' --output text
```

名稱怎麼來的：四項設定的值（`defaults/security.tf:5-18`）；hop limit 2 與 `http_tokens = "required"`（`modules/account-security-defaults/main.tf:29-30`）；`ebs_default_kms_key_arn` 沒給，所以用 AWS 管理的 key（`modules/account-security-defaults/main.tf:17-22`）；analyzer `"${local.name_prefix}-account"`、`ACCOUNT`（`defaults/analyzer.tf:5-6`）。

**預期結果**

- public access block 四項都是 `true`。
- EBS 預設加密 `true`；預設 key 是 `alias/aws/ebs`。
- IMDS 預設 `HttpTokens` 是 `required`、`HttpPutResponseHopLimit` 是 `2`。
- 密碼政策：`MinimumPasswordLength` 14、符號、數字、大小寫都要、`MaxPasswordAge` 90、`PasswordReusePrevention` 24、`AllowUsersToChangePassword` `true`。
- analyzer `ACCOUNT`、`ACTIVE`；ACTIVE finding 逐筆看，跟資源負責人確認是預期的外部存取。
- 測試 volume `Encrypted` 是 `true`，`KmsKeyId` 是 `aws/ebs` 的 key。
- apply 後一週內記下有沒有其他專案因此出問題（公開 bucket、IMDSv1、密碼到期）。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／影響到其他專案的事 ______

### S5. GuardDuty feature 與 Inspector 掃描類型（§14 `guardduty`、`inspector`，design K7、K8）

**前提**：階段 E 完成。

**指令**

```bash
aws guardduty get-detector --detector-id "$DETECTOR" --query '{status:Status,freq:FindingPublishingFrequency}'
aws guardduty get-detector --detector-id "$DETECTOR" --query 'Features[].[Name,Status]' --output text

aws inspector2 batch-get-account-status --account-ids "$ACCOUNT" \
  --query 'accounts[0].{state:state.status,ec2:resourceState.ec2.status,ecr:resourceState.ecr.status,lambda:resourceState.lambda.status,lambdaCode:resourceState.lambdaCode.status}'
aws inspector2 list-coverage --query 'coveredResources[].[resourceType,scanStatus.statusCode]' --output text | sort | uniq -c
```

名稱怎麼來的：feature 清單與狀態（`modules/guardduty/variables.tf:6-13`）；`detect` 沒有覆寫，用 module 預設（`detect/detectors.tf:8-12`）；finding 頻率（`modules/guardduty/variables.tf:42`）；Inspector 的三種類型（`detect/detectors.tf:5`、`modules/inspector/main.tf:3-7`）。

**預期結果**

- detector `ENABLED`，頻率 `FIFTEEN_MINUTES`。
- `S3_DATA_EVENTS`、`EKS_AUDIT_LOGS`、`EBS_MALWARE_PROTECTION`、`RDS_LOGIN_EVENTS`、`LAMBDA_NETWORK_LOGS` 是 `ENABLED`，`RUNTIME_MONITORING` 是 `DISABLED`。清單裡其他沒列在 module 的 feature（例如 `EKS_RUNTIME_MONITORING`），module 不管，照實記下它們的狀態（`modules/guardduty/README.md` 的「只管理列出的 feature」）。
- Inspector `state` 是 `ENABLED`，`ec2`、`ecr`、`lambda` 是 `ENABLED`，`lambdaCode` 是 `DISABLED`。
- `list-coverage` 列出帳號裡的 ECR 映像、Lambda 與受 SSM 管理的 EC2；EC2 沒有 SSM agent 的會是不能掃的狀態（`modules/inspector/README.md` 的 EC2 說明），記下數量。

**結果紀錄**：日期 ______ ／執行人 ______ ／通過 □ 不通過 □ ／其他 feature 的狀態 ______

---

## 結果怎麼回寫

執行人是負責 apply 帳號 baseline 的人（通常是 platform team 或帳號擁有者）；回寫都用 PR：

| 回寫到哪裡 | 誰改 | 怎麼改 | 誰審 |
|---|---|---|---|
| 本 runbook 的「結果紀錄」 | 執行人 | 每一項填完那一行；不通過的附 issue 連結 | 跟下一列同一個 PR |
| `templates/account-baseline/infra/REFERENCE.md`〈雲端整合待驗證〉表與〈已知限制的細節〉 | 執行人 | 表格加一欄「結果」，寫 `通過（YYYY-MM-DD，dev）` 或 `不通過：<一句話>（#issue）`。8 項都通過時，比照〈靜態驗證通過（2026-10-29）〉另開一節〈雲端驗證通過（日期）〉；〈已知限制的細節〉裡已經確認的條目刪掉或改寫；第 8 項確認「失敗後保護被拆掉」成立時，在〈destroy〉補上；README 第 11 行「還沒在真實帳號 apply 過」與 README〈已知限制〉第 4 點跟著改 | platform team（`/templates/` 的 CODEOWNERS） |
| `docs/design/v10/design-docs.md` §11 | platform team | 每一點後面加 `→ 已確認（YYYY-MM-DD，runbook S<n> 或第 <n> 項）`，或 `→ 不成立：<實際行為>，改法見 #issue`；不成立而要改設計的，記在 §14 | platform team |
| 11 個 module 與 `sns-alarm-topic`、`s3-bucket` README 的「還沒在真實帳號 apply 過」 | platform team | 對應的項目通過後改成實際驗證的日期與帳號類型（單帳號） | platform team |

不通過的處理：

- 問題在 module（例如 `sns-alarm-topic` 的 Budgets 條件、`s3-bucket` 的 bucket policy）：照 `docs/guides/team-roles.md`〈交接點〉在本 repo 開 issue 給 platform team，附指令輸出。
- 問題在範本的 stack（例如 `foundation/kms.tf` 的條件、`iam/policies.tf` 的動作）：開 issue 並標 `templates/account-baseline`，修正走一般的範本改版 PR。
- 同一項修好後重跑，結果紀錄寫新的一行，舊的不刪。
