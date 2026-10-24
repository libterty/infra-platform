# Changelog

## [0.1.1](https://github.com/libterty/infra-platform/compare/lambda-function-v0.1.0...lambda-function-v0.1.1) (2026-10-23)


### Bug Fixes

* **lambda-function:** rewrite the input and output descriptions in Chinese ([c0000ac](https://github.com/libterty/infra-platform/commit/c0000acae2e242e00248061d2f456707bf177583))

## 0.1.0（2026-10-20）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 只支援 container image（`package_type = "Image"`），不設 `handler`、`runtime`、zip 相關參數。
- `image_uri` 只收 ECR，要有 tag 或 sha256 digest，拒絕 `:latest`（大小寫不拘）。
- 預設 `arm64`、512 MB、30 秒；`architectures` 必須剛好一個。
- module 自己建 log group `/aws/lambda/<name>`（預設保留 30 天，不接受 0，可選 KMS），`logging_config` 指到它；`log_format` 預設 `Text`，可選 `JSON`。
- `environment` 名稱像 secret（`SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`、`PRIVATE_KEY`、`CREDENTIAL`）會被拒，除非名稱以 `_ARN` 結尾且值是 ARN，檢查邏輯與 `agentcore-runtime` 相同；名稱另外必須是合法的環境變數名稱。
- `vpc` 可選，給了就至少要有一個 subnet 與一個 security group。
- `permissions`：每個項目建一個 `aws_lambda_permission`。`principal` 必須是 `*.amazonaws.com` 的 AWS 服務；`source_arn` 必填；`principal` 是 `s3.amazonaws.com` 時 `source_account` 必填（bucket ARN 沒有帳號，避免 confused deputy）；`action` 預設 `lambda:InvokeFunction`，不接受萬用字元。
- 輸出 `function_name`、`function_arn`、`invoke_arn`、`log_group_name`；`function_arn` 有 `depends_on` 所有 permission，下游的 S3 notification 因此會在授權之後才建。
- 不建 IAM role、不支援 zip 套件、layer、alias、版本、function URL、dead letter queue、EFS、event source mapping。
