# log-delivery

建 CloudWatch Logs 的 vended log 三件組：delivery source（哪個資源、哪種 log）、delivery destination（送到哪）、delivery（把兩者接起來）。AgentCore 的 Runtime、Memory、Gateway 都靠它把 application log 送進 log group、把 trace 送進 X-Ray。這三個資源是 CloudWatch 的通用機制，其他會產生 vended log 的服務也能用。

log group 本身不在這裡建，用 `log-group` module 建好再把 ARN 傳進來。

## 用法

```hcl
module "runtime_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/log-delivery?ref=log-delivery-v0.1.0"

  name_prefix = "alpha-dev"

  sources = {
    chat-logs   = { resource_arn = module.chat_runtime.arn, log_type = "APPLICATION_LOGS" }
    chat-traces = { resource_arn = module.chat_runtime.arn, log_type = "TRACES" }
  }

  destinations = {
    chat        = { type = "CWL", resource_arn = module.chat_log_group.arn }
    xray-traces = { type = "XRAY" }
  }

  deliveries = {
    chat-logs   = { source = "chat-logs", destination = "chat" }
    chat-traces = { source = "chat-traces", destination = "xray-traces" }
  }
}
```

完整範例見 [`examples/runtime-logs-and-traces/`](./examples/runtime-logs-and-traces/main.tf)。

## 容易出錯的地方

- **資源重建時 apply 卡在半途**：Runtime 或 Memory 重建後 ARN 換了，delivery source 會被替換；如果 delivery 沒有跟著換，刪 source 時會撞 `ConflictException`。這個 module 讓 delivery 在它的 source `resource_arn` 改變時一起替換。只改 tag 不會連帶替換 delivery。
- **XRAY 目的地不能帶設定**：`XRAY` 只設 `delivery_destination_type = "XRAY"`，不送 `delivery_destination_configuration`；`CWL`、`S3` 反過來只送 `destination_resource_arn`。validation 會擋 `XRAY` 給 `resource_arn`、`CWL` 沒給或給了 bucket ARN、`S3` 沒給或給了 log group ARN。

## 注意

- 名稱是 `<name_prefix>-<key>`，最多 60 字（照 API 文件，**未實測**）。
- `USAGE_LOGS` 照 AWS 文件放行，**未實測**；`APPLICATION_LOGS`、`TRACES` 有部署過的參考。
- `CWL` 目的地需要的 log group resource policy 由 CloudWatch 在建立 delivery 時自動加，前提是部署者有 `logs:PutResourcePolicy`，**未實測**。
- trace 送進 X-Ray 需要帳號層開啟 Transaction Search（`aws/spans` log group）。被清掉時 span 全部遺失而且不報錯，部署後要確認 `aws/spans` 存在。
- delivery 的 `tags` 只有輸入的 `tags`；source 與 destination 另外加 `Name`。

## 刻意不做

- log group 本身（`log-group` module）。
- 跨帳號的 destination policy。
- `record_fields`、`field_delimiter`、S3 的 `s3_delivery_configuration`、`output_format`，一律用服務預設。
- 建 IAM。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | source 與 destination 的名稱是 `<name_prefix>-<key>`，最多 60 字 |
| `sources` | `map(object)` | `{}` | 否 | `resource_arn`（產生 log 的資源）、`log_type`（`APPLICATION_LOGS`／`TRACES`／`USAGE_LOGS`） |
| `destinations` | `map(object)` | `{}` | 否 | `type`（`CWL`／`XRAY`／`S3`）、`resource_arn`（`CWL` 是 log group ARN、`S3` 是 bucket ARN、`XRAY` 必須是 null） |
| `deliveries` | `map(object)` | `{}` | 否 | `source`、`destination`，分別是 `sources`、`destinations` 裡存在的 key；同一組不能接兩次 |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；source 與 destination 另外加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `source_names` | `map(string)` | 每個 `sources` key 對應的 delivery source 名稱 |
| `destination_arns` | `map(string)` | 每個 `destinations` key 對應的 delivery destination ARN |
| `delivery_ids` | `map(string)` | 每個 `deliveries` key 對應的 delivery id |

## 測試

```bash
scripts/validate.sh modules/log-delivery
```
