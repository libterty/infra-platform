# log-group

建一個 CloudWatch log group，可以選擇加上 KMS 加密和一個 subscription filter。用在 Lambda、應用程式自訂 log，以及範本 stack 需要的 log。`ecs-service`、`rds` 的 log group 還是由它們自己建，不改成呼叫這個 module。

## 用法

```hcl
module "worker_logs" {
  source = "git::https://github.com/<org>/<repo>.git//modules/log-group?ref=log-group-v0.1.0"

  name           = "/alpha/dev/worker"
  retention_days = 90
  kms_key_arn    = data.aws_ssm_parameter.kms_key_arn.insecure_value

  tags = {
    Project = "alpha"
  }
}
```

完整範例（含 Firehose 訂閱）見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- **保留天數不接受 0（永不過期）**，也不接受 CloudWatch Logs 不支援的值（例如 2）。
- 用 `kms_key_arn` 時，key policy 必須允許 `logs.<region>.amazonaws.com`，否則 log group 建不起來。
- `subscription.destination_arn` 可以是 Lambda、Kinesis、Firehose 或 logs destination。Kinesis 與 Firehose 一定要給 `role_arn`；這個 module 不建 IAM，role 請用 `iam-role` 建好再傳進來。
- 目的地是 Lambda 時，需要 `aws_lambda_permission` 允許 `logs.amazonaws.com` 呼叫。這個 permission 不在這個 module 建，由擁有那支 Lambda 的 stack 建。
- `filter_pattern` 為空字串時轉送所有事件。
- subscription filter 的名稱跟 log group 名稱相同。

## 刻意不做

- 永不過期（`retention_days = 0`）、`INFREQUENT_ACCESS` log class。
- 一個 log group 掛多個 subscription filter。
- 建立訂閱目的地本身。
- 建 IAM；Kinesis、Firehose 的 role 由 `iam-role` 建。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | log group 名稱，1–512 字元，限英數字與 `_`、`.`、`/`、`#`、`-`，不可以 `aws/` 開頭。 |
| `retention_days` | `number` | `30` | 否 | 保留天數，只接受 CloudWatch Logs 允許的值：`1`、`3`、`5`、`7`、`14`、`30`、`60`、`90`、`120`、`150`、`180`、`365`、`400`、`545`、`731`、`1096`、`1827`、`2192`、`2557`、`2922`、`3288`、`3653`。不接受 `0`（永不過期）。 |
| `kms_key_arn` | `string` | `null` | 否 | 自管 KMS key 的 ARN，`null` 時用 CloudWatch Logs 預設加密。key policy 要允許 `logs.<region>.amazonaws.com`。 |
| `subscription` | `object` | `null` | 否 | 選用的 subscription filter，`null` 時不建。欄位：`destination_arn`（必填，Lambda、Kinesis、Firehose 或 logs destination 的 ARN）、`filter_pattern`（預設 `""`，空字串時轉送所有事件）、`role_arn`（目的地是 Kinesis、Firehose 時必填）。 |
| `tags` | `map(string)` | `{}` | 否 | log group 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | log group 名稱。 |
| `arn` | log group ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/log-group
```
