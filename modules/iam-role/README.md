# iam-role

建立一個 IAM role：trust policy 加 inline policy。

整個 repo 只有這個 module 與 [`iam-role-policy`](../iam-role-policy/README.md) 可以宣告 `aws_iam_*` 資源（`scripts/validate.sh` 的 S4 規則強制）。

## 用法

```hcl
module "ecs_execution" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iam-role?ref=iam-role-v0.1.0"

  name = "alpha-dev-ecs-execution"

  trust = {
    service_principals = ["ecs-tasks.amazonaws.com"]
    source_account     = "111111111111"
  }

  inline_policies = {
    ecr-pull = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }]
    })
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 行為

- trust policy 只有一段 statement：`sts:AssumeRole`，Principal 為輸入的服務主體。給了 `source_account` 才加 `StringEquals` 的 `aws:SourceAccount` 條件；給了 `source_arn`（0.1.1 起）才加 `ArnLike` 的 `aws:SourceArn` 條件。兩個都給時是同一段 statement 的兩個條件，必須同時成立。
- policy 一律傳 JSON 字串（用 `jsonencode()`），不收 `aws_iam_policy_document` 的輸出。
- `arn` 輸出帶 `depends_on = [aws_iam_role_policy.this]`，下游拿到 ARN 時 inline policy 已附加。
- Allow statement 的 Action 不可是 `*` 或以 `:*` 結尾；Deny statement 不受限。
- Allow statement 不可使用 `NotAction`（等於授權「列出的動作以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotAction` 不受限。
- Allow statement 不可使用 `NotResource`（等於授權「列出的資源以外全部」）；沒寫 `Effect` 視為 Allow。Deny 搭配 `NotResource` 不受限。

## 限制

- 不收 AWS managed policy 與 customer managed policy，也沒有 instance profile。
- trust 只收 AWS 服務主體，不收 AWS 帳號、OIDC 或 `*`。
- `source_arn` 只檢查 `arn:` 開頭，不檢查 service、region、帳號是否與服務主體相符；萬用字元放多寬由呼叫端決定。
- 不使用任何獨佔管理 inline policy 的資源（例如 provider 的 role policies exclusive 類型），否則會刪掉 `iam-role-policy` 附加的 policy。
- 只檢查 Action、`NotAction`、`NotResource`，不檢查 `Resource`；`Resource = "*"` 是否合理由呼叫端的測試負責。
- `Statement` 必須是清單（單一物件的寫法會被擋）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | role 名稱，1–64 字元，限字母、數字與 `+=,.@_-` |
| `description` | `string` | `null` | 否 | role 說明 |
| `trust` | `object({ service_principals = set(string), source_account = optional(string), source_arn = optional(string) })` | 無 | 是 | 至少一個 `*.amazonaws.com` 服務主體；`source_account` 為 12 位數字；`source_arn` 以 `arn:` 開頭、可含萬用字元（例如 `arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/*`），用 `ArnLike` 比對 |
| `inline_policies` | `map(string)` | `{}` | 否 | policy 名稱對 policy JSON 字串 |
| `permissions_boundary` | `string` | `null` | 否 | permissions boundary 的 policy ARN |
| `tags` | `map(string)` | `{}` | 否 | 額外 tag，module 只再加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `arn` | `string` | role ARN；所有 inline policy 附加之後才有值 |
| `name` | `string` | role 名稱 |
| `id` | `string` | role ID |

## 測試

```bash
scripts/validate.sh modules/iam-role
```
