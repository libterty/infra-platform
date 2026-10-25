# sagemaker-endpoint

從 Model Registry 裡核准過的 model package 版本建 SageMaker 即時推論 endpoint：一個 model、一份 endpoint configuration、一個 endpoint。variant 是 instance 或 serverless 二選一；instance variant 一定在 VPC 裡、預設關掉對外網路，更新時用 blue/green 或 rolling，烘烤期間看 CloudWatch 告警自動 rollback。

## 用法

```hcl
module "detector" {
  source = "git::https://github.com/<org>/<repo>.git//modules/sagemaker-endpoint?ref=sagemaker-endpoint-v0.1.0"

  name               = "alpha-dev-detector"
  model_package_arn  = var.model_package_arn
  execution_role_arn = module.role_sagemaker_endpoint.arn
  kms_key_arn        = module.key.key_arn

  variant = {
    instance = { instance_type = "ml.m5.large", initial_instance_count = 2 }
  }

  vpc = {
    subnet_ids         = local.subnet_ids_app
    security_group_ids = [local.sg_sagemaker_id]
  }

  deployment = {
    blue_green = {
      traffic     = "CANARY"
      canary_size = { type = "CAPACITY_PERCENT", value = 10 }
    }
    rollback_alarm_names = [module.alarm_5xx.alarm_name]
  }
}
```

serverless：

```hcl
  variant = {
    serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
  }
  enable_network_isolation = false
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| model 來源 | 只有 `primary_container.model_package_name`（有版本的 model package ARN），不收 image 與 model data URL |
| model 名稱 | 由 provider 產生，`create_before_destroy`，換版本時新 model 先建好 |
| endpoint configuration | `name_prefix = "<name>-"`、`create_before_destroy`；只有一個 variant，名稱固定 `primary`，權重 1 |
| 加密 | endpoint configuration 的 `kms_key_arn` 與 data capture 的 `kms_key_id` 都是必填輸入 `kms_key_arn` |
| network isolation | 預設 `true`；serverless 要明確設成 `false` |
| data capture | 有給時同時記錄 `Input` 與 `Output` |
| tag | 三個 resource 都是給定的 `tags` 加上 `Name` |

## 各 variant 的限制

| | instance | serverless |
|---|---|---|
| `vpc` | 必填 | 必須是 `null` |
| `enable_network_isolation` | 預設 `true` | 必須是 `false` |
| `data_capture` | 選填 | 必須是 `null` |
| `deployment` | 必填（`blue_green` 或 `rolling`） | 選填，只能 `blue_green` |
| 規格 | `instance_type` 以 `ml.` 開頭 | 記憶體 1024–6144 MB、1024 的倍數；`max_concurrency` 1–200 |

## 注意

- 換模型版本（改 `model_package_arn`）會建新的 model 與 endpoint configuration，endpoint 用 `deployment` 的方式切過去，成功後舊的才刪掉。告警在烘烤期間進入 ALARM 就自動 rollback 到舊的 configuration。
- variant 名稱固定是 `primary`：blue/green 與 rolling 要求新舊 configuration 的 variant 名稱相同。
- serverless 不支援 rolling，只支援 blue/green；instance 轉成 serverless 會失敗，serverless 轉成 instance 之後不能轉回來。
- 有本機 NVMe 儲存的 instance type（例如 `ml.m5d.*`、`ml.g4dn.*`）不收 endpoint configuration 的 KMS key（AWS 文件），這個 module 一律帶 key，遇到這類 type 要換 instance type。serverless endpoint 帶 KMS key 的行為未確認。
- model package 要是核准（`Approved`）的版本，SageMaker 才讓它部署；跨帳號的 package 要對方 group 的 resource policy 允許 `sagemaker:CreateModel`（見 `sagemaker-model-registry`）。
- `execution_role_arn` 要能讀模型 artifact 與它的 KMS key、拉 ECR image、寫 CloudWatch Logs；instance variant 還要能建 VPC ENI。這個 module 不建 IAM 與 security group。
- 告警（`rollback_alarm_names`）由 `metric-alarm` 另外建，名稱傳進來；告警不存在時 SageMaker 會拒絕更新。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

多個 variant、shadow variant、async inference、autoscaling（之後用 Application Auto Scaling 另外做）、任意 image、Model Monitor、inference component。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | endpoint 名稱，1–36 字元，限英數字與 `-`，開頭結尾是英數字。endpoint configuration 用 `<name>-` 當 `name_prefix`，後面接 26 字元的亂數，總長不能超過 63，所以上限是 36。 |
| `model_package_arn` | `string` | 無 | 是 | 要部署的 model package 版本 ARN（`arn:<partition>:sagemaker:<region>:<account>:model-package/<group>/<version>`），要是核准過的版本。module 只從 model package 建 model，不收任意 image。 |
| `execution_role_arn` | `string` | 無 | 是 | model 執行用的 IAM role ARN（module 不建 role），要能讀模型 artifact、拉 image、用 `kms_key_arn`，instance variant 還要能建 VPC ENI。 |
| `kms_key_arn` | `string` | 無 | 是 | 客戶管理 KMS key ARN（symmetric），必填。加密 endpoint configuration 的 ML storage volume 與 data capture 寫進 S3 的資料。 |
| `variant` | `object` | 無 | 是 | 唯一的 variant，`instance` 與 `serverless` 擇一。`instance`：`instance_type` 以 `ml.` 開頭，`initial_instance_count` 至少 1（預設 1），必須給 `vpc` 與 `deployment`。`serverless`：`memory_size_in_mb` 是 1024–6144 且是 1024 的倍數，`max_concurrency` 1–200，`provisioned_concurrency` 選填且不能大於 `max_concurrency`；不能給 `vpc`、`data_capture`，`enable_network_isolation` 要設成 `false`。 |
| `vpc` | `object` | `null` | 否 | model container 所在的 VPC：`subnet_ids`、`security_group_ids` 各至少一個。instance variant 必填，serverless variant 必須是 `null`（serverless 不支援 VPC）。 |
| `enable_network_isolation` | `bool` | `true` | 否 | model container 是否關掉對外網路（預設 `true`）。serverless variant 不支援，要明確設成 `false`。 |
| `data_capture` | `object` | `null` | 否 | 記錄推論的請求與回應：`destination_s3_uri` 是 `s3://` 路徑，`sampling_percentage` 是 0–100 的整數。用 `kms_key_arn` 加密。`null` 不開；serverless variant 必須是 `null`。 |
| `deployment` | `object` | `null` | 否 | 更新 endpoint 的方式，`blue_green` 與 `rolling` 擇一，`rollback_alarm_names` 是 1–10 個 CloudWatch 告警名稱，烘烤期間任何一個進入 ALARM 就自動 rollback。`blue_green.traffic` 是 `ALL_AT_ONCE`、`CANARY`（要 `canary_size`）或 `LINEAR`（要 `linear_step_size`）；size 的 `type` 是 `INSTANCE_COUNT` 或 `CAPACITY_PERCENT`；`wait_interval_in_seconds` 是烘烤秒數，0–3600（預設 600）。instance variant 必填；serverless variant 選填，且只能用 `blue_green`（rolling 不支援 serverless）。 |
| `tags` | `map(string)` | `{}` | 否 | model、endpoint configuration、endpoint 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `endpoint_name` | endpoint 名稱，呼叫端 `sagemaker:InvokeEndpoint` 用。 |
| `endpoint_arn` | endpoint 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/sagemaker-endpoint
```
