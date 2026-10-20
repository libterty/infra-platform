# metric-alarm

對任何 CloudWatch 指標建告警。一次呼叫處理同一組前綴的多個告警，每個告警可以是單一指標，也可以是 metric math（例如錯誤率 = 錯誤數 ÷ 請求數）。告警與恢復都會通知 SNS。

要從 log 產生自訂指標再告警，請用 [`log-metric-alarm`](../log-metric-alarm/README.md)。

## 用法

```hcl
module "alarms" {
  source = "git::https://github.com/<org>/<repo>.git//modules/metric-alarm?ref=metric-alarm-v0.1.0"

  name_prefix    = "alpha-dev-api"
  sns_topic_arns = [module.alarm_topic.topic_arn]

  alarms = {
    queue_depth_high = {
      description         = "Messages are piling up. Check whether the consumer is running first."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 100
      metric = {
        namespace   = "AWS/SQS"
        metric_name = "ApproximateNumberOfMessagesVisible"
        dimensions  = { QueueName = "alpha-dev-jobs" }
        statistic   = "Maximum"
      }
    }
  }
}
```

完整範例（含 metric math）見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- 名稱是 `<name_prefix>-<key 的 _ 換成 ->`，跟 `log-metric-alarm` 一致。
- 每個告警必須二選一：`metric` 或 `queries`。
- `queries` 的規則：每項要有 `expression` 或 `metric` 其中一個；id 小寫字母開頭且不可重複；**只能有一個 `return_data = true`**，告警比較的就是那一個。
- `metric` 預設 `Average`、300 秒。AWS 服務的基本指標多數是 1 或 5 分鐘一筆，用 300 最不容易落在 INSUFFICIENT_DATA；需要更細就自己指定。
- `period` 只接受 10、30 或 60 的倍數；`statistic` 只接受 `Sum`、`Average`、`Maximum`、`Minimum`、`SampleCount`。
- 預設 `evaluation_periods = 1`、`GreaterThanOrEqualToThreshold`、`treat_missing_data = "notBreaching"`。
- `sns_topic_arns` 必填，同時接上 `alarm_actions` 與 `ok_actions`，所以恢復時也會通知。
- `description` 請寫「代表什麼」與「先查什麼」，值班的人收到告警時只看得到這段。

## 刻意不做

- percentile（`extended_statistic`，例如 p99）、anomaly detection、composite alarm。
- `insufficient_data_actions`、`unit`。
- 建 metric filter（用 `log-metric-alarm`）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | 名稱前綴，小寫英數字與連字號 |
| `alarms` | `map(object)` | 無 | 是 | key（snake_case）對應 `description`、`threshold`，以及可選的 `comparison_operator`、`evaluation_periods`（`1`）、`datapoints_to_alarm`（`null`）、`treat_missing_data`（`notBreaching`）；再加 `metric`（`namespace`、`metric_name`、`dimensions`、`statistic`、`period`）或 `queries`（`id`、`expression`、`label`、`return_data`、`metric`）二選一 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 至少一個 SNS topic ARN，同時用於 `alarm_actions` 與 `ok_actions` |
| `tags` | `map(string)` | `{}` | 否 | alarm 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `alarm_arns` | `map(string)` | alarm ARN，key 同 `alarms` |
| `alarm_names` | `map(string)` | alarm 名稱，key 同 `alarms` |

## 測試

```bash
scripts/validate.sh modules/metric-alarm
```
