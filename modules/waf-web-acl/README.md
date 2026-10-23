# waf-web-acl

建一個 REGIONAL 的 WAFv2 web ACL，可以選擇加上 kill switch、rate limit（含 IP allowlist）、AWS managed rule groups、body size 例外規則與 CloudWatch logging。給掛在 ALB 前面的 API 用。

這個 module **不建 association**。ALB 的關聯由 `alb` 的 `web_acl_arn` 輸入負責，把這裡的 `web_acl_arn` 輸出傳過去就好。

## 用法

```hcl
module "waf" {
  source = "git::https://github.com/<org>/<repo>.git//modules/waf-web-acl?ref=waf-web-acl-v0.1.0"

  name = "alpha-dev-waf"

  rate_limit = {
    limit           = 2000
    allowlist_cidrs = ["10.10.0.0/16"]
  }

  managed_rule_groups = [
    { name = "AWSManagedRulesCommonRuleSet" },
    { name = "AWSManagedRulesKnownBadInputsRuleSet" },
  ]

  logging = {
    redacted_headers = ["authorization", "cookie", "X-Origin-Verify"]
  }

  tags = {
    Project = "alpha"
  }
}

module "alb" {
  # ...
  web_acl_arn = module.waf.web_acl_arn
}
```

完整範例（含 kill switch 與 body size 例外）見 [`examples/basic/`](./examples/basic/main.tf)。

## 規則與 priority

priority 由 module 依固定順序產生，呼叫端不能指定，而且不會因為少了某一條規則而位移：

| 順序 | 規則名稱 | priority | 動作 |
|---|---|---|---|
| 1 | `kill-switch` | 10 | `count` 或 `block` |
| 2 | （保留，allowlist 不是獨立規則，見下） | 20 | 無 |
| 3 | `rate-limit` | 30 | block |
| 4 | managed 群組，名稱 `<vendor>-<name>`，依清單順序 | 100、101、102、… | 群組原本的動作 |
| 5 | `body-size-limit` | 1000 | block |

## 注意

- **預設動作是 allow**，規則只負責擋。什麼都不開時 web ACL 沒有任何規則。
- **allowlist 只豁免 rate limit，不是 allow 規則。** WAF 的 allow 動作會結束評估，如果做成 allow 規則，名單內的 IP 連 managed 規則與 body size 規則都會跳過。所以這裡做成 rate limit 規則加上「不在 IP set 內」的條件：名單內的 IP 不受 rate limit，其他規則照常檢查。只支援 IPv4，CIDR 前綴長度 1–32，不接受 `0.0.0.0/0`。
- kill switch 的 `action = "block"` 擋所有請求，包含 allowlist 內的 IP，因為它排在最前面。給 `response_json` 時回 HTTP 503 和這段 JSON（最多 10240 字元，必須是合法 JSON）；只有 `block` 能給。要關掉就把 `kill_switch` 設回 `null`。
- `count_overrides` 只把群組內個別規則改成 count，群組本身永遠維持原本的動作（`override_action = none`），不提供把整個群組改成 count 的選項。
- `body_size_exempt_path_prefixes`：AWS 的 common rule set 用 `SizeRestrictions_BODY` 限制 8 KB body，會擋掉某些需要上傳大 body 的 path。要例外時，必須先在 `AWSManagedRulesCommonRuleSet`（vendor `AWS`）的 `count_overrides` 加上 `SizeRestrictions_BODY`，否則 validation 會拒絕。module 會再加一條 `body-size-limit`，對「不在例外 prefix 內」的請求擋超過 8192 bytes 的 body。prefix 要以 `/` 開頭、至少再有一個字元，不能只寫 `/`。
- logging：log group 名稱固定是 `aws-waf-logs-<name>`（WAF 只接受這個前綴）。**`authorization` 與 `cookie` 一律遮蔽**，`redacted_headers` 是在這兩個之外再加，名稱轉小寫、重複的會合併；想遮蔽 origin verify header 就把 `X-Origin-Verify` 加進來。WAF 建立 logging configuration 時會自己在帳號裡補 CloudWatch Logs 的 resource policy，所以執行 apply 的身分需要 `logs:PutResourcePolicy`；帳號內 resource policy 數量有上限（10 個）。用 `kms_key_arn` 時，key policy 要允許 `logs.<region>.amazonaws.com`。
- 一個 REGIONAL web ACL 只能在同一個 region 關聯資源；provider 的 region 就是 web ACL 的 region。
- web ACL 的 WCU 上限（預設 1500）由呼叫端自己留意，module 不計算。

## 刻意不做

- CLOUDFRONT scope（需要 us-east-1 的 provider）。
- 建 association。
- 呼叫端自訂 priority、自訂規則、geo／bot／IP reputation 以外的規則。
- IPv6 allowlist。
- 把整個 managed 群組改成 count。
- logging 到 S3 或 Firehose。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Web ACL 名稱，也是 CloudWatch metric 名稱與 log group `aws-waf-logs-<name>` 的後綴。1–128 字元，限英數字、`_`、`-`。 |
| `kill_switch` | `object` | `null` | 否 | 比對所有請求的緊急開關，`null` 時關閉。欄位：`action`（`count` 只觀察，`block` 擋下）、`response_json`（只有 `block` 能給，是 503 回應的 body，必須是合法 JSON，最多 10240 字元）。 |
| `rate_limit` | `object` | `null` | 否 | 流量限制，`null` 時不限。欄位：`limit`（每個來源 IP 每 5 分鐘的請求數上限，超過就擋，10–2000000000）、`allowlist_cidrs`（IPv4 CIDR，前綴長度 1–32，預設 `[]`；只免除流量限制，其他規則照樣套用）。 |
| `managed_rule_groups` | `list(object)` | `[]` | 否 | 依評估順序排列的 managed rule group，`vendor` 加 `name` 不可重複。欄位：`name`、`vendor`（預設 `AWS`），兩者皆 1–100 字元，限英數字、`_`、`-`；`count_overrides`（預設 `[]`，群組內改成只 count 不擋的規則名稱，不可重複）。群組本身一律維持自己的 action。 |
| `body_size_exempt_path_prefixes` | `list(string)` | `[]` | 否 | 不受 8 KB body 大小限制的 path prefix，以 `/` 開頭且後面至少一個字元，不可重複。`managed_rule_groups` 必須有 `AWSManagedRulesCommonRuleSet`（vendor `AWS`），且 `SizeRestrictions_BODY` 在它的 `count_overrides` 裡；module 會另外加一條規則，擋下其他 path 的過大 body。 |
| `logging` | `object` | `null` | 否 | 寫到 CloudWatch log group `aws-waf-logs-<name>` 的 log，`null` 時不開。欄位：`retention_days`（預設 14，限 CloudWatch Logs 接受的值，不可為 0）、`kms_key_arn`（預設 `null`）、`redacted_headers`（預設 `["authorization", "cookie"]`，在這兩個一律遮蔽的 header 之外追加，名稱轉小寫，1–64 字元）。origin verify header 要加在這裡。 |
| `tags` | `map(string)` | `{}` | 否 | web ACL、IP set 與 log group 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `web_acl_arn` | Web ACL ARN，傳給 `alb` module 做關聯；這個 module 不建關聯。 |
| `web_acl_name` | Web ACL 名稱。 |
| `ip_set_arn` | allowlist IP set ARN；沒有 allowlist 時是 `null`。 |
| `log_group_name` | WAF log group 名稱 `aws-waf-logs-<name>`；沒開 logging 時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/waf-web-acl
```
