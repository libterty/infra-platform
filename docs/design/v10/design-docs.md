# infra-platform v10 設計文件：帳號層治理 module 與 templates/account-baseline

> 狀態：已實作（2026-10-29，J0–J9，見 [`implement-process.md`](./implement-process.md)）。實作時跟設計不同的決定記在 §14，兩邊不同時以 §14 與程式碼為準。§3.1 的 D 是使用者拍板的決策；§3.2 的 K 是照慣例的判斷，審閱時可以推翻。標「審閱重點」的是需要特別看的取捨。
> 範圍：新增帳號層治理用的 module（CloudTrail、Config、GuardDuty、Security Hub、Inspector、IAM Access Analyzer、Backup、Budgets、帳號層安全預設、Organizations 的委派管理），兩個既有 module 升 minor（`s3-bucket`、`sns-alarm-topic`），新建範本 `templates/account-baseline`。不改 example2–example6、project-infra。
> 文中路徑除非特別註明，都是 repo 內相對路徑。provider schema 是 aws 6.70.0（`terraform providers schema -json`）的結果。標「未確認」的要在實作或真實環境驗證。環境只有 `dev`、`sit`。

## 1. 結論

- **新 module 11 個**，每個發 0.1.0、在 HCP 登記。repo 的 module 從 80 個變成 91 個：
  - 稽核與組態：`cloudtrail`、`config-recorder`。
  - 威脅與弱點偵測：`guardduty`、`securityhub`、`inspector`、`access-analyzer`。
  - 備份與成本：`backup-vault`、`backup-plan`、`budgets`。
  - 帳號設定：`account-security-defaults`、`organization-delegated-admin`。
- **既有 module 升 minor 2 個**，只加輸入，預設值行為不變：
  - `s3-bucket` 0.5.0 → 0.6.0：`log_delivery` 多兩種，`cloudtrail` 與 `config`，含 organization trail 的寫入路徑。
  - `sns-alarm-topic` 0.1.1 → 0.2.0：`service_publishers`，讓 Budgets、Backup、EventBridge 能發佈到 topic。
- **單帳號與 Organizations 兩種模式都支援（D2）**：
  - 每個偵測類 module 都能在單一帳號啟用，也能在委派管理帳號設定整個 organization。
  - 管理帳號要做的事（委派管理員、trusted access、organization trail）集中在 `organization-delegated-admin` 與 `cloudtrail`。
  - 範本示範單帳號；Organizations 的帳號分工寫在 REFERENCE，由 module 測試覆蓋。
- **新範本 `templates/account-baseline`（D3）**：
  - 每個帳號 apply 一份，跟應用範本分開。一個帳號放多個專案時，trail、detector 不會重複建。
  - 7 個 stack（§8）。
- **`validate.sh` 的 S4 要開一個例外**：`aws_iam_account_password_policy` 是帳號設定，不是 role 或 policy，只准出現在 `account-security-defaults`（K3）。這是 v10 第一個 Phase 的內容。
- **region**：GuardDuty、Security Hub、Config、Inspector、Access Analyzer、Backup 都是 regional 服務。module 收 `region`，用 aws 6.x 的 resource 層級 `region` 屬性（v9 K4 的做法）。範本只啟用主 region（`ap-northeast-1`），其他 region 的啟用方式寫在 REFERENCE（§11）。CloudTrail 用 multi-region trail，一條涵蓋所有 region。
- **Phase**：J0–J9（§12）。module 先做（J1–J5），全部在 HCP 上之後才做範本（J6–J9）。

## 2. 查證發現

1. **aws 6.70.0 都有對應 resource**：
   - `aws_cloudtrail`、`aws_config_*`、`aws_guardduty_*`、`aws_securityhub_*`、`aws_inspector2_*`、`aws_accessanalyzer_*`、`aws_backup_*`、`aws_budgets_*`。
   - `aws_organizations_delegated_administrator`、`aws_organizations_aws_service_access`。
   - `aws_s3_account_public_access_block`、`aws_ebs_encryption_by_default`、`aws_ebs_default_kms_key`、`aws_ec2_instance_metadata_defaults`、`aws_iam_account_password_policy`。
   - 不需要 awscc。
2. **resource 層級 `region`**：`aws_cloudtrail`、`aws_guardduty_detector`、`aws_securityhub_account`、`aws_backup_vault` 有；`aws_budgets_budget` 沒有，Budgets 是全域服務。
3. **Config recorder 一定要 role**：`aws_config_configuration_recorder.role_arn` 必填。不建 service-linked role（S4 不准 module 建 `aws_iam_*`）；範本的 `iam` stack 用 `iam-role` 建一般 role，掛 AWS managed policy `AWS_ConfigRole`（K4）。
4. **`aws_iam_account_password_policy` 會被 S4 擋**：S4 只准 `iam-role`、`iam-role-policy`、`iam-oidc-provider` 建 `aws_iam_*`。
5. **`sns-alarm-topic` 沒有 topic policy**：只有同帳號的 CloudWatch alarm 能發佈。Budgets、Backup、EventBridge 都要 topic policy 給服務 principal；topic 用 CMK 時，key policy 也要給同一組服務。
6. **Security Hub 的標準**（未確認，J3 查 AWS 文件確認 ARN 與版本）：
   - FSBP：`arn:aws:securityhub:<region>::standards/aws-foundational-security-best-practices/v/1.0.0`。
   - CIS：`arn:aws:securityhub:<region>::standards/cis-aws-foundations-benchmark/v/3.0.0`。
   - 大部分 control 依賴 Config 的 recorder。所以 `detect` 要排在 `audit` 之後。
   - AWS 在 2025 年把原本的 Security Hub 改名為 Security Hub CSPM，另推新版 Security Hub（provider 的 `*_v2` resource）。FSBP 與 CIS 屬於 CSPM 那一套，module 用 `aws_securityhub_account` 與 `aws_securityhub_standards_subscription`（未確認，J3 確認名稱與行為）。
7. **Backup vault lock 的 compliance 模式不可逆**：`changeable_for_days` 給了值就是 compliance 模式，冷卻期過後連 root 都解不開。

## 3. 決策

### 3.1 使用者拍板（2026-10-29）

| # | 決策 |
|---|---|
| D1 | 範圍：CloudTrail、Config、GuardDuty、Security Hub、Backup、Budgets，加 IAM Access Analyzer、帳號層安全預設（S3 public access block、EBS 預設加密、IAM 密碼政策）、Amazon Inspector |
| D2 | 單帳號與 AWS Organizations 多帳號兩種模式都支援 |
| D3 | 放在新範本 `templates/account-baseline`，每個帳號一份，不改應用範本 |
| D4 | Security Hub 開 AWS FSBP 與 CIS AWS Foundations Benchmark |

### 3.2 照慣例的判斷（審閱時可以推翻）

| # | 判斷 | 理由 |
|---|---|---|
| K1 | Config 不另做 rule module，`config-recorder` 只收少量 managed rule（選填） | FSBP 與 CIS 的 control 已經由 Security Hub 透過 Config 評估；再自己寫一套 rule 會重複計費 |
| K2 | 範本示範單帳號；Organizations 模式由 module 測試覆蓋，REFERENCE 寫三種帳號（管理、資安、成員）各 apply 哪些 module | 這個 repo 沒有 Organizations 的佔位結構；範本示範兩種會讓每個 stack 都多一層分支 |
| K3 | `validate.sh` 的 S4 新增：`modules/account-security-defaults` 只准 `aws_iam_account_password_policy` 這一種 `aws_iam_*` | 密碼政策是帳號設定，不是權限；放進 `iam-role` 不合責任邊界 |
| K4 | Config、Backup、CloudTrail→CloudWatch Logs 的 role 在範本的 `iam` stack 用 `iam-role` 建，module 只收 role ARN | 沿用「IAM 集中在 iam stack」的慣例（S4） |
| K5 | CloudTrail：multi-region、log file validation、CMK 加密、只記 management event；data event 預設關 | management event 的第一份免費；S3、Lambda data event 依量計費，需要時用 `advanced_event_selectors` 開 |
| K6 | CloudTrail 同時送 CloudWatch Logs，範本用 `log-metric-alarm` 建兩個告警：root 帳號使用、未授權的 API 呼叫 | 這兩項是最常被稽核問的；其他 CIS 監控項目等 Security Hub 的 finding |
| K7 | GuardDuty 預設開 S3、EKS audit log、EBS malware、RDS login、Lambda network log；runtime monitoring 預設關 | runtime monitoring 要裝 agent、依 vCPU 計費；應用範本沒有對應的 agent 設定 |
| K8 | Inspector 預設掃 EC2、ECR、Lambda；Lambda code 掃描預設關 | example2 有 bastion（EC2）、所有範本都有 ECR 與 Lambda；code 掃描依函式數另計 |
| K9 | Access Analyzer 只開外部存取分析（免費）；unused access 分析預設關 | unused access 依分析的 role 與 user 數計費 |
| K10 | Backup 用 tag 選資源：`backup-plan` 收 `selection_tags`，範本用 `backup = "daily"` | 不改應用範本；專案要被備份就在資源加 tag |
| K11 | Backup vault lock 預設 governance 模式；compliance 模式要明寫 `compliance_acknowledged = true` 才准 | §2 第 7 點；設錯就永遠解不開 |
| K12 | Budgets 範本建一個月成本預算：實際 80%、實際 100%、預測 100% 三個通知，送 SNS 與 email | 最小可用的成本告警 |
| K13 | GuardDuty 與 Security Hub 的高嚴重度 finding 用既有 `eventbridge-rule` 送到告警 SNS | 不用另外接通知管道 |
| K14 | 帳號層安全預設：S3 account public access block 全開、EBS 預設加密（CMK 選填）、IMDSv2 為新 instance 的預設、IAM 密碼政策（最短 14 字元、90 天到期、記住 24 組） | CIS 的對應項目；不影響既有資源 |
| K15 | Phase 代號用 J，接在 v9 的 I 之後 | 慣例 |

## 4. trust boundary 與特權操作

| 邊界 | 誰跨過 | 控制 |
|---|---|---|
| AWS 服務 → log bucket | CloudTrail、Config | bucket policy 只給 `cloudtrail.amazonaws.com`、`config.amazonaws.com`，條件 `aws:SourceArn` 或 `aws:SourceAccount`；organization 模式加 `aws:SourceOrgID` |
| AWS 服務 → CMK | CloudTrail、Config、Backup、SNS | `kms-key` 的 `service_principals`，CloudTrail 加 encryption context 條件 `kms:EncryptionContext:aws:cloudtrail:arn` |
| AWS 服務 → SNS | Budgets、Backup、EventBridge | `sns-alarm-topic` 0.2.0 的 topic policy，條件 `aws:SourceAccount` |
| AWS 服務 → 帳號資源 | Config、Backup | `iam` stack 的 role，只信任對應服務，條件 `aws:SourceAccount` |
| 管理帳號 → 成員帳號 | Organizations 的委派管理員 | `organization-delegated-admin` 只在管理帳號 apply；資安帳號拿到的是各服務的管理權，不是成員帳號的 IAM |
| 人 → backup recovery point | 維運人員 | vault policy deny `backup:DeleteRecoveryPoint` 給所有 principal（除了 vault lock 管理的保留期） |

### 4.1 log bucket 的刪除保護（審閱重點）

- CloudTrail 與 Config 的 bucket 是稽核證據，被刪就沒有證據了。
- 範本做法：
  - `s3-bucket` 開 versioning，`force_destroy = false`。
  - 保留 365 天，dev 也一樣。稽核證據不分環境；短了就失去意義。
  - CloudTrail 開 log file validation，被改過的檔案可以驗出來。
- 不做 S3 Object Lock：要在建 bucket 時就開，而且 `s3-bucket` 還不支援。需要 WORM 時另升 `s3-bucket` 的版本，不在這一版。

### 4.2 Organizations 模式的帳號分工

| 帳號 | apply 的 module | 說明 |
|---|---|---|
| 管理帳號 | `organization-delegated-admin`、`cloudtrail`（`is_organization_trail = true`） | trusted access、把 GuardDuty、Security Hub、Inspector、Config、Access Analyzer 的管理委派給資安帳號 |
| 資安帳號 | `guardduty`、`securityhub`、`inspector`、`access-analyzer` 的 `organization` 輸入、`config-recorder` 的 aggregator | organization 層級的自動啟用與彙整 |
| log 封存帳號 | `s3-bucket`（`cloudtrail` 的 organization 寫入路徑） | organization trail 與 Config 的集中 bucket |
| 成員帳號 | `account-baseline` 範本裡帳號層的部分：`account-security-defaults`、`backup-*`、`budgets` | 偵測類服務由資安帳號自動啟用，成員帳號不再各自建 |

範本不示範這個分工（K2），REFERENCE 用一張表加一段 module 呼叫範例說明。

## 5. module 清單

| module | provider | resource | 用在 `account-baseline` |
|---|---|---|---|
| `cloudtrail` | aws | `aws_cloudtrail` | `audit` |
| `config-recorder` | aws | `aws_config_configuration_recorder`、`_recorder_status`、`_delivery_channel`、`_retention_configuration`、`_config_rule`、`_configuration_aggregator` | `audit` |
| `guardduty` | aws | `aws_guardduty_detector`、`_detector_feature`、`_organization_configuration`、`_organization_configuration_feature` | `detect` |
| `securityhub` | aws | `aws_securityhub_account`、`_standards_subscription`、`_finding_aggregator`、`_organization_configuration` | `detect` |
| `inspector` | aws | `aws_inspector2_enabler`、`_organization_configuration` | `detect` |
| `access-analyzer` | aws | `aws_accessanalyzer_analyzer`、`_archive_rule` | `defaults` |
| `backup-vault` | aws | `aws_backup_vault`、`_vault_policy`、`_vault_lock_configuration`、`_vault_notifications` | `backup` |
| `backup-plan` | aws | `aws_backup_plan`、`aws_backup_selection` | `backup` |
| `budgets` | aws | `aws_budgets_budget` | `budget` |
| `account-security-defaults` | aws | `aws_s3_account_public_access_block`、`aws_ebs_encryption_by_default`、`aws_ebs_default_kms_key`、`aws_ec2_instance_metadata_defaults`、`aws_iam_account_password_policy` | `defaults` |
| `organization-delegated-admin` | aws | `aws_organizations_aws_service_access`、`aws_organizations_delegated_administrator`、`aws_guardduty_organization_admin_account`、`aws_securityhub_organization_admin_account`、`aws_inspector2_delegated_admin_account` | 不用（管理帳號專用） |

共用的規則跟 v9 一樣：

- 不建 IAM 與 security group（S4，K3 的例外除外），不用 `random_password`（S7）。
- `description` 用台灣繁體中文，註解與 `error_message` 用英文。
- README 表格由 terraform-docs 產生（S11），每個 module 有 `examples/basic` 與 `tests/`。
- regional 的 module 都收 `region`（`null` 用 provider 的 region），跟 v9 一樣不用 provider alias。

### 5.1 `cloudtrail`

- 責任：一條 trail。
- 輸入：
  - `name`、`s3_bucket_name`、`s3_key_prefix`、`kms_key_arn`（必填，只收 key ARN）。
  - `is_multi_region_trail`（預設 `true`）、`is_organization_trail`（預設 `false`）。
  - `cloudwatch_logs = { log_group_arn, role_arn }`（選填）。
  - `advanced_event_selectors`（選填；`null` 時只記 management event）。
  - `insight_types`（預設 `[]`；可選 `ApiCallRateInsight`、`ApiErrorRateInsight`，另外計費）。
  - `region`、`tags`。
- 固定：`enable_log_file_validation = true`、`include_global_service_events = true`、`enable_logging = true`。
- validation：
  - KMS 與 role 的 ARN 格式。
  - `cloudwatch_logs.log_group_arn` 要以 `:*` 結尾，CloudTrail 要求這個格式（未確認，J2 用 provider 文件確認）。
  - `is_organization_trail` 時 `is_multi_region_trail` 必須是 `true`。
- 輸出：`arn`、`name`、`home_region`。
- 刻意不做：CloudTrail Lake（event data store）、SNS 通知、建 bucket（用 `s3-bucket` 0.6.0）。

### 5.2 `config-recorder`

- 責任：一個 region 的 Config recorder、delivery channel、啟用狀態、保留期，加上選填的 managed rule 與 aggregator。
- 輸入：
  - `name`、`role_arn`（必填）、`s3_bucket_name`、`s3_key_prefix`、`s3_kms_key_arn`、`sns_topic_arn`。
  - `recording`：`{ all_supported = true, include_global_resource_types, exclusion_types = [] }`。`include_global_resource_types` 預設 `true`，只能在一個 region 為 `true`，README 寫清楚。
  - `recording_frequency`：`CONTINUOUS`（預設）或 `DAILY`。
  - `snapshot_frequency`：預設 `TwentyFour_Hours`。
  - `retention_days`：30–2557，預設 2557。
  - `managed_rules`：identifier → `{ input_parameters, scope_resource_types }`。
  - `aggregator`：`{ name, account_ids, regions }`，或 `{ name, organization_role_arn }`，擇一。
  - `region`、`tags`。
- validation：role ARN；`retention_days` 範圍；aggregator 兩種擇一；`managed_rules` 的 identifier 是大寫底線格式。
- 輸出：`recorder_name`、`delivery_channel_name`、`aggregator_arn`。
- 實作要點：`recorder_status` 要 `depends_on` delivery channel，否則啟用會失敗。
- 刻意不做：conformance pack（K1）、custom rule（Lambda、Guard）、remediation。

### 5.3 `guardduty`

- 責任：一個 region 的 detector 與防護功能，加上選填的 organization 自動啟用設定（在委派管理帳號）。
- 輸入：
  - `features`：feature 名稱 → `{ status, additional_configuration }`。預設照 K7。
  - `finding_publishing_frequency`：預設 `FIFTEEN_MINUTES`。
  - `organization = { auto_enable = "ALL" | "NEW" | "NONE", features = {...} }`（選填）。
  - `region`、`tags`。
- validation：feature 名稱在允許清單（`S3_DATA_EVENTS`、`EKS_AUDIT_LOGS`、`EBS_MALWARE_PROTECTION`、`RDS_LOGIN_EVENTS`、`LAMBDA_NETWORK_LOGS`、`RUNTIME_MONITORING`）；`status` 是 `ENABLED` 或 `DISABLED`。
- 輸出：`detector_id`、`detector_arn`。
- 刻意不做：IP set、threat intel set、filter、publishing destination、malware protection plan（S3 物件掃描）。

### 5.4 `securityhub`

- 責任：一個 region 的 Security Hub（CSPM）、訂閱標準，加上選填的跨 region 彙整與 organization 設定。
- 輸入：
  - `standards`：`["fsbp", "cis"]` 這類短名，module 換成 ARN（§2 第 6 點）。
  - `control_finding_generator`：預設 `SECURITY_CONTROL`。
  - `auto_enable_controls`：預設 `true`。
  - `finding_aggregator = { linking_mode, regions }`（選填）。
  - `organization = { auto_enable, auto_enable_standards }`（選填）。
  - `region`。
- 固定：`enable_default_standards = false`，標準只由 `standards` 決定。
- validation：短名在允許清單；`linking_mode` 合法。
- 輸出：`account_id`、`standards_subscription_arns`。
- 刻意不做：automation rule、custom action、insight、停用個別 control（之後用 `standards_control_association` 另加）、新版 Security Hub（`*_v2`）。

### 5.5 `inspector`

- 責任：在一個或多個帳號啟用 Inspector 的掃描類型。
- 輸入：`account_ids`（預設 `[]`，用目前帳號）、`resource_types`（預設 `["EC2", "ECR", "LAMBDA"]`）、`organization = { auto_enable = { ec2, ecr, lambda, lambda_code } }`、`region`。
- validation：`resource_types` 只能是 `EC2`、`ECR`、`LAMBDA`、`LAMBDA_CODE`。
- 輸出：`enabled_resource_types`。
- 刻意不做：filter（suppression rule）、CIS scan、SBOM 匯出。

### 5.6 `access-analyzer`

- 責任：一個 analyzer 與 archive rule。
- 輸入：`name`、`type`（`ACCOUNT` 預設、`ORGANIZATION`；unused access 版本要另外寫 `ACCOUNT_UNUSED_ACCESS` 或 `ORGANIZATION_UNUSED_ACCESS`，K9）、`unused_access_age_days`、`archive_rules`（name → filter 清單）、`region`、`tags`。
- validation：`type` 合法；unused 類型才收 `unused_access_age_days`。
- 輸出：`arn`。

### 5.7 `backup-vault`

- 責任：一個 vault、它的 policy、選填的 vault lock 與通知。
- 輸入：
  - `name`、`kms_key_arn`（必填）、`force_destroy`（預設 `false`）。
  - `deny_delete_recovery_points`（預設 `true`）：vault policy deny `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy`。
  - `lock = { min_retention_days, max_retention_days, changeable_for_days, compliance_acknowledged = false }`（K11）。
  - `notifications = { sns_topic_arn, events }`。
  - `region`、`tags`。
- validation：
  - `changeable_for_days` 有值時 `compliance_acknowledged` 必須是 `true`，而且值 ≥ 3。
  - min ≤ max；events 在允許清單。
- 輸出：`arn`、`name`。

### 5.8 `backup-plan`

- 責任：一個 backup plan 與一個用 tag 選資源的 selection。
- 輸入：
  - `name`、`vault_name`、`role_arn`。
  - `rules`：name → `{ schedule, start_window_minutes, completion_window_minutes, delete_after_days, cold_storage_after_days, enable_continuous_backup, copy_to = { vault_arn, delete_after_days } }`。
  - `selection_tags`：key → value，至少一個（K10）。
  - `region`、`tags`。
- validation：
  - `schedule` 是 `cron(...)`。
  - `delete_after_days` ≥ `cold_storage_after_days` + 90（AWS 的規定）。
  - continuous backup 時 `delete_after_days` ≤ 35。
  - role ARN 格式。
- 輸出：`plan_id`、`plan_arn`、`selection_id`。
- 刻意不做：用 ARN 選資源、restore testing、report plan、framework。

### 5.9 `budgets`

- 責任：多個 cost budget 與它們的通知。
- 輸入：
  - `budgets`：name → `{ limit_amount, time_unit = "MONTHLY", cost_filters, notifications = [{ comparison = "GREATER_THAN", threshold, threshold_type = "PERCENTAGE", type = "ACTUAL" | "FORECASTED", sns_topic_arns, emails }] }`。
  - `tags`。
- validation：`limit_amount` 為正數；每個 notification 至少一個 SNS 或 email；`threshold` 0–1000。
- 固定：`budget_type = "COST"`、`limit_unit = "USD"`。
- 輸出：`budget_arns`。
- 刻意不做：budget action（自動套 SCP 或 IAM policy）、usage budget、RI／Savings Plans 的覆蓋率預算。

### 5.10 `account-security-defaults`

- 責任：帳號在一個 region 的安全預設（K14）。
- 輸入：
  - `s3_public_access_block`（預設 `true`，四個開關全開）。
  - `ebs_encryption_by_default`（預設 `true`）、`ebs_default_kms_key_arn`（選填）。
  - `imdsv2_default`（預設 `true`：`http_tokens = "required"`、`http_put_response_hop_limit = 2`）。
  - `password_policy`：`{ minimum_length = 14, require_symbols, require_numbers, require_uppercase, require_lowercase, max_age_days = 90, reuse_prevention = 24, allow_users_to_change = true }`，`null` 時不管理（S4 例外，K3）。
  - `region`。
- validation：`minimum_length` 14–128；`reuse_prevention` 1–24；`max_age_days` 1–1095。
- 輸出：無（只有設定）。
- 注意：S3 public access block 與密碼政策是帳號全域設定，一個帳號只能有一份。README 寫清楚，範本只在主 region 管這兩項。

### 5.11 `organization-delegated-admin`

- 責任：在管理帳號開 trusted access，並把服務的管理委派給資安帳號。
- 輸入：`delegated_admin_account_id`、`services`（`guardduty`、`securityhub`、`inspector`、`config`、`access-analyzer`、`cloudtrail`、`backup` 的子集）。
- 實作：
  - 每個服務一筆 `aws_organizations_aws_service_access`（service principal）。
  - 一般服務用 `aws_organizations_delegated_administrator`。
  - GuardDuty、Security Hub、Inspector 要用各自的 `*_organization_admin_account`／`delegated_admin_account` resource（未確認是否還要同時寫 `aws_organizations_delegated_administrator`，J5 查文件確認）。
- validation：帳號 ID 12 碼；`services` 在允許清單。
- 刻意不做：建 organization、OU、SCP、帳號。

### 5.12 既有 module 的 minor 版

| module | 版本 | 新輸入 | 預設值 | 說明 |
|---|---|---|---|---|
| `s3-bucket` | 0.5.0 → 0.6.0 | `log_delivery` 多 `cloudtrail`、`config` 兩種，加上 `organization_id` | 現有種類不變 | bucket policy 加 `GetBucketAcl` 與 `PutObject`，條件 `aws:SourceArn`、`aws:SourceAccount`、`s3:x-amz-acl = bucket-owner-full-control`；有 `organization_id` 時加 organization trail 的寫入路徑 `AWSLogs/<org id>/*` |
| `sns-alarm-topic` | 0.1.1 → 0.2.0 | `service_publishers`（服務 principal 的清單） | `[]` | 非空時加 topic policy：`sns:Publish` 給這些 principal，條件 `aws:SourceAccount` 等於目前帳號 |

## 6. 既有 module

- 照用：`kms-key`（`service_principals` 已支援條件）、`iam-role`、`iam-role-policy`、`log-group`、`log-metric-alarm`、`eventbridge-rule`、`ssm-publish`、`ssm-read`。
- 不改：所有應用範本。

## 7. 範本對帳號的假設

- 一個 env 一個帳號：`dev` 在 `111111111111`，`sit` 在 `222222222222`，跟其他範本的佔位一致。
- `account-baseline` 要比該帳號的任何應用範本先 apply。應用範本不讀它的 SSM，所以兩邊沒有 apply 順序的硬性相依。唯一的例外是 Backup：應用範本的資源要加 `backup = "daily"` tag 才會被備份，這是約定，REFERENCE 寫清楚。
- 主 region `ap-northeast-1`。CloudTrail 是 multi-region trail；其他 regional 服務只在主 region（§11）。

## 8. templates/account-baseline

### 8.1 stack 清單與 ORDER

```
foundation defaults iam audit detect backup budget
```

| # | stack | 建什麼 | 主要 module |
|---|---|---|---|
| 1 | `foundation` | 治理用 CMK（CloudTrail、Config、Backup、SNS、CloudWatch Logs 的 service principal）、CloudTrail 與 Config 的 log bucket（各一個，365 天、versioning）、資安告警 SNS topic（`service_publishers`：`budgets.amazonaws.com`、`backup.amazonaws.com`、`events.amazonaws.com`） | `kms-key`、`s3-bucket` 0.6.0、`sns-alarm-topic` 0.2.0 |
| 2 | `defaults` | 帳號層安全預設、Access Analyzer（ACCOUNT） | `account-security-defaults`、`access-analyzer` |
| 3 | `iam` | Config recorder role（`AWS_ConfigRole`）、Backup role（`AWSBackupServiceRolePolicyForBackup` 與 `...ForRestores`）、CloudTrail 寫 CloudWatch Logs 的 role | `iam-role`、`iam-role-policy` |
| 4 | `audit` | CloudTrail（multi-region、CMK、送 CloudWatch Logs）、trail 的 log group、兩個 metric filter 告警（K6）、Config recorder | `cloudtrail`、`log-group`、`log-metric-alarm`、`config-recorder` |
| 5 | `detect` | GuardDuty、Security Hub（FSBP、CIS）、Inspector、高嚴重度 finding 送 SNS 的 EventBridge rule | `guardduty`、`securityhub`、`inspector`、`eventbridge-rule` |
| 6 | `backup` | vault（CMK、deny delete、governance lock）、每日備份 plan（tag `backup = "daily"`） | `backup-vault`、`backup-plan` |
| 7 | `budget` | 月成本預算（K12） | `budgets` |

- 照 `templates/project-infra` 的標準：只有樹 A，沒有 bridge。所有 stack 只呼叫 module，S8 沒有例外。
- `iam` 排在 `defaults` 之後、`audit` 之前：role 要先有，recorder 與 trail 才建得起來；role 的權限範圍用命名規則組 ARN（log group、bucket），不讀 `audit`。

### 8.2 SSM 合約（樹 A）

| key | 寫 | 讀 |
|---|---|---|
| `foundation/kms_key_arn`、`trail_bucket_name`、`config_bucket_name`、`alert_topic_arn` | `foundation` | `defaults`、`iam`、`audit`、`detect`、`backup`、`budget` |
| `iam/config_role_arn`、`backup_role_arn`、`trail_logs_role_arn` | `iam` | `audit`、`backup` |
| `audit/trail_arn`、`config_recorder_name` | `audit` | `detect`（確認 Config 已啟用） |
| `detect/guardduty_detector_id` | `detect` | — |
| `backup/vault_name` | `backup` | — |

key 的實際寫法照 example6 的命名。

### 8.3 dev／sit 的預設規格

| 項目 | dev | sit |
|---|---|---|
| CloudTrail | management event、CloudWatch Logs 保存 90 天 | 同左，保存 365 天 |
| log bucket | 365 天、versioning | 同左 |
| Config | `CONTINUOUS`，保留 2557 天 | 同左 |
| GuardDuty | K7 | 同左 |
| Security Hub | FSBP、CIS | 同左 |
| Inspector | EC2、ECR、LAMBDA | 同左 |
| Backup | 每日 03:00（UTC+8），保留 7 天；vault lock governance、最短 1 天 | 保留 35 天，最短 7 天 |
| Budgets | 月 100 美元（佔位） | 月 300 美元（佔位） |
| 密碼政策 | K14 | 同左 |

### 8.4 文件

`infra/README.md`（短）、`infra/REFERENCE.md`（含 §4.2 的 Organizations 分工、其他 region 的啟用方式、Backup tag 約定、destroy 前的注意事項）、`infra/architecture.drawio.svg`。根 README 的範本表加一列。

## 9. 測試情境（TDD）

每個 module 用 `mock_provider "aws"`，至少要有：

| module | 正向 | 要被擋的 |
|---|---|---|
| `cloudtrail` | 單帳號 multi-region 加 CloudWatch Logs；organization trail | KMS 不是 key ARN；organization trail 但不是 multi-region；log group ARN 格式錯 |
| `config-recorder` | 全資源加 global；`DAILY`；帳號 aggregator；organization aggregator | 兩種 aggregator 同時給；保留期 29 天；role ARN 錯 |
| `guardduty` | 預設 feature；organization `ALL` | 未知 feature；`status` 值錯 |
| `securityhub` | FSBP 加 CIS，確認 ARN 依 region 組出；finding aggregator | 未知標準短名；`enable_default_standards` 不能被打開 |
| `inspector` | 預設三種；organization 自動啟用 | 未知 resource type |
| `access-analyzer` | ACCOUNT；ORGANIZATION；archive rule | unused 天數給在非 unused 類型 |
| `backup-vault` | 預設 deny delete；governance lock；通知 | compliance 沒有 acknowledged；`changeable_for_days` 2；min > max |
| `backup-plan` | 每日加冷儲存；continuous；跨 vault 複製 | 沒有 selection tag；冷儲存不足 90 天；continuous 超過 35 天 |
| `budgets` | 三個通知送 SNS 與 email | 通知沒有對象；金額 0 |
| `account-security-defaults` | 全預設；不管理密碼政策 | 密碼長度 8；reuse 25 |
| `organization-delegated-admin` | 五個服務 | 帳號 ID 11 碼；未知服務 |
| `s3-bucket` 0.6.0 | `cloudtrail`、`config`、organization 路徑；不給時 policy 跟 0.5.0 一樣 | 組織 ID 格式錯 |
| `sns-alarm-topic` 0.2.0 | 三個服務；不給時沒有 topic policy | principal 不是 `.amazonaws.com` |

範本 stack 的測試照 example6：每個 stack 的 `tests/` 驗 SSM 讀寫、名稱、跨 stack 一致的值，另外鎖住 §4 的控制（bucket policy 條件、vault deny、topic policy 條件）。

## 10. 成本估計（美元，2026-10-29 查官方價目頁，價目頁的例子用 us-east-1）

| 項目 | 價格 | dev 帳號閒置時的量級 |
|---|---|---|
| CloudTrail | management event 第一份送到 S3 免費；額外一份每 10 萬筆 2.00；data event 每 10 萬筆 0.10 | 低於 1（只有 S3 與 KMS） |
| Config | 每個 continuous configuration item 0.003；rule 評估前 10 萬次每次 0.001 | 數元到十幾元，依資源數與變更頻率 |
| GuardDuty | management event 每百萬筆 4.00；VPC flow 與 DNS log 前 500 GB 每 GB 1.00；沒用過的帳號有 30 天試用 | 數元起 |
| Security Hub | CSPM 已併入 Security Hub 的 Essentials 方案，按資源計價（價目頁的例子是每個 resource unit 3.75），不再按檢查次數；30 天試用 | 依資源數，要用 AWS Pricing Calculator 估（未確認） |
| Inspector | EC2 每台每月 1.258（agent）或 1.75（agentless）；ECR 映像首次掃描 0.09、重掃 0.01；Lambda 每個每月 0.30；15 天試用 | 依資源數 |
| Access Analyzer | 外部存取分析免費 | 0 |
| Backup | EBS 備份每 GB-月約 0.05 | 依資料量 |
| Budgets | 一般預算免費；有 action 的預算前 2 個免費，之後每個每天 0.10 | 0 |
| CMK | 每把每月 1 | 1 |

- Security Hub 的計價方式在 2025 年改過，FSBP 加 CIS 的實際費用要依帳號的資源數用 Pricing Calculator 估，這是成本裡最不確定的一項。
- 其他項目閒置時每個帳號每月約十幾到幾十美元，主要是 Config、GuardDuty 與 Inspector，依資源數變動。

## 11. 風險與 mock 驗不到的事

- **只啟用主 region**：GuardDuty、Security Hub、Config、Inspector、Access Analyzer 都是 regional，其他 region 沒有偵測。FSBP 與 CIS 會對未啟用的 region 出 finding。REFERENCE 寫用 `region` 輸入多呼叫一次 module 的做法；全 region 啟用通常在 Organizations 模式由資安帳號做。
- **Config 的 global resource 只能在一個 region 記錄**：多 region 時要確認只有主 region 的 `include_global_resource_types = true`。
- **既有帳號已經有 trail、recorder 或 detector**：一個 region 只能有一個 recorder 與 detector，apply 會失敗；要先 `terraform import` 或在 console 移除。REFERENCE 寫 import 指令。
- **Security Hub 的標準 ARN 與 CSPM 改名**：§2 第 6 點未確認。
- **vault lock**：governance 模式有權限的人仍可移除；要真正不可刪，要改 compliance（K11）。
- **budgets 的 SNS**：Budgets 是全域服務，topic 在 `ap-northeast-1`，能不能送達要第一次 apply 時確認（未確認）。
- **destroy**：log bucket 有 versioning 與 365 天保留，刪不掉是預期的；GuardDuty 與 Security Hub 停用會刪掉既有 finding；vault 裡有 recovery point 時刪不掉；compliance lock 的 vault 永遠刪不掉。REFERENCE〈destroy 之前〉要列。
- **Organizations 模式沒有範本示範**（K2）：只有 module 測試與 REFERENCE 的說明。

## 12. Phase

| Phase | 內容 | 依賴 |
|---|---|---|
| J0 | 這份設計與實作流程 | — |
| J1 | `validate.sh` S4 例外；`s3-bucket` 0.6.0、`sns-alarm-topic` 0.2.0；`account-security-defaults`、`access-analyzer` | J0 |
| J2 | `cloudtrail`、`config-recorder` | J0 |
| J3 | `guardduty`、`securityhub`、`inspector` | J0 |
| J4 | `backup-vault`、`backup-plan`、`budgets` | J0 |
| J5 | `organization-delegated-admin` | J0 |
| J6 | 範本骨架與 `foundation`、`defaults`、`iam` | J1 發版 |
| J7 | `audit`、`detect` | J2、J3、J6 |
| J8 | `backup`、`budget` | J4、J6 |
| J9 | README、REFERENCE、架構圖；根 README（91 個 module）、標準指南；全量驗證；§10 價格查證；§14 | J5、J7、J8 |

- J1 的 S4 commit 要在 `account-security-defaults` 之前合併。
- J2–J5 的目錄互不重疊，可以平行。
- J7、J8 可以平行。

## 13. 來源

- aws provider 6.70.0 schema：本機 `terraform providers schema -json`，§2 第 1–4 點、§5 的 resource。
- 既有 module：`modules/sns-alarm-topic`（沒有 topic policy）、`modules/kms-key`（`service_principals` 支援條件）、`scripts/validate.sh` 的 S4。
- 實作時查證（2026-10-29）：
  - Security Hub 標準：<https://docs.aws.amazon.com/securityhub/latest/userguide/cis-aws-foundations-benchmark.html>、<https://docs.aws.amazon.com/securityhub/latest/userguide/fsbp-standard.html>、<https://docs.aws.amazon.com/securityhub/latest/userguide/standards-reference.html>
  - GuardDuty feature：<https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorFeatureConfiguration.html>
  - 委派管理員：<https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html>、<https://docs.aws.amazon.com/securityhub/latest/userguide/designate-orgs-admin-account.html>、<https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-add-delegated-administrator.html>
  - CloudTrail 與 Config 的 bucket policy：<https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-s3-bucket-policy-for-cloudtrail.html>、<https://docs.aws.amazon.com/config/latest/developerguide/s3-bucket-policy.html>
  - Config 的 recording group：<https://docs.aws.amazon.com/config/latest/APIReference/API_RecordingGroup.html>
  - Backup：<https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html>、<https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html>
  - Budgets 的 SNS policy：<https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html>
  - 價格：<https://aws.amazon.com/config/pricing/>、<https://aws.amazon.com/security-hub/pricing/>、<https://aws.amazon.com/guardduty/pricing/>、<https://aws.amazon.com/inspector/pricing/>、<https://aws.amazon.com/cloudtrail/pricing/>、<https://aws.amazon.com/backup/pricing/>、<https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/>

## 14. 實作後的變更

### 查證結果

- §2 第 6 點：FSBP 與 CIS 仍屬 Security Hub CSPM，`aws_securityhub_account` 加 `aws_securityhub_standards_subscription` 是正確的組合，跟 `*_v2` 可以並存。CIS 的最新版是 v5.0.0，AWS 建議用這一版（設計寫 3.0.0）。
- §5.1：CloudTrail 的 log group ARN 要加 `:*`。
- §5.11：GuardDuty、Security Hub、Inspector 要用各自的委派 API；再寫 `aws_organizations_delegated_administrator` 會重複註冊而衝突。CloudTrail 用自己的 API（會順便建 service-linked role）。
- §10：Security Hub CSPM 改成按資源計價，見 §10。

### module

- `organization-delegated-admin`：
  - 輸入改成 `regions`（set），因為 trusted access 與部分委派是 organization 全域的，同一個 organization 呼叫兩次會重複註冊。
  - Config 開 `config.amazonaws.com` 與 `config-multiaccountsetup.amazonaws.com` 兩個 principal；GuardDuty 多開 `malware-protection.guardduty.amazonaws.com`。
  - Backup 不在允許清單：委派還需要 `aws_organizations_resource_policy` 與 backup policy 類型。
- `config-recorder`：`all_supported` 由 `exclusion_types` 推導；有 exclusion 時不能再開 global resource types。`aggregator.regions` 兩種形式都適用，空 list 代表所有 region。
- `securityhub`：`organization` 輸入不給預設，因為 AWS 的 `DEFAULT` 會幫新成員開 CIS 1.2.0。
- `guardduty`：不收 `EKS_RUNTIME_MONITORING`（已併入 `RUNTIME_MONITORING`），也不收新的 `AI_PROTECTION`、`AI_ANALYST`。
- `inspector`：`LAMBDA_CODE` 必須搭配 `LAMBDA`。
- `backup-plan`：多個 selection tag 是「符合任一個」。`backup-vault` 的 policy 也 deny `PutBackupVaultAccessPolicy`，之後要改 policy 只能刪掉 vault 重建。
- `budgets`：0–1000 的門檻範圍只套用在 `PERCENTAGE`。
- `s3-bucket` 0.6.0：
  - CloudTrail 的 `aws:SourceArn` 放寬成本帳號的 `trail/*`，因為建 bucket 時還不知道 trail 名稱。
  - organization 路徑用 `aws:SourceOrgID`；管理帳號自己的 `AWSLogs/<帳號>/` 路徑不開。
  - `cloudtrail`、`config` 這兩種 `log_delivery` 可以搭配 versioning。
  - 一個既有測試原本拿 `cloudtrail` 當未知值，改成 `waf_logs`。
- `sns-alarm-topic` 0.2.0：topic policy 保留 SNS 預設的同帳號發佈。
- `iam-role` 0.5.0（設計沒有排）：白名單加 `service-role/AWS_ConfigRole`、`service-role/AWSBackupServiceRolePolicyForBackup`、`service-role/AWSBackupServiceRolePolicyForRestores`，給 `account-baseline` 的 `iam` stack 用。
- release-please 為已發布的 `cloudtrail`、`config-recorder`、`guardduty` 重複開了沒有差異的 release PR，已關閉。

### 範本

- `defaults` 不讀 `foundation`，多發布 `defaults/access_analyzer_arn`。EBS 預設加密用 AWS 管理的 `aws/ebs`：治理 CMK 沒有開給 EC2，用它會讓 instance 開不起來。
- 治理 CMK：CloudTrail 的授權用 `StringLikeIfExists` 加 `aws:SourceArn`（本帳號的 `trail/*`），因為 DescribeKey 不帶 encryption context；另外開給 `cloudwatch.amazonaws.com`，讓告警能寫進加密的 topic。
- `audit`：trail log group 的保存天數由 `trail_log_retention_days` 決定；未授權 API 呼叫的告警用 CIS 較新的 pattern，排除 `delivery.logs` 與 `HeadBucket`。
- `detect`：Security Hub 的 rule 加 `RecordState = ACTIVE`，並排除 GuardDuty 來源的 finding，避免同一個 finding 寄兩封信；讀 `audit/config_recorder_name` 只為了保證 apply 順序。
- `backup`：通知事件多加 `BACKUP_JOB_EXPIRED`（備份沒在時間窗內開始）；保留天數在 tfvars，驗證介於 lock 的最短天數與 365 之間。
- `budget`：Budgets 的 topic policy 只有 `aws:SourceAccount`；AWS 文件建議再加 `aws:SourceArn`，但不是必要條件，第一次 apply 時確認。
- `project` 的佔位值是 `baseline`。
