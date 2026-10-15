# xray

建 X-Ray 的 sampling rule 與 group。sampling rule 控制「抓多少」，是追蹤成本的主要開關；group 用 filter expression 把錯誤或慢的 trace 獨立出來看，可選開 X-Ray Insights。兩個 map 都可以不給，這時什麼都不建。

## 用法

```hcl
module "xray" {
  source = "git::https://github.com/<org>/<repo>.git//modules/xray?ref=xray-v0.1.0"

  name_prefix = "alpha-dev"

  sampling_rules = {
    health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" }
    api    = { priority = 200, fixed_rate = 0.05, reservoir_size = 1, service_name = "alpha-dev-api" }
  }

  groups = {
    errors = { filter_expression = "fault = true OR error = true" }
    slow   = { filter_expression = "responsetime > 3" }
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- **sampling rule 只對向 X-Ray 拿抽樣規則的 SDK 或 collector 生效**（X-Ray SDK、或 ADOT／OTEL 用 X-Ray remote sampler）。在 SDK 端用 `traceidratio` 固定比例抽樣的應用程式不會套用這裡的 rule。這段行為尚未在我們的環境實測。
- 要用 remote sampling，task role 要有 `xray:GetSamplingRules`、`xray:GetSamplingTargets`（只支援 `Resource = "*"`），這個 module 不建 IAM。
- rule 與 group 的名稱是 `<name_prefix>-<key>`，X-Ray 限制 32 字元，超過會在 plan 階段被擋。
- `priority` 越小越先套用，帳號內建的 `Default` rule 是 10000。同一次呼叫裡 `priority` 不可重複。
- sampling rule 是帳號層級的資源，名稱帶 `name_prefix` 才不會跟同帳號其他專案撞。
- `notifications_enabled = true` 時，`insights_enabled` 也必須是 `true`（X-Ray 的限制）。Insights 另外計費；group 本身不省錢，成本由 sampling rule 控制。

## 刻意不做

- 帳號層級的 `Default` sampling rule：AWS 內建，不能用 Terraform 建，也不改它。
- X-Ray 加密設定（`aws_xray_encryption_config`）：一個帳號只有一份，不適合放在專案 module。
- Resource Policy。
- IAM：寫入與抽樣權限由 `iam-app` 給 task role。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name_prefix` | `string` | 無 | 是 | rule 與 group 名稱前綴，名稱為 `<name_prefix>-<key>`，總長不得超過 32 字元 |
| `sampling_rules` | `map(object)` | `{}` | 否 | key 為 rule 短名。欄位：`priority`（1–9999，必填、不可重複）、`fixed_rate`（0–1，必填）、`reservoir_size`（預設 1，不得為負）、`service_name`、`service_type`、`host`、`http_method`、`url_path`（預設都是 `*`）、`attributes`（預設 `{}`） |
| `groups` | `map(object)` | `{}` | 否 | key 為 group 短名。欄位：`filter_expression`（必填、不可為空白）、`insights_enabled`（預設 `false`）、`notifications_enabled`（預設 `false`，為 `true` 時 `insights_enabled` 也要是 `true`） |
| `tags` | `map(string)` | `{}` | 否 | 套用到每個 rule 與 group 的 tag |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `sampling_rule_arns` | `map(string)` | sampling rule 的 ARN，key 為 `sampling_rules` 的 key |
| `group_arns` | `map(string)` | group 的 ARN，key 為 `groups` 的 key |

## 測試

```bash
scripts/validate.sh modules/xray
```
