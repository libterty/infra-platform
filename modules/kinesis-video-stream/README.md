# kinesis-video-stream

建一組 Kinesis Video Streams 的 stream，一律用客戶管理的 KMS key 加密。給攝影機（例如 Greengrass 上的 KVS edge connector）上傳影像用，一台攝影機一個 stream。

## 用法

```hcl
module "cameras" {
  source = "git::https://github.com/<org>/<repo>.git//modules/kinesis-video-stream?ref=kinesis-video-stream-v0.1.0"

  kms_key_arn = module.key.key_arn

  streams = {
    alpha-dev-cam-01 = {
      retention_hours = 24
      device_name     = "alpha-dev-core-01"
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 加密 | `kms_key_id` 一律是必填輸入 `kms_key_arn`，沒有用 AWS 管理 key 的選項 |
| 保留 | `retention_hours` 預設 24，範圍 0–87600（0 是不保留） |
| 媒體類型 | `media_type` 預設 `video/h264` |
| tag | 給定的 `tags` 加上 `Name`（stream 名稱） |

## 注意

- `kms_key_arn` 只收客戶管理 key 的 ARN（含 multi-Region key），不收 alias 與裸 key id。寫入端要有 `kms:GenerateDataKey`，讀取端要有 `kms:Decrypt`；這個 module 不管 key policy 與 IAM。
- `retention_hours = 0` 時影像不落地，只能用 GetMedia 即時讀取，HLS、DASH 播放與 GetClip 都需要保留期。保留越久儲存費越高（每 GB-月計費）。
- stream 名稱就是 map 的 key，同帳號同 region 必須唯一。改名會刪掉重建，舊影像跟著消失；其他欄位哪些會重建要看 plan。
- 寫入端（KVS edge connector 用的 token exchange role）的 `kinesisvideo:PutMedia`、`DescribeStream`、`GetDataEndpoint` 由呼叫端給，Resource 用 `stream_arns`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

signaling channel（WebRTC）、儲存分層（只有 `awscc_kinesisvideo_stream` 有，需要時再評估）、image generation 與 notification 設定、告警（用 `metric-alarm`）、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `kms_key_arn` | `string` | 無 | 是 | stream 加密用的客戶管理 KMS key ARN（symmetric），必填，所有 stream 共用。key policy 或寫入端、讀取端的 role 要有這把 key 的 `kms:GenerateDataKey`、`kms:Decrypt`。 |
| `streams` | `map(object)` | `{}` | 否 | Kinesis Video stream，key 是 stream 名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`retention_hours` 是保留時數，0–87600（預設 24；0 表示不保留，只能即時消費）；`media_type` 是 MIME 類型（預設 `video/h264`）；`device_name` 是寫入這個 stream 的裝置名稱（選填，1–128 字元）。空的 map 不建任何 stream。 |
| `tags` | `map(string)` | `{}` | 否 | 每個 stream 的 tag；`Name` 由 module 加上（stream 名稱）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `stream_names` | stream 名稱，由小到大排序。 |
| `stream_arns` | stream 名稱對應 ARN 的 map。給寫入端（KVS edge connector）與讀取端的 IAM policy 當 Resource 用。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/kinesis-video-stream
```
