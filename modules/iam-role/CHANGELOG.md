# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 IAM role：trust policy 只收 AWS 服務主體，可加 `aws:SourceAccount` 條件；inline policy 以 `map(string)`（JSON 字串）傳入，一個 entry 一個 `aws_iam_role_policy`。
- 輸出 `arn`、`name`、`id`；`arn` 在所有 inline policy 附加之後才有值。
- 輸入檢查：`name` 格式與長度、trust 格式、policy 必須是含非空 `Statement` 清單的 JSON、Allow statement 不可用 `*` 或 `service:*` 動作（Deny 不受限）。
- 不收 AWS managed policy 與 customer managed policy。
