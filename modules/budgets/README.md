# budgets

建一個或多個 AWS Budgets 成本預算，每個預算可以設多個通知，送到 SNS topic 或 email。Budgets 是全域服務，沒有 `region` 輸入。

## 用法

```hcl
module "budgets" {
  source = "git::https://github.com/<org>/<repo>.git//modules/budgets?ref=budgets-v0.1.0"

  budgets = {
    alpha-dev-monthly = {
      limit_amount = 100
      notifications = [
        for n in [["ACTUAL", 80], ["ACTUAL", 100], ["FORECASTED", 100]] : {
          type           = n[0]
          threshold      = n[1]
          sns_topic_arns = [module.alarm_topic.topic_arn]
          emails         = ["ops@example.com"]
        }
      ]
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 預算類型 | `COST`，金額單位 `USD` |
| 帳號 | provider 所在的帳號 |
| 通知預設 | `GREATER_THAN`、`PERCENTAGE` |
| tag | 給定的 `tags` 加上 `Name`（預算名稱） |

## 注意

- **SNS topic policy**：topic 要允許 `budgets.amazonaws.com` 的 `SNS:Publish`，建議加條件 `aws:SourceAccount` 等於自己的帳號、`aws:SourceArn` 符合 `arn:aws:budgets::<account>:*`（`sns-alarm-topic` 0.2.0 的 `service_publishers`）。topic 要在同一個帳號。
- topic 用 CMK 加密時，key policy 也要允許 `budgets.amazonaws.com` 用這把 key（`kms:GenerateDataKey*`、`kms:Decrypt`）。AWS 的 Budgets 文件說要設定 key policy，但沒有列出動作；這兩個動作是照 SNS 對其他服務的通用做法，還沒驗證。
- topic 在 `ap-northeast-1` 這類非 `us-east-1` 的 region 能不能收到 Budgets 的通知，AWS 文件沒有明寫，第一次 apply 後要用實際通知確認。
- 每個通知最多 1 個 SNS topic、10 個 email。email 訂閱不用確認，SNS 的 email 訂閱才要。
- `FORECASTED` 通知要累積約 5 週的用量資料才會開始發送，新帳號一開始收不到。
- 一般的預算與通知不收費；要收費的是 budget action（這個 module 不做）。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

budget action（自動套 SCP 或 IAM policy）、usage budget、RI 與 Savings Plans 的使用率與覆蓋率預算、`planned_limit`（逐期不同的金額）、`auto_adjust_data`、`cost_types` 調整、跨帳號（`account_id`）、`filter_expression`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `budgets` | `map(object)` | 無 | 是 | 成本預算，key 是預算名稱（1–100 字元，不含 `:` 與 `\`）。`limit_amount` 是美元金額（正數）；`time_unit` 是 `DAILY`、`MONTHLY`（預設）、`QUARTERLY`、`ANNUALLY`；`cost_filters` 是 filter 名稱對值清單，例如 `{ Service = ["Amazon Elastic Compute Cloud - Compute"] }`。`notifications` 每個：`comparison` 是 `GREATER_THAN`（預設）、`LESS_THAN`、`EQUAL_TO`；`threshold_type` 是 `PERCENTAGE`（預設，`threshold` 0–1000）或 `ABSOLUTE_VALUE`（`threshold` 是美元金額）；`type` 是 `ACTUAL` 或 `FORECASTED`；`sns_topic_arns` 最多 1 個、`emails` 最多 10 個，兩者合計至少 1 個。 |
| `tags` | `map(string)` | `{}` | 否 | 每個預算的 tag；`Name` 由 module 加上（預算名稱）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `budget_arns` | 預算名稱對 ARN 的 map。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/budgets
```
