# alb

建一個 Application Load Balancer、HTTP／HTTPS listener、ALB 整體的 ELB 5xx 告警，可選 access log 與 WAF 關聯。target group 與 listener rule 可以由 `ecs-service` 建；0.2.0 起也可以在這個 module 建，見〈target group 與 listener rule〉。

## 用法

```hcl
module "alb" {
  source = "git::https://github.com/<org>/<repo>.git//modules/alb?ref=alb-v0.1.0"

  name               = "alpha-prod"
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [local.alb_sg_id]
  certificate_arn    = local.certificate_arn
  sns_topic_arns     = [module.alarm_topic.topic_arn]

  access_logs = { bucket = local.alb_log_bucket, prefix = "alb" }
  web_acl     = { arn = aws_wafv2_web_acl.this.arn }
}
```

範例：[`examples/https/`](./examples/https/main.tf)、[`examples/http-only/`](./examples/http-only/main.tf)。

## 怎麼接

- `listener_arn` 接到 `ecs-service` 的 `load_balancer.listener_arn`。
- `alb_arn_suffix` 接到 `ecs-service` 與 `ecs-service-alarms` 的 `load_balancer.alb_arn_suffix`。

## Listener 行為

| `certificate_arn` | HTTP:80 預設 action | HTTPS:443 | `listener_arn` |
|---|---|---|---|
| 有 | 301 轉 HTTPS | 建立，TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`，預設回 404 | HTTPS listener |
| `null` | 回 404（`text/plain`） | 不建立 | HTTP listener |

預設 action 回 404 而不是 403：沒有對應路由就是「找不到」。

## target group 與 listener rule

0.2.0 起可以在這個 module 建 target group 與 listener rule；兩個變數都預設 `{}`，不給就跟 0.1.0 一樣什麼都不建。

- `target_groups`：key 對應 `port`（必填）、`protocol_version`（`HTTP1`）、`deregistration_delay`（300）、`health_check`（`path` `/health`、`matcher` `200`、`interval` 15、`timeout` 5、`healthy_threshold` 2、`unhealthy_threshold` 3，可只覆寫部分欄位）。名稱是 `<name>-<key>`，HTTP；非空時必須給 `vpc_id`。0.4.0 起多兩個欄位：`target_type`（`ip` 或 `instance`，預設 `ip`）與 `stickiness`（`object({ duration })`，預設 `null`；開了就是 `lb_cookie`，`duration` 1–604800 秒）。
- `listener_rules`：key 對應 `priority`、`target_group`（`target_groups` 的 key）或 `forward`（加權轉發，見下一節；兩者擇一）、`path_patterns`、`host_headers`、`require_origin_verify`（預設 `false`）。規則掛在 HTTPS listener；沒有 `certificate_arn` 時掛在 HTTP listener。
- origin verify：`origin_verify_header_name` 與 `origin_verify_header_value`（`sensitive`）要一起給或一起不給。分成兩個變數是因為包成一個物件時，`var.x == null` 的結果會變成 sensitive，不能拿來當 `for_each` 或 `dynamic` 的條件。`require_origin_verify` 預設 `false`（要用才開）：只有設成 `true` 的規則才會多一個 `http_header` 條件；就算 header 有設定，沒開的規則也不會加。值請從 `TF_VAR_origin_verify_header_value` 傳入，不要寫進 tfvars；它仍會以明文存在 state，state 的存取控制要跟 secret 一樣嚴。
- `require_origin_verify = true` 但沒有設定 `origin_verify_header_name` 與 value 時，validation 會擋下，所以不會有規則默默少了這層保護。
- validation：規則的 `target_group` 要存在；每條規則 `target_group` 與 `forward` 要剛好給一個；`priority` 不可重複；每條規則至少有一個 path pattern 或 host header（只有 header 條件的規則不接受）；ALB 每條規則的條件值上限是 5，`path_patterns`、`host_headers` 與 origin verify header（`require_origin_verify = true` 時算 1 個）合計不可超過；`<name>-<key>` 要是 1–32 字元的字母、數字與連字號，不能以連字號開頭或結尾。
- 改 `port` 會讓 target group 重建；規則還在用的時候刪除會失敗（`ResourceInUse`）。要換 port 就新增一個 key、把規則改指過去，再移除舊的。

## 加權 forward（0.4.0）

規則用 `forward` 取代 `target_group`，就能把流量按權重分給最多 5 個 target group，用在金絲雀或新舊系統並存。

```hcl
listener_rules = {
  app = {
    priority      = 10
    host_headers  = ["app.example.com"]
    forward = {
      targets = {
        new = { target_group = "web", weight = 10 }  # 本 module 的 target group
        old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy-web/0123456789abcdef", weight = 90 }
      }
      stickiness_duration = 600
    }
  }
}
```

- 每個 target 的 `target_group` 與 `target_group_arn` 擇一。`target_group` 是本 module `target_groups` 的 key；`target_group_arn` 是外部的 target group（舊系統、ECS、別的 ALB 建的），必須長得像 `arn:aws:elasticloadbalancing:<region>:<account>:targetgroup/<name>/<id>`，也就是 ELB target group ARN。只用外部 ARN 時，不需要 `vpc_id` 與 `target_groups`。
- validation：`targets` 1–5 個（ALB 上限）；`weight` 0–999，且至少一個大於 0；`stickiness_duration` 1–604800。原本的 validation（`priority` 不重複、至少一個條件、條件值上限 5、origin verify）對 forward 規則一樣有效。
- 沒給 `forward` 的規則寫法與 0.3.0 完全一樣。

### stickiness

- target group 層：`target_groups` 的 `stickiness` 開 `lb_cookie`，讓同一個 client 留在同一個 target group 內的同一個 target。
- 規則層：`forward.stickiness_duration` 讓同一個 client 在這段時間內固定到同一個 target group，加權分流時避免 client 在新舊系統間來回跳。
- 規則裡用到的本 module target group 只要有一個開了 `stickiness`，就必須給 `stickiness_duration`，否則 validation 擋下。只用外部 ARN 的規則可給可不給。
- aws provider 的 `forward.stickiness.duration` 在 schema 裡是必填（文件寫 Optional，以 schema 為準）。所以沒給 `stickiness_duration` 時，module 不送 `stickiness` block，不是送 `enabled = false`；給了才送 `enabled = true` 與該 duration。

### 與 lb-traffic-breaker 的關係，以及權重被改回去（R1）

- 權重寫在 tfvars。`lb-traffic-breaker` 觸發時，Lambda 會直接改 AWS 上這條規則的權重（舊系統 100%、其他 0）。
- module **不加 `ignore_changes`**：加了之後，tfvars 改權重也不會生效，金絲雀就調不動了。
- 代價：斷路器改了權重之後，下次 apply 會把權重改回 tfvars 的值，新系統又會接到流量。所以斷路器觸發後，要先把 tfvars 裡那條規則改成舊系統 100%，再 apply；apply 前請看 plan 有沒有改到權重。
- `listener_rule_arns` 與 `listener_arns` 是給 `lb-traffic-breaker` 用的輸出。

### ALB 加權分流的行為限制

- 加權 target group **不會自動 failover**。權重是你設的比例，某個 target group 變 unhealthy 不會把它的流量轉給其他 target group；要降級就要改權重（手動，或由斷路器改）。
- 一個 target group 內所有 target 都 unhealthy 時，ALB 會 fail open：把請求送給所有 target，不管健康檢查。所以全掛的新系統還是會收到流量，不會被自動排除。

## 注意

- **沒有憑證時只開 HTTP:80，ALB 的 security group 必須收窄**。SG 由 `network` stack 建，收窄規則也在那裡檢查；這個 module 不建 SG，也看不到 SG 的內容。
- **access log 的 bucket 只能用 SSE-S3 加密**。ALB 的 log delivery 不支援 customer managed KMS，設了 KMS 之後 log 會默默遺失。bucket 由 `foundation` stack 建，這裡只收名稱（不是 ARN）。
- `additional_certificate_arns` 只掛在 HTTPS listener，所以必須同時給 `certificate_arn`。
- **WAF 與 ALB 在同一個 configuration 建時，用 `web_acl`，不要用 `web_acl_arn`**。`web_acl_arn` 是 unknown 時，`count` 無法在 plan 決定，會報 `Invalid count argument`；`web_acl` 是物件，是否為 `null` 在 plan 時就知道，`arn` unknown 也沒關係。`web_acl` 與 `web_acl_arn` 同時給會被 validation 擋下。
- `deletion_protection` 預設 `true`；測試或 PoC 要 destroy 時先設成 `false` 並 apply。
- ELB 5xx 告警只有 `LoadBalancer` 維度，所以放在這裡，一個 ALB 一份；各服務的 target 告警在 `ecs-service-alarms`。

## 刻意不做

- 不建 security group、Web ACL（只做關聯）、access log bucket。
- target group 只有 `ip` 與 `instance` 兩種類型、HTTP；不建 `lambda`、`alb` 類型。listener rule 只有 forward 一種 action。
- 不加 `ignore_changes` 保護權重（見上方 R1 說明）。
- 不建 IAM。
- 不支援 NLB、mutual TLS、Cognito／OIDC 認證 action。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | ALB 名稱，2–32 字元，不得以 `internal-` 開頭 |
| `internal` | `bool` | `false` | 否 | `true` 建內部 ALB |
| `subnet_ids` | `list(string)` | 無 | 是 | 至少兩個不同的 subnet |
| `security_group_ids` | `list(string)` | 無 | 是 | 至少一個 SG |
| `certificate_arn` | `string` | `null` | 否 | ACM 憑證；`null` 時只開 HTTP:80 |
| `additional_certificate_arns` | `set(string)` | `[]` | 否 | SNI 憑證；非空時必須給 `certificate_arn` |
| `idle_timeout` | `number` | `60` | 否 | 1–4000 秒 |
| `deletion_protection` | `bool` | `true` | 否 | 刪除保護 |
| `access_logs` | `object({ bucket, prefix })` | `null` | 否 | `bucket` 為 SSE-S3 bucket 名稱；`prefix` 可省略 |
| `web_acl` | `object({ arn })` | `null` | 否 | regional WAFv2 Web ACL；只做關聯。ARN 在 plan 時還不知道時（同一個 configuration 建 WAF），一定要用這個變數 |
| `web_acl_arn` | `string` | `null` | 否 | regional WAFv2 Web ACL ARN；**只適合 plan 時已知的值**，日後移除。與 `web_acl` 不能同時給 |
| `vpc_id` | `string` | `null` | 視情況 | target group 的 VPC；`target_groups` 非空時必填 |
| `target_groups` | `map(object)` | `{}` | 否 | 見上方 target group 與 listener rule |
| `listener_rules` | `map(object)` | `{}` | 否 | 見上方 target group 與 listener rule、加權 forward |
| `origin_verify_header_name` | `string` | `null` | 否 | CDN 加在回源請求的 header 名稱；要跟 value 一起給 |
| `origin_verify_header_value` | `string`（sensitive） | `null` | 否 | header 的值；從 `TF_VAR_origin_verify_header_value` 傳入 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警通知的 SNS topic；至少一個 |
| `alarm_config` | `object({ elb_5xx_threshold, period })` | `{}` | 否 | `elb_5xx_threshold` 預設 1、`period` 預設 60 秒 |
| `tags` | `map(string)` | `{}` | 否 | tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `alb_arn` | `string` | ALB ARN |
| `alb_arn_suffix` | `string` | `app/<name>/<id>`，給告警與 `requests_per_target` |
| `alb_dns_name` | `string` | ALB DNS 名稱 |
| `alb_zone_id` | `string` | alias record 用的 hosted zone ID |
| `listener_arn` | `string` | 有憑證時是 HTTPS listener，否則是 HTTP listener |
| `listener_arns` | `object({ http, https })` | `http` 一定有值；沒有憑證時 `https` 是 `null` |
| `listener_rule_arns` | `map(string)` | listener rule ARN，key 同 `listener_rules`；沒給時是空 map |
| `listener_protocol` | `string` | `"HTTPS"` 或 `"HTTP"` |
| `alarm_arns` | `map(string)` | 告警 ARN，目前只有 `elb_5xx` |
| `web_acl_association_ids` | `list(string)` | WAF 關聯 ID；沒關聯時是空 list |
| `target_group_arns` | `map(string)` | target group ARN，key 同 `target_groups`；沒給時是空 map |
| `target_group_arn_suffixes` | `map(string)` | `targetgroup/<name>/<id>`，key 同 `target_groups`，給 CloudWatch dimension 用 |

## 測試

```bash
scripts/validate.sh modules/alb
```
