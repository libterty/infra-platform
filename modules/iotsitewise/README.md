# iotsitewise

建 AWS IoT SiteWise 的 asset model、asset，以及跑在 Greengrass v2 core device 上的 SiteWise gateway。用 awscc provider，因為 aws provider 沒有 SiteWise 的 resource。property 只支援 attribute 與 measurement，夠用來描述設備屬性與感測值，也夠建 KVS edge connector 要的 hub 與攝影機 asset。

## 用法

```hcl
module "sitewise" {
  source = "git::https://github.com/<org>/<repo>.git//modules/iotsitewise?ref=iotsitewise-v0.1.0"

  asset_models = {
    alpha-dev-sensor = {
      properties = {
        serial      = { data_type = "STRING", type = "attribute" }
        temperature = { data_type = "DOUBLE", type = "measurement", unit = "Celsius" }
      }
    }
    alpha-dev-line = {
      properties  = { line_name = { data_type = "STRING", type = "attribute" } }
      hierarchies = { Sensors = "alpha-dev-sensor" }
    }
  }

  assets = {
    alpha-dev-line-01 = { model = "alpha-dev-line" }
    alpha-dev-sensor-01 = {
      model      = "alpha-dev-sensor"
      parent     = { asset = "alpha-dev-line-01", hierarchy = "Sensors" }
      properties = { temperature = { alias = "/alpha/dev/sensor-01/temperature" } }
    }
  }

  gateways = {
    alpha-dev-gateway-01 = { core_device_thing_name = "alpha-dev-core-01" }
  }

  tags = local.common_tags
}
```

KVS edge connector 的 hub 與攝影機 model 見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 引用範圍 | asset 的 `model`、`parent` 與 model 的 `hierarchies` 只能指向同一個呼叫裡的 key |
| 階層 | 最多兩層；子 model 與有上層的 asset 先建，上層再引用它們的 ID |
| property 的 ID | property 與階層的 `logical_id` 等於名稱，asset 的 `properties`、`parent.hierarchy` 用名稱對應 |
| gateway | 一律 Greengrass v2 平台 |
| tag | awscc 沒有 `default_tags`，module 把 `tags` 轉成 `{ key, value }` 清單並加上 `Name` |

## 注意

- **KVS edge connector 要的 asset 結構**（`aws.iot.EdgeConnectorForKVS`，結構取自 AWS 的 getting started 腳本 `resourceManager.py`）：每台 core device 一個 hub asset，每台攝影機一個 camera asset，camera asset 透過 hub model 的 `ConnectedCameras` 階層掛在 hub 底下。
  - hub model：attribute `HubName`（`STRING`）；階層 `ConnectedCameras` 指向 camera model。
  - camera model 的 attribute：`KinesisVideoStreamName`（`STRING`）、`RTSPStreamSecretARN`（`STRING`，secret 裡的 key 是 `RTSPStreamUrl`）、`LocalDataRetentionPeriodInMinutes`（`INTEGER`，預設 `60`）、`LiveStreamingStartTime`（`STRING`，預設 `-`）、`LiveStreamingDurationInMinutes`（`INTEGER`，預設 `0`）、`CaptureStartTime`（`STRING`，預設 `-`）、`CaptureDurationInMinutes`（`INTEGER`，預設 `0`）。
  - camera model 的 measurement：`VideoUploadRequest`（`STRING`）、`VideoUploadedTimeRange`、`VideoRecordedTimeRange`、`CachedVideoAgeOutOnEdge`（都是 `DOUBLE`）。
  - 部署元件時把 hub asset 的 ID（`asset_ids` 輸出）放進元件設定 `SiteWiseAssetIdForHub`；元件只能部署到單台 core device，不能部署到 thing group。
- **asset 的 attribute 值不能用這個 module 設**：CloudFormation 的 `AWS::IoTSiteWise::Asset` 沒有 attribute 值的欄位，值要用 `BatchPutAssetPropertyValue` 寫入，或在 model 的 `default_value` 給。每台攝影機的 `KinesisVideoStreamName`、`RTSPStreamSecretARN` 不同時，要嘛 apply 後用 API 寫入，要嘛一台攝影機一個 camera model（範例的做法）。
- 階層只支援兩層：Terraform 的同一個 resource 不能引用自己的 instance，所以拆成子層與上層兩個 resource。需要更深的階層時再擴充。
- property 的 `alias` 是 gateway 或 `BatchPutAssetPropertyValue` 寫資料時用的資料流別名，同帳號同 region 必須唯一。
- 改 model 的 property 或階層會在原地更新 model，再由 SiteWise 傳到所有用這個 model 的 asset；刪掉 asset 正在用的 model 會失敗，要先刪 asset。
- gateway 的 core device 要先註冊成 IoT thing，並部署 SiteWise Edge 的元件（`aws.iot.SiteWiseEdgeCollectorOpcua`、`aws.iot.SiteWiseEdgePublisher` 等）；元件部署用 `greengrass-deployment`。core device 的 token exchange role 要有寫 SiteWise 的權限，這個 module 不建 IAM。
- awscc 透過 Cloud Control API 管理資源，drift 偵測與錯誤訊息比 aws provider 少。這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過；KVS edge connector 的 asset 結構要在真實環境驗證。

## 刻意不做

- portal、dashboard、project、access policy：SiteWise Monitor 從 2025-11-07 起不開放新客戶，AWS 建議改用 Amazon Managed Grafana。
- Edge Data Processing Pack 與資料處理 pipeline（同樣不開放新客戶）、Siemens IE gateway。
- transform 與 metric property、composite model、interface model、gateway 的 capability 設定（OPC UA source 等，由元件設定處理）、三層以上的階層、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `asset_models` | `map(object)` | `{}` | 否 | SiteWise asset model，key 是名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`properties` 的 key 是 property 名稱，`type` 是 `attribute` 或 `measurement`，`data_type` 是 `STRING`、`INTEGER`、`DOUBLE`、`BOOLEAN`，`unit` 選填，`default_value` 只有 `attribute` 能給；`hierarchies` 是階層名稱對應子 model 的 key（子 model 要在同一個呼叫裡）。階層最多兩層：當子 model 的不能再有自己的 `hierarchies`。每個 model 至少要有一個 property 或階層。 |
| `assets` | `map(object)` | `{}` | 否 | SiteWise asset，key 是名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`model` 是同一個呼叫裡 `asset_models` 的 key；`parent` 選填，`asset` 是同一個呼叫裡的上層 asset，`hierarchy` 是上層 model 裡指向這個 asset 的 model 的階層名稱（model 階層最多兩層，所以 asset 也最多兩層）；`properties` 的 key 是 model 的 property 名稱，可設 `alias`（例如 gateway 寫入用的資料流別名）、`notification_state`（`ENABLED` 或 `DISABLED`）、`unit`。attribute 的值不能在這裡設，見 README〈注意〉。 |
| `gateways` | `map(object)` | `{}` | 否 | 跑在 Greengrass v2 core device 上的 SiteWise gateway，key 是 gateway 名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`core_device_thing_name` 是 core device 的 IoT thing 名稱（1–128 字元，限英數字、`:`、`_`、`-`）。 |
| `tags` | `map(string)` | `{}` | 否 | 所有資源的 tag；module 轉成 awscc 要的 `{ key, value }` 清單，並加上 `Name`（資源名稱）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `asset_model_ids` | asset model 名稱對應 ID 的 map。 |
| `asset_ids` | asset 名稱對應 ID 的 map。KVS edge connector 的 `SiteWiseAssetIdForHub` 用 core device 那個 asset 的 ID。 |
| `gateway_ids` | gateway 名稱對應 ID 的 map。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/iotsitewise
```
