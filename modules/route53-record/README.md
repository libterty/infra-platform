# route53-record

在一個 hosted zone 裡建多筆 record。`records` 的每一筆是一般 record（`values` 加 `ttl`）或 alias（指到 CloudFront、ALB 等 AWS 資源），兩種擇一。不覆寫已經存在的 record。

## 用法

```hcl
module "records" {
  source = "git::https://github.com/<org>/<repo>.git//modules/route53-record?ref=route53-record-v0.1.0"

  zone_id = module.zone.zone_id

  records = {
    app = {
      name = "app.dev.example.com"
      type = "A"
      alias = {
        name    = module.cdn.domain_name
        zone_id = module.cdn.hosted_zone_id
      }
    }
    www = {
      name   = "www.dev.example.com"
      type   = "CNAME"
      ttl    = 300
      values = ["app.dev.example.com"]
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| 覆寫 | `allow_overwrite = false`：同名同類型的 record 已經存在時 apply 失敗，不會接管 |
| 類型 | 只收 `A`、`AAAA`、`CNAME`、`TXT`、`MX`、`NS`、`CAA`、`SRV` |
| alias | 只能用在 `A`、`AAAA`，不帶 `ttl`；`evaluate_target_health` 預設 `false` |
| 一般 record | `values` 非空，`ttl` 必填（60–172800 秒）；`CNAME` 只能一個值 |
| routing | 一律 simple routing |

## 注意

- 一個 module 呼叫只對一個 zone。不同 zone 的 record 分開呼叫。
- `records` 的 key 只用在 Terraform address 與 `fqdns` 輸出，改 key 會讓 Terraform 刪掉重建那筆 record，中間會有短暫查不到的時間。
- 要接管 zone 裡已經存在的 record，先用 `terraform import` 匯入，不要靠覆寫。ACM 的 DNS 驗證 record 由 `acm-certificate` 自己建，不要在這裡重複建。
- `TXT` 的單一值超過 255 字元時，要自己切成多段並用 `""` 隔開（例如 DKIM 公鑰），Route 53 不會自動切。
- alias 指到 CloudFront 時，`zone_id` 是 CloudFront 固定的 `Z2FDTNDATAQYW2`，取 `cloudfront-distribution` 的輸出即可。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

routing policy（weighted、latency、failover、geolocation 等）、health check、跨 zone 的 record、`PTR`、`NAPTR`、`DS` 等其他類型、覆寫既有 record。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `zone_id` | `string` | 無 | 是 | record 所在的 hosted zone ID（`route53-zone` 的 `zone_id` 輸出），例如 `Z0123456789ABCDEFGHIJ`。 |
| `records` | `map(object)` | 無 | 是 | 這個 zone 裡要建的 record，key 是短名（只用在 Terraform address 與 `fqdns` 輸出）。欄位：`name`（record 名稱，例如 `app.dev.example.com`）、`type`（`A`、`AAAA`、`CNAME`、`TXT`、`MX`、`NS`、`CAA`、`SRV`）。其餘二選一：一般 record 給 `values`（非空）與 `ttl`（60–172800 秒），`CNAME` 只能一個值；alias 給 `alias = { name, zone_id, evaluate_target_health }`（`evaluate_target_health` 預設 `false`），只能用在 `A`、`AAAA`，不給 `ttl`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `fqdns` | `records` 的 key 對應 record 的 FQDN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/route53-record
```
