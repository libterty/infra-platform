# agentcore-memory

建一個 AgentCore Memory，可選加上內建的長期記憶 strategy。`strategies` 不給時只有短期記憶（事件），這也是目前唯一部署過的形態。

## 用法

```hcl
module "memory" {
  source = "git::https://github.com/<org>/<repo>.git//modules/agentcore-memory?ref=agentcore-memory-v0.1.1"

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

## 容易出錯的地方

- **事件保留天數預設 90，不用上限 365。** 保留越久，留下的個資越多，所以預設取中間值；要更長的專案自己明寫。這個預設是判斷出來的，沒有實測。
- **保留天數的下限是 7，不是 3。** API 文件寫 3–365，但 aws provider 6.69.0 在 plan 階段就擋掉 7 以下的值（`value must be between 7 and 365`）。module 照 provider 的範圍先擋，錯誤直接在 module 這一層報出來，不用等 provider。
- **`namespaces` 送進 provider 的 `namespace_templates`。** provider 6.69.0 把 strategy 的 `namespaces` 標成 deprecated，改用 `namespace_templates`。module 的輸入仍叫 `namespaces`，呼叫端不用管這個改名。

## 注意

- 改 `event_expiry_days` 只影響之後寫入的事件，已經寫入的事件仍照舊的天數過期。
- 名稱只能用字母、數字、底線，字母開頭，最長 48 字。不能有 `-`，專案的命名前綴要先把 `-` 換成 `_`。provider 也會在 plan 階段擋同一條規則。
- strategy 的名稱就是 `strategies` 的 key，規則跟 Memory 名稱相同（照 API 文件，**未實測**）。
- strategy 只收內建的 `SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE`，每個至少一個 namespace，namespace 以 `/` 開頭（照 API 文件，**未實測**）。內建 strategy 不給 `memory_execution_role_arn` 能不能建、能不能產生長期記憶，也**未實測**。
- `kms_key_arn` 只收 `arn:aws:kms:<region>:<account>:key/<uuid>` 或 multi-region key 的 `key/mrk-<32 碼>`，alias 與 `*` 都擋。給自管 key 時，key policy 要讓 AgentCore 使用這把 key；要給哪些 service principal 與條件**未實測**，範本目前傳 `null`。
- Runtime 的 execution role 需要 `bedrock-agentcore:CreateEvent`、`ListEvents`、`GetEvent`、`RetrieveMemoryRecords`，Resource 用這裡輸出的 `memory_arn`。這個 module 不建 IAM。
- strategy 沒有 tag，`tags` 只套用到 Memory。

## 刻意不做

- `CUSTOM` 與 self-managed strategy（`configuration` 區塊）：這需要自訂模型、`append_to_prompt` 與 Memory execution role，範本得多一個 role 與權限；需要時再加（MINOR）。
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
| `kms_key_arn` | `string` | `null` | 否 | 自管 KMS key 的 ARN（`key/<uuid>`，不收 alias 與 `*`）；`null` 用 AWS 管的 key |
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
