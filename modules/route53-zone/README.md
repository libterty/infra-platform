# route53-zone

建一個 Route 53 hosted zone。`private_vpc_ids` 空的時候是 public zone，有值就是只在那些 VPC 內解析的 private zone。範本用它替每個環境建一個子網域 zone（例如 `dev.example.com`）。

## 用法

```hcl
module "zone" {
  source = "git::https://github.com/<org>/<repo>.git//modules/route53-zone?ref=route53-zone-v0.1.0"

  name = "dev.example.com"
}
```

public zone 建好之後，拿 `name_servers` 輸出到上層網域（例如 `example.com`）建一筆 `NS` record 做委派。委派是一次性的手動步驟，這個 module 不做。

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| public／private | `private_vpc_ids` 空的是 public zone，有值是 private zone |
| 刪除 | `force_destroy` 預設 `false`，zone 裡還有 record 時刪不掉 |
| tag | 給定的 `tags` 加上 `Name`（值是 `name`） |

## 注意

- 每個 hosted zone 每月約 0.5 美元，查詢量另計。
- 委派還沒生效前，public zone 的 record 在網際網路上查不到；`acm-certificate` 的 DNS 驗證會一直等到 timeout。先確認上層網域的 `NS` record 已經指到 `name_servers`，再 apply 憑證。
- private zone 的 VPC 必須在 provider 的 region，而且 VPC 要開 `enableDnsHostnames` 與 `enableDnsSupport`。
- 名稱只收小寫，結尾不帶 `.`；Route 53 本身不分大小寫，統一小寫可以避免 plan 一直出現差異。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

DNSSEC（`aws_route53_key_signing_key` 要 us-east-1 的 KMS key 與 key policy）、query log、reusable delegation set、跨帳號 VPC 關聯、record（用 `route53-record`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | hosted zone 的網域名稱，例如 `dev.example.com`。小寫、至少兩層、結尾不帶 `.`，最長 253 字元。 |
| `comment` | `string` | `null` | 否 | zone 的說明；`null` 時用 AWS 的預設值（`Managed by Terraform`）。 |
| `private_vpc_ids` | `list(string)` | `[]` | 否 | 要關聯的 VPC ID（`vpc-` 開頭）。有值就建 private zone，只在這些 VPC 內解析；空的（預設）就建 public zone。VPC 必須在 provider 的 region。 |
| `force_destroy` | `bool` | `false` | 否 | destroy 時是否連 zone 裡的 record 一起刪（預設 `false`）。`false` 時 zone 裡還有 Terraform 以外建的 record 就刪不掉，避免誤刪。 |
| `tags` | `map(string)` | `{}` | 否 | zone 的 tag；`Name` 由 module 加上（值是 `name`）。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `zone_id` | hosted zone ID，`route53-record` 與 `acm-certificate` 的 `zone_id` 用這個值。 |
| `name` | zone 的網域名稱（結尾不帶 `.`）。 |
| `name_servers` | public zone 的 name server，拿去在上層網域建 NS 委派；private zone 時是空 list。 |
| `arn` | zone 的 ARN。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/route53-zone
```
