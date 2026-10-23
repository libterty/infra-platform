# xray-transaction-search

開啟 X-Ray 的 Transaction Search：span 改存進 CloudWatch Logs 的 `aws/spans`，並設定要拿多少比例的 span 建索引。OTLP 送進 X-Ray 的 trace（例如 AgentCore Runtime）要先開這個，否則 span 會全部遺失而且不報錯。

這是帳號加 region 層級的設定，一個 region 只有一份。**每個帳號、每個 region 只能由一處呼叫**（帳號 baseline 或平台 stack），不要放進專案範本的 stack；兩處都呼叫時，後 apply 的會蓋掉前面的 indexing 比例。

## 用法

```hcl
module "xray_transaction_search" {
  source = "git::https://github.com/<org>/<repo>.git//modules/xray-transaction-search?ref=xray-transaction-search-v0.1.0"

  indexing_percentage = 1
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 建了什麼

照 AWS 文件〈Enable Transaction Search〉的 API 步驟，依序建：

1. CloudWatch Logs resource policy：允許 `xray.amazonaws.com` 對 `aws/spans` 與 `/aws/application-signals/data` 做 `logs:PutLogEvents`，限定本帳號、本 region 的 X-Ray（`aws:SourceArn`、`aws:SourceAccount`）。
2. `aws_xray_trace_segment_destination`：destination 設成 `CloudWatchLogs`。
3. `aws_xray_indexing_rule`：更新內建的 `Default` rule，比例為 `indexing_percentage`。

## 注意

- `indexing_percentage` 預設 1，這 1% 免費；調高另外計費。span 本身不論比例都會進 `aws/spans`，依 CloudWatch Logs 計費。
- 開啟後約 10 分鐘，span 才查得到。確認方式：`aws xray get-trace-segment-destination` 回 `Destination` 是 `CloudWatchLogs`、`Status` 是 `ACTIVE`。
- 帳號已經在 console 開過也可以直接 apply：destination 與 indexing rule 會被接管成這裡的值；console 建的 resource policy 名稱不同，兩份並存不衝突。
- **destroy 不會關掉 Transaction Search**：provider 刪除 destination 與 indexing rule 時不呼叫 AWS，設定維持原樣；但 resource policy 會被刪掉，之後 X-Ray 可能寫不進 `aws/spans`，span 遺失且不報錯。要關掉時，先用 `aws xray update-trace-segment-destination --destination XRay` 改回，再 destroy。
- `resource_policy_name` 在同帳號、同 region 內必須唯一；CloudWatch Logs 每個 region 最多 10 份 resource policy。
- 部署者要有 `logs:PutResourcePolicy`、`logs:DescribeResourcePolicies`、`xray:GetTraceSegmentDestination`、`xray:UpdateTraceSegmentDestination`、`xray:GetIndexingRules`、`xray:UpdateIndexingRule`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- sampling rule 與 group：專案層級的設定，用 [`xray`](../xray/README.md)。
- `aws/spans` 的保留期：log group 由 X-Ray 自己建，要改保留期就在 log group 出現後另外設。
- Application Signals 的 discovery 與 service-linked role。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `indexing_percentage` | `number` | `1` | 否 | 建索引的 span 比例，0–100；1 免費 |
| `resource_policy_name` | `string` | `"xray-transaction-search"` | 否 | 讓 X-Ray 寫入 span 的 CloudWatch Logs resource policy 名稱，同帳號同 region 內唯一，不可為空白 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `spans_log_group_name` | `string` | X-Ray 寫入 span 的 log group，固定是 `aws/spans` |
| `indexing_percentage` | `number` | `Default` indexing rule 的比例 |

## 測試

```bash
scripts/validate.sh modules/xray-transaction-search
```
