# access-analyzer

建一個 IAM Access Analyzer 的 analyzer，加上選填的 archive rule。預設只分析本帳號的外部存取（`ACCOUNT`，免費）；要分析整個 organization 或未使用的權限，改 `type`。

## 用法

```hcl
module "access_analyzer" {
  source = "git::https://github.com/<org>/<repo>.git//modules/access-analyzer?ref=access-analyzer-v0.1.0"

  name = "alpha-dev-account"

  archive_rules = {
    sit-account = [
      { criteria = "principal.AWS", eq = ["222222222222"] },
    ]
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 預設類型 | `ACCOUNT`：外部存取分析，免費 |
| unused access | 只有 `*_UNUSED_ACCESS` 類型才帶 `configuration.unused_access`；`unused_access_age_days` 沒給時用 AWS 預設 |
| archive rule | 每個 map key 一條，名稱就是 key；一條 rule 的 filter 要全部符合才封存 |
| tag | 給定的 `tags` 加上 `Name`（值是 `name`） |

## 注意

- **Access Analyzer 是 regional 服務**：analyzer 只看所在 region 的資源（IAM role 這類全域資源每個 region 都看得到）。多 region 用 `region` 輸入各呼叫一次。
- `ORGANIZATION` 與 `ORGANIZATION_UNUSED_ACCESS` 要在管理帳號或 Access Analyzer 的委派管理帳號建，而且 organization 要先開 Access Analyzer 的 trusted access（`organization-delegated-admin`）。
- **unused access 依分析的 IAM role 與 user 數按月計費**，外部存取分析免費。外部存取與未使用權限是兩種不同的 analyzer，兩個都要就呼叫兩次。
- 一個 region 同一種類型的 analyzer 有數量上限；帳號已經有 console 建的 analyzer 時，要先 `terraform import` 或刪掉，不要重複建。
- `exists` 在 provider 是字串，module 收 `bool` 再轉成 `"true"`／`"false"`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

internal access 分析（`ACCOUNT_INTERNAL_ACCESS`、`ORGANIZATION_INTERNAL_ACCESS`）、unused access 的 exclusion 規則、policy 驗證與 policy 產生、把 finding 送到 EventBridge 或 Security Hub（Security Hub 會自動收 Access Analyzer 的 finding）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | analyzer 名稱，1–255 字元，英文字母開頭，限英數字、`.`、`_`、`-`。 |
| `type` | `string` | `"ACCOUNT"` | 否 | analyzer 類型：`ACCOUNT`（預設，本帳號的外部存取，免費）、`ORGANIZATION`（整個 organization 的外部存取，要在管理帳號或委派管理帳號建）、`ACCOUNT_UNUSED_ACCESS`、`ORGANIZATION_UNUSED_ACCESS`（未使用的權限，依分析的 role 與 user 數計費）。 |
| `unused_access_age_days` | `number` | `null` | 否 | 超過幾天沒用就算未使用的權限（1–365）。只有 `type` 是 `*_UNUSED_ACCESS` 時能給；`null` 用 AWS 預設。 |
| `archive_rules` | `map(list(object))` | `{}` | 否 | archive rule 名稱對應 filter 清單；符合全部 filter 的 finding 會自動封存。每個 filter 有 `criteria`（例如 `principal.AWS`、`resourceType`、`isPublic`）與至少一個比對：`eq`、`neq`、`contains`、`exists`。空的就不建 archive rule。 |
| `region` | `string` | `null` | 否 | analyzer 所在的 region；`null`（預設）用 provider 的 region。Access Analyzer 是 regional 服務，每個要分析的 region 各建一個。 |
| `tags` | `map(string)` | `{}` | 否 | analyzer 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | analyzer 的 ARN。 |
<!-- END_TF_DOCS -->
