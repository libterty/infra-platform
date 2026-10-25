# iot-job-template

建一個 IoT Jobs 的 job template：job document（HCL 物件或 S3 網址擇一）、S3 presigned URL、發布速度、中止與重試條件、逾時與維護時段。給不跑 Greengrass 的裝置做 OTA 之類的遠端操作；Greengrass 裝置用 `greengrass-deployment`。用 awscc provider（aws provider 沒有 job template 的 resource）。

## 用法

```hcl
module "firmware_update" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iot-job-template?ref=iot-job-template-v0.1.0"

  job_template_id = "alpha-dev-firmware-update"
  description     = "Firmware update for non-Greengrass devices."
  document_source = "s3://alpha-dev-ota-artifacts/jobs/firmware-update.json"

  presigned_url = { role_arn = module.presign_role.role_arn, expires_in_sec = 900 }
  rollout       = { maximum_per_minute = 50 }
  abort = [
    { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
  ]
}
```

document 用 HCL 物件寫的例子見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| job document | `document`（物件，module `jsonencode`）與 `document_source`（`s3://`）擇一 |
| presigned URL | 有效秒數 60–3600，預設 3600 |
| 中止條件 | `action` 固定 `CANCEL` |
| 重試 | 每條 0–10 次 |
| tag | 給定的 `tags` 加上 `Name`（template ID），轉成 `key`／`value` 的 set |

## 注意

- **所有屬性改了都會 replace。** job template 的每個屬性（含 tag 與 document）都不能直接改，plan 會顯示刪掉再建。template 被 replace 不影響已經建立的 job。
- **這個 module 只建 template，不建 job。** 每次發布的 job 是執行期的操作，由 CI 或操作者用 `aws iot create-job --job-template-arn <arn> --targets ...` 建立。
- `presigned_url.role_arn` 的 role 要信任 `iot.amazonaws.com`，並能 `s3:GetObject` document 裡引用的檔案；這個 module 不建 IAM。
- `rollout`、`abort`、`retry`、`maintenance_windows` 都是選填，空的就不設定。
- awscc 透過 Cloud Control API 建立資源，錯誤訊息與 drift 偵測比 aws provider 少。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

job 本身、從既有 job 複製（`job_arn`）、software package catalog 與 `destination_package_versions`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `job_template_id` | `string` | 無 | 是 | job template ID，1–64 字元，限英數字、`_`、`-`；也用在 `Name` tag。 |
| `description` | `string` | 無 | 是 | job template 的說明，1–2028 字元（AWS 必填）。 |
| `document` | `any` | `null` | 否 | job document，用 HCL 物件寫，module 會 `jsonencode`（編碼後最多 32 KB）。跟 `document_source` 擇一。要讓裝置下載 S3 檔案時，網址寫成 `${aws:iot:s3-presigned-url:https://s3.amazonaws.com/<bucket>/<key>}` 並設定 `presigned_url`。 |
| `document_source` | `string` | `null` | 否 | 放在 S3 的 job document 網址（`s3://<bucket>/<key>`）。跟 `document` 擇一。 |
| `presigned_url` | `object` | `null` | 否 | job document 裡 S3 presigned URL 的設定；`null` 不設定。`role_arn` 是 IoT 用來簽網址的 role（要能 `s3:GetObject` 檔案）；`expires_in_sec` 是網址有效秒數，60–3600（預設 3600）。 |
| `rollout` | `object` | `null` | 否 | 發布速度；`null` 不限制。`maximum_per_minute`（每分鐘最多通知幾台，1–1000）與 `exponential` 擇一。`exponential` 的欄位：`base_rate_per_minute`（1–1000）、`increment_factor`（1.1–5）、`number_of_succeeded_things`（成功幾台後加速，至少 1）。 |
| `abort` | `list(object)` | `[]` | 否 | 中止條件，符合任一條就取消 job（`action` 固定 `CANCEL`）；空的就不設定。欄位：`failure_type`（`FAILED`、`REJECTED`、`TIMED_OUT`、`ALL`）、`threshold_percentage`（大於 0、最多 100）、`min_number_of_executed_things`（至少 1）。 |
| `timeout_minutes` | `number` | `null` | 否 | 每台裝置執行 job 的時間上限（分鐘，1–10080）；超過就標成 `TIMED_OUT`。`null` 不設上限。 |
| `retry` | `list(object)` | `[]` | 否 | 失敗重試條件；空的就不重試。欄位：`failure_type`（`FAILED`、`TIMED_OUT`、`ALL`）、`number_of_retries`（0–10）。 |
| `maintenance_windows` | `list(object)` | `[]` | 否 | 只在這些時段發布 job；空的就不限制。欄位：`start_time`（cron 運算式，例如 `cron(0 18 ? * MON-FRI *)`，UTC）、`duration_minutes`（1–1430）。 |
| `tags` | `map(string)` | `{}` | 否 | job template 的 tag；`Name`（template ID）由 module 加上，module 轉成 `key`／`value` 的 set 傳給 resource。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `arn` | job template 的 ARN；建立 job 時用 `--job-template-arn` 引用。 |
| `job_template_id` | job template ID。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iot-job-template
```
