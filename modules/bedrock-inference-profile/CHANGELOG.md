# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 每個 `profiles` 建立一個 `aws_bedrock_inference_profile`，名稱 `<name_prefix>-<key>`，`model_source.copy_from` 與 `description` 照輸入，`tags` 套用到每個 profile。
- `profiles` 必填但可以是 `{}`，空 map 時什麼都不建。
- 擋下：名稱超過 64 字、名稱含 AWS 文件規則以外的字元（未實測）、`copy_from` 不是 `foundation-model` 或 `inference-profile` 的 ARN（含 `provisioned-model`、`application-inference-profile` 與只給 model id）。
- 輸出 `arns`、`ids`。
- aws provider 下限是 6.69。
- 不管模型使用權、provisioned throughput，不建 IAM。
