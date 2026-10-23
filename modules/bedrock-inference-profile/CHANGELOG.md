# Changelog

## [0.1.2](https://github.com/libterty/infra-platform/compare/bedrock-inference-profile-v0.1.1...bedrock-inference-profile-v0.1.2) (2026-10-23)


### Bug Fixes

* **bedrock-inference-profile:** rewrite the input and output descriptions in Chinese ([306d7cb](https://github.com/libterty/infra-platform/commit/306d7cb4ea39b4aa093b89ddaa0f168560b68a07))

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 每個 `profiles` 建立一個 `aws_bedrock_inference_profile`，名稱 `<name_prefix>-<key>`，`model_source.copy_from` 與 `description` 照輸入，`tags` 套用到每個 profile，另外自動加 `Name`（值是 profile 名稱，跟其他 module 一致）。
- `profiles` 必填但可以是 `{}`，空 map 時什麼都不建。
- 擋下：名稱超過 64 字、名稱含 AWS 文件規則以外的字元（未實測）、`copy_from` 不是 `foundation-model` 或 `inference-profile` 的 ARN（含 `provisioned-model`、`application-inference-profile` 與只給 model id）。
- `copy_from` 的 ARN 最後一段只收 `[A-Za-z0-9._:-]`，含 `*` 的 ARN 被擋；`inference-profile` 的 `copy_from` 必須在目前的帳號（profile resource 的 precondition），foundation-model ARN 不受影響。
- 輸出 `arns`、`ids`。
- aws provider 下限是 6.69。
- 不管模型使用權、provisioned throughput，不建 IAM。
