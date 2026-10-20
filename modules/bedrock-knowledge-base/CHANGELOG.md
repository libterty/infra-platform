# Changelog

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_bedrockagent_knowledge_base`：`VECTOR` 型，向量儲存只收 Aurora PostgreSQL（`storage_configuration.type = "RDS"`），`dimensions` 照 `embedding_dimensions`。
- `field_mapping` 預設 `id`／`embedding`／`chunks`／`metadata`，`custom_metadata_field` 預設不送。
- 每個 `data_sources` 建立一個 S3 data source，名稱是 map 的 key；`data_deletion_policy` 預設 `RETAIN`；chunking 預設 `FIXED_SIZE`（300 token、重疊 20%），`NONE` 時不送 fixed size 設定。
- `kms_key_arn` 有給時套到每個 data source 的 server-side encryption。
- 擋下：`cluster_arn` 不是 Aurora cluster ARN（含 DB instance ARN）、`credentials_secret_arn` 不是 Secrets Manager ARN、資料庫名稱／表名／欄位名不是小寫識別字或表名超過兩段、欄位名重複、`embedding_dimensions` 不是正整數、嵌入模型不是 foundation-model ARN（含 inference profile）、chunking 不是 `FIXED_SIZE`／`NONE`、`max_tokens` 不大於 0、`overlap_percentage` 不在 1–99、`data_deletion_policy` 不是 `RETAIN`／`DELETE`、prefix 以 `/` 開頭、bucket ARN 格式錯、名稱不合規則。
- `data_sources[*].bucket_owner_account_id` 改為必填（12 位數字），必須等於目前的帳號或列在新增的 `allowed_account_ids`（預設 `[]`）；原本不給的呼叫端要補上這個欄位。
- `aurora.cluster_arn`、`aurora.credentials_secret_arn` 必須在目前的帳號與 region（KB resource 的 precondition）。
- `aurora.credentials_secret_arn` 只收完整 secret ARN（含 6 字元尾碼、不含 `*`）；`role_arn` 的 path 不能有空的一段；`embedding_model_arn` 不能含 `*`；`kms_key_arn` 只收 `key/<uuid>` 形式的 KMS key ARN。
- 輸出 `knowledge_base_id`、`knowledge_base_arn`、`data_source_ids`。
- 不建 IAM、不建語料 bucket、不建資料庫帳號與 secret、不跑 ingestion。
