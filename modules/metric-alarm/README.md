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

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | alarm 的名稱前綴，名稱是 `<name_prefix>-<key 的 _ 換成 ->`。小寫字母開頭，2–101 個小寫英數字或連字號。 |
| `alarms` | `map(object)` | 無 | 是 | key（snake\_case）對應一個 alarm 的設定，每個 alarm 用 `metric`（單一指標）或 `queries`（metric math）二選一。欄位見〈`alarms` 欄位〉。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | SNS topic ARN，至少一個，同時用於每個 alarm 的 `alarm_actions` 與 `ok_actions`。 |
| `tags` | `map(string)` | `{}` | 否 | alarm 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alarm_arns` | key 同 `alarms` 的 map，值是 alarm ARN。 |
| `alarm_names` | key 同 `alarms` 的 map，值是 alarm 名稱。 |
<!-- END_TF_DOCS -->

## `alarms` 欄位

每個 `alarms` 項目建一個 alarm。key 必須是 snake_case。`metric` 與 `queries` 必須二選一。

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `description` | `string` | 必填 | 告警代表什麼、先查什麼，不可為空白 |
| `threshold` | `number` | 必填 | 門檻 |
| `comparison_operator` | `string` | `GreaterThanOrEqualToThreshold` | `GreaterThanOrEqualToThreshold`、`GreaterThanThreshold`、`LessThanThreshold` 或 `LessThanOrEqualToThreshold` |
| `evaluation_periods` | `number` | `1` | 評估幾期，至少 1 |
| `datapoints_to_alarm` | `number` | `null` | 幾期超標就告警，1 到 `evaluation_periods` |
| `treat_missing_data` | `string` | `notBreaching` | `missing`、`ignore`、`breaching` 或 `notBreaching` |
| `metric` | `object` | `null` | 單一指標，欄位見下表 |
| `queries` | `list(object)` | `[]` | metric math，欄位見下表 |

`metric`（以及 `queries` 裡的 `metric`）的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `namespace` | `string` | 必填 | 指標 namespace，例如 `AWS/SQS` |
| `metric_name` | `string` | 必填 | 指標名稱 |
| `dimensions` | `map(string)` | `{}` | 指標的 dimension |
| `statistic` | `string` | `Average` | `Sum`、`Average`、`Maximum`、`Minimum` 或 `SampleCount` |
| `period` | `number` | `300` | 秒數，只接受 10、30 或 60 的倍數 |

`queries` 每一項的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `id` | `string` | 必填 | 小寫字母開頭，1–255 個英數字或底線，同一個 alarm 內不可重複 |
| `expression` | `string` | `null` | metric math 運算式；跟 `metric` 二選一 |
| `label` | `string` | `null` | 顯示名稱 |
| `return_data` | `bool` | `false` | 只能有一項是 `true`，告警比較的就是那一項 |
| `metric` | `object` | `null` | 單一指標，欄位同上表；跟 `expression` 二選一 |

## 測試

```bash
scripts/validate.sh modules/metric-alarm
```
