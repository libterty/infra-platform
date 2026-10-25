# acm-pca

建一個 AWS Private CA（ACM PCA）。`ROOT` 時 module 自己簽發 root 憑證並安裝；`SUBORDINATE` 時只產生 CSR，等上層 CA 簽好再把憑證裝回來。不開 CRL 與 OCSP。用來簽發 IoT 裝置憑證，註冊到 IoT Core 由 `iot-fleet` 處理。

## 用法

```hcl
module "device_root_ca" {
  source = "git::https://github.com/<org>/<repo>.git//modules/acm-pca?ref=acm-pca-v0.1.0"

  type = "ROOT"
  subject = {
    common_name  = "alpha-dev-device-root"
    organization = "Example"
    country      = "JP"
  }
}
```

`SUBORDINATE` 要 apply 兩次：第一次不給 `subordinate_certificate`，拿 `csr` 輸出去給上層 CA 簽；第二次把簽好的憑證與憑證鏈填進 `subordinate_certificate` 再 apply，module 會安裝到 CA。

完整範例見 [`examples/root/`](./examples/root/main.tf) 與 [`examples/subordinate/`](./examples/subordinate/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 撤銷 | 不設定 `revocation_configuration`，CRL 與 OCSP 都不開 |
| 金鑰演算法 | `key_algorithm` 預設 `EC_prime256v1`，只收 P-256、P-384、P-521 與 RSA 2048／3072／4096 |
| 簽章演算法 | 依金鑰決定：P-256 與 RSA 用 SHA-256、P-384 用 SHA-384、P-521 用 SHA-512 |
| root 憑證 | `ROOT` 時用 `RootCACertificate/V1` template 自簽，`validity_years` 預設 10 年 |
| 刪除保留 | `permanent_deletion_time_in_days` 預設 30，範圍 7–30 |
| tag | 給定的 `tags` 加上 `Name`（值是 `subject.common_name`） |

## 注意

- **費用**：general-purpose CA 每個每月約 400 美元，short-lived CA 每月約 50 美元，憑證另計（general-purpose 前 1,000 張每張 0.75 美元、short-lived 每張 0.058 美元）。CA 在刪除保留期間不收費，但還是先確定真的要用再建；每個 region 第一個 CA 有 30 天免費試用。
- 註冊到 IoT Core 一律用 `SNI_ONLY` 模式，由 `iot-fleet` 做，這個 module 不碰 IoT。`SNI_ONLY` 不需要 verification certificate，裝置連線時要送 SNI。
- 不開 CRL：CRL 要讓 ACM PCA 寫進 S3 bucket，需要 bucket policy，而 `s3-bucket` 刻意不做 bucket policy。裝置憑證要撤銷時，在 IoT registry 把憑證設成 `INACTIVE` 或 `REVOKED`。
- 金鑰演算法不收 RSA 2048 以下（ACM PCA 本來也沒有）。RSA 2048 保留，因為 NIST SP 800-57 認可到 2030 年、IoT Core 支援，而且不少 MCU 只做得了 RSA 2048。SM2 只在中國區、ML-DSA 不確定 IoT Core 能不能驗，兩者都不收。
- `SHORT_LIVED_CERTIFICATE` 的 CA 只能簽有效期 7 天以內的憑證，裝置要有自動換憑證的流程。
- `SUBORDINATE` 沒裝憑證前，CA 狀態是等待憑證，不能簽發；`ca_certificate_pem` 是 `null`。上層 CA 簽的憑證必須用 `csr` 輸出的那份 CSR。
- `key_storage_security_standard` 用 AWS 預設（`FIPS_140_2_LEVEL_3_OR_HIGHER`），module 不開放設定。
- CA 的權限（誰能簽發憑證）由呼叫端給 role 的 IAM，這個 module 不建 IAM 也不建 `aws_acmpca_permission`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

CRL、OCSP、`aws_acmpca_permission`、跨帳號 RAM 共用、簽發裝置憑證、自訂 CSR extension、`key_storage_security_standard`、IAM。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `type` | `string` | 無 | 是 | CA 類型：`ROOT`（module 建自簽的 root 憑證並安裝）或 `SUBORDINATE`（module 只產生 CSR，由上層 CA 簽好後透過 `subordinate_certificate` 安裝）。 |
| `usage_mode` | `string` | `"GENERAL_PURPOSE"` | 否 | 用途：`GENERAL_PURPOSE`（約 400 美元／月）或 `SHORT_LIVED_CERTIFICATE`（憑證最長 7 天，約 50 美元／月）。 |
| `key_algorithm` | `string` | `"EC_prime256v1"` | 否 | CA 金鑰演算法：`EC_prime256v1`（預設）、`EC_secp384r1`、`EC_secp521r1`、`RSA_2048`、`RSA_3072`、`RSA_4096`。簽章演算法由 module 依金鑰決定（P-256 與 RSA 用 SHA-256、P-384 用 SHA-384、P-521 用 SHA-512）。 |
| `subject` | `object` | 無 | 是 | CA 憑證的 X.500 subject。`common_name` 必填（1–64 字元，也當 `Name` tag）；`country` 是兩碼大寫國碼。 |
| `validity_years` | `number` | `10` | 否 | `ROOT` 自簽憑證的有效年數，1–30（預設 10）。`SUBORDINATE` 的有效期由上層 CA 簽發時決定，這個值不使用。 |
| `permanent_deletion_time_in_days` | `number` | `30` | 否 | 刪除 CA 後可以還原的天數，7–30（預設 30）。期間內 CA 仍可還原，過了就永久刪除。 |
| `subordinate_certificate` | `object` | `null` | 否 | 上層 CA 用 `csr` 簽好的憑證與憑證鏈（PEM），只在 `type = "SUBORDINATE"` 時給；給了就安裝到 CA。`null` 時 CA 停在等待憑證的狀態，只輸出 CSR。 |
| `tags` | `map(string)` | `{}` | 否 | CA 的 tag；`Name` 由 module 加上（值是 `subject.common_name`）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `ca_arn` | CA 的 ARN，`iot-fleet` 註冊 CA 或簽發憑證時用。 |
| `ca_certificate_pem` | 已安裝的 CA 憑證（PEM）：`ROOT` 是自簽憑證，`SUBORDINATE` 是 `subordinate_certificate.certificate`；還沒安裝時是 `null`。 |
| `csr` | CA 的 CSR（PEM）。`SUBORDINATE` 時拿去給上層 CA 簽。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/acm-pca
```
