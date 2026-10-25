# sagemaker-pipeline

建一個 SageMaker Pipeline（訓練與註冊模型的流程）。definition 是 commit 在 repo 裡的 JSON 字串，跟著 PR 審查；module 不從 S3 讀，也不啟動執行。

## 用法

```hcl
module "train" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sagemaker-pipeline?ref=sagemaker-pipeline-v0.1.0"

  name               = "alpha-dev-train"
  definition         = file("${path.module}/pipelines/train.json")
  role_arn           = module.role_sagemaker_pipeline.arn
  max_parallel_steps = 2
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| definition 來源 | `pipeline_definition` 字串，沒有 `pipeline_definition_s3_location` |
| definition 檢查 | 合法 JSON，有 `Version` 與非空的 `Steps`；其他內容由 SageMaker 在 apply 時檢查 |
| 顯示名稱 | `display_name` 沒給就用 `name` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- definition 通常由 SageMaker Python SDK 的 `pipeline.definition()` 匯出。module 只檢查 JSON 的外形，step 的參數錯了要到 apply 才會被 SageMaker 擋下。
- definition 裡的 role、image、S3 路徑、KMS key 都是寫死在 JSON 裡的值，換環境要換一份檔案或在匯出時帶入；module 不做字串替換。
- `role_arn` 要能 `iam:PassRole` 給 definition 裡各 step 用的 role（通常是同一個），並能讀寫 definition 用到的 S3 與 KMS key；這個 module 不建 IAM。
- pipeline 的執行由 `scheduler-schedule` 或人觸發，這個 module 不啟動執行。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

從 S3 讀 definition、執行 pipeline、definition 的字串替換、pipeline 的 experiment 設定。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | pipeline 名稱，1–256 字元，限英數字與 `-`，開頭結尾是英數字。 |
| `definition` | `string` | 無 | 是 | pipeline definition 的 JSON 字串（SageMaker Python SDK 的 `pipeline.definition()` 匯出後 commit，範本用 `file()` 讀），要有 `Version` 與至少一個 `Steps`。module 原樣傳給 SageMaker，不從 S3 讀。 |
| `role_arn` | `string` | 無 | 是 | pipeline 執行用的 IAM role ARN（module 不建 role）。 |
| `display_name` | `string` | `null` | 否 | 在 SageMaker Studio 顯示的名稱，規則同 `name`；`null` 就用 `name`。 |
| `description` | `string` | `null` | 否 | pipeline 的說明，最多 3072 字元；`null` 不設。 |
| `max_parallel_steps` | `number` | `null` | 否 | 同一次執行最多同時跑幾個 step，至少 1；`null` 不設（用 SageMaker 的預設）。 |
| `tags` | `map(string)` | `{}` | 否 | pipeline 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `pipeline_name` | pipeline 名稱。 |
| `pipeline_arn` | pipeline 的 ARN，給 `scheduler-schedule` 的 target 用。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/sagemaker-pipeline
```
