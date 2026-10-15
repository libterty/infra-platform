# ecr-repository

建立一個 ECR repository 與它的 lifecycle policy。一次呼叫一個 repository，多個服務就用 `for_each` 呼叫多次。

## 用法

```hcl
module "ecr" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ecr-repository?ref=ecr-repository-v0.1.0"

  name        = "alpha-dev-api"
  kms_key_arn = module.kms.key_arn # 可選，不給就用 AES256
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

這三項不開放設定：

| 項目 | 值 | 理由 |
|---|---|---|
| `image_tag_mutability` | `IMMUTABLE` | 同一個 tag 不能被覆蓋，部署才可追溯 |
| `scan_on_push` | `true` | 推送時掃描 |
| `force_delete` | `false` | 還有映像時 destroy 會失敗，不會連映像一起刪 |

lifecycle policy 兩條規則：

1. 優先序 1：未加 tag 的映像，推送超過 `untagged_expire_days` 天（預設 7）就刪除。
2. 優先序 2：`tagStatus = "any"`，超過 `keep_count` 個（預設 50）就刪掉較舊的。

第二條用 `any` 而不是 `tagged`，因為 ECR 的 `tagged` 規則必須搭配 tag 前綴或樣式。

## 限制

- 已存在的 repository 改 `kms_key_arn`（加密設定）會讓 repository 重建，映像會跟著消失。這屬於 MAJOR 等級的變更，要先把映像搬走。
- 因為 tag 不可變，同一個 tag 不能重推；重新部署要換新的 tag。
- 不支援 repository policy（跨帳號拉映像）、replication、pull-through cache、enhanced scanning（Inspector）。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 完整 repository 名稱，2–256 字元；小寫字母、數字，以 `.`、`_`、`-` 分隔，可用 `/` 分層 |
| `kms_key_arn` | `string` | `null` | 否 | 加密用的客戶管理金鑰；`null` 用 `AES256` |
| `lifecycle_rules` | `object({ untagged_expire_days = optional(number, 7), keep_count = optional(number, 50) })` | `{}` | 否 | 兩個值都須至少為 1 |
| `tags` | `map(string)` | `{}` | 否 | 額外 tag，module 只另外加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `repository_url` | `string` | repository URL，不含 tag |
| `arn` | `string` | repository ARN |
| `name` | `string` | repository 名稱 |
| `registry_id` | `string` | registry 所屬的帳號 ID |

## 測試

```bash
scripts/validate.sh modules/ecr-repository
```
