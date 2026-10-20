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
- alarm 預設 `Sum`、60 秒、1 期、`>= 1`、`notBreaching`。要改門檻或週期就在該項目覆寫（例如 300 秒、門檻 60）。
- `alarms` 非空時 `sns_topic_arns` 必填，`alarm_actions` 與 `ok_actions` 都接，恢復時也會通知；沒給會被 validation 擋下。只給 `metrics` 時不需要 SNS（0.2.0 起）。
- `metrics`（0.2.0 起）只建 metric filter，不建 alarm，給 dashboard 或在別處管理的告警用。名稱規則跟 `alarms` 相同，key 不能同時出現在 `alarms` 與 `metrics`。
- 什麼都沒給（`alarms`、`metrics`、`sns_topic_arns` 都空）會被擋下。`alarms = {}` 搭配有給的 `sns_topic_arns` 維持 0.1.0 的行為：什麼都不建，不會報錯，給範本預設不開告警用。
- `period` 只接受 10、30 或 60 的倍數。
- `namespace` 不可以 `AWS/` 開頭。
- `description` 請寫「代表什麼」與「先查什麼」，值班的人收到告警時只看得到這段。

## 刻意不做

- metric filter 的 `dimensions`（跟 `default_value` 不能同時用，選 `default_value`）。
- 一次處理多個 log group；多個 log group 就呼叫多次。
- composite alarm、anomaly detection。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | 名稱前綴，小寫英數字與連字號 |
| `log_group_name` | `string` | 無 | 是 | metric filter 讀取的 log group |
| `namespace` | `string` | 無 | 是 | 自訂指標 namespace，不可以 `AWS/` 開頭 |
| `alarms` | `map(object)` | `{}` | 否 | key（snake_case）對應 `pattern`、`metric_name`、`description`，以及可選的 `metric_value`（`"1"`）、`default_value`（`0`）、`statistic`（`Sum`）、`period`（`60`）、`evaluation_periods`（`1`）、`datapoints_to_alarm`（`null`）、`threshold`（`1`）、`comparison_operator`（`GreaterThanOrEqualToThreshold`）、`treat_missing_data`（`notBreaching`） |
| `metrics` | `map(object)` | `{}` | 否 | 只建 metric filter 的項目：key（snake_case）對應 `pattern`、`metric_name`，以及可選的 `metric_value`（`"1"`）、`default_value`（`0`）；key 不可與 `alarms` 重複 |
| `sns_topic_arns` | `list(string)` | `[]` | 視情況 | `alarms` 非空時至少一個 SNS topic ARN，同時用於 `alarm_actions` 與 `ok_actions`；只給 `metrics` 時可不給 |
| `tags` | `map(string)` | `{}` | 否 | alarm 的 tag；`Name` 由 module 加上（metric filter 不支援 tag） |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `alarm_arns` | `map(string)` | alarm ARN，key 同 `alarms` |
| `alarm_names` | `map(string)` | alarm 名稱，key 同 `alarms` |
| `metric_filter_names` | `map(string)` | metric filter 名稱，key 為 `alarms` 與 `metrics` 的 key |
| `metric_names` | `map(string)` | 指標名稱（搭配 `namespace` 使用），key 為 `alarms` 與 `metrics` 的 key |

## 測試

```bash
scripts/validate.sh modules/log-metric-alarm
```
