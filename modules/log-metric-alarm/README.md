# log-metric-alarm

從一個 log group 的 log 產生自訂指標，再對指標建告警（metric filter 加 alarm）。一次呼叫處理同一個 log group 的多組 filter 與告警。適合「應用程式印出某個事件就代表出事」的訊號，例如 audit 寫入失敗、rate limit fail-open。

## 用法

```hcl
module "log_alarms" {
  source = "git::https://github.com/<org>/<repo>.git//modules/log-metric-alarm?ref=log-metric-alarm-v0.1.0"

  name_prefix    = "alpha-dev-api"
  log_group_name = module.api.log_group_name
  namespace      = "Alpha/dev"
  sns_topic_arns = [module.alarm_topic.topic_arn]

  alarms = {
    record_write_failed = {
      pattern     = "{ $.event = \"record_write_failed\" }"
      metric_name = "RecordWriteFailed"
      description = "Audit rows failed to reach the database. Check RDS Proxy first."
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- 名稱是 `<name_prefix>-<key 的 _ 換成 ->`，filter 與 alarm 同名（兩種資源的名稱空間各自獨立）。
- filter 預設 `value = "1"`、`default_value = 0`，沒有事件時指標是 0，不會落在 INSUFFICIENT_DATA。
- alarm 預設 `Sum`、60 秒、1 期、`>= 1`、`notBreaching`。要改門檻或週期，就在那個項目裡覆寫（例如 300 秒、門檻 60）。
- `alarms` 有內容時 `sns_topic_arns` 必填，沒給會被 validation 擋下。這些 topic 同時接上 `alarm_actions` 與 `ok_actions`，所以恢復時也會通知。只給 `metrics` 時不需要 SNS（0.2.0 起）。
- `metrics`（0.2.0 起）只建 metric filter，不建 alarm，給 dashboard 或在別處管理的告警用。名稱規則跟 `alarms` 相同，key 不能同時出現在 `alarms` 與 `metrics`。
- 什麼都沒給（`alarms`、`metrics`、`sns_topic_arns` 都空）會被擋下。`alarms = {}` 搭配有給的 `sns_topic_arns` 維持 0.1.0 的行為：什麼都不建，不會報錯，給範本預設不開告警用。
- `period` 只接受 10、30 或 60 的倍數。
- `namespace` 不可以 `AWS/` 開頭。
- `description` 請寫「代表什麼」與「先查什麼」，值班的人收到告警時只看得到這段。

## 刻意不做

- metric filter 的 `dimensions`（跟 `default_value` 不能同時用，選 `default_value`）。
- 一次處理多個 log group；多個 log group 就呼叫多次。
- composite alarm、anomaly detection。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | filter 與 alarm 的名稱前綴，名稱是 `<name_prefix>-<key 的 _ 換成 ->`。小寫字母開頭，2–101 個小寫英數字或連字號。 |
| `log_group_name` | `string` | 無 | 是 | metric filter 讀取的 log group 名稱。 |
| `namespace` | `string` | 無 | 是 | 自訂指標的 namespace，例如 `Alpha/dev`。1–255 字元，不可以 `AWS/` 開頭。 |
| `alarms` | `map(object)` | `{}` | 否 | key（snake\_case）對應一組 metric filter 加 alarm；非空時必須給 `sns_topic_arns`，key 不可與 `metrics` 重複。欄位見〈`alarms` 欄位〉。 |
| `metrics` | `map(object)` | `{}` | 否 | 只建 metric filter、不建 alarm 的項目，給 dashboard 或在別處管理的告警用。key（snake\_case）對應 `pattern`（必填，不可為空白）、`metric_name`（必填），以及 `metric_value`（預設 `"1"`）、`default_value`（預設 `0`）；key 不可與 `alarms` 重複。`alarms`、`metrics`、`sns_topic_arns` 不可全空。 |
| `sns_topic_arns` | `list(string)` | `[]` | 否 | `alarms` 非空時必填，至少一個。SNS topic ARN，同時用於每個 alarm 的 `alarm_actions` 與 `ok_actions`；只給 `metrics` 時可不給。 |
| `tags` | `map(string)` | `{}` | 否 | alarm 的 tag；`Name` 由 module 加上（metric filter 不支援 tag）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alarm_arns` | key 同 `alarms` 的 map，值是 alarm ARN。 |
| `alarm_names` | key 同 `alarms` 的 map，值是 alarm 名稱。 |
| `metric_filter_names` | key 為 `alarms` 與 `metrics` 的 key 的 map，值是 metric filter 名稱。 |
| `metric_names` | key 為 `alarms` 與 `metrics` 的 key 的 map，值是指標名稱；搭配 `namespace` 給 dashboard 或在別處管理的告警用。 |
<!-- END_TF_DOCS -->

## `alarms` 欄位

每個 `alarms` 項目建一個 metric filter 與一個 alarm。key 必須是 snake_case，不可與 `metrics` 重複。

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `pattern` | `string` | 必填 | metric filter 的 log pattern，不可為空白 |
| `metric_name` | `string` | 必填 | 自訂指標名稱 |
| `description` | `string` | 必填 | 告警代表什麼、先查什麼，不可為空白 |
| `metric_value` | `string` | `"1"` | 每筆符合的事件寫入的值 |
| `default_value` | `number` | `0` | 沒有符合事件時的值 |
| `statistic` | `string` | `Sum` | `Sum`、`Average`、`Maximum`、`Minimum` 或 `SampleCount` |
| `period` | `number` | `60` | 秒數，只接受 10、30 或 60 的倍數 |
| `evaluation_periods` | `number` | `1` | 評估幾期 |
| `datapoints_to_alarm` | `number` | `null` | 幾期超標就告警，不可大於 `evaluation_periods` |
| `threshold` | `number` | `1` | 門檻 |
| `comparison_operator` | `string` | `GreaterThanOrEqualToThreshold` | `GreaterThanOrEqualToThreshold`、`GreaterThanThreshold`、`LessThanThreshold` 或 `LessThanOrEqualToThreshold` |
| `treat_missing_data` | `string` | `notBreaching` | `missing`、`ignore`、`breaching` 或 `notBreaching` |

## 測試

```bash
scripts/validate.sh modules/log-metric-alarm
```
