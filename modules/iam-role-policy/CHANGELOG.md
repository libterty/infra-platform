# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/iam-role-policy-v0.1.0...iam-role-policy-v0.1.1) (2026-10-23)


### Bug Fixes

* **iam-role-policy:** rewrite the input and output descriptions in Chinese ([bcd8904](https://github.com/libterty/infra-platform/commit/bcd890447fe6e7769512b110421435daf8e9da8d))

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 對一個已存在的 role 附加 inline policy，一個 entry 一個 `aws_iam_role_policy`；role 名稱取自 `role_arn` 的最後一段。
- 輸出 `policy_names`、`role_name`。
- 輸入檢查：`role_arn` 必須是不帶 path 的 role ARN、`policies` 不可為空、policy 必須是含非空 `Statement` 清單的 JSON、Allow statement 不可用 `*` 或 `service:*` 動作，也不可帶 `NotAction` 或 `NotResource`（Deny 不受限）。
- 「禁止萬用動作」的檢查與 `iam-role` 逐字相同。
