# cloudfront-distribution

建一個 CloudFront distribution，加上每個 S3 origin 用的 origin access control（OAC）。給 SPA 前端（S3）與放在 CloudFront 後面的 API（ALB、API Gateway）用。

這個 module **不建** bucket policy、WAF、憑證與 DNS record：bucket policy 由 `s3-bucket` 的 `cloudfront_distribution_arns` 負責，WAF 用 `waf-web-acl`（`scope = "CLOUDFRONT"`），憑證用 `acm-certificate`（`region = "us-east-1"`），alias record 用 `route53-record`，把這裡的 `domain_name` 與 `hosted_zone_id` 傳過去。

## 用法

```hcl
module "web" {
  source = "git::https://github.com/<org>/<repo>.git//modules/cloudfront-distribution?ref=cloudfront-distribution-v0.1.0"

  name            = "alpha-dev-web"
  aliases         = ["app.dev.example.com"]
  certificate_arn = module.certificate.certificate_arn # us-east-1
  web_acl_arn     = module.edge_waf.web_acl_arn        # CLOUDFRONT scope

  origins = {
    site = { type = "s3", domain_name = module.bucket.bucket_regional_domain_name }
    api  = { type = "custom", domain_name = "abcde12345.execute-api.ap-northeast-1.amazonaws.com" }
  }

  default_behavior = { origin = "site" }

  ordered_behaviors = [
    {
      path_pattern          = "/api/*"
      origin                = "api"
      allowed_methods       = "all"
      cache_policy          = "Managed-CachingDisabled"
      origin_request_policy = "Managed-AllViewerExceptHostHeader"
    },
  ]

  origin_verify              = { origin = "api", header_name = "X-Origin-Verify" }
  origin_verify_header_value = var.origin_verify_header_value # TF_VAR_origin_verify_header_value

  default_root_object = "index.html"
}
```

完整範例：只有 S3 的 SPA 見 [`examples/basic/`](./examples/basic/main.tf)；S3 加 API Gateway 見 [`examples/spa-with-api/`](./examples/spa-with-api/main.tf)。

## 固定行為

- viewer：`redirect-to-https`、`compress = true`；有憑證時 `TLSv1.2_2021`、`sni-only`。
- `http_version = "http2and3"`、`is_ipv6_enabled = true`。
- `s3` origin：每個建一個 OAC（`sigv4`、`always`），名稱 `<name>-<origin key>`。
- `custom` origin：`https-only`、`origin_ssl_protocols = ["TLSv1.2"]`，不能改成 HTTP。
- `allowed_methods` 只有三種組合：`read`（GET、HEAD）、`read_options`（再加 OPTIONS）、`all`（7 種）。三種都只快取 GET、HEAD。

## 注意

- **origin verify 的值**：用 `origin_verify_header_value`（sensitive）給，從 `TF_VAR_origin_verify_header_value` 傳入，不要寫進 tfvars。plan 會把整個 `origin` 顯示成 `(sensitive value)`，但 provider 沒有把 `custom_header.value` 標成 sensitive，**state 裡仍是明文**。state 要放在加密、權限受控的 bucket。
- 換 origin verify 值時，origin 端要先能同時接受新舊兩個值，再改這裡，否則換值期間 origin 會回 403。
- **`spa_fallback`**：建一個 CloudFront Function `<name>-spa-fallback`（`cloudfront-js-2.0`，程式在 [`functions/spa-fallback.js`](./functions/spa-fallback.js)），只掛在預設 behavior 的 viewer-request。最後一段路徑沒有副檔名的請求（例如 `/orders/42`）改讀 `/index.html`；有副檔名的照常讀，不存在時仍回 S3 的錯誤。`ordered_behaviors`（例如 `/api/*`）不掛，API 的 403、404 原樣回給 client。CloudFront Function 依呼叫次數計費，預設 behavior 的每個請求都算一次。開啟時 `name` 最多 51 字元，function 名稱才不會超過 64 字元。
- **轉送 Host header 時的憑證**：behavior 的 origin request policy 轉送 viewer 的 Host（例如 `Managed-AllViewer`）時，CloudFront 用 Host 做 SNI 與憑證比對，origin 的憑證要涵蓋 viewer 用的網域，而不是 `domain_name`。API Gateway 的 execute-api 網址只認自己的名稱，所以 API Gateway origin 要用 `Managed-AllViewerExceptHostHeader`。
- 三種 policy 都收 managed policy 名稱（例如 `Managed-CachingOptimized`），module 用 data source 查 ID；名稱打錯時 plan 會失敗。
- 沒給 `certificate_arn` 時用 CloudFront 預設憑證（`*.cloudfront.net`），這時 CloudFront 不套用 `TLSv1.2_2021`，`aliases` 也必須是空的。
- `web_acl_arn` 只收 CLOUDFRONT scope（`global/webacl`）的 ARN；REGIONAL 的 web ACL 掛不上 CloudFront。
- S3 origin 只收 bucket 的 regional domain name。website endpoint 不支援 HTTPS 也不支援 OAC，validation 會擋。

## 刻意不做

- Lambda@Edge、`spa_fallback` 以外的 CloudFront Functions、origin group（failover）。
- signed URL（key group）、field-level encryption、continuous deployment。
- VPC origin（v9 的 ALB 維持 public 加 origin verify header）。
- 自訂 cache policy、自訂 TTL、舊式 `forwarded_values`。
- logging：用 `log-delivery`，source 是這裡的 `arn`，`region = "us-east-1"`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | distribution 的識別名稱：`Name` tag、`comment` 的預設值，也是 OAC 名稱 `<name>-<origin key>` 的前綴。1–64 字元，限英數字、`_`、`-`。 |
| `comment` | `string` | `null` | 否 | distribution 的說明，最多 128 字元，`null` 時用 `name`。 |
| `aliases` | `list(string)` | `[]` | 否 | distribution 的自訂網域（CNAME），例如 `app.dev.example.com`，不可重複。非空時必須給 `certificate_arn`，憑證要涵蓋每個名稱。 |
| `certificate_arn` | `string` | `null` | 否 | viewer 憑證，必須是 us-east-1 的 ACM 憑證 ARN（CloudFront 只讀 us-east-1 的憑證）。`null` 時用 CloudFront 預設憑證，此時 `aliases` 必須是空的。 |
| `web_acl_arn` | `string` | `null` | 否 | 掛在 distribution 上的 WAF web ACL，必須是 CLOUDFRONT scope 的 ARN（`arn:aws:wafv2:us-east-1:<帳號>:global/webacl/...`）。`null` 時不掛。 |
| `price_class` | `string` | `"PriceClass_200"` | 否 | edge location 範圍：`PriceClass_100`、`PriceClass_200`（預設，含亞洲）或 `PriceClass_All`。 |
| `origins` | `map(object)` | 無 | 是 | key 是 origin ID（behavior 用它指定 origin），至少一個。欄位：`type`（`s3` 時 module 建一個 OAC；`custom` 時固定 `https-only` 與 TLSv1.2）、`domain_name`（`s3` 要給 bucket 的 regional domain name，不能是 website endpoint；`custom` 只給主機名稱，不含 `https://` 與路徑）、`origin_path`（以 `/` 開頭、不以 `/` 結尾）、`custom`（只有 `custom` 能給：`https_port` 預設 443、`read_timeout` 預設 30 秒（1–180）、`keepalive_timeout` 預設 5 秒（1–180））。 |
| `origin_verify` | `object` | `null` | 否 | 在一個 `custom` origin 的回源請求加上 origin verify header，`null` 時不加。欄位：`origin`（`origins` 裡 `type = "custom"` 的 key）、`header_name`（例如 `X-Origin-Verify`）。值由 `origin_verify_header_value` 給，兩者要一起給或一起不給。 |
| `origin_verify_header_value` | `string` | `null` | 否 | origin verify header 的值（sensitive）。從 `TF_VAR_origin_verify_header_value` 環境變數傳入，不要寫進 tfvars；plan 會遮住，state 仍是明文。 |
| `default_behavior` | `object` | 無 | 是 | 預設 behavior。欄位：`origin`（`origins` 的 key）、`allowed_methods`（`read` 是 GET、HEAD，`read_options` 再加 OPTIONS，`all` 是全部 7 種；一律只快取 GET、HEAD）、`cache_policy`（預設 `Managed-CachingOptimized`）、`origin_request_policy`（預設 `null`）、`response_headers_policy`（預設 `Managed-SecurityHeadersPolicy`）。三個 policy 都收 managed policy 名稱，module 查出 ID。 |
| `ordered_behaviors` | `list(object)` | `[]` | 否 | 依比對順序排列的其他 behavior，`path_pattern` 不可重複（例如 `/api/*`）。其他欄位與預設值同 `default_behavior`。 |
| `spa_fallback` | `bool` | `false` | 否 | `true` 時建一個 CloudFront Function `<name>-spa-fallback`，掛在預設 behavior 的 viewer-request：最後一段路徑沒有副檔名的請求改成讀 `/index.html`，給 SPA 的前端路由用。`ordered_behaviors`（例如 `/api/*`）不受影響。 |
| `default_root_object` | `string` | `null` | 否 | 請求根路徑時回的物件，例如 `index.html`（不含開頭的 `/`）。 |
| `geo_restriction` | `object` | `null` | 否 | 地理限制，`null` 時不限。欄位：`type`（`whitelist` 只允許、`blacklist` 擋下）、`locations`（ISO 3166-1 alpha-2 大寫國碼，至少一個）。 |
| `tags` | `map(string)` | `{}` | 否 | distribution 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `distribution_id` | distribution ID（建立 invalidation 時用）。 |
| `arn` | distribution 的 ARN，給 `s3-bucket` 的 `cloudfront_distribution_arns` 與 `log-delivery` 的 source 用。 |
| `domain_name` | distribution 的網域（`*.cloudfront.net`），alias record 指向它。 |
| `hosted_zone_id` | CloudFront 的 hosted zone ID，給 Route 53 alias record 用。 |
| `oac_ids` | `s3` origin 的 key 對應 OAC ID。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/cloudfront-distribution
```
