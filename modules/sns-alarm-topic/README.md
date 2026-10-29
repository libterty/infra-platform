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

module "account_alerts" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sns-alarm-topic?ref=sns-alarm-topic-v0.2.0"

  name                = "alpha-dev-account-alerts"
  email_subscriptions = ["ops@example.com"]
  service_publishers  = ["budgets.amazonaws.com", "backup.amazonaws.com", "events.amazonaws.com"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。其他 module 的 `sns_topic_arns` 傳 `[module.alarm_topic.topic_arn]`。

## 注意

- **email 訂閱建立後是「待確認」狀態**，收件人要點確認信才會收到告警。`terraform apply` 成功不代表通知會到。
- 加密 topic 時不能用 `alias/aws/sns`：CloudWatch 告警無法發布到用 AWS 受管金鑰加密的 topic。要用自管 KMS key，而且 key policy 要允許 `cloudwatch.amazonaws.com`。不給 `kms_master_key_id` 時 topic 不加密。
- 同一個 email 重複出現只會建一個訂閱。
- **`service_publishers`（0.2.0 起）非空時，module 接管整份 topic policy**：
  - 第一段照抄 SNS 的預設 policy（principal `*`、8 個 `SNS:*` 動作、條件 `AWS:SourceOwner` 等於目前帳號），本帳號與同帳號 CloudWatch 告警的權限不變。
  - 第二段給列出的服務 `sns:Publish`，條件 `aws:SourceAccount` 等於目前帳號；不支援 `aws:SourceAccount` 的服務會發佈失敗，要先查該服務的文件。
  - 不要在 module 外面再對同一個 topic 建 `aws_sns_topic_policy`，會互相覆蓋。
  - 空的時候不建 topic policy，跟 0.1.1 完全一樣。
- **topic 用客戶管理的 KMS key 加密時，key policy 也要允許這些服務**（`kms:GenerateDataKey*`、`kms:Decrypt`），用 `kms-key` 的 `service_principals` 給；只改 topic policy 不夠，服務會發佈失敗。

## 刻意不做

- 跨帳號發布、給其他帳號或 IAM principal 的 topic policy。topic policy 只為 `service_publishers` 而建。
- 不建 KMS key。key 屬於 `foundation` stack，這裡只收 ARN。
- 不做 Lambda、https、Slack、Chatbot 訂閱。要的話用輸出的 `topic_arn` 自己加。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | topic 名稱，1–256 字元，限英數字、連字號、底線。 |
| `email_subscriptions` | `list(string)` | `[]` | 否 | 要訂閱告警的 email，每一筆都要是 email 格式。收件人確認訂閱之後才收得到告警。 |
| `kms_master_key_id` | `string` | `null` | 否 | 客戶管理 KMS key 的 ARN，不可為 `alias/aws/sns`；key policy 要允許 `cloudwatch.amazonaws.com` 使用。`null` 不加密。 |
| `tags` | `map(string)` | `{}` | 否 | topic 的 tag；`Name` 由 module 加上。 |
| `service_publishers` | `list(string)` | `[]` | 否 | 可以發佈到這個 topic 的 AWS 服務 principal（例如 `budgets.amazonaws.com`、`backup.amazonaws.com`、`events.amazonaws.com`）。非空時建 topic policy：保留 SNS 預設給本帳號的權限，另給這些服務 `sns:Publish`，條件 `aws:SourceAccount` 等於目前帳號。空的就不建 topic policy，沿用 SNS 預設。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `topic_arn` | 告警 topic 的 ARN，給告警的 `alarm_actions`、`ok_actions` 用。 |
| `topic_name` | 告警 topic 的名稱。 |
| `subscription_arns` | email 訂閱的 ARN，key 為 email。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/sns-alarm-topic
```
