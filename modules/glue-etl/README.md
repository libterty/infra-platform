# glue-etl

建 Glue 的 ETL 元件：security configuration、crawler、Spark ETL job、trigger、workflow，以及可選的 S3 事件觸發（S3 → EventBridge → Glue workflow 的批次觸發）。job 與 crawler 一律掛同一份 security configuration，S3 寫入、CloudWatch log、job bookmark 都用客戶管理的 KMS key 加密，沒有關閉的選項。

## 用法

```hcl
module "etl" {
  source = "git::https://github.com/<org>/<repo>.git//modules/glue-etl?ref=glue-etl-v0.1.0"

  name        = "alpha-dev-etl"
  kms_key_arn = module.key.key_arn

  crawlers = {
    alpha-dev-raw = {
      role_arn      = module.role_glue_crawler.arn
      database_name = "alpha_dev_raw"
      s3_paths      = ["s3://alpha-dev-raw/raw/"]
      schedule      = "cron(0 18 * * ? *)"
    }
  }

  jobs = {
    alpha-dev-raw-to-curated = {
      role_arn          = module.role_glue_job.arn
      script_location   = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
      execution_class   = "FLEX"
      default_arguments = { "--job-bookmark-option" = "job-bookmark-enable" }
    }
  }

  workflow = { name = "alpha-dev-raw-to-curated" }

  event_trigger = {
    bucket_name = "alpha-dev-raw"
    key_prefix  = "raw/"
    role_arn    = module.role_glue_events.arn
    actions     = [{ job = "alpha-dev-raw-to-curated" }]
    batch_size  = 100
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| security configuration | 名稱是 `name`；S3 資料 `SSE-KMS`、CloudWatch log `SSE-KMS`、job bookmark `CSE-KMS`，key 都是必填輸入 `kms_key_arn` |
| job、crawler | 一律掛上面那份 security configuration |
| job 類型 | `glueetl`（Spark ETL），Python 3 |
| job log | 每個 job 一個 module 自己建的 log group `/aws-glue/jobs/<name>/<job>`，用 `kms_key_arn` 加密、保留 `log_retention_days` 天；job 的 `--enable-continuous-cloudwatch-log` 與 `--continuous-log-logGroup` 由 module 設定，`default_arguments` 不能覆蓋 |
| 事件觸發 | `event_trigger` 有給時建 `EVENT` trigger（workflow 的起始 trigger）、default bus 上的 EventBridge rule 與 target；沒給就一個都不建 |
| 命名 | EVENT trigger 與 EventBridge rule 都叫 `<workflow 名稱>-s3-event` |

## 事件觸發

```text
S3 Object Created ──> EventBridge default bus ──> rule <workflow>-s3-event ──> target（workflow ARN，用 role_arn）
                                                                              └─> EVENT trigger：batch_size 個事件，或第一個事件起算 batch_window_seconds 秒，先到先觸發 ──> actions
```

rule 的 event pattern 固定是：

```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": { "name": ["<bucket_name>"] },
    "object": { "key": [{ "prefix": "<key_prefix>" }] }
  }
}
```

- 這是 S3 自己送到 EventBridge 的事件，**不需要 CloudTrail**；前提是 bucket 開了 EventBridge 通知（`s3-bucket` 的 `eventbridge = true`）。
- `key_prefix` 不可為空、不可以 `/` 開頭：空的前綴會讓整個 bucket 的物件都觸發。
- EventBridge assume 的 role 由呼叫端建（module 不建 IAM）：trust policy 給 `events.amazonaws.com`，可用 output `event_rule_arn` 當 `aws:SourceArn` 限定單一 rule；權限只要對 output `workflow_arn` 的 `glue:notifyEvent`。
- `batch_size` 1–100、`batch_window_seconds` 1–900（沒給是 900）。視窗從第一個事件開始算，兩者先到先觸發。
- **Glue 不保證送達，也不去重**（AWS 文件：Glue 不提供 EventBridge 訊息的 guaranteed delivery，重複的訊息不會去重）。job 要自己做到冪等，例如開 `--job-bookmark-option = job-bookmark-enable`。漏掉的物件會在下一次觸發被撿到。
- rule 在 EVENT trigger 之後才建立（`depends_on`），不會有事件送到還不能啟動的 workflow。
- AWS 文件說每個 workflow 有一個起始 trigger（schedule、on-demand 或 EventBridge 事件）。module 用 validation 擋：`workflow = true` 的 `SCHEDULED` 最多一個；有 `event_trigger` 時一個都不能有，`workflow = true` 的 trigger 只能是 `CONDITIONAL`。

## 注意

- **允許的規格值（validation）**：
  - `glue_version`：`3.0`、`4.0`、`5.0`、`5.1`（預設，也是 AWS 沒指定時的預設）、`6.0`。`Flex` 要 3.0 以上，所以不收更舊的版本。
  - `worker_type`：`G.1X`（預設）、`G.2X`、`G.4X`、`G.8X`，是 CreateJob API 文件列的 Spark 用 worker。`Standard`（舊版）、`G.025X`（只給 streaming）、`Z.2X`（只給 Ray）不收；worker types 頁另外列了 `G.12X`、`G.16X` 與 `R.1X`–`R.8X`，這個 module 暫不收，需要再加。
  - `execution_class = "FLEX"`：AWS 文件寫 Flex 要 Glue 3.0 以上且只支援 `G.1X`、`G.2X`，所以 `FLEX` 搭其他 worker 會被擋下。Flex 的啟動與完成時間不固定，不適合有時限的工作。
  - `number_of_workers` 至少 2：Spark job 最少 2 DPU（Glue 定價頁）。`timeout` 1–2880 分鐘。
- **最低計費**（Glue 定價頁）：job 是 Glue 2.0 以上每次 1 分鐘（0.9／1.0 是 10 分鐘），crawler 每次執行 10 分鐘。crawler 照事件頻繁執行會放大成本，建議 crawler 用每日排程，事件只觸發 job。
- job 的 role 要能寫 module 建的 log group：`logs:CreateLogStream`、`logs:PutLogEvents` 到 `/aws-glue/jobs/<name>/*`，並有 `kms_key_arn` 的 `kms:Decrypt`、`kms:GenerateDataKey`、`kms:Encrypt`（security configuration 會用這把 key 加密輸出與 bookmark）。crawler 的 role 同樣要有這把 key 的權限。
- Glue 自己建的 log group（job 的 `/aws-glue/jobs/...` 預設群組、crawler 的 `/aws-glue/crawlers...`）不歸這個 module 管，保留期不受 `log_retention_days` 影響；security configuration 會用 `kms_key_arn` 加密它們。
- crawler 與 job 的 role 由呼叫端建（module 不建 IAM），部署者要有對這些 role 的 `iam:PassRole`，建 EventBridge target 要對 `event_trigger.role_arn` 有 `iam:PassRole`，並有 `events:PutRule`、`events:PutTargets`。
- 腳本不由 Terraform 上傳（`script_location` 只是路徑），由 CI 或呼叫端放進 S3。
- job 與 crawler 的名稱就是 map 的 key，跨這個帳號與 region 必須唯一。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過；EVENT trigger 的實際觸發次數、batch 行為與 EventBridge role 的權限都要在真實環境驗證。

## 刻意不做

自訂 event bus、跨帳號事件、SQS 事件模式的 crawler、Glue connection、VPC 內的 job、streaming job、Python shell 與 Ray job、`ON_DEMAND` trigger、上傳腳本、IAM role 與 policy（用 `iam-role`）、告警（用 `metric-alarm`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 這個 module 的名稱，1–255 字元，限英數字、`_`、`-`、`.`。用作 security configuration 的名稱，也是 job log group 的路徑（`/aws-glue/jobs/<name>/<job>`）。 |
| `kms_key_arn` | `string` | 無 | 是 | 加密用的客戶管理 KMS key ARN（symmetric），必填。用在 security configuration（job 寫 S3 的資料、CloudWatch log、job bookmark）與 module 自己建的 log group。key policy 或 job、crawler 的 role 要有這把 key 的 `kms:Decrypt`、`kms:GenerateDataKey`、`kms:Encrypt`。 |
| `log_retention_days` | `number` | `30` | 否 | module 自己建的 job log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 30）。Glue 自己建的 log group（`/aws-glue/jobs/output`、`/aws-glue/crawlers` 等）不受這個設定影響。 |
| `crawlers` | `map(object)` | `{}` | 否 | crawler，key 是 crawler 名稱（1–255 字元，限英數字、`_`、`-`、`.`）。`role_arn` 是 crawler 用的 IAM role ARN（module 不建 role）；`database_name` 是寫入的 Glue database；`s3_paths` 是要掃的 `s3://` 路徑（至少一個）；`schedule` 是 `cron(...)` 運算式，沒給就只能手動或由 trigger 啟動；`table_prefix`、`description` 選填。每次執行最低計費 10 分鐘。crawler 一律掛 module 的 security configuration。 |
| `jobs` | `map(object)` | `{}` | 否 | Spark ETL job（`glueetl`），key 是 job 名稱（1–255 字元，限英數字、`_`、`-`、`.`）。`role_arn` 是 job 用的 IAM role ARN（module 不建 role）；`script_location` 是 `s3://` 的腳本路徑（module 不上傳腳本）；`glue_version` 可選 `3.0`、`4.0`、`5.0`、`5.1`（預設）、`6.0`；`worker_type` 可選 `G.1X`（預設）、`G.2X`、`G.4X`、`G.8X`；`number_of_workers` 至少 2；`execution_class` 是 `STANDARD`（預設）或 `FLEX`（只能搭 `G.1X`、`G.2X`）；`timeout` 是分鐘，1–2880（預設 60）；`default_arguments` 例如 `--job-bookmark-option`，module 會另外加上 continuous logging 的兩個參數且不可覆蓋。job 一律掛 module 的 security configuration。 |
| `workflow` | `object` | `null` | 否 | Glue workflow；`null` 不建。`name` 限英數字、`_`、`-`，1–255 字元；`event_trigger` 與 `triggers` 的 `workflow = true` 都要有它。 |
| `triggers` | `map(object)` | `{}` | 否 | trigger，key 是 trigger 名稱。`type` 是 `SCHEDULED`（要 `schedule` 的 `cron(...)`，不能有 `predicate`）或 `CONDITIONAL`（要 `predicate`，不能有 `schedule`）；`actions` 至少一個，每個恰好指向這個 module 的一個 `job` 或 `crawler`；`predicate.conditions` 的 `state` 對 job 是 `SUCCEEDED`、`STOPPED`、`TIMEOUT`、`FAILED`，對 crawler 是 `RUNNING`、`SUCCEEDED`、`CANCELLED`、`FAILED`；`workflow = true` 把 trigger 放進 `workflow`（要先給 `workflow`）；`workflow = true` 的 `SCHEDULED` 是 workflow 的起始 trigger，最多一個，有 `event_trigger` 時不能有。EVENT trigger 不在這裡，用 `event_trigger`。 |
| `event_trigger` | `object` | `null` | 否 | S3 事件觸發 `workflow`；`null` 不建。module 會建 `type = "EVENT"` 的 trigger 當 workflow 的起始 trigger（名稱 `<workflow>-s3-event`），以及 default bus 上同名的 EventBridge rule 與指向 workflow 的 target。rule 只比對 `bucket_name` 這個 bucket、`key_prefix`（不可為空、不可以 `/` 開頭）開頭的 `Object Created` 事件；bucket 要先開 EventBridge 通知（`s3-bucket` 的 `eventbridge = true`）。`role_arn` 是 EventBridge assume 的 IAM role ARN（module 不建 role，權限是對這個 workflow 的 `glue:notifyEvent`）。`batch_size` 1–100，`batch_window_seconds` 1–900（預設 900）：事件數或視窗（從第一個事件起算）先到先觸發。`actions` 的規則同 `triggers`。要有 `workflow`，且 workflow 名稱最長 55 字元（rule 名稱上限 64）。 |
| `tags` | `map(string)` | `{}` | 否 | 每個 resource 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `crawler_names` | crawler 名稱，由小到大排序。 |
| `job_names` | job 名稱，由小到大排序。 |
| `workflow_name` | workflow 名稱；沒建 workflow 時是 `null`。 |
| `workflow_arn` | workflow 的 ARN；沒建 workflow 時是 `null`。EventBridge 的 target 與 role 的 `glue:notifyEvent` 都用這個 ARN。 |
| `event_rule_arn` | S3 事件的 EventBridge rule ARN；沒給 `event_trigger` 時是 `null`。給 EventBridge role 的 trust policy 當 `aws:SourceArn` 用。 |
| `security_configuration_name` | job 與 crawler 共用的 security configuration 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/glue-etl
```
