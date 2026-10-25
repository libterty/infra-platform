# greengrass-deployment

對一個 target（thing group 或一台 core device）建 Greengrass v2 部署：列出要裝的元件與版本、每個元件的設定，以及發布速度、中止條件與失敗時的處理。用 awscc provider（aws provider 沒有 Greengrass v2 的 resource）。

## 用法

```hcl
module "fleet_deployment" {
  source = "git::https://github.com/<org>/<repo>.git//modules/greengrass-deployment?ref=greengrass-deployment-v0.1.0"

  name       = "alpha-dev-fleet"
  target_arn = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet"

  components = {
    "aws.greengrass.Nucleus" = { version = "2.14.3" }
    "com.example.Inference" = {
      version = module.inference_1_0_0.component_version
      merge   = { threshold = 0.8 }
    }
  }

  rollout = { maximum_per_minute = 50 }
  abort = [
    { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
  ]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 失敗處理 | `failure_handling` 預設 `ROLLBACK` |
| 元件更新 | 預設 `NOTIFY_COMPONENTS`，等 60 秒 |
| 設定驗證 | 預設等 30 秒 |
| 發布速度 | `rollout` 必填，`maximum_per_minute` 與 `exponential` 擇一 |
| 中止條件 | `abort` 必填，至少一條，`action` 固定 `CANCEL` |
| 元件設定 | `merge` 用物件寫，module `jsonencode` 後送出 |
| tag | 給定的 `tags` 加上 `Name`（部署名稱），以 map 傳給 resource |

## 注意

- **每次變更都會 replace 部署。** 除了 tag，Greengrass 部署的屬性都不能直接改，改元件版本、設定或發布政策時 plan 會顯示刪掉再建，這是正常的。每個 target 只有一個部署，新部署會取代舊的。
- **從 `components` 拿掉的元件，會在裝置上解除安裝。** PR 審查時要看 `components` 的差異。`aws.greengrass.Nucleus` 的版本要明確釘住，不然在無關的變更時也可能升級。
- **刪掉這個 resource 不會移除裝置上的元件。** 刪除時會先取消、再刪除部署，已經裝好的元件留在裝置上；要移除元件，就部署一份不含該元件的新版本。
- 同時最多 10 個部署在刪除中，超過會被 throttle。一次 apply 不要刪除或 replace 超過 10 個部署。
- 引用自訂元件時，`version` 用 `greengrass-component` 的 `component_version` output，部署才會等元件版本建好。刪掉還在部署的元件版本會讓部署失敗。
- `components` 的型別是 `any`，因為每個元件的 `merge` 形狀不同，Terraform 的 map 型別無法容納；欄位由 validation 檢查，多了不認得的欄位會被擋。
- awscc 透過 Cloud Control API 建立資源，錯誤訊息與 drift 偵測比 aws provider 少。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

子部署（`parent_target_arn`）、Windows user（`run_with.windows_user`）、元件的系統資源上限（`system_resource_limits`）、一次部署到多個 target。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 部署名稱，1–256 字元，顯示在 Greengrass console 與 API，也用在 `Name` tag。 |
| `target_arn` | `string` | 無 | 是 | 部署對象：一個 thing group（`arn:aws:iot:<region>:<account>:thinggroup/<name>`）或一台 core device 的 thing（`.../thing/<name>`）。每個 target 只有一個部署，新部署會取代舊的。 |
| `components` | `any` | 無 | 是 | 要部署的元件，key 是元件名稱（含 `aws.greengrass.Nucleus` 與公開元件），value 是物件：`version`（必填，semver）、`merge`（選填，要合併進元件設定的物件，module 會 `jsonencode`）、`reset`（選填，要重設成預設值的 JSON pointer 清單）、`run_with`（選填，`{ posix_user = "user:group" }`）。至少一個元件；不在這裡的元件會從裝置上解除安裝。型別是 `any`，因為每個元件的 `merge` 形狀不同。 |
| `failure_handling` | `string` | `"ROLLBACK"` | 否 | 裝置部署失敗時的處理：`ROLLBACK`（預設，回到上一版的元件與設定）或 `DO_NOTHING`。 |
| `component_update` | `object` | `{}` | 否 | 元件更新政策：`action` 是 `NOTIFY_COMPONENTS`（預設，先通知元件，讓元件可以延後更新）或 `SKIP_NOTIFY_COMPONENTS`；`timeout_seconds` 是等元件回應的秒數（預設 60）。 |
| `configuration_validation_timeout_seconds` | `number` | `30` | 否 | 元件驗證新設定的等待秒數（預設 30）。 |
| `rollout` | `object` | 無 | 是 | 發布速度，必填，`maximum_per_minute`（每分鐘最多通知幾台，1–1000）與 `exponential` 擇一。`exponential` 的欄位：`base_rate_per_minute`（1–1000）、`increment_factor`（1.1–5）、`number_of_succeeded_things`（成功幾台後加速，至少 1）。 |
| `abort` | `list(object)` | 無 | 是 | 中止條件，必填，至少一條；符合任一條就取消還沒收到的裝置（`action` 固定 `CANCEL`）。欄位：`failure_type`（`FAILED`、`REJECTED`、`TIMED_OUT`、`ALL`）、`threshold_percentage`（大於 0、最多 100）、`min_number_of_executed_things`（至少執行幾台才開始判斷，至少 1）。 |
| `in_progress_timeout_minutes` | `number` | `null` | 否 | 每台裝置執行部署的時間上限（分鐘，1–10080）；超過就標成 `TIMED_OUT`。`null` 不設上限。 |
| `tags` | `map(string)` | `{}` | 否 | 部署的 tag；`Name`（部署名稱）由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `deployment_id` | 部署 ID。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/greengrass-deployment
```
