# config-recorder

在一個 region 啟用 AWS Config：configuration recorder、delivery channel、啟用狀態與保留期，預設記錄所有支援的 resource type 加上 IAM 的 global 類型。可以另外啟用少量 AWS managed rule，或建 aggregator 彙整多帳號、整個 organization 的資料。

## 用法

```hcl
module "config" {
  source = "git::https://github.com/<org>/<repo>.git//modules/config-recorder?ref=config-recorder-v0.1.0"

  name           = "default"
  role_arn       = module.config_role.role_arn
  s3_bucket_name = module.audit_logs.bucket_name
  s3_key_prefix  = "config"
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 記錄範圍 | 沒有 `recording.exclusion_types` 時是 `ALL_SUPPORTED_RESOURCE_TYPES`（含之後新增的類型）；有的話改 `EXCLUSION_BY_RESOURCE_TYPES` |
| 啟用 | recorder 一律啟動（`is_enabled = true`） |
| 建立順序 | recorder → delivery channel → 啟動；managed rule 在 recorder 之後 |
| managed rule | 只收 AWS managed rule（`owner = "AWS"`），名稱是 identifier 轉小寫加 `-` |
| aggregator | 有 `regions` 就只彙整那些 region，沒有就彙整所有 region |
| tag | managed rule 與 aggregator 加上 `Name`；recorder、delivery channel、保留期不支援 tag |

## 注意

- 一個帳號的一個 region 只能有一個 recorder 與一個 delivery channel。帳號已經在 console 開過 Config 時，apply 會失敗，要先 `terraform import` 既有的 recorder 與 delivery channel，或在 console 刪掉。
- IAM 的 global 類型（user、group、role、customer managed policy）只需要在一個 region 記錄。多個 region 都呼叫這個 module 時，只有主 region 保留 `include_global_resource_types = true`，其他 region 設 `false`，否則會重複計費。2022 年 2 月之後才開放 Config 的 region 不能記錄這些類型。
- 用 `exclusion_types` 時 `include_global_resource_types` 要設 `false`（module 會擋）；排除策略下 IAM 類型照樣記錄，不想記就把它們列進 `exclusion_types`。
- `AWS::RDS::GlobalCluster` 在每個開了 recorder 的 region 都會被記錄，不想重複記錄就列進其他 region 的 `exclusion_types`。
- role 與 bucket 由其他 module 建：
  - role 要信任 `config.amazonaws.com`（條件 `aws:SourceAccount`），掛 AWS managed policy `AWS_ConfigRole`；寫入 bucket 與用 `s3_kms_key_arn` 的權限也要給 role。
  - bucket policy 要允許 `config.amazonaws.com` 的 `s3:GetBucketAcl`、`s3:ListBucket`、`s3:PutObject`，條件 `aws:SourceAccount`；`s3-bucket` 0.6.0 的 `log_delivery` 有 `config`。
- Security Hub 的 FSBP 與 CIS control 大多靠 Config 評估，Security Hub 要排在這個 module 之後。`managed_rules` 只放這兩套標準沒有涵蓋的 rule，重複的 rule 會重複計費。
- organization aggregator 只能在管理帳號或 Config 的委派管理帳號建，role 要掛 `AWSConfigRoleForOrganizations`；帳號 aggregator 要各來源帳號授權（`aws_config_aggregate_authorization`，這個 module 不建）。
- `recording_frequency = "DAILY"` 每天只記一次最後的狀態，期間的變更看不到；稽核用途建議維持 `CONTINUOUS`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

conformance pack、custom rule（Lambda、Guard）、remediation、指定 resource type 的 inclusion 策略、依 resource type 覆寫記錄頻率（`recording_mode_override`）、aggregation authorization、建 role 或 bucket。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | recorder 與 delivery channel 的名稱，1–256 字元，限英數字、`.`、`_`、`-`。一個 region 只能有一個 recorder，慣例用 `default`。 |
| `role_arn` | `string` | 無 | 是 | recorder 用的 IAM role ARN，必填。role 要信任 `config.amazonaws.com`（條件 `aws:SourceAccount`）並掛 AWS managed policy `AWS_ConfigRole`；在範本的 `iam` stack 建，module 不建 IAM。 |
| `s3_bucket_name` | `string` | 無 | 是 | delivery channel 寫入 configuration snapshot 與 history 的 S3 bucket。bucket policy 要允許 `config.amazonaws.com`（`s3-bucket` 0.6.0 的 `log_delivery` 含 `config`）。 |
| `s3_key_prefix` | `string` | `null` | 否 | 寫入 bucket 的 key prefix；`null`（預設）寫在 bucket 根目錄的 `AWSLogs/`。 |
| `s3_kms_key_arn` | `string` | `null` | 否 | 寫入 S3 時用的客戶管理 KMS key ARN（`key/<id>`，不收 alias）；`null`（預設）用 bucket 的預設加密。key policy 要允許 recorder 的 role 用這把 key。 |
| `sns_topic_arn` | `string` | `null` | 否 | Config 送組態變更與合規通知的 SNS topic ARN；`null`（預設）不送。通知量大，通常不送到告警 topic。 |
| `recording` | `object` | `{}` | 否 | 記錄範圍。`exclusion_types` 空的（預設）記錄所有支援的 resource type，`include_global_resource_types`（預設 `true`）決定要不要加上 IAM user、group、role、customer managed policy；多個 region 都有 recorder 時只能在一個 region 為 `true`。給 `exclusion_types`（例如 `AWS::EC2::NetworkInterface`）改用排除策略，這時 `include_global_resource_types` 要設 `false`，IAM 類型除非列進排除清單，否則照樣記錄。 |
| `recording_frequency` | `string` | `"CONTINUOUS"` | 否 | 記錄頻率：`CONTINUOUS`（預設，每次變更都記）或 `DAILY`（每天一次，configuration item 較少、費用較低）。 |
| `snapshot_frequency` | `string` | `"TwentyFour_Hours"` | 否 | configuration snapshot 送到 S3 的頻率：`One_Hour`、`Three_Hours`、`Six_Hours`、`Twelve_Hours`、`TwentyFour_Hours`（預設）。 |
| `retention_days` | `number` | `2557` | 否 | Config 保留 configuration item 的天數，30–2557（預設 2557，約 7 年）。只影響 Config 服務內的歷史，不影響 S3 裡的檔案。 |
| `managed_rules` | `map(object)` | `{}` | 否 | 要啟用的 AWS managed rule，key 是 rule identifier（大寫底線格式，例如 `S3_BUCKET_VERSIONING_ENABLED`），rule 名稱是 identifier 轉小寫加 `-`。`input_parameters` 是 rule 參數；`scope_resource_types` 限定評估的 resource type。FSBP 與 CIS 已由 Security Hub 評估，這裡只放額外需要的 rule。空的（預設）不建 rule。 |
| `aggregator` | `object` | `null` | 否 | 彙整多帳號或整個 organization 的 Config 資料（選填）。`account_ids` 與 `organization_role_arn` 擇一：前者彙整指定帳號（各帳號要授權），後者在管理帳號或委派管理帳號彙整整個 organization，role 要掛 `AWSConfigRoleForOrganizations`。`regions` 空的（預設）彙整所有 region。`null`（預設）不建。 |
| `region` | `string` | `null` | 否 | recorder 所在的 region；`null`（預設）用 provider 的 region。Config 是 regional 服務，每個 region 各呼叫一次 module。 |
| `tags` | `map(string)` | `{}` | 否 | managed rule 與 aggregator 的 tag（recorder 與 delivery channel 不支援 tag）；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `recorder_name` | configuration recorder 的名稱。 |
| `delivery_channel_name` | delivery channel 的名稱。 |
| `aggregator_arn` | aggregator 的 ARN；沒有 `aggregator` 時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/config-recorder
```
