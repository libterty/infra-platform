# agentcore-memory

建一個 AgentCore Memory，可選加上內建的長期記憶 strategy。`strategies` 不給時只有短期記憶（事件），這也是目前唯一部署過的形態。

## 用法

```hcl
module "memory" {
  source = "git::https://github.com/<org>/<repo>.git//modules/agentcore-memory?ref=agentcore-memory-v0.1.0"

  name              = "alpha_dev_chat"
  event_expiry_days = 90

  strategies = {
    facts = { type = "SEMANTIC", namespaces = ["/actors/{actorId}/facts"] }
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 要修掉的坑

- **事件保留天數的預設從 365 改成 90。** 參考實作用 365，保留越久、留存的個資範圍越大。這裡預設取中間值，要更長的專案自己明寫。這是判斷，不是實測結果。
- **保留天數的下限是 7，不是 3。** 參考實作與 API 文件寫 3–365，但 aws provider 6.69.0 在 plan 階段就擋掉 7 以下的值（`value must be between 7 and 365`）。module 照 provider 的範圍擋，錯誤訊息在 module 這一層出現，不用等到 provider 才報。
- **`namespaces` 送進 provider 的 `namespace_templates`。** provider 6.69.0 把 strategy 的 `namespaces` 標成 deprecated，改用 `namespace_templates`。module 的輸入仍叫 `namespaces`，呼叫端不用知道這個改名。

## 注意

- 改 `event_expiry_days` 只影響之後寫入的事件，已經存在的事件照舊的天數過期。
- 名稱只能用字母、數字、底線，字母開頭，最長 48 字。不能有 `-`，專案的命名前綴要先把 `-` 換成 `_`。provider 也會在 plan 階段擋同一條規則。
- strategy 的名稱就是 `strategies` 的 key，規則跟 Memory 名稱相同（照 API 文件，**未實測**）。
- strategy 只收內建的 `SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE`，每個至少一個 namespace，namespace 以 `/` 開頭（照 API 文件，**未實測**）。內建 strategy 不給 `memory_execution_role_arn` 能不能建、能不能產生長期記憶，也**未實測**。
- `kms_key_arn` 給自管 key 時，key policy 要讓 AgentCore 使用這把 key；要給哪些 service principal 與條件**未實測**，範本目前傳 `null`。
- Runtime 的 execution role 需要 `bedrock-agentcore:CreateEvent`、`ListEvents`、`GetEvent`、`RetrieveMemoryRecords`，Resource 用這裡輸出的 `memory_arn`。這個 module 不建 IAM。
- strategy 沒有 tag，`tags` 只套用到 Memory。

## 刻意不做

- `CUSTOM` 與 self-managed strategy（`configuration` 區塊）：要自訂模型、`append_to_prompt` 與 Memory execution role，範本就得多一個 role 與權限；參考專案都沒用過，需要時 MINOR。
- Memory execution role、Kinesis stream delivery、`indexed_key`。
- log 與 trace delivery：用 `log-delivery`。
- IAM。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Memory 的完整名稱。字母開頭，只能用字母、數字、底線，最長 48 字 |
| `description` | `string` | `null` | 否 | Memory 的說明 |
| `event_expiry_days` | `number` | `90` | 否 | 短期事件保留天數，7–365 的整數 |
| `strategies` | `map(object)` | `{}` | 否 | key 為 strategy 名稱（規則同 `name`）。欄位：`type`（`SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE`，必填）、`namespaces`（至少一個、以 `/` 開頭，例如 `/actors/{actorId}/facts`，必填）、`description`（選填） |
| `kms_key_arn` | `string` | `null` | 否 | 自管 KMS key 的 ARN；`null` 用 AWS 管的 key |
| `tags` | `map(string)` | `{}` | 否 | 套用到 Memory 的 tag，另外自動加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `memory_id` | `string` | Memory 的 id，給 Runtime 的環境變數用 |
| `memory_arn` | `string` | Memory 的 ARN，給 Runtime execution role 的權限用 |
| `strategy_ids` | `map(string)` | strategy 的 id，key 為 `strategies` 的 key |

## 測試

```bash
scripts/validate.sh modules/agentcore-memory
```
