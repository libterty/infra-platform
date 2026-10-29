# guardduty

在一個 region 啟用 GuardDuty：建 detector，用 `aws_guardduty_detector_feature` 逐項管理防護功能。在委派管理帳號可以另給 `organization`，讓成員帳號自動啟用 GuardDuty 與各項功能。

## 用法

```hcl
module "guardduty" {
  source = "git::https://github.com/<org>/<repo>.git//modules/guardduty?ref=guardduty-v0.1.0"

  tags = {
    Project = "alpha"
  }
}
```

Organizations 模式（在資安帳號，也就是 GuardDuty 的委派管理帳號）：

```hcl
module "guardduty" {
  source = "git::https://github.com/<org>/<repo>.git//modules/guardduty?ref=guardduty-v0.1.0"

  organization = {
    auto_enable = "ALL"
    features = {
      S3_DATA_EVENTS         = { auto_enable = "ALL" }
      EKS_AUDIT_LOGS         = { auto_enable = "ALL" }
      EBS_MALWARE_PROTECTION = { auto_enable = "ALL" }
      RDS_LOGIN_EVENTS       = { auto_enable = "ALL" }
      LAMBDA_NETWORK_LOGS    = { auto_enable = "ALL" }
      RUNTIME_MONITORING     = { auto_enable = "NONE" }
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| detector | `enable = true` |
| 功能的管理方式 | 只用 `aws_guardduty_detector_feature`；detector 的 `datasources` 已經 deprecated，不使用 |
| 預設功能 | `S3_DATA_EVENTS`、`EKS_AUDIT_LOGS`、`EBS_MALWARE_PROTECTION`、`RDS_LOGIN_EVENTS`、`LAMBDA_NETWORK_LOGS` 開；`RUNTIME_MONITORING` 關 |
| finding 頻率 | `finding_publishing_frequency` 預設 `FIFTEEN_MINUTES` |

## 注意

- **一個 region 只能有一個 detector**。帳號在這個 region 已經啟用 GuardDuty 時，apply 會失敗；先用 `terraform import` 把既有 detector 匯入，或在 console 停用。
- **其他 region**：GuardDuty 是 regional 服務，要涵蓋其他 region 就用 `region` 多呼叫一次 module。
- **runtime monitoring 預設關**：它要在 EKS、ECS Fargate、EC2 上跑 GuardDuty 的 agent，依 vCPU 計費。要開時給 `RUNTIME_MONITORING = { status = "ENABLED", additional_configuration = { EKS_ADDON_MANAGEMENT = "ENABLED", ... } }`；`additional_configuration` 是讓 GuardDuty 自動裝、更新 agent，不給就要自己裝。
- **不收 `EKS_RUNTIME_MONITORING`**：AWS 已經把它併進 `RUNTIME_MONITORING`，建議遷移，兩個同時給 API 會報錯。
- **只管理列出的 feature**：`features` 沒列的功能維持 AWS 的現況，不會被關掉。
- **Organizations 模式**：`organization` 只在委派管理帳號給；委派本身由 `organization-delegated-admin` 在管理帳號做。`auto_enable = "ALL"` 會連既有成員一起啟用。`organization.features` 不給時，只有 GuardDuty 本身會在成員帳號自動啟用。
- **停用會刪 finding**：destroy 這個 module 會刪掉 detector 與它的所有 finding。
- 高嚴重度 finding 的通知用 `eventbridge-rule` 接，這個 module 不做。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

IP set、threat intel set、filter、publishing destination、malware protection plan（S3 物件掃描）、`EKS_RUNTIME_MONITORING`、成員帳號邀請（`aws_guardduty_member`）、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `features` | `map(object)` | `{ "EBS_MALWARE_PROTECTION": { "status": "ENABLED" }, "EKS_AUDIT_LOGS": { "status": "ENABLED" }, "LAMBDA_NETWORK_LOGS": { "status": "ENABLED" }, "RDS_LOGIN_EVENTS": { "status": "ENABLED" }, "RUNTIME_MONITORING": { "status": "DISABLED" }, "S3_DATA_EVENTS": { "status": "ENABLED" } }` | 否 | detector 的防護功能，key 是 feature 名稱：`S3_DATA_EVENTS`、`EKS_AUDIT_LOGS`、`EBS_MALWARE_PROTECTION`、`RDS_LOGIN_EVENTS`、`LAMBDA_NETWORK_LOGS`、`RUNTIME_MONITORING`。`status` 是 `ENABLED` 或 `DISABLED`；`additional_configuration` 是名稱 → status，只有 `RUNTIME_MONITORING` 能給，名稱限 `EKS_ADDON_MANAGEMENT`、`ECS_FARGATE_AGENT_MANAGEMENT`、`EC2_AGENT_MANAGEMENT`（讓 GuardDuty 自動裝 agent）。預設開 runtime monitoring 以外的五項。只列出的 feature 由 module 管理。 |
| `finding_publishing_frequency` | `string` | `"FIFTEEN_MINUTES"` | 否 | finding 更新送到 EventBridge 與 Security Hub 的頻率：`FIFTEEN_MINUTES`（預設）、`ONE_HOUR`、`SIX_HOURS`。新 finding 約 5 分鐘內送出，這個值只影響既有 finding 的更新。 |
| `organization` | `object` | `null` | 否 | organization 的自動啟用設定，只在 GuardDuty 的委派管理帳號給。`auto_enable` 是成員帳號自動啟用 GuardDuty 的範圍：`ALL`（含既有成員）、`NEW`（只有新加入的）、`NONE`。`features` 是 feature 名稱 → `{ auto_enable, additional_configuration }`，名稱與 `features` 相同，`auto_enable` 與 `additional_configuration` 的值也是 `ALL`、`NEW`、`NONE`。`null`（預設）時不管理 organization 設定。 |
| `region` | `string` | `null` | 否 | detector 所在的 region；`null`（預設）用 provider 的 region。GuardDuty 是 regional 服務，每個 region 各呼叫一次。 |
| `tags` | `map(string)` | `{}` | 否 | detector 的 tag。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `detector_id` | detector ID。 |
| `detector_arn` | detector 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/guardduty
```
