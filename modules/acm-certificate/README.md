# acm-certificate

建一張用 DNS 驗證的 ACM 公開憑證：在指定的 hosted zone 寫入驗證 record，並等到憑證簽發才結束。給 `region = "us-east-1"` 就是 CloudFront 能用的憑證，stack 不用另外宣告 provider alias。

## 用法

```hcl
module "cdn_certificate" {
  source = "git::https://github.com/<org>/<repo>.git//modules/acm-certificate?ref=acm-certificate-v0.1.0"

  domain_name               = "dev.example.com"
  subject_alternative_names = ["*.dev.example.com"]
  zone_id                   = module.zone.zone_id
  region                    = "us-east-1"
}
```

`certificate_arn` 取自驗證完成的 resource，拿到時憑證已經簽發，可以直接給 ALB listener 或 CloudFront。

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 驗證方式 | 只用 DNS 驗證，驗證 record 由 module 寫進 `zone_id` |
| 驗證 record | 每個不同的名稱一筆（apex 與 `*.apex` 共用一筆），`CNAME`、TTL 60 秒、`allow_overwrite = true` |
| 等待簽發 | `aws_acm_certificate_validation` 等到簽發，上限 `validation_timeout`（預設 `45m`） |
| region | 憑證與驗證 resource 都用 `region`；驗證 record 是 Route 53 的全域資源，不受影響 |
| 金鑰 | `key_algorithm` 預設 `RSA_2048`，可選 `EC_prime256v1`、`EC_secp384r1` |
| 換憑證 | `create_before_destroy`：改名稱時先建新憑證，再刪掉舊的 |

## 注意

- **委派要先生效**：zone 的上層 `NS` 委派還沒生效時，ACM 查不到驗證 record，apply 會一直等到 `validation_timeout` 才失敗。先 apply `route53-zone`、做好委派，再 apply 這個 module。
- 驗證 record 開 `allow_overwrite`，這是 `route53-record` 固定 `false` 以外唯一的例外。同一個帳號裡涵蓋同一個名稱的憑證（例如 ALB 用的 regional 憑證與 CloudFront 用的 us-east-1 憑證），ACM 給的驗證 record 完全相同，不覆寫的話第二張憑證會建不起來。代價是兩份 state 管同一筆 record：destroy 其中一張時會刪掉這筆 record，另一張憑證之後的自動續約會驗證失敗，要重新 apply 另一張補回 record。
- 憑證的所有名稱都要在 `zone_id` 這個 zone 底下，module 不檢查；名稱不在 zone 底下時，驗證 record 寫得進去但 ACM 查不到，同樣會等到 timeout。
- wildcard 只涵蓋一層：`*.dev.example.com` 不含 `dev.example.com` 本身，也不含 `a.b.dev.example.com`。
- CloudFront 只收 us-east-1 的憑證。CloudFront 能用的金鑰演算法有限制（`EC_secp384r1` 能不能用未確認），給 CloudFront 的憑證建議用 `RSA_2048` 或 `EC_prime256v1`。
- 憑證還被 ALB 或 CloudFront 使用時刪不掉，destroy 要先拿掉使用端。
- 不加 `Name` tag：ACM 的 tag 值不收 `*`，wildcard 名稱放不進去。
- ACM 公開憑證免費，自動續約靠驗證 record 一直留在 zone 裡，不要手動刪。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

email 驗證、匯入憑證、private CA 憑證（用 `acm-pca`）、跨帳號的 zone、多個 zone 的驗證、certificate transparency logging 設定、`early_renewal_duration`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `domain_name` | `string` | 無 | 是 | 憑證的主要名稱，例如 `dev.example.com` 或 `*.dev.example.com`。小寫、結尾不帶 `.`；wildcard 只能是最左邊一整層（`*.`）。名稱要在 `zone_id` 這個 zone 底下。 |
| `subject_alternative_names` | `list(string)` | `[]` | 否 | 其他名稱（SAN），最多 9 個，加上 `domain_name` 共 10 個（ACM 的預設上限）。格式規則跟 `domain_name` 一樣。apex 和 `*.apex` 共用同一筆驗證 record。 |
| `zone_id` | `string` | 無 | 是 | 寫入 DNS 驗證 record 的 hosted zone ID（`route53-zone` 的 `zone_id` 輸出）。憑證的所有名稱都要在這個 zone 底下，而且 zone 要已經完成委派。 |
| `region` | `string` | `null` | 否 | 憑證所在的 region；`null`（預設）用 provider 的 region。給 CloudFront 用的憑證一定要 `"us-east-1"`。 |
| `key_algorithm` | `string` | `"RSA_2048"` | 否 | 憑證金鑰演算法：`RSA_2048`（預設，相容性最好）、`EC_prime256v1`、`EC_secp384r1`。 |
| `validation_timeout` | `string` | `"45m"` | 否 | 等待憑證簽發的時間上限，Go duration 格式（例如 `45m`、`1h30m`，預設 `45m`）。zone 的委派還沒生效時，apply 會等到這個時間才失敗。 |
| `tags` | `map(string)` | `{}` | 否 | 憑證的 tag。module 不加 `Name`，因為 ACM 的 tag 值不收 wildcard 的 `*`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `certificate_arn` | 憑證 ARN，取自驗證完成的 resource，所以拿到時憑證已經簽發，可以直接給 ALB listener 或 CloudFront。 |
| `domain_name` | 憑證的主要名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/acm-certificate
```
