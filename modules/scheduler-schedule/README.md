# scheduler-schedule

用 EventBridge Scheduler 建一組排程：每個排程有自己的運算式（`cron`、`rate`、`at`）、時區、flexible window 與 target，可以選擇放進 module 建的 schedule group。target 是 SageMaker pipeline 時可以帶 pipeline 參數。排程資料一律用客戶管理的 KMS key 加密。

## 用法

```hcl
module "retrain" {
  source = "git::https://github.com/<org>/<repo>.git//modules/scheduler-schedule?ref=scheduler-schedule-v0.1.0"

  kms_key_arn = module.key.key_arn
  group_name  = "alpha-dev-ml"

  schedules = {
    alpha-dev-retrain = {
      expression = "cron(0 3 ? * MON *)"
      state      = "DISABLED"
      target = {
        arn      = module.train_pipeline.pipeline_arn
        role_arn = module.scheduler_role.role_arn
        sagemaker_pipeline_parameters = {
          InputPrefix = "s3://alpha-dev-ml-artifacts/datasets/"
        }
      }
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | 每個排程都用 `kms_key_arn`（必填），不用 AWS 擁有的 key |
| target 授權 | 每個 target 都要有 `role_arn`，Scheduler 一律用 role 呼叫 target |
| flexible window | `flexible_window_minutes = null` 是 `OFF`（準時觸發），有值是 `FLEXIBLE` |
| 時區 | 預設 `Asia/Taipei` |
| group | `group_name = null` 放 `default` group；有值就建這個 group |
| tag | schedule group 的 `tags` 加上 `Name`；排程本身不支援 tag |

## 注意

- target 的 role 由呼叫端建，trust policy 的 principal 是 `scheduler.amazonaws.com`（建議帶 `aws:SourceAccount`），權限只給要呼叫的動作，例如 SageMaker pipeline 的 `sagemaker:StartPipelineExecution` 到單一 pipeline。部署者要有對這個 role 的 `iam:PassRole`。
- `kms_key_arn` 的 key policy 要讓 Scheduler 能用這把 key 解密排程資料；這個 module 不管 key policy。
- `cron(...)` 與 `at(...)` 照 `timezone` 解讀，`rate(...)` 不受時區影響。`at(...)` 是一次性排程，觸發後排程會留著，不會自動刪除。
- 用 flexible window 時，實際觸發時間會落在排程時間之後的視窗內，適合不在意準確時間的工作（例如重新訓練）。
- `sagemaker_pipeline_parameters` 只能給 `arn:aws:sagemaker:...:pipeline/...` 的 target；參數名稱要跟 pipeline definition 的參數一致。
- 排程名稱在同一個 group 內要唯一。`group_name` 改變會讓所有排程 replace。
- dev 不需要定期跑的排程用 `state = "DISABLED"`，排程留著但不觸發。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

ECS、EventBridge、Kinesis、SQS FIFO 等其他 target 專用參數（需要時再加）、一次性排程觸發後自動刪除（`action_after_completion`）、`start_date` 與 `end_date`、IAM role。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `kms_key_arn` | `string` | 無 | 是 | 加密排程資料（含 target 的 `input` 與 SageMaker pipeline 參數）用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 `scheduler.amazonaws.com` 與 target 的 role 能用這把 key 的 `kms:Decrypt`。 |
| `group_name` | `string` | `null` | 否 | schedule group 名稱，1–64 字元，限英數字、`_`、`-`、`.`，不能是 `default`。有值就建這個 group，所有排程放進去；`null` 就放 `default` group。 |
| `schedules` | `map(object)` | `{}` | 否 | 排程，key 是排程名稱（1–64 字元，限英數字、`_`、`-`、`.`）。`expression` 是 `cron(...)`、`rate(...)` 或 `at(...)`；`timezone` 是 IANA 時區（預設 `Asia/Taipei`）；`state` 是 `ENABLED`（預設）或 `DISABLED`；`flexible_window_minutes` 1–1440，`null` 就是準時觸發（`OFF`）。`target.arn` 是 target 的 ARN；`target.role_arn` 是 Scheduler 呼叫 target 用的 role（必填，module 不建）；`input` 是送給 target 的內容；`sagemaker_pipeline_parameters` 是 pipeline 參數（名稱 → 值，最多 200 個），只能給 SageMaker pipeline target；`dead_letter_arn` 是 SQS queue ARN；`retry` 的 `maximum_event_age_seconds` 60–86400、`maximum_retry_attempts` 0–185。空的 map 就不建排程。 |
| `tags` | `map(string)` | `{}` | 否 | schedule group 的 tag；`Name` 由 module 加上。排程本身不支援 tag。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `schedule_arns` | 排程名稱 → 排程 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/scheduler-schedule
```
