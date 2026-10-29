# backup-vault

建一個 AWS Backup vault，用客戶管理的 KMS key 加密，預設加上 vault policy，禁止任何人刪除 recovery point、改它的生命週期或換掉這份 policy。可以選擇加 vault lock 與事件通知。backup plan 用 `backup-plan` 另外建。

## 用法

```hcl
module "backup_vault" {
  source = "git::https://github.com/<org>/<repo>.git//modules/backup-vault?ref=backup-vault-v0.1.0"

  name        = "alpha-dev-backup"
  kms_key_arn = module.backup_key.key_arn

  lock = {
    min_retention_days = 7
    max_retention_days = 35
  }

  notifications = {
    sns_topic_arn = module.alarm_topic.topic_arn
    events        = ["BACKUP_JOB_COMPLETED", "COPY_JOB_FAILED", "RESTORE_JOB_COMPLETED"]
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | 一律用 `kms_key_arn`（必填），不用 AWS Backup 的預設 key |
| vault policy | `deny_delete_recovery_points = true`（預設）時建立：對所有 principal deny `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy` |
| vault lock | `lock` 不給 `changeable_for_days` 是 governance 模式；給了是 compliance 模式，而且必須 `compliance_acknowledged = true` |
| region | 所有 resource 都帶 `region`，`null` 用 provider 的 region |
| tag | 給定的 `tags` 加上 `Name`（vault 名稱） |

## 注意

- **compliance 模式不可逆**：給了 `changeable_for_days` 就是 compliance 模式。冷卻期（至少 3 天）過後，lock 不能改也不能移除，連 root 與 AWS 都不行；vault 裡還有 recovery point 時，vault 也刪不掉。先用 governance 模式跑一段時間，確定保留天數再改。
- governance 模式下，有 `backup:DeleteBackupVaultLockConfiguration` 權限的人可以移除 lock，擋不住有管理權限的人。
- vault policy 連 `backup:PutBackupVaultAccessPolicy` 都 deny，所以這份 policy 之後改不了（Terraform 的更新也會被擋）；要改只能先用 `backup:DeleteBackupVaultAccessPolicy` 刪掉 policy 再重建。把 `deny_delete_recovery_points` 改成 `false` 走的是刪除，不受影響。
- recovery point 照 backup plan 的生命週期到期時，由 AWS Backup 刪除，不受 vault policy 的 deny 影響。
- `force_destroy = true` 在 vault policy 或 lock 還在時沒有用：recovery point 刪不掉，vault 也就刪不掉。
- 通知的 topic 要在同一個帳號、不能是 FIFO，topic policy 要允許 `backup.amazonaws.com` 發佈（`sns-alarm-topic` 0.2.0 的 `service_publishers`）；topic 用 CMK 時，key policy 也要給同一個服務。
- `events` 的允許清單照 `PutBackupVaultNotifications` API 參考，裡面包含已經不再發送的舊事件，AWS 沒有標出是哪幾個；常用的是 `BACKUP_JOB_COMPLETED`、`COPY_JOB_FAILED`、`RESTORE_JOB_COMPLETED`、`RECOVERY_POINT_MODIFIED`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

logically air-gapped vault、跨帳號的 vault policy（允許其他帳號複製進來）、自訂 vault policy statement、backup plan（用 `backup-plan`）、restore testing、Backup Audit Manager。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | vault 名稱，2–50 字元，限英數字、`_`、`-`。 |
| `kms_key_arn` | `string` | 無 | 是 | 加密 recovery point 用的客戶管理 KMS key ARN（symmetric），必填，不用 AWS Backup 的預設 key。 |
| `force_destroy` | `bool` | `false` | 否 | destroy 時是否連同 vault 裡的 recovery point 一起刪（預設 `false`）。`deny_delete_recovery_points = true` 或有 vault lock 時，recovery point 仍然刪不掉。 |
| `deny_delete_recovery_points` | `bool` | `true` | 否 | 是否建 vault policy，對所有 principal deny `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy`（預設 `true`）。recovery point 仍會照 backup plan 的生命週期到期刪除。 |
| `lock` | `object` | `null` | 否 | vault lock；`null`（預設）不鎖。`min_retention_days`（1 以上）與 `max_retention_days`（36500 以下）至少給一個。不給 `changeable_for_days` 是 governance 模式，有權限的人仍可移除 lock；給了就是 compliance 模式，3–36500 天的冷卻期過後連 root 與 AWS 都改不了、刪不掉，所以要同時寫 `compliance_acknowledged = true`。 |
| `notifications` | `object` | `null` | 否 | vault 事件通知；`null`（預設）不通知。`sns_topic_arn` 是同帳號的 standard topic（不支援 FIFO），topic policy 要允許 `backup.amazonaws.com` 發佈；`events` 至少一個，值照 `PutBackupVaultNotifications` 的清單，例如 `BACKUP_JOB_COMPLETED`、`COPY_JOB_FAILED`、`RESTORE_JOB_COMPLETED`。 |
| `region` | `string` | `null` | 否 | vault 所在的 region；`null`（預設）用 provider 的 region。 |
| `tags` | `map(string)` | `{}` | 否 | vault 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | vault 的 ARN（`backup-plan` 跨 vault 複製時的 `copy_to.vault_arn`）。 |
| `name` | vault 的名稱（`backup-plan` 的 `vault_name`）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/backup-vault
```
