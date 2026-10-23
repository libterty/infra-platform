# kms-key

建一把對稱式 customer managed key（CMK），連同它的 key policy 與 alias。專案共用的那把 key 由 `foundation` stack 呼叫這個 module 一次建立。

## 用法

```hcl
module "key" {
  source = "git::https://github.com/<org>/<repo>.git//modules/kms-key?ref=kms-key-v0.1.0"

  name        = "alpha-dev"
  description = "alpha dev shared key"

  service_principals = {
    "logs.ap-northeast-1.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"]
      }]
    }
    "cloudwatch.amazonaws.com" = {}
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## key policy 的組成

policy 由三種 statement 依序串成，一律用 `jsonencode` 產生：

1. 帳號 root：`arn:aws:iam::<account>:root` 取得 `kms:*`。永遠是第一段，不能移除；少了它，IAM policy 就沒辦法再授權這把 key，這把 key 可能變成沒人管得了。
2. 管理者：`administrator_arns` 有給才有。只給管理動作（建立、停用、輪替、排程刪除等），不含 `Encrypt`、`Decrypt`、`GenerateDataKey*`。
3. 服務：每個 `service_principals` 一段，`Resource = "*"`（key policy 裡的 `*` 指這把 key 本身）。預設動作是 `kms:Decrypt`、`kms:GenerateDataKey*`、`kms:DescribeKey`。

## 注意

- key policy 是 resource policy，不是 IAM 資源，所以這個 module 不建任何 `aws_iam_*`。
- 服務 principal 必須以 `.amazonaws.com` 結尾；動作不可給 `*` 或 `kms:*`；管理者必須是 IAM role 或 user ARN，且不可含萬用字元。
- 每個 AWS 服務接受的條件 key 都不一樣。這個 module 只把你給的條件原樣寫進 policy，**沒有在實際環境驗證過**。`rds`、`secretsmanager` 這類服務通常靠 `kms:ViaService` 走 IAM 授權就夠了，要不要放進 key policy，看實測結果決定。
- `deletion_window_in_days` 預設 30，範圍 7–30。key 刪除後，所有用它加密的資料都無法再解密。

## 刻意不做

非對稱 key、multi-region key、外部金鑰材料、grant 管理、對 `*` principal 開放。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | alias 名稱，不含 `alias/` 前綴。1–250 字元，限英數字、`/`、`_`、`-`，不可以 `aws/` 開頭。 |
| `description` | `string` | `null` | 否 | key 的說明。 |
| `deletion_window_in_days` | `number` | `30` | 否 | 刪除 key 前的等待天數，7–30。 |
| `administrator_arns` | `list(string)` | `[]` | 否 | 額外的 key 管理者，限 IAM role 或 user ARN，不可含萬用字元。帳號 root 一律是管理者，不用列。 |
| `service_principals` | `map(object)` | `{}` | 否 | 服務 principal（例如 `logs.ap-northeast-1.amazonaws.com`，必須以 `.amazonaws.com` 結尾）對應它在這把 key 上的權限。欄位：`actions`（預設 `kms:Decrypt`、`kms:GenerateDataKey*`、`kms:DescribeKey`，不可給 `*` 或 `kms:*`）、`conditions`（`test`、`variable`、`values` 的清單，預設 `[]`）。 |
| `tags` | `map(string)` | `{}` | 否 | key 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `key_arn` | key 的 ARN。 |
| `key_id` | key 的 ID。 |
| `alias_name` | alias 名稱，格式 `alias/<name>`。 |
| `alias_arn` | alias 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/kms-key
```
