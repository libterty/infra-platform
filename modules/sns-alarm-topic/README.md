# sns-alarm-topic

建一個告警用 SNS topic，加上 email 訂閱。一次呼叫一個 topic；要多個群組時，在 root 用 `for_each` 呼叫這個 module。

## 用法

```hcl
module "alarm_topic" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sns-alarm-topic?ref=sns-alarm-topic-v0.1.0"

  name                = "alpha-dev-alarms"
  email_subscriptions = ["ops@example.com"]
  kms_master_key_id   = data.aws_ssm_parameter.kms_key_arn.insecure_value

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。其他 module 的 `sns_topic_arns` 傳 `[module.alarm_topic.topic_arn]`。

## 注意

- **email 訂閱建立後是「待確認」狀態**，收件人要點確認信才會收到告警。`terraform apply` 成功不代表通知會到。
- 加密 topic 時不能用 `alias/aws/sns`：CloudWatch 告警無法發布到用 AWS 受管金鑰加密的 topic。要用自管 KMS key，key policy 要允許 `cloudwatch.amazonaws.com`。不給 `kms_master_key_id` 時 topic 不加密。
- 同一個 email 重複出現只會建一個訂閱。

## 刻意不做

- 不管 topic policy。同帳號的 CloudWatch 告警用預設 policy 即可發布；跨帳號發布不在第一版範圍。
- 不建 KMS key。key 屬於 `foundation` stack，這裡只收 ARN。
- 不做 Lambda、https、Slack、Chatbot 訂閱。要的話用輸出的 `topic_arn` 自己加。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | topic 名稱，1–256 字元，限英數字、連字號、底線 |
| `email_subscriptions` | `list(string)` | `[]` | 否 | 要訂閱的 email；每一筆都要是 email 格式 |
| `kms_master_key_id` | `string` | `null` | 否 | 自管 KMS key 的 ARN；不可為 `alias/aws/sns` |
| `tags` | `map(string)` | `{}` | 否 | topic 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `topic_arn` | `string` | topic ARN，給告警的 `alarm_actions`、`ok_actions` 用 |
| `topic_name` | `string` | topic 名稱 |
| `subscription_arns` | `map(string)` | email 訂閱的 ARN，key 為 email |

## 測試

```bash
scripts/validate.sh modules/sns-alarm-topic
```
