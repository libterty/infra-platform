# log-delivery

建 CloudWatch Logs 的 vended log 三件組：delivery source（哪個資源、哪種 log）、delivery destination（送到哪）、delivery（把兩者接起來）。任何支援 vended log delivery 的 AWS 服務都能用，目的地可以是 CloudWatch Logs、S3、Firehose，trace 可以送 X-Ray。

log group、bucket、Firehose stream 本身不在這裡建：log group 用 `log-group`、bucket 用 `s3-bucket` 建好，再把 ARN 傳進來。

## 哪些服務能用

只有 AWS 文件〈[Supported log destinations and permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AWS-logs-destinations-table.html)〉表裡標 **Supported (V2 permissions)** 的服務走這套 API。`log_type` 由各服務定義，完整清單見 [PutDeliverySource](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_PutDeliverySource.html)。module 只檢查格式（1–255 個英數字或底線），值對不對由 AWS 在 apply 時判斷。常用的幾個（2026-10-21 查的文件）：

| 服務 | `resource_arn` | `log_type` |
|---|---|---|
| ALB | load balancer ARN | `ALB_ACCESS_LOGS`、`ALB_CONNECTION_LOGS`、`ALB_HEALTH_CHECK_LOGS` |
| NLB | load balancer ARN | `NLB_ACCESS_LOGS` |
| S3 | bucket ARN（`arn:aws:s3:::<bucket>`） | `S3_SERVER_ACCESS_LOGS` |
| CloudFront | distribution ARN | `ACCESS_LOGS` |
| EKS Auto Mode | cluster ARN | `AUTO_MODE_COMPUTE_LOGS`、`AUTO_MODE_BLOCK_STORAGE_LOGS`、`AUTO_MODE_IPAM_LOGS`、`AUTO_MODE_LOAD_BALANCING_LOGS` |
| AgentCore Runtime | runtime ARN | `APPLICATION_LOGS`、`USAGE_LOGS`、`TRACES` |
| Bedrock Knowledge Base | knowledge base ARN | `APPLICATION_LOGS`、`TRACES` |

**用不到這個 module 的服務：** ECS／Fargate 的容器 log、RDS 與 Aurora 的 log export、EKS control plane log、Lambda 都不走 delivery API，是在各自的資源上設定（`ecs-service`、`rds`、`eks-cluster`、`lambda-function` 已經處理），log group 用 `log-group` 建。

## 用法

```hcl
module "runtime_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/log-delivery?ref=log-delivery-v0.1.1"

  name_prefix = "alpha-dev"

  sources = {
    chat-logs   = { resource_arn = module.chat_runtime.runtime_arn, log_type = "APPLICATION_LOGS" }
    chat-traces = { resource_arn = module.chat_runtime.runtime_arn, log_type = "TRACES" }
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

完整範例：AgentCore 見 [`examples/runtime-logs-and-traces/`](./examples/runtime-logs-and-traces/main.tf)；ALB 與 S3 的 access log 見 [`examples/alb-and-s3-access-logs/`](./examples/alb-and-s3-access-logs/main.tf)。

## 容易出錯的地方

- 資源重建時 apply 卡在半途：Runtime 或 Memory 重建後 ARN 會變，delivery source 也跟著替換；如果 delivery 沒有一起換，刪 source 時會撞上 `ConflictException`。所以 source 的 `resource_arn` 一改，這個 module 就讓 delivery 一起替換。只改 tag 不會連帶替換 delivery。
- XRAY 目的地不能帶設定：`XRAY` 只設 `delivery_destination_type = "XRAY"`，不送 `delivery_destination_configuration`；`CWL`、`S3`、`FH` 反過來只送 `destination_resource_arn`。validation 會擋下這幾種情況：`XRAY` 給了 `resource_arn`；`CWL` 沒給或不是 log group ARN；`S3` 沒給或不是 bucket ARN；`FH` 沒給或不是 Firehose delivery stream ARN。
- 不是每個服務都能送 X-Ray：只有 AgentCore、Bedrock Knowledge Base 這類會產生 trace 的服務支援，其他服務接 `XRAY` 會在 apply 時被 AWS 拒絕。

## 注意

- **source、`CWL` 與 `FH` 目的地預設只能在目前的帳號。** source 的 `resource_arn` 必須是帶 12 位數帳號的 ARN；source、`CWL` 目的地 log group、`FH` 目的地 stream 的帳號，如果既非目前帳號、也不在 `allowed_account_ids` 裡，precondition 會在 plan 時擋下。S3 bucket 的 ARN 不帶帳號，module 判斷不了 bucket 屬於誰，所以 S3 bucket 當 source 或 `S3` 目的地時都不檢查帳號；`XRAY` 沒有 ARN。

- 名稱是 `<name_prefix>-<key>`，最多 60 字（照 API 文件，**未實測**）。
- 實際部署過的只有 AgentCore 的 `APPLICATION_LOGS`、`TRACES`；其他服務與 `FH` 目的地是照 AWS 文件放行，**未實測**。
- 有些服務對 delivery source 所在的 region 有限制，以該服務的文件為準。
- `CWL` 目的地需要的 log group resource policy 由 CloudWatch 在建立 delivery 時自動加，前提是部署者有 `logs:PutResourcePolicy`，**未實測**。
- trace 送進 X-Ray 需要帳號層開啟 Transaction Search（`aws/spans` log group）。被清掉的話，span 會全部遺失而且不會報錯，所以部署後要確認 `aws/spans` 存在。
- delivery 的 `tags` 只有輸入的 `tags`；source 與 destination 另外加 `Name`。

## 刻意不做

- log group 本身（`log-group` module）。
- 跨帳號的 destination policy。
- `record_fields`、`field_delimiter`、S3 的 `s3_delivery_configuration`、`output_format`，一律用服務預設。
- 建 IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | source 與 destination 的名稱前綴，名稱是 `<name_prefix>-<key>`，最多 60 字元。 |
| `sources` | `map(object)` | `{}` | 否 | delivery source，key 是短名。欄位：`resource_arn`（產生 log 的資源 ARN，任何支援 vended log delivery 的資源都可以，例如 ALB、EKS cluster、CloudFront distribution、AgentCore Runtime；必須帶 12 位數帳號，帳號是目前帳號或在 `allowed_account_ids` 裡，S3 bucket ARN 不帶帳號，是唯一例外）、`log_type`（服務定義的值，例如 `ALB_ACCESS_LOGS`、`S3_SERVER_ACCESS_LOGS`，1–255 個英數字或底線）。 |
| `destinations` | `map(object)` | `{}` | 否 | delivery destination，key 是短名。欄位：`type`（`CWL`、`S3`、`FH` 或 `XRAY`）、`resource_arn`（`CWL` 是 log group ARN、`S3` 是 bucket ARN、`FH` 是 delivery stream ARN，`XRAY` 必須是 `null`）。`CWL`、`FH` 的帳號必須是目前帳號或在 `allowed_account_ids` 裡；S3 bucket ARN 不帶帳號，不檢查。 |
| `allowed_account_ids` | `set(string)` | `[]` | 否 | 除了目前帳號，source 與 `CWL`、`FH` 目的地還可以放在哪些帳號（12 位數字）。空的時候都必須在目前帳號。 |
| `deliveries` | `map(object)` | `{}` | 否 | delivery，key 是短名。欄位：`source`、`destination`，分別是 `sources`、`destinations` 裡存在的 key；同一組 source 與 destination 不能接兩次。 |
| `tags` | `map(string)` | `{}` | 否 | 每個資源的 tag；source 與 destination 另外由 module 加上 `Name`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `source_names` | key 同 `sources` 的 map，值是 delivery source 名稱。 |
| `destination_arns` | key 同 `destinations` 的 map，值是 delivery destination ARN。 |
| `delivery_ids` | key 同 `deliveries` 的 map，值是 delivery id。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/log-delivery
```
