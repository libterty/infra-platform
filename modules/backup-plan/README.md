# backup-plan

建一個 AWS Backup plan 與一個用 tag 選資源的 selection。資源要被備份，就在資源上加 `selection_tags` 裡的 tag（範本用 `backup = "daily"`），不必改應用範本的 module 呼叫。vault 用 `backup-vault` 另外建。

## 用法

```hcl
module "backup_plan" {
  source = "git::https://github.com/<org>/<repo>.git//modules/backup-plan?ref=backup-plan-v0.1.0"

  name       = "alpha-dev-daily"
  vault_name = module.backup_vault.name
  role_arn   = module.backup_role.role_arn

  rules = {
    daily = {
      schedule          = "cron(0 18 * * ? *)"
      delete_after_days = 35
    }
  }

  selection_tags = {
    backup = "daily"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 選資源 | 只用 tag，條件是 `STRINGEQUALS`；`selection_tags` 有多個時，符合任一個就會被備份 |
| selection 名稱 | 跟 plan 同名 |
| 冷儲存 | `delete_after_days` 至少是 `cold_storage_after_days` + 90 |
| continuous backup | `delete_after_days` 必填且不超過 35 |
| region | 所有 resource 都帶 `region`，`null` 用 provider 的 region |
| tag | plan 加上 `Name`；selection 不支援 tag |

## 注意

- `schedule` 是 UTC。`cron(0 18 * * ? *)` 是台北時間每天凌晨 2 點。
- AWS 規定冷儲存的 recovery point 至少要放 90 天，所以 `delete_after_days` 要比 `cold_storage_after_days` 多 90 天以上。冷儲存只支援部分資源類型（例如 EFS、DynamoDB 進階功能），不支援的資源會忽略這個設定。
- continuous backup（point-in-time recovery）最多保留 35 天，也不支援冷儲存。只有部分資源類型支援（例如 RDS、Aurora、S3），其他資源照 `schedule` 做一般備份。
- `role_arn` 的 role 要信任 `backup.amazonaws.com`，通常掛 AWS managed policy `AWSBackupServiceRolePolicyForBackup` 與 `AWSBackupServiceRolePolicyForRestores`；S3 另外要 `AWSBackupServiceRolePolicyForS3Backup`。module 不建 role。
- 資源用 CMK 加密時，role 要能用那把 key；跨 vault 複製時，目的 vault 的 key 也一樣。
- `copy_to` 跨 region 或跨帳號時，目的 vault 要先建好；跨帳號還要 Organizations 的設定與目的 vault 的 access policy，這個 module 不處理。
- `region` 要跟 `vault_name` 的 vault 相同。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

用 ARN 選資源、`not_resources` 與 `condition` 區塊、restore testing、report plan、Backup Audit Manager framework、`advanced_backup_setting`（Windows VSS）、logically air-gapped vault、malware scan。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | backup plan 的名稱，也是 selection 的名稱，1–50 字元，限英數字、`_`、`-`、`.`。 |
| `vault_name` | `string` | 無 | 是 | 備份存放的 vault 名稱（`backup-vault` 的 `name` 輸出），不是 ARN。 |
| `role_arn` | `string` | 無 | 是 | AWS Backup 備份與複製時用的 IAM role ARN，信任 `backup.amazonaws.com`。module 不建 role，在 `iam` stack 用 `iam-role` 建。 |
| `rules` | `map(object)` | 無 | 是 | 備份規則，至少一個，key 是規則名稱（1–50 字元，限英數字、`_`、`-`、`.`）。`schedule` 是 `cron(...)`（UTC）；`start_window_minutes`、`completion_window_minutes` 不給用 AWS 的預設；`delete_after_days` 不給就不刪；`cold_storage_after_days` 有值時 `delete_after_days` 至少要再多 90 天；`enable_continuous_backup = true` 時 `delete_after_days` 必填且 1–35（加上冷儲存的 90 天規定，等於不能搭配冷儲存）；`copy_to` 把每份備份複製到另一個 vault（`vault_arn`），`delete_after_days` 是副本的保留天數。 |
| `selection_tags` | `map(string)` | 無 | 是 | 用 tag 選要備份的資源，key 是 tag key、value 是 tag 值（完全相等），至少一個。給多個時，符合任一個 tag 的資源都會被備份。範本用 `{ backup = "daily" }`。 |
| `region` | `string` | `null` | 否 | backup plan 所在的 region，要跟 `vault_name` 的 vault 相同；`null`（預設）用 provider 的 region。 |
| `tags` | `map(string)` | `{}` | 否 | backup plan 的 tag；`Name` 由 module 加上。這些 tag 不會加到 recovery point。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `plan_id` | backup plan 的 ID。 |
| `plan_arn` | backup plan 的 ARN。 |
| `selection_id` | 用 tag 選資源的 selection ID。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/backup-plan
```
