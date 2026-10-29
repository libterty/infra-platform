# account-baseline 參考資料

這份是 [`README.md`](./README.md) 的參考資料：README 只放第一次用範本需要的步驟，細節、合約、Organizations 模式、import 與 destroy 都在這裡。

狀態：離線驗證通過，還沒在真實帳號 apply 過；第一次 apply 時逐項確認〈已知限制的細節〉與〈驗證〉的「雲端整合待驗證」。設計見 [`docs/design/v10/design-docs.md`](../../../docs/design/v10/design-docs.md) §4、§7、§8、§11。設計與程式碼不一致時以程式碼為準，這份文件照程式碼寫。

## 成本

量級與計費方式見 [design §10](../../../docs/design/v10/design-docs.md)。固定費用只有 CMK（每把約 1 美元／月）；其餘依用量：Config 依 configuration item 與 rule 評估次數（Security Hub 的 control 也走 Config 評估），GuardDuty 依分析的事件量，Security Hub 依檢查次數與 finding 數，Inspector 依掃描的 EC2、映像、Lambda 數，Backup 依備份儲存量。GuardDuty 與 Security Hub 前 30 天免費試用，試用期結束前看一次帳單的預估。Access Analyzer 的外部存取分析、management event 的第一份 trail 免費。

## 檔案

`infra/terraform/` 底下每個 stack 一個目錄，另有 `stacks.sh`（依序跑各 stack）與 `check-ssm-contract.sh`（靜態檢查 SSM 合約與 tfvars 一致性）。每個 stack 的固定檔案跟 example6 相同（`versions.tf`、`providers.tf`、`common.tf`、`envs/<env>.tfvars`、`envs/<env>.tfbackend`、`tests/`、`.terraform.lock.hcl`；有發布 key 的 stack 另有 `ssm-outputs.tf`，有讀上游的 stack 另有 `ssm-inputs.tf`）。`common.tf` 7 個 stack 一字不差。只有 aws provider，沒有 provider alias。

## stack 的內容

apply 順序與 `ORDER` 見 README。`<prefix>` 是 `<project>-<env>`，`<account>` 是 `expected_account_id`。

| 順序 | stack | 建的東西 | 讀 |
|---|---|---|---|
| 1 | `foundation` | CMK `<prefix>-governance`：key policy 放行 CloudTrail（條件 `aws:SourceArn` 與 encryption context 都限本帳號的 trail）、Config、Backup、Budgets、EventBridge、CloudWatch、本 region 的 CloudWatch Logs（限本帳號的 log group）。log bucket `<prefix>-trail-<account>`、`<prefix>-config-<account>`：CMK 加密、365 天過期、versioning（舊版本 365 天過期）、`force_destroy = false`，bucket policy 只讓 CloudTrail、Config 寫本帳號的路徑。告警 topic `<prefix>-alerts`：CMK 加密，`alert_emails` 用 email 訂閱，topic policy 放行 `budgets.amazonaws.com`、`backup.amazonaws.com`、`events.amazonaws.com`（條件 `aws:SourceAccount`） | 無 |
| 2 | `defaults` | S3 account public access block 四項全開；EBS 預設加密（用 AWS 管理的 `aws/ebs`，治理 CMK 沒有放行 EC2）；新 instance 預設 IMDSv2（hop limit 2）；IAM 密碼政策：至少 14 字元、要有符號、數字、大小寫，90 天到期，不能重複最近 24 組，使用者可以自己改。Access Analyzer `<prefix>-account`（`ACCOUNT`，免費；unused access 分析不開） | 無 |
| 3 | `iam` | role `<prefix>-config-recorder`（`AWS_ConfigRole`，加上 config bucket 的 `GetBucketAcl`、寫 `AWSLogs/<account>/Config/*`、CMK 的 `Decrypt`、`GenerateDataKey`）；`<prefix>-backup`（`AWSBackupServiceRolePolicyForBackup`、`AWSBackupServiceRolePolicyForRestores`）；`<prefix>-trail-logs`（只能在 `/aws/cloudtrail/<prefix>` 建 log stream、寫 event）。每個 role 只信任一個服務，條件 `aws:SourceAccount` | foundation |
| 4 | `audit` | log group `/aws/cloudtrail/<prefix>`（CMK，dev 保存 90 天、sit 365 天）；trail `<prefix>-trail`：multi-region、只記 management event、log file validation、CMK 加密，送 trail bucket 與這個 log group；告警 `RootAccountUsage`（root 帳號的 API 呼叫）與 `UnauthorizedApiCalls`（`*UnauthorizedOperation`、`AccessDenied*`，排除 `delivery.logs.amazonaws.com` 與 `HeadBucket`），metric namespace `<project>/<env>/cloudtrail`，告警與恢復都送告警 topic；Config recorder `default`：記錄所有支援的 resource type 加 IAM 這類 global type、`CONTINUOUS`、保留 2557 天，送 config bucket | foundation、iam |
| 5 | `detect` | GuardDuty detector：S3、EKS audit log、EBS malware、RDS login、Lambda network log 開，runtime monitoring 關，finding 更新每 15 分鐘送出。Security Hub（CSPM）：FSBP v1.0.0 與 CIS v5.0.0、`SECURITY_CONTROL`、新 control 自動啟用、不開 AWS 的預設標準。Inspector：`EC2`、`ECR`、`LAMBDA`（Lambda 程式碼掃描不開）。EventBridge rule `<prefix>-guardduty-findings`（severity ≥ 7，即 HIGH 與 CRITICAL）、`<prefix>-securityhub-findings`（`HIGH`、`CRITICAL`、`ACTIVE`，排除 GuardDuty 送進來的 finding，同一筆不會寄兩次），目標都是告警 topic | foundation、audit |
| 6 | `backup` | vault `<prefix>-backup`：CMK 加密、vault policy 對所有人 deny 刪除 recovery point、改生命週期、換 policy；governance lock 最短 dev 1 天、sit 7 天，最長 365 天；`BACKUP_JOB_FAILED`、`BACKUP_JOB_EXPIRED`（時段內沒開始，等於漏備份）、`RESTORE_JOB_FAILED` 送告警 topic。plan `<prefix>-daily`：每天 03:00（UTC+8，`cron(0 19 * * ? *)`），保留 dev 7 天、sit 35 天，選 tag `backup = "daily"` 的資源 | foundation、iam |
| 7 | `budget` | 預算 `<prefix>-monthly`：每月 dev 100、sit 300 美元（佔位），實際 80%、實際 100%、預測 100% 時通知告警 topic 與 `budget_emails`（最多 10 個） | foundation |

「讀」欄看不出來的順序限制：

- `iam` 比 `audit` 先 apply，拿不到 log group 的 ARN，所以照命名規則組：`/aws/cloudtrail/<prefix>`（`iam/naming.tf`）。`audit/trail.tf` 用同一個名稱，改名時兩邊要一起改。
- `iam` 的三個 role 等 policy 附加完才發布到 SSM，`audit`、`backup` 看到 role 時權限已經在。
- `detect` 讀 `audit/config_recorder_name` 但不拿來建任何東西，只是讓 `audit` 還沒 apply 時 `detect` 的 plan 會失敗：Security Hub 的 FSBP 與 CIS control 要靠 Config 評估。
- `backup` 的保留天數要介於 lock 的最短天數與 365 之間，tfvars 的 validation 會擋；超出範圍的備份工作，vault lock 會拒絕。

## SSM 合約

路徑 `/<project>/<env>/<stack>/<key>`（[ADR-0003](../../../docs/adr/0003-cross-stack-values-via-ssm-only.md)），只有樹 A，沒有 bridge。全部是 String。下表照各 stack 的 `ssm-outputs.tf` 與 `ssm-inputs.tf` 整理，不一致時以程式碼為準。

| key | 內容 | 讀的 stack |
|---|---|---|
| `foundation/kms_key_arn` | 治理 CMK | `iam`、`audit`、`backup` |
| `foundation/trail_bucket_name` | CloudTrail 的 log bucket | `audit` |
| `foundation/config_bucket_name` | Config 的 log bucket | `iam`、`audit` |
| `foundation/alert_topic_arn` | 資安告警 topic | `audit`、`detect`、`backup`、`budget` |
| `defaults/access_analyzer_arn` | Access Analyzer | 沒有 stack 讀 |
| `iam/config_role_arn` | Config recorder 的 role | `audit` |
| `iam/backup_role_arn` | Backup plan 的 role | `backup` |
| `iam/trail_logs_role_arn` | CloudTrail 寫 CloudWatch Logs 的 role | `audit` |
| `audit/trail_arn` | trail | 沒有 stack 讀 |
| `audit/config_recorder_name` | Config recorder 名稱（`default`） | `detect`（只用來排順序） |
| `detect/guardduty_detector_id` | GuardDuty detector ID | 沒有 stack 讀；給 import 與查 finding |
| `backup/vault_name` | vault 名稱 | 沒有 stack 讀 |

`budget` 不發布任何 key。

跟 design §8.2 的差異：`defaults` 不讀 `foundation`，另外發布 `defaults/access_analyzer_arn`；`detect` 讀 `foundation/alert_topic_arn` 與 `audit/config_recorder_name`，不讀 `audit/trail_arn`。

`check-ssm-contract.sh` 檢查兩件事：每個讀取的 key 都由 `ORDER` 更早的 stack 發布、型別一致；同一個 env 各 stack tfvars 的 `project`、`env`、`aws_region`、`expected_account_id` 一致，`env` 等於檔名。

## Backup 的 tag 約定

`backup` 的 plan 用 tag 選資源，不列 ARN，所以應用範本不用讀這份範本的任何值。要每天備份的資源加這個 tag：

```hcl
tags = {
  backup = "daily"
}
```

- key 與 value 要完全一樣，都是小寫。
- Backup 只備份它支援的資源類型，例如 RDS、Aurora、DynamoDB、EFS、EBS、EC2。
- 資源已經有自己的備份機制（例如 DynamoDB PITR、RDS 自動備份）時，加 tag 是另外多一份每日備份，儲存費用另計。
- 備份用治理 CMK 加密存進 vault。來源資源用自己的 CMK 加密時，Backup 的 role 可能需要那把 key 的權限；`<prefix>-backup` 只掛 AWS 管理的 policy，這部分沒有在真實帳號確認。

## 帳號已經有 trail、recorder 或 detector

一個 region 只能有一個 Config recorder、一個 delivery channel、一個 GuardDuty detector；Security Hub 啟用過再啟用會失敗。帳號已經有這些時，`audit`、`detect` 會 apply 失敗，要先 import 進 state，或在 console 移除。CloudTrail 不會失敗，但第二條記 management event 的 trail 要計費，舊 trail 不要了就刪掉，要留就 import。

`stacks.sh` 沒有 import 動作，import 時在 stack 目錄直接跑 terraform，`TF_DATA_DIR` 與 tfvars 跟 `stacks.sh` 用的一樣（以 `dev` 為例）：

```bash
cd infra/terraform
./stacks.sh dev audit init
cd audit
export TF_DATA_DIR=.terraform-dev

# CloudTrail：名稱要等於 <prefix>-trail，不同的話 import 之後 Terraform 會 replace
terraform import -var-file=envs/dev.tfvars module.trail.aws_cloudtrail.this \
  arn:aws:cloudtrail:ap-northeast-1:111111111111:trail/baseline-dev-trail

# Config：範本的 recorder 與 delivery channel 都叫 default（console 建的也是 default）
terraform import -var-file=envs/dev.tfvars module.config_recorder.aws_config_configuration_recorder.this default
terraform import -var-file=envs/dev.tfvars module.config_recorder.aws_config_delivery_channel.this default
terraform import -var-file=envs/dev.tfvars module.config_recorder.aws_config_configuration_recorder_status.this default
terraform import -var-file=envs/dev.tfvars module.config_recorder.aws_config_retention_configuration.this default
```

```bash
cd infra/terraform
./stacks.sh dev detect init
cd detect
export TF_DATA_DIR=.terraform-dev

# GuardDuty：ID 用 aws guardduty list-detectors 查
terraform import -var-file=envs/dev.tfvars module.guardduty.aws_guardduty_detector.this <detector-id>

# Security Hub：帳號 ID；已經訂閱的標準用 subscription ARN
terraform import -var-file=envs/dev.tfvars module.securityhub.aws_securityhub_account.this 111111111111
terraform import -var-file=envs/dev.tfvars 'module.securityhub.aws_securityhub_standards_subscription.this["fsbp"]' \
  arn:aws:securityhub:ap-northeast-1:111111111111:subscription/aws-foundational-security-best-practices/v/1.0.0
terraform import -var-file=envs/dev.tfvars 'module.securityhub.aws_securityhub_standards_subscription.this["cis"]' \
  arn:aws:securityhub:ap-northeast-1:111111111111:subscription/cis-aws-foundations-benchmark/v/5.0.0
```

- 每個 import 完都跑 `./stacks.sh dev <stack> plan`，確認沒有 replace 再 apply。import 後 apply 會把既有設定改成範本的值，例如 Config 的 delivery channel 改送新的 config bucket，舊 bucket 留著不動。
- 還沒訂閱的標準不用 import，apply 時會訂閱。不在範本裡的標準（例如 AWS 預設會開的 CIS v1.2.0）Terraform 不管，要停用就在 console 關。
- GuardDuty 的 feature 與 Inspector 的掃描類型沒有 import，apply 時直接改成範本的設定；這點沒有在真實帳號確認。

## 啟用其他 region

範本只在 `ap-northeast-1` 啟用 regional 服務（design §7、§11）。CloudTrail 是 multi-region trail，已經涵蓋所有 region，不用再建。其他服務在 module 加 `region` 輸入、每個 region 多呼叫一次，stack 不用另外宣告 provider。以 `us-east-1` 為例：

```hcl
# audit/config.tf：global resource type 只能在一個 region 記錄，主 region 以外一律 false
module "config_recorder_use1" {
  source  = "app.terraform.io/libterty/config-recorder/aws"
  version = "~> 0.1.0"

  region              = "us-east-1"
  name                = "default"
  role_arn            = local.config_recorder.role_arn
  s3_bucket_name      = local.config_recorder.s3_bucket_name
  s3_kms_key_arn      = local.config_recorder.s3_kms_key_arn
  recording           = { include_global_resource_types = false, exclusion_types = [] }
  recording_frequency = "CONTINUOUS"
  retention_days      = 2557
}

# detect/detectors.tf
module "guardduty_use1" {
  source  = "app.terraform.io/libterty/guardduty/aws"
  version = "~> 0.1.0"

  region = "us-east-1"
}

module "securityhub_use1" {
  source  = "app.terraform.io/libterty/securityhub/aws"
  version = "~> 0.1.0"

  region    = "us-east-1"
  standards = local.securityhub_standards
}

module "inspector_use1" {
  source  = "app.terraform.io/libterty/inspector/aws"
  version = "~> 0.1.0"

  region         = "us-east-1"
  resource_types = local.inspector_resource_types
}
```

- Security Hub 的 control 靠 Config 評估，所以開 Security Hub 的 region 也要有 recorder。recorder 可以送到 `ap-northeast-1` 的 config bucket；跨 region 寫 CMK 加密的 bucket 沒有在真實帳號確認。
- Access Analyzer 一樣用 `region` 每個 region 建一個（`defaults/analyzer.tf`）。EBS 預設加密與 IMDSv2 預設也是 regional，`account-security-defaults` 收 `region`，但 S3 public access block 與密碼政策是帳號全域，第二次呼叫要把這兩項設成 `false` 與 `null`。
- EventBridge rule 是 regional，`eventbridge-rule` 沒有 `region` 輸入，其他 region 的 finding 不會進 `ap-northeast-1` 的 rule。最簡單的做法是在主 region 的 `module "securityhub"` 加 `finding_aggregator = { linking_mode = "SPECIFIED_REGIONS", regions = ["us-east-1"] }`，把 finding 彙整到 `ap-northeast-1`。這時其他 region 的 GuardDuty finding 只會經 Security Hub 進來，但 Security Hub 的 rule 排除了 GuardDuty，要把 `detect/findings.tf` 的 `ProductName` 條件拿掉，或接受這些 finding 不寄信。彙整後的 finding 會不會觸發主 region 的 rule，沒有在真實帳號確認。
- 全 region 啟用通常在 Organizations 模式由資安帳號做（下一節）。

## Organizations 模式

範本示範單一帳號（design K2）。用 AWS Organizations 時，帳號分工照下表（design §4.2）；module 都支援，但範本沒有對應的 stack，要自己組。

| 帳號 | apply 的 module | 說明 |
|---|---|---|
| 管理帳號 | `organization-delegated-admin`、`cloudtrail`（`is_organization_trail = true`） | 開 trusted access，把 GuardDuty、Security Hub、Inspector、Config、Access Analyzer 的管理委派給資安帳號 |
| 資安帳號 | `guardduty`、`securityhub`、`inspector`、`access-analyzer` 的 organization 設定、`config-recorder` 的 aggregator | organization 層級的自動啟用與彙整 |
| log 封存帳號 | `s3-bucket`（`organization_id`） | organization trail 與 Config 的集中 bucket |
| 成員帳號 | 這份範本裡帳號層的部分：`account-security-defaults`、`backup-*`、`budgets` | 偵測類服務由資安帳號自動啟用，成員帳號不再各自建 |

下面的例子：organization ID `o-exampleorgid`，資安帳號 `333333333333`。

管理帳號：

```hcl
module "delegated_admin" {
  source  = "app.terraform.io/libterty/organization-delegated-admin/aws"
  version = "~> 0.1.0"

  delegated_admin_account_id = "333333333333"
  services                   = ["guardduty", "securityhub", "inspector", "config", "access-analyzer"]
  regions                    = ["ap-northeast-1"]
}

module "org_trail" {
  source  = "app.terraform.io/libterty/cloudtrail/aws"
  version = "~> 0.1.0"

  name                  = "example-org-trail"
  s3_bucket_name        = "example-org-trail-logs"   # log 封存帳號的 bucket
  kms_key_arn           = module.org_trail_key.key_arn
  is_multi_region_trail = true
  is_organization_trail = true
}
```

log 封存帳號：

```hcl
module "org_log_bucket" {
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.6.0"

  name            = "example-org-trail-logs"
  log_delivery    = ["cloudtrail", "config"]
  organization_id = "o-exampleorgid"
  kms_key_arn     = module.log_key.key_arn
  expiration_days = 365
  versioning      = { noncurrent_expiration_days = 365 }
  force_destroy   = false
}
```

資安帳號：

```hcl
module "guardduty" {
  source  = "app.terraform.io/libterty/guardduty/aws"
  version = "~> 0.1.0"

  organization = {
    auto_enable = "ALL"
    features = {
      S3_DATA_EVENTS         = { auto_enable = "ALL" }
      EKS_AUDIT_LOGS         = { auto_enable = "ALL" }
      EBS_MALWARE_PROTECTION = { auto_enable = "ALL" }
      RDS_LOGIN_EVENTS       = { auto_enable = "ALL" }
      LAMBDA_NETWORK_LOGS    = { auto_enable = "ALL" }
    }
  }
}

module "securityhub" {
  source  = "app.terraform.io/libterty/securityhub/aws"
  version = "~> 0.1.0"

  standards    = ["fsbp", "cis"]
  organization = { auto_enable = true, auto_enable_standards = "NONE" }
}

module "inspector" {
  source  = "app.terraform.io/libterty/inspector/aws"
  version = "~> 0.1.0"

  organization = { auto_enable = { ec2 = true, ecr = true, lambda = true } }
}

module "access_analyzer" {
  source  = "app.terraform.io/libterty/access-analyzer/aws"
  version = "~> 0.1.0"

  name = "example-organization"
  type = "ORGANIZATION"
}

module "config_recorder" {
  source  = "app.terraform.io/libterty/config-recorder/aws"
  version = "~> 0.1.0"

  name           = "default"
  role_arn       = "arn:aws:iam::333333333333:role/example-config-recorder"
  s3_bucket_name = "example-org-trail-logs"
  aggregator = {
    name                  = "example-organization"
    organization_role_arn = "arn:aws:iam::333333333333:role/example-config-aggregator"   # 掛 AWSConfigRoleForOrganizations
  }
}
```

- `organization-delegated-admin` 只在管理帳號 apply，對同一個 organization 只呼叫一次，要多個 region 就全部放進 `regions`。資安帳號不能是管理帳號。
- organization trail 只能在管理帳號（或 CloudTrail 的委派管理帳號，`services` 加 `cloudtrail`）建，而且一定是 multi-region。`s3-bucket` 給了 `organization_id` 之後，bucket policy 多開 `AWSLogs/o-exampleorgid/` 給 organization trail、`AWSLogs/<帳號>/Config/` 給成員帳號的 Config，都用 `aws:SourceOrgID` 限制。
- 跨帳號的 KMS key（trail 用的 `org_trail_key`、bucket 用的 `log_key`）要在 key policy 放行 CloudTrail 與 Config 寫入整個 organization，`kms-key` 的 `service_principals` 可以加 `aws:SourceOrgID` 條件；這部分範本與 module 測試都沒有涵蓋。
- Security Hub 的 `auto_enable_standards` 用 `NONE`：`DEFAULT` 會在新成員開 FSBP 與 CIS v1.2.0，不是範本用的 v5.0.0。module 用的是 local configuration，不是 Security Hub 的 central configuration。
- 偵測類服務的委派是 regional，`organization` 設定也只管 provider 的 region；其他 region 照〈啟用其他 region〉多呼叫一次。
- 成員帳號 apply 這份範本時，拿掉 `detect`；`audit` 的 trail 由 organization trail 取代。Config 沒有 organization 層級的自動啟用，成員帳號的 recorder 照樣在 `audit` 建，`s3_bucket_name` 改成 log 封存帳號的 bucket。
- Backup 的委派不在範圍內：要管理 backup policy 時，還需要管理帳號的 resource-based delegation policy、organization 開 backup policy 類型與 cross-account monitoring，`organization-delegated-admin` 沒有做。

## vault lock：governance 與 compliance

`backup` 的 vault lock 用 governance 模式（design K11）：vault lock 會拒絕保留天數比最短天數短或比 365 天長的備份，但有 `backup:DeleteBackupVaultLockConfiguration` 權限的人仍然可以拿掉 lock。

要改成 compliance 模式，在 `backup/backup.tf` 的 `lock` 加 `changeable_for_days`（3 天以上）與 `compliance_acknowledged = true`。冷卻期過後，lock 不能改也不能移除，連 root 與 AWS 都不行，vault 裡還有 recovery point 時也刪不掉。先用 governance 模式跑一段時間，確定保留天數之後再改；sit 這種會拆掉重建的環境不建議用 compliance。

vault policy 另外對所有人 deny `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy`，跟 lock 模式無關。recovery point 到期時由 AWS Backup 刪除，不受這份 deny 影響。這份 policy 之後 Terraform 改不了，要改只能先用 `backup:DeleteBackupVaultAccessPolicy` 刪掉 policy 再 apply。

## destroy

`./stacks.sh <env> all destroy` 依反向順序跑。這份範本保護的是稽核證據，下面幾種會擋住或會造成損失，要先決定怎麼處理：

| 資源 | 預設 | destroy 的結果與要先做什麼 |
|---|---|---|
| Backup vault（`backup`） | `force_destroy = false`，vault policy deny 刪除 recovery point，governance lock | vault 裡有 recovery point 就刪不掉。等 recovery point 照保留天數到期（最後一次備份後 dev 7 天、sit 35 天），或先刪掉 vault policy 與 lock 再手動刪 recovery point。compliance 模式的 vault 只能等到期 |
| Backup plan（`backup`） | | 刪了就停止備份，已經有的 recovery point 留在 vault |
| GuardDuty、Security Hub、Inspector（`detect`） | | 停用會刪掉既有 finding。要留紀錄先匯出 |
| trail、Config recorder（`audit`） | | 停止記錄；已經寫進 bucket 的 log 留著。trail 的 log group 跟著刪，裡面的 log 一起刪掉（稽核證據在 trail bucket） |
| 帳號安全預設（`defaults`） | | destroy 會刪掉 S3 account public access block（等於關掉）、EBS 預設加密與 IMDS 預設值回到 AWS 的預設、刪掉密碼政策。帳號還在用就不要 destroy `defaults` |
| log bucket（`foundation`） | versioning、365 天過期、`force_destroy = false` | 不是空的刪不掉，這是預期的。要保留證據就先 `terraform state rm 'module.log_bucket["trail"]' 'module.log_bucket["config"]'` 讓 Terraform 不再管理，bucket 留著；真的要刪就先清空所有版本 |
| CMK（`foundation`） | 刪除等待 30 天 | key 刪掉之後，bucket 裡的 log 與 vault 裡的備份都解不開。bucket 要留，key 就要留：一起 `terraform state rm module.kms`，或在等待期內取消刪除 |
| 告警 topic（`foundation`） | | 刪掉後 email 訂閱一起消失 |

## 複製出去之後要改什麼

| 項目 | 改什麼 |
|---|---|
| module 的 `source` | 從 HCP private registry 引用（`app.terraform.io/libterty/<module>/aws`，ADR-0004）；換 organization 或改 git 來源見 [`docs/guides/consuming-modules.md`](../../../docs/guides/consuming-modules.md) |
| 帳號表 | 7 個 stack 的 `common.tf` 的 `accounts_by_env`（`111111111111`、`222222222222`），同步改、保持一字不差 |
| state | 每份 `envs/*.tfbackend` 的 `bucket`、`kms_key_id`，`key` 的 `baseline-` 前綴換成自己的 `project`。state bucket 的強化做法見 [example4 REFERENCE〈前置作業的細節〉第 1 項](../../example4/infra/REFERENCE.md#前置作業的細節) |
| 每份 tfvars | `project`（現在是 `baseline`）、`expected_account_id` |
| `foundation` | `alert_emails`（現在是 `security-alerts@example.com`）；log bucket 的保留天數在 `buckets.tf`（365） |
| `audit` | `trail_log_retention_days`（dev 90、sit 365）；Config 的保留天數在 `config.tf`（2557）；告警的 pattern 在 `alarms.tf` |
| `detect` | 標準、掃描類型在 `detectors.tf`；寄信的嚴重度門檻在 `findings.tf` |
| `backup` | `vault_min_retention_days`、`backup_delete_after_days`；備份時間與 tag 在 `backup.tf` |
| `budget` | `monthly_budget_usd`（dev 100、sit 300，佔位）、`budget_emails`（現在是 `finops@example.com`） |
| 命名規則 | trail 的 log group `/aws/cloudtrail/<prefix>` 在 `iam/naming.tf` 與 `audit/trail.tf` 各一份，要一起改 |

## 已知限制的細節

下面是 mock 驗不到或刻意不做的事，第一次 apply 時要逐項確認。

| 範圍 | 限制 |
|---|---|
| 只啟用主 region | GuardDuty、Security Hub、Config、Inspector、Access Analyzer 只在 `ap-northeast-1`，其他 region 沒有偵測；FSBP 與 CIS 會對沒啟用的 region 出 finding。做法見〈啟用其他 region〉 |
| Budgets 送 SNS | topic policy 只用 `aws:SourceAccount` 限制。AWS 文件建議加 `aws:SourceArn`（`arn:aws:budgets::<account>:*`）但不是必要條件；Budgets 是全域服務，topic 在 `ap-northeast-1`，送不送得到要第一次 apply 時確認 |
| CloudTrail、Config 的 bucket 與 key policy | CloudTrail 的條件用 `trail/*`（建 bucket 時還不知道 trail 名稱），encryption context 用 `StringLikeIfExists`；organization 模式靠 `aws:SourceOrgID`。各服務實際送哪些 condition key，沒有對真實帳號確認 |
| event pattern | 兩個 EventBridge rule 與兩個 metric filter 的 pattern 照 AWS 與 CIS 文件寫，沒有用真實 finding 與 event 確認會比對成功 |
| CIS v5.0.0 | module 組出的標準 ARN（`standards/cis-aws-foundations-benchmark/v/5.0.0`）照 AWS 文件寫，沒有在真實帳號訂閱過 |
| Security Hub 的版本 | 用的是 Security Hub CSPM（`aws_securityhub_account`），不是新版 Security Hub（provider 的 `*_v2` resource） |
| IAM 與 KMS | `iam` 的動作清單與 `foundation` key policy 依文件寫，沒有對真實帳號驗證 |
| vault lock | governance 模式有權限的人仍可移除（〈vault lock：governance 與 compliance〉） |
| log bucket | 沒有 S3 Object Lock：要在建 bucket 時開，`s3-bucket` 還不支援。刪除保護靠 versioning、365 天保留與 log file validation |
| Organizations | 沒有範本示範，只有 module 測試與〈Organizations 模式〉的說明；Backup 的委派不在範圍內 |

## 驗證

```bash
scripts/validate.sh templates/account-baseline/infra/terraform
```

依序做 `fmt`、靜態規則（含 S1 mock provider、S8 stack 只呼叫 module、S10 lock 的 darwin 與 linux hash）、`check-ssm-contract.sh`；再對每個 stack 跑 `init -backend=false`、`validate`、`terraform test`（`dev`、`sit` 兩份 tfvars 各一次），最後 tflint。全部離線，不需要 AWS 憑證，但需要 HCP registry token。

### 靜態驗證通過（2026-10-29）

| 項目 | 結果 |
|---|---|
| `scripts/validate.sh templates/account-baseline/infra/terraform` 全量 | 通過（exit 0）：fmt、靜態規則、7 個 stack 的 `init -backend=false`、`validate`、`terraform test`、tflint |
| `terraform test` | 7 個 stack、14 個測試檔跑 21 次（主測試 1 次，tfvars 測試 `dev`、`sit` 各 1 次），159 個 run 全過 |
| `check-ssm-contract.sh` | 7 個 stack、14 個讀取、2 個 env 通過 |

### 雲端整合待驗證

需要真實帳號，這個里程碑沒有做。

| 項目 | 怎麼確認 |
|---|---|
| CloudTrail | trail bucket 收到 CMK 加密的 log 與 digest 檔；`aws cloudtrail validate-logs` 通過；log group 收到 event |
| CloudTrail 告警 | 用 root 登入或打一個沒權限的 API，告警 topic 收到信 |
| Config | recorder 開始記錄，config bucket 收到快照；`AWS_ConfigRole` 加上 inline policy 夠用 |
| Security Hub | FSBP 與 CIS v5.0.0 訂閱成功，control 開始評估 |
| finding 告警 | 用 GuardDuty 的 sample finding（`aws guardduty create-sample-findings`）確認 HIGH 以上會寄信，Security Hub 不會重寄同一筆 |
| Backup | 加了 `backup = "daily"` tag 的資源隔天有 recovery point；故意讓工作失敗時收到通知 |
| Budgets | 把預算暫時調低，確認 SNS 與 email 都收到 |
| destroy | vault、log bucket、CMK 照〈destroy〉的預期擋住 |
