# Changelog

## [0.3.0](https://github.com/libterty/infra-platform/compare/iam-role-v0.2.0...iam-role-v0.3.0) (2026-10-21)


### Features

* **iam-role:** allow allowlisted managed policies and Pod Identity and IRSA trust ([a8d45ee](https://github.com/libterty/infra-platform/commit/a8d45ee623970380bea994f1a127db3fa956b64d))

## 0.2.0（2026-10-20）

新增功能，升 MINOR。tag 在驗收後由人手動打。

- 新增選填變數 `instance_profile_name`（預設 `null`）：有給時建一個 `aws_iam_instance_profile`，綁這個 role；沒給就不建。格式 `^[\w+=,.@-]{1,128}$`，不合法由 validation 擋下。
- 新增輸出 `instance_profile_name`、`instance_profile_arn`；沒建 instance profile 時為 `null`。
- 沒給 `instance_profile_name` 的既有呼叫端，resource 與既有輸出都沒有變化，換版應該零差異。**這是測試與讀程式推論的，沒有用 plan 驗證。**

## 0.1.1（2026-10-16）

新增功能，照 semver 表本該升 MINOR；這一版照使用者決定（比照 design 決策 54）用 `0.1.1`，在驗收後手動打 tag，release-please 不會產生這一段。之後的版本照 semver 表。

- `trust` 新增選填欄位 `source_arn`：有給時，在同一段 trust statement 加 `ArnLike` 的 `aws:SourceArn` 條件，可含萬用字元（例如 `arn:aws:bedrock:<region>:<account>:knowledge-base/*`）。跟 `source_account` 可以同時給，兩個條件在同一段 statement。
- `source_arn` 必須以 `arn:` 開頭、不含空白，否則 validation 擋下。
- 沒給 `source_arn` 的既有呼叫端，trust policy JSON 與 0.1.0 逐字相同（測試 `source_account_only_policy_unchanged` 固定了整段字串），換版應該零差異。**這是測試與讀程式推論的，沒有用 plan 驗證。**

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 IAM role：trust policy 只收 AWS 服務主體，可加 `aws:SourceAccount` 條件；inline policy 以 `map(string)`（JSON 字串）傳入，一個 entry 一個 `aws_iam_role_policy`。
- 輸出 `arn`、`name`、`id`；`arn` 在所有 inline policy 附加之後才有值。
- 輸入檢查：`name` 格式與長度、trust 格式、policy 必須是含非空 `Statement` 清單的 JSON、Allow statement 不可用 `*` 或 `service:*` 動作，也不可帶 `NotAction` 或 `NotResource`（Deny 不受限）。
- 不收 AWS managed policy 與 customer managed policy。
