# sagemaker-model-registry

建一個 SageMaker Model Registry 的 model package group，訓練 pipeline 把模型版本註冊進來，人工核准後才部署。可以選擇加一份唯讀的 resource policy，讓其他帳號讀這個 group 的模型版本並從它建 model。

## 用法

```hcl
module "registry" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sagemaker-model-registry?ref=sagemaker-model-registry-v0.1.0"

  name        = "alpha-dev-detector"
  description = "Defect detector models"

  cross_account_read_principals = ["arn:aws:iam::222222222222:role/alpha-sit-inference"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| resource policy | `cross_account_read_principals` 空的就不建；有值時只給讀取與建 model 的動作，不給 `UpdateModelPackage`（核准）、`CreateModelPackage`、刪除 |
| policy 的 Resource | group 本身與 `model-package/<group>/*`，沒有 `*` |
| principal | 帳號 ID 轉成 `arn:<partition>:iam::<id>:root`，role ARN 原樣放入；不收 `*` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- 新註冊的模型版本預設是 `PendingManualApproval`，改成 `Approved` 是人的動作，這個 module 不管核准。
- 對方帳號除了這份 resource policy，自己的 role 也要有對應的 `sagemaker:*` 權限；模型 artifact 放在 S3 且用 CMK 加密時，bucket policy 與 key policy 也要讓對方讀，這個 module 不管。
- `sagemaker:CreateModel` 是為了讓對方從 model package 建 model（部署時需要），不會改到這個 group 的內容。
- model package group 沒有加密設定；模型 artifact 的加密由 pipeline 寫入 S3 時決定。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

model package 本身（由 pipeline 註冊）、核准、model card、RAM 分享、寫入權限的跨帳號 policy。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | model package group 名稱，1–63 字元，限英數字與 `-`，開頭結尾是英數字。 |
| `description` | `string` | `null` | 否 | model package group 的說明，最多 1024 字元；`null` 不設。 |
| `cross_account_read_principals` | `list(string)` | `[]` | 否 | 可以唯讀這個 group 的其他帳號：12 位數帳號 ID（轉成 `arn:<partition>:iam::<id>:root`）或 IAM role ARN。有值時建 resource policy，只給 `sagemaker:DescribeModelPackageGroup`、`sagemaker:DescribeModelPackage`、`sagemaker:ListModelPackages` 與 `sagemaker:CreateModel`（讓對方從 model package 建 model）；空的就不建。不收 `*`。 |
| `tags` | `map(string)` | `{}` | 否 | model package group 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `name` | model package group 名稱。 |
| `arn` | model package group 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/sagemaker-model-registry
```
