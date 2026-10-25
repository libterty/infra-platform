# iot-account-settings

IoT Core 在帳號加 region 層級只有一份的三項設定：fleet indexing、logging、registry 事件。每一項都是選填物件，`null` 就不建。

**每個帳號、每個 region 只能由一處呼叫**（帳號 baseline 或一個專案的 `fleet` stack）。這三項設定沒有名稱或 ID，兩處都呼叫時，後 apply 的會蓋掉前面的設定。**同帳號的第二個專案不要再管這些設定，把呼叫端的三個輸入都設成 `null`**。

## 用法

```hcl
module "iot_account_settings" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iot-account-settings?ref=iot-account-settings-v0.1.0"

  indexing = {
    thing_indexing_mode              = "REGISTRY_AND_SHADOW"
    thing_connectivity_indexing_mode = "STATUS"
    device_defender_indexing_mode    = "VIOLATIONS"
  }

  logging = {
    role_arn = module.iot_logging_role.role_arn
  }

  event_configurations = {
    THING                  = true
    THING_GROUP_MEMBERSHIP = true
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 建立條件 | `indexing`、`logging`、`event_configurations` 各自是 `null` 就不建 |
| logging | provider 呼叫 `SetV2LoggingOptions`；`default_log_level` 預設 `WARN`，`disable_all_logs` 固定 `false`（要關就把 level 設成 `DISABLED`） |
| indexing | 沒給的 mode 都是 `OFF`；thing group indexing 一律送出（預設 `OFF`） |

## 注意

- **每個帳號、每個 region 只能由一處呼叫**。同帳號的第二個專案要把三個輸入都設成 `null`，否則兩個專案的 apply 會互相蓋掉。AWS 文件沒有明寫兩處同時管理的行為，這是依 API 沒有名稱或 ID 推論的。
- **刪掉 `event_configurations` 不會關掉事件**：provider 文件寫明「Deleting this resource does not disable the event configurations」。要關掉某種事件，先把它設成 `false` 並 apply，再移除。
- 三個 resource 的 delete 在 provider 裡都不呼叫 AWS（原始碼是 `schema.NoopContext`）：把 `indexing` 或 `logging` 改成 `null`、或 destroy，AWS 上的設定維持最後一次 apply 的值。要關掉 logging 就先把 `default_log_level` 設成 `DISABLED`；要關掉 indexing 就先把 mode 設成 `OFF`。
- logging 作用在整個 fleet（同帳號、同 region 所有裝置），`DEBUG`、`INFO` 會產生大量 log，依 CloudWatch Logs 計費。`logging.role_arn` 的 role 由呼叫端建立，trust 是 `iot.amazonaws.com`，要能寫 `AWSIotLogsV2` log group。
- fleet indexing 開了就依索引更新與查詢計費。`thing_connectivity_indexing_mode = "STATUS"` 與 `device_defender_indexing_mode = "VIOLATIONS"` 都需要 thing index（`thing_indexing_mode` 不是 `OFF`）；後者有 validation 擋，前者由 AWS 擋。
- 部署者要有 `iot:SetV2LoggingOptions`、`iot:GetV2LoggingOptions`、`iot:UpdateIndexingConfiguration`、`iot:GetIndexingConfiguration`、`iot:UpdateEventConfigurations`、`iot:DescribeEventConfigurations`，以及對 logging role 的 `iam:PassRole`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- resource-specific logging（`SetV2LoggingLevel`）。
- IoT Core 的 CMK 加密設定（`awscc_iot_encryption_configuration`）：帳號層，會影響同帳號所有裝置，要另外評估。
- named shadow 的 filter、managed field。
- 舊版 logging API（`SetLoggingOptions`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `indexing` | `object` | `null` | 否 | fleet indexing 設定；`null` 就不建。`thing_indexing_mode` 為 `OFF`、`REGISTRY`、`REGISTRY_AND_SHADOW`；`thing_connectivity_indexing_mode` 為 `OFF`、`STATUS`；`named_shadow_indexing_mode`、`thing_group_indexing_mode` 為 `OFF`、`ON`；`device_defender_indexing_mode` 為 `OFF`、`VIOLATIONS`（要搭 `thing_indexing_mode` 不是 `OFF`）；沒給的都是 `OFF`。`custom_fields` 是欄位名稱（例如 `attributes.model`）→ 型別（`Number`、`String`、`Boolean`）。**每個帳號、每個 region 只能由一處呼叫。** |
| `logging` | `object` | `null` | 否 | IoT Core 的帳號層 logging（`SetV2LoggingOptions`，作用在整個 fleet）；`null` 就不建。`role_arn` 是讓 IoT 寫 CloudWatch Logs 的 role，由呼叫端建立；`default_log_level` 為 `DEBUG`、`INFO`、`WARN`、`ERROR`、`DISABLED`（預設 `WARN`）。**每個帳號、每個 region 只能由一處呼叫。** |
| `event_configurations` | `map(bool)` | `null` | 否 | registry 事件的開關，事件種類（`THING`、`THING_GROUP`、`THING_TYPE`、`THING_GROUP_MEMBERSHIP`、`THING_GROUP_HIERARCHY`、`THING_TYPE_ASSOCIATION`、`JOB`、`JOB_EXECUTION`、`POLICY`、`CERTIFICATE`、`CA_CERTIFICATE`）→ 是否發布；`null` 就不建。從設定移除不會關掉事件，要關就設成 `false`。**每個帳號、每個 region 只能由一處呼叫。** |

## 輸出

| 名稱 | 說明 |
|---|---|
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iot-account-settings
```
