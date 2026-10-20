# lambda-function

建一個 container image 的 Lambda function，加上它自己的 log group 與呼叫授權（`aws_lambda_permission`）。只支援 ECR 的 image，不支援 zip 套件。

## 用法

```hcl
module "worker" {
  source = "git::https://github.com/<org>/<repo>.git//modules/lambda-function?ref=lambda-function-v0.1.0"

  name      = "alpha-dev-worker"
  image_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha/worker:v1.0.0"
  role_arn  = module.worker_role.role_arn

  environment = {
    LOG_LEVEL     = "info"
    DB_SECRET_ARN = module.db.secret_arn
  }

  permissions = {
    s3_upload = {
      principal      = "s3.amazonaws.com"
      source_arn     = module.uploads.bucket_arn
      source_account = "111111111111"
    }
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例（含 VPC 與 S3 notification）見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- **image 要有明確的 tag 或 digest，拒絕 `:latest`。** 換版就改 `image_uri` 再 apply，tag 由 Terraform 管。只收 ECR（`<account>.dkr.ecr.<region>.amazonaws.com/...`）。
- `architectures` 必須跟 image 建置的架構一致，預設 `arm64`；不一致時 function 建得起來，但執行會失敗。
- **`environment` 不放 secret。** 名稱像 secret（`SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`、`PRIVATE_KEY`、`CREDENTIAL`）會被拒；環境變數會存在 state 與 control plane。要傳 secret，放 Secrets Manager，只傳 ARN，名稱以 `_ARN` 結尾（例如 `DB_SECRET_ARN`），function 自己在執行時讀。名稱開頭必須是字母。
- **`permissions` 必填 `source_arn`**，不能只給 principal 就讓整個服務都能呼叫。`principal` 必須是 `*.amazonaws.com`（例如 `s3.amazonaws.com`、`events.amazonaws.com`）。`s3.amazonaws.com` **一定要給 `source_account`**：bucket ARN 沒有帳號，少了它，別的帳號建同名 bucket 也能呼叫（confused deputy）。key 是 statement id。
- **下游資源請用 `function_arn` 輸出**（不要自己拼 ARN）。它 `depends_on` 所有 permission，`aws_s3_bucket_notification` 這類資源因此會在授權建好之後才建；順序錯了 S3 會回 `Unable to validate the following destination configurations`。
- log group 由 module 建，名稱 `/aws/lambda/<name>`，預設保留 30 天，不接受 0（永不過期）。用 `log_kms_key_arn` 時，key policy 必須允許 `logs.<region>.amazonaws.com`。execution role 需要對這個 log group 的寫入權限（用 `iam-role` 建）。
- 給 `vpc` 時，execution role 需要建立 network interface 的權限，subnet 要有路徑到 Lambda 要連的服務（NAT 或 VPC endpoint）。
- `reserved_concurrent_executions` 預設 `null`（不保留）；`0` 會讓 function 完全不能被呼叫。
- `log_format = "JSON"` 時，runtime 與 Lambda 自己的訊息會以 JSON 輸出；沒有設定 `application_log_level`、`system_log_level`。

## 刻意不做

- zip 套件（`handler`、`runtime`、`filename`、`s3_bucket`）、layer。
- alias、版本發佈、function URL、dead letter queue、EFS、event source mapping。
- IAM role；用 `iam-role` 建。
- S3 notification、EventBridge rule 等觸發來源；由呼叫端建，並使用 `function_arn`。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | function 名稱，小寫英數字與連字號，2–64 字元 |
| `image_uri` | `string` | 無 | 是 | ECR image，要有 tag（不可 `latest`）或 sha256 digest |
| `role_arn` | `string` | 無 | 是 | execution role 的 ARN |
| `architectures` | `list(string)` | `["arm64"]` | 否 | 剛好一個：`arm64` 或 `x86_64` |
| `memory_size` | `number` | `512` | 否 | MB，128 到 10240 的整數 |
| `timeout` | `number` | `30` | 否 | 秒，1 到 900 的整數 |
| `reserved_concurrent_executions` | `number` | `null` | 否 | 保留的並行數；`null` 不保留，`0` 停用 |
| `environment` | `map(string)` | `{}` | 否 | 環境變數；名稱像 secret 的會被拒，除非名稱以 `_ARN` 結尾且值是 ARN |
| `vpc` | `object` | `null` | 否 | `subnet_ids`、`security_group_ids`，各至少一個；`null` 不進 VPC |
| `log_retention_days` | `number` | `30` | 否 | log group 保留天數，不接受 0 |
| `log_kms_key_arn` | `string` | `null` | 否 | log group 的 KMS key ARN（`key/<id>`，不接受 alias） |
| `log_format` | `string` | `"Text"` | 否 | `Text` 或 `JSON` |
| `permissions` | `map(object)` | `{}` | 否 | statement id 對應 `principal`（`*.amazonaws.com`）、`source_arn`（必填）、`source_account`（`s3.amazonaws.com` 必填）、`action`（`lambda:InvokeFunction`） |
| `tags` | `map(string)` | `{}` | 否 | function 與 log group 的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `function_name` | `string` | function 名稱 |
| `function_arn` | `string` | function ARN；等所有 permission 建好才可用 |
| `invoke_arn` | `string` | invoke ARN，給 API Gateway 整合用 |
| `log_group_name` | `string` | module 建的 log group 名稱 |

## 測試

```bash
scripts/validate.sh modules/lambda-function
```
