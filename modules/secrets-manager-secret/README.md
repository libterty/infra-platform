# secrets-manager-secret

建一個 Secrets Manager secret 的容器，可以加上 resource policy 與輪替設定。module 不寫入值：值由人或輪替流程寫，不經過 tfvars、SSM 或 state。

## 用法

```hcl
module "db_user_secret" {
  source = "git::https://github.com/<org>/<repo>.git//modules/secrets-manager-secret?ref=secrets-manager-secret-v0.1.0"

  name        = "alpha-dev/db-user"
  description = "Database user of alpha-dev. The value is written outside Terraform."
  kms_key_arn = module.key.key_arn

  policy_statements = [{
    sid        = "DenyOtherAccounts"
    effect     = "Deny"
    principals = { type = "AWS", identifiers = ["*"] }
    actions    = ["secretsmanager:*"]
    conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalAccount", values = ["111111111111"] }]
  }]

  rotation = {
    lambda_arn               = module.db_rotate.function_arn
    automatically_after_days = 30
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- **值要在 apply 之後另外寫入**（console 或 `aws secretsmanager put-secret-value`）。還沒寫入值之前，讀這個 secret 的服務會失敗。
- `kms_key_arn` 是 `null` 時用 AWS 管理的 `aws/secretsmanager`。用 CMK 時，讀 secret 的 role 也要有這把 key 的 `kms:Decrypt`；換 key 不會重新加密既有的版本。
- `recovery_window_in_days` 預設 7，不收 `0`。刪除後在還原期內同名的 secret 建不起來；要立刻重建同名 secret，先在 console 還原再刪除，或等還原期過。
- 沒給 `policy_statements` 時不建 resource policy，存取完全由 IAM 決定。policy 一律開 `block_public_policy`，AWS 會拒絕開放給所有人的 policy。`Resource` 固定是這個 secret。
- AWS 在 secret 的 ARN 結尾加 `-` 與 6 個字元。名稱本身以 `-` 加 6 個字元結尾（例如 `-master`）時，用名稱或部分 ARN 找 secret 可能找錯，所以 IAM policy 與 ECS、Lambda 一律用 `arn` 輸出的完整 ARN。
- 輪替 Lambda 要允許 `secretsmanager.amazonaws.com` 呼叫（`lambda-function` 的 `permissions`，`source_arn` 給這個 secret 的 ARN）；Lambda 的 role 要能讀寫這個 secret 與 key。`rotate_immediately = false`（預設）時，設定好輪替後要等到下一次排程才會輪替。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

- secret 的值（`aws_secretsmanager_secret_version`）。
- 跨 region replica。
- managed external rotation（`external_secret_rotation_*`）。
- 輪替 Lambda 本身；用 `lambda-function` 建。
- 任意 JSON 的 resource policy；只收結構化的 statement。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | secret 的名稱，1–512 字元，限英數字與 `/_+=.@-`。以 `-` 加 6 個字元結尾的名稱（例如 `-master`）可以用，但引用時要用完整 ARN，不要用名稱或部分 ARN。 |
| `description` | `string` | `null` | 否 | secret 的說明（預設 `null`）。建議寫明值由誰、在哪裡寫入。 |
| `kms_key_arn` | `string` | `null` | 否 | 加密 secret 的客戶管理 KMS key ARN（symmetric）。`null`（預設）時用 AWS 管理的 `aws/secretsmanager`。只收 key ARN，不收 alias。 |
| `recovery_window_in_days` | `number` | `7` | 否 | 刪除 secret 後可以還原的天數，7–30（預設 7）。不收 `0`，避免刪除後立刻消失、名稱也被釋放。 |
| `policy_statements` | `list(object)` | `[]` | 否 | resource policy 的 statement。空的（預設）就不建 policy，存取完全由 IAM 決定。欄位：`sid`（英數字，不可重複）、`effect`（`Allow` 或 `Deny`）、`principals`（`type` 是 `AWS` 或 `Service`，`identifiers` 至少一個）、`actions`（`secretsmanager:` 開頭）、`conditions`（`test`、`variable`、`values` 的清單，預設 `[]`）。`Resource` 固定是這個 secret。`Allow` 不可給 `secretsmanager:*`；`identifiers` 含 `*` 的 `Allow` 一定要有 condition。policy 一律開 `block_public_policy`。 |
| `rotation` | `object` | `null` | 否 | 輪替設定。`null`（預設）就不設定輪替。欄位：`lambda_arn`（輪替 Lambda 的 function ARN）、`automatically_after_days`（1–1000）或 `schedule_expression`（`rate(...)` 或 `cron(...)`）擇一、`duration`（輪替視窗，`1h`–`24h`，選填）、`rotate_immediately`（設定後是否立刻輪替一次，預設 `false`）。Lambda 的 resource policy 要允許 `secretsmanager.amazonaws.com`（`lambda-function` 的 `permissions`）。 |
| `tags` | `map(string)` | `{}` | 否 | secret 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | secret 的 ARN（含 AWS 加的 6 字元後綴）。IAM policy 與 ECS、Lambda 讀 secret 時用這個。 |
| `name` | secret 的名稱。 |
| `id` | secret 的 ID（等於 ARN）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/secrets-manager-secret
```
