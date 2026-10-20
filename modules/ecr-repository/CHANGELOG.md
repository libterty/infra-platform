# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 ECR repository 與它的 lifecycle policy。
- 固定行為：`image_tag_mutability = "IMMUTABLE"`、`scan_on_push = true`、`force_delete = false`，不開放設定。
- lifecycle：未加 tag 的映像 7 天後刪除，有 tag 的保留 50 個，兩個值可由 `lifecycle_rules` 覆寫。
- `kms_key_arn` 為 null 時用 `AES256`，有給時用 `KMS`。
- 輸出 `repository_url`、`arn`、`name`、`registry_id`。
- 輸入檢查：`name` 須為合法的 ECR repository 名稱、`lifecycle_rules` 的兩個值至少為 1。
