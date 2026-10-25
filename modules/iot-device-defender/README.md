# iot-device-defender

設定 AWS IoT Device Defender 的 audit：帳號層的 audit 設定（啟用哪些 check、結果送哪個 SNS topic）、排程稽核、mitigation action。用 awscc provider，因為 aws provider 沒有 Device Defender 的 resource。

## 用法

```hcl
module "defender" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iot-device-defender?ref=iot-device-defender-v0.1.0"

  account_id = data.aws_caller_identity.current.account_id

  audit = {
    role_arn = module.role_iot_audit.arn
    checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    sns      = { target_arn = module.topic.arn, role_arn = module.role_iot_audit_sns.arn }
  }

  scheduled_audits = {
    alpha-dev-weekly = {
      frequency   = "WEEKLY"
      day_of_week = "MON"
      checks      = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    }
  }

  mitigation_actions = {
    alpha-dev-quarantine = {
      role_arn                  = module.role_iot_mitigation.arn
      add_things_to_thing_group = { thing_group_names = ["alpha-dev-quarantine"] }
    }
  }

  tags = local.common_tags
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| audit check | `audit.checks` 沒列到的已知 check 一律設成停用，不沿用帳號原本的狀態 |
| 排程與 audit | 排程稽核用到的 check 都要在 `audit.checks` 裡；排程稽核在 audit 設定之後建立 |
| mitigation action | 每個剛好一種 action；`update_device_certificate` 只做 `DEACTIVATE` |
| tag | awscc 沒有 `default_tags`，module 把 `tags` 轉成 `{ key, value }` 集合並加上 `Name` |

## 注意

- **audit 設定是帳號層**：同一個帳號同一個 region 只有一份，第二個呼叫這個 module 的專案要設 `audit = null`（只建自己的排程與 mitigation action），否則兩邊互相覆蓋。刪除這個 resource 會把帳號的 audit 設定還原成預設，所有 check 都變成停用。
- `account_id` 由呼叫端傳入：awscc 拿不到呼叫者身分，stack 用 `data.aws_caller_identity.current.account_id` 傳進來。
- `audit = null` 時不檢查排程的 check 是否啟用，要由管帳號層設定的那個專案確保 check 已開啟，否則建排程會失敗。
- check 名稱用 API 名稱（例如 `LOGGING_DISABLED_CHECK`），可用的 17 個：`AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK`、`CA_CERTIFICATE_EXPIRING_CHECK`、`CA_CERTIFICATE_KEY_QUALITY_CHECK`、`CONFLICTING_CLIENT_IDS_CHECK`、`DEVICE_CERTIFICATE_AGE_CHECK`、`DEVICE_CERTIFICATE_EXPIRING_CHECK`、`DEVICE_CERTIFICATE_KEY_QUALITY_CHECK`、`DEVICE_CERTIFICATE_SHARED_CHECK`、`INTERMEDIATE_CA_REVOKED_FOR_ACTIVE_DEVICE_CERTIFICATES_CHECK`、`IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK`、`IOT_POLICY_OVERLY_PERMISSIVE_CHECK`、`IOT_ROLE_ALIAS_ALLOWS_ACCESS_TO_UNUSED_SERVICES_CHECK`、`IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK`、`LOGGING_DISABLED_CHECK`、`REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK`、`REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK`、`UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK`。`DEVICE_CERTIFICATE_AGE_CHECK`、`DEVICE_CERTIFICATE_EXPIRING_CHECK` 的門檻天數用 AWS 預設。
- `LOGGING_DISABLED_CHECK` 要帳號開了 IoT logging 才會過（用 `iot-account-settings`）。
- role 由呼叫端建（module 不建 IAM）：audit role 用 `AWSIoTDeviceDefenderAudit` 的權限，SNS role 要能 `sns:Publish` 到 topic，mitigation role 依 action 給權限（例如 `AWSIoTDeviceDefenderAddThingsToThingGroupMitigationAction`）。部署者要對這些 role 有 `iam:PassRole`。
- 計費依稽核的裝置數（Tokyo 每 1,000 台約 1.49 美元／月），排程頻率不影響單價。
- awscc 透過 Cloud Control API 管理資源，drift 偵測與錯誤訊息比 aws provider 少。這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- **security profile（Detect）**：Device Defender Detect（rules Detect 與 ML Detect）從 2026-08-31 起不開放新客戶，audit 不受影響。要偵測裝置的異常行為，改用 IoT logging 加 CloudWatch 告警（`iot-account-settings`、`metric-alarm`）。
- custom metric、dimension（都是 Detect 用的）。
- 其他 mitigation action（`replace_default_policy_version`、`update_ca_certificate`）、check 的自訂門檻、按需稽核（on-demand audit 由 API 觸發）、audit 結果的 suppression、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `account_id` | `string` | `null` | 否 | audit 設定所屬的 AWS 帳號 ID（12 位數字）。給 `audit` 時必填，`audit = null` 時不用給。awscc 拿不到呼叫者身分，所以由呼叫端傳入（通常是 `data.aws_caller_identity.current.account_id`）。 |
| `audit` | `object` | `null` | 否 | 帳號層的 Device Defender audit 設定；`null` 不建（同帳號同 region 只能有一份，第二個專案要設 `null`）。`role_arn` 是讓 IoT 讀取設定的 role（要有 `AWSIoTDeviceDefenderAudit` 的權限）；`checks` 是要啟用的 check（API 名稱，例如 `LOGGING_DISABLED_CHECK`），沒列的一律停用；`sns` 給了就把 audit 結果送到 SNS topic（`role_arn` 要能 `sns:Publish`）。 |
| `scheduled_audits` | `map(object)` | `{}` | 否 | 排程稽核，key 是名稱（1–128 字元，限英數字、`_`、`-`）。`frequency` 是 `DAILY`、`WEEKLY`、`BIWEEKLY`、`MONTHLY`；`WEEKLY`、`BIWEEKLY` 要給 `day_of_week`（`SUN`–`SAT`），`MONTHLY` 要給 `day_of_month`（`1`–`31` 或 `LAST`），其他組合不收；`checks` 是這次稽核跑的 check（至少一個）。有給 `audit` 時，`checks` 都要在 `audit.checks` 裡（AWS 不准停用排程在用的 check）。 |
| `mitigation_actions` | `map(object)` | `{}` | 否 | mitigation action，key 是名稱（1–128 字元，限英數字、`_`、`-`）。`role_arn` 是執行 action 用的 role；以下四種剛好給一種：`add_things_to_thing_group`（把裝置移到隔離用的 thing group，`thing_group_names` 1–10 個）、`update_device_certificate`（停用裝置憑證，`action` 只能是 `DEACTIVATE`）、`publish_finding_to_sns`（`topic_arn`）、`enable_iot_logging`（`role_arn_for_logging` 與 `log_level`：`DEBUG`、`INFO`、`WARN`、`ERROR`）。 |
| `tags` | `map(string)` | `{}` | 否 | 排程稽核與 mitigation action 的 tag；module 轉成 awscc 要的 `{ key, value }` 集合，並加上 `Name`（資源名稱）。帳號層 audit 設定沒有 tag。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `scheduled_audit_arns` | 排程稽核名稱對應 ARN 的 map。 |
| `mitigation_action_arns` | mitigation action 名稱對應 ARN 的 map。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iot-device-defender
```
