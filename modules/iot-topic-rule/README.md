# iot-topic-rule

建一組 IoT rule：每條 rule 用 SQL 從 MQTT topic 挑訊息，送到 Kinesis、Firehose、S3、SQS 等目的地；所有 rule 共用一個 error action，action 失敗時把錯誤送過去。

## 用法

```hcl
module "iot_rules" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iot-topic-rule?ref=iot-topic-rule-v0.1.0"

  rules = {
    alpha_dev_telemetry = {
      sql = "SELECT *, topic(3) AS deviceId FROM 'alpha/dev/+/telemetry'"
      actions = {
        kinesis = [{
          stream_name   = module.telemetry_stream.name
          role_arn      = module.iot_rule_role.role_arn
          partition_key = "$${topic(3)}"
        }]
      }
    }
  }

  error_action = {
    sqs = {
      queue_url = module.iot_errors.url
      role_arn  = module.iot_rule_role.role_arn
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| SQL 版本 | `sql_version = "2016-03-23"`，不能改 |
| action 種類 | `kinesis`、`firehose`、`s3`、`sqs`、`lambda`、`dynamodbv2`、`republish`、`cloudwatch_logs`、`cloudwatch_metric`、`sns` |
| error action | 必填，剛好一種 action，所有 rule 共用 |
| rule 名稱 | map 的 key，限英數字與 `_` |
| tag | 給定的 `tags` 加上 `Name`（rule 名稱） |

## 注意

- rule 名稱不能有連字號，命名規則跟其他資源不同；範本裡習慣用 `<專案>_<環境>_<用途>`。
- `sql` 只檢查以 `SELECT` 開頭，語法錯誤要到 apply 時才會被 AWS 擋。SQL 或 action 的參數用到 `${...}` substitution template 時，HCL 字串要寫成 `$${...}`。
- 型別裡沒有的 action 種類（例如 `http`）寫了會被 Terraform 直接忽略，不會報錯；plan 看不到那個 action 就是這個原因。
- action 的 `role_arn` 由呼叫端建立，trust 是 `iot.amazonaws.com`，建議帶 `aws:SourceAccount` 與 `aws:SourceArn`，權限限縮到單一目的地。這個 module 不建 IAM。
- `lambda` action 需要 Lambda 的 resource-based policy 允許 `iot.amazonaws.com` 呼叫，用 `lambda-function` 的 `permissions` 給。
- `sqs.use_base64` 預設 `false`；`sns.message_format` 預設 `RAW`；`republish.qos` 預設 0。
- 部署者要有 `iot:CreateTopicRule`、`iot:ReplaceTopicRule`、`iot:GetTopicRule`、`iot:DeleteTopicRule`、`iot:TagResource`，以及對 action role 的 `iam:PassRole`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- `http`、`kafka`、`elasticsearch`：需要對外網路或 VPC destination（IoT rule 送不進 VPC 內的 OpenSearch，要經 Kinesis 與 Firehose）。
- `iot_analytics`、`iot_events`：AWS 已停止支援。
- `timestream`、`step_functions`、`dynamodb`（v1）、`cloudwatch_alarm`、topic rule destination。
- S3 action 的 `canned_acl`：bucket 用 bucket owner enforced，不靠 ACL。
- Lambda 的 invoke permission：在 `lambda-function`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `rules` | `map(object)` | 無 | 是 | IoT rule，rule 名稱（1–128 字元，限英數字與 `_`）→ 設定。`sql` 要以 `SELECT` 開頭，`sql_version` 固定 `2016-03-23`；`enabled` 預設 `true`。`actions` 只收 `kinesis`、`firehose`、`s3`、`sqs`、`lambda`、`dynamodbv2`、`republish`、`cloudwatch_logs`、`cloudwatch_metric`、`sns`，每種是 list，每條 rule 至少一個 action；其他種類不在型別裡，寫了會被 Terraform 忽略。`role_arn` 是讓 IoT 寫入目的地的 role，由呼叫端建立；Lambda 的 invoke permission 由 `lambda-function` 的 `permissions` 給。 |
| `error_action` | `object` | 無 | 是 | 所有 rule 共用的 error action，必填，剛好給一種 action（種類同 `rules` 的 `actions`，但每種是單一物件）。action 失敗時 IoT 把錯誤送到這裡，常見是 SQS queue。 |
| `tags` | `map(string)` | `{}` | 否 | 每條 rule 的 tag；`Name` 由 module 加上（rule 名稱）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `rule_arns` | rule 名稱 → rule 的 ARN。 |
| `rule_names` | 所有 rule 的名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iot-topic-rule
```
