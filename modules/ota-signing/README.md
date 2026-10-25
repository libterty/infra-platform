# ota-signing

建一個 AWS Signer 的 signing profile，給 IoT OTA 韌體簽章用。platform 只收 IoT 的三種，簽章憑證是在 Terraform 外匯入 ACM 的 code signing 憑證；可以選擇讓指定的 role 用這個 profile 開簽章 job。

## 用法

```hcl
module "firmware_signing" {
  source = "git::https://github.com/<org>/<repo>.git//modules/ota-signing?ref=ota-signing-v0.1.0"

  name            = "alpha_dev_firmware"
  platform_id     = "AmazonFreeRTOS-Default"
  certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"

  signing_parameters = {
    certname = "ota_signer_pub.pem"
  }

  start_job_principals = ["arn:aws:iam::111111111111:role/alpha-dev-ci"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| platform | 只收 `AWSIoTDeviceManagement-SHA256-ECDSA`、`AmazonFreeRTOS-Default`、`AmazonFreeRTOS-TI-CC3220SF` |
| 簽章憑證 | `certificate_arn` 必填，只收 ACM 憑證 ARN；module 不收私鑰 |
| 簽章有效期 | 不設定（`signature_validity_period` 只對 Lambda 與 Notation platform 有效） |
| profile permission | 每個 `start_job_principals` 一筆，動作固定 `signer:StartSigningJob` |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- code signing 憑證與私鑰在 repo 外產生並匯入 ACM，這裡只給 ARN，私鑰不經過 Terraform 與 state。憑證要在同一個 region、同一個帳號。
- Signer 只替 Lambda 與 container image 管理金鑰，IoT 的三種 platform 都要自備憑證，所以 `certificate_arn` 不分 platform 一律必填。
- `aws_signer_signing_profile` 的參數改了都會 replace，profile 會換一個新的。裝置端信任的是憑證，不是 profile，所以換 profile 不影響已經簽好的韌體；開簽章 job 的流程要改用新的 profile 名稱與版本。
- AWS 文件說簽章有效期（預設也是上限 135 個月）只適用 `AWSLambda-SHA384-ECDSA` 與 `Notation-OCI-SHA384-ECDSA`，IoT platform 不適用，所以這個 module 不提供這個輸入。
- `start_job_principals` 只建 Signer 這一側的 profile permission；role 本身還要有 `signer:StartSigningJob` 與讀寫來源、目的 bucket 的 IAM 權限，由呼叫端給。
- Signer 搭配 IoT Device Management 不另外收費。Greengrass 元件不用 Signer，完整性靠建立元件時算的 digest。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

簽章 job、Lambda 與 container image 的簽章 platform、`signature_validity_period`、撤銷 profile、`signer:StartSigningJob` 以外的 profile permission、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | signing profile 名稱，2–64 字元，限英數字與 `_`（Signer 不收連字號）。 |
| `platform_id` | `string` | 無 | 是 | 簽章 platform：`AWSIoTDeviceManagement-SHA256-ECDSA`、`AmazonFreeRTOS-Default` 或 `AmazonFreeRTOS-TI-CC3220SF`。 |
| `certificate_arn` | `string` | 無 | 是 | 在 Terraform 外匯入 ACM 的 code signing 憑證 ARN，必填。Signer 只替 Lambda 與 container image 管理金鑰，IoT 的三種 platform 都要自備憑證；這個 module 不收私鑰。 |
| `signing_parameters` | `map(string)` | `{}` | 否 | 簽章參數，例如 `{ certname = "ota_signer_pub.pem" }`（裝置上驗章憑證的路徑，FreeRTOS OTA 會用到）。空的就不送。 |
| `start_job_principals` | `set(string)` | `[]` | 否 | 可以用這個 profile 開簽章 job（`signer:StartSigningJob`）的 IAM role ARN。空的就不建 profile permission。 |
| `tags` | `map(string)` | `{}` | 否 | signing profile 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `profile_name` | signing profile 名稱，開簽章 job 時用。 |
| `profile_arn` | signing profile 的 ARN。 |
| `profile_version_arn` | 含版本的 signing profile ARN，IAM policy 要鎖定特定版本時用。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/ota-signing
```
