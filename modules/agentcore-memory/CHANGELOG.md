# Changelog

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_bedrockagentcore_memory`，名稱照 `name`，`event_expiry_duration` 照 `event_expiry_days`（預設 90），`encryption_key_arn` 照 `kms_key_arn`（預設 null，用 AWS 管的 key），tag 只多加 `Name`。
- 每個 `strategies` 建立一個 `aws_bedrockagentcore_memory_strategy`，名稱是 map 的 key，`memory_id` 指向這個 Memory，`namespaces` 送進 provider 的 `namespace_templates`；不送 `configuration` 與 `memory_execution_role_arn`。`strategies` 預設 `{}`，只有短期記憶。
- 擋下：名稱或 strategy key 不是字母開頭、含字母數字底線以外的字元或超過 48 字；`event_expiry_days` 不是 7–365 的整數；strategy 型別不是 `SEMANTIC`、`SUMMARIZATION`、`USER_PREFERENCE`；strategy 沒有 namespace 或 namespace 不以 `/` 開頭；`kms_key_arn` 不是 `key/<uuid>` 形式的 KMS key ARN（alias、`*` 都擋）。
- 輸出 `memory_id`、`memory_arn`、`strategy_ids`。
- 不做 `CUSTOM` 與 self-managed strategy、Memory execution role、Kinesis stream delivery、`indexed_key`、log 與 trace delivery，不建 IAM。
