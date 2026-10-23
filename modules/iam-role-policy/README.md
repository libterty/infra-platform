# iam-role-policy

對一個已經存在的 role 附加 inline policy。只建 `aws_iam_role_policy`，不建 role。

role 和它的權限必須分開時間建立時，用這個 module。例如 RDS Proxy 的 role 要在資料庫之前存在，讀 master secret 的權限則要等 secret 建好後才附加。其他情況用 [`iam-role`](../iam-role/README.md) 的 `inline_policies`。

## 用法

```hcl
module "proxy_secret_access" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role-policy?ref=iam-role-policy-v0.1.0"

  role_arn = module.proxy_role.arn

  policies = {
    read-master-secret = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = module.db.master_secret_arn
      }]
    })
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 行為

- role 名稱取 `role_arn` 最後一個 `/` 之後的部分。
- policy 一律傳 JSON 字串（用 `jsonencode()`）。
- Allow statement 的 Action 不可是 `*` 或以 `:*` 結尾；Deny statement 不受限。這段檢查跟 `iam-role` 一字不差。
- Allow statement 不可使用 `NotAction`（等於授權「列出的動作以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotAction` 不受限。
- Allow statement 不可使用 `NotResource`（等於授權「列出的資源以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotResource` 不受限。

## 限制

- 不建 role，不附加 AWS managed policy 或 customer managed policy。
- 不支援帶 path 的 role（`role/service/x` 會被擋）。
- 同一個 role 同時由 `iam-role` 與這個 module 附加 policy 時，policy 名稱不可重複。
- 只檢查 Action、`NotAction`、`NotResource`，不檢查 `Resource`。
- `Statement` 必須是清單（單一物件的寫法會被擋）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `role_arn` | `string` | 無 | 是 | 要附加 policy 的既有 role ARN，不可帶 path；role 名稱取 ARN 最後一段。 |
| `policies` | `map(string)` | 無 | 是 | policy 名稱對 policy JSON 字串（用 `jsonencode()` 產生），至少一個。每份 JSON 的 `Statement` 必須是清單；Allow statement（沒寫 `Effect` 視為 Allow）的 Action 不可是 `*` 或以 `:*` 結尾，也不可用 `NotAction`、`NotResource`；Deny statement 不受限。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `policy_names` | 已附加的 inline policy 名稱清單。 |
| `role_name` | 從 `role_arn` 取出的 role 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iam-role-policy
```
