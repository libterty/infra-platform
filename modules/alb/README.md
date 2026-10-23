# alb

建一個 Application Load Balancer、HTTP／HTTPS listener、ALB 整體的 ELB 5xx 告警，可選 WAF 關聯。target group 與 listener rule 可以由 `ecs-service` 建；0.2.0 起也可以在這個 module 建，見〈target group 與 listener rule〉。

## 用法

```hcl
module "alb" {
  source = "git::https://github.com/<org>/<repo>.git//modules/alb?ref=alb-v0.1.0"

  name               = "alpha-prod"
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [local.alb_sg_id]
  certificate_arn    = local.certificate_arn
  sns_topic_arns     = [module.alarm_topic.topic_arn]

  web_acl = { arn = aws_wafv2_web_acl.this.arn }
}
```

範例：[`examples/https/`](./examples/https/main.tf)、[`examples/http-only/`](./examples/http-only/main.tf)。

## 怎麼接

- `listener_arn` 接到 `ecs-service` 的 `load_balancer.listener_arn`。
- `alb_arn_suffix` 接到 `ecs-service` 與 `ecs-service-alarms` 的 `load_balancer.alb_arn_suffix`。
- access log 用 `log-delivery` 開：`alb_arn` 當 source 的 `resource_arn`，見下一節。

## access log

0.5.0 起這個 module 不再開 access log（移除了 `access_logs`），改由 `log-delivery` 用 CloudWatch Logs 的 vended delivery 送。可以送 CloudWatch Logs、S3 或 Firehose，log type 有 `ALB_ACCESS_LOGS`、`ALB_CONNECTION_LOGS`、`ALB_HEALTH_CHECK_LOGS`。

```hcl
module "alb_access_logs" {
  source  = "app.terraform.io/<org>/log-delivery/aws"
  version = "~> 0.2.0"

  name_prefix = "alpha-prod-alb"

  sources      = { access = { resource_arn = module.alb.alb_arn, log_type = "ALB_ACCESS_LOGS" } }
  destinations = { archive = { type = "S3", resource_arn = module.access_log_bucket.arn } }
  deliveries   = { access = { source = "access", destination = "archive" } }
}
```

送 S3 時，bucket 用 `s3-bucket` 建並給 `log_delivery = ["vended_logs"]`。從 0.4.x 升級：拿掉 `access_logs`，加上面這段；bucket 的 `alb_access_logs` 改成 `vended_logs`。vended delivery 寫進 S3 的路徑是 `AWSLogs/<account>/elasticloadbalancing/<region>/<yyyy>/<MM>/<dd>/`（AWS 文件〈Logs sent to Amazon S3〉），前面不會有舊寫法的 `prefix`；查 log 的 Athena 表或 lifecycle 規則如果依賴 prefix，要跟著改。

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
- `additional_certificate_arns` 只掛在 HTTPS listener，所以必須同時給 `certificate_arn`。
- **WAF 與 ALB 在同一個 configuration 建時，用 `web_acl`，不要用 `web_acl_arn`**。`web_acl_arn` 是 unknown 時，`count` 無法在 plan 決定，會報 `Invalid count argument`；`web_acl` 是物件，是否為 `null` 在 plan 時就知道，`arn` unknown 也沒關係。`web_acl` 與 `web_acl_arn` 同時給會被 validation 擋下。
- `deletion_protection` 預設 `true`；測試或 PoC 要 destroy 時先設成 `false` 並 apply。
- ELB 5xx 告警只有 `LoadBalancer` 維度，所以放在這裡，一個 ALB 一份；各服務的 target 告警在 `ecs-service-alarms`。

## 刻意不做

- 不建 security group、Web ACL（只做關聯）、access log（用 `log-delivery`）。
- target group 只有 `ip` 與 `instance` 兩種類型、HTTP；不建 `lambda`、`alb` 類型。listener rule 只有 forward 一種 action。
- 不加 `ignore_changes` 保護權重（見上方 R1 說明）。
- 不建 IAM。
- 不支援 NLB、mutual TLS、Cognito／OIDC 認證 action。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | ALB 名稱。2–32 字元，限英數字與 `-`，頭尾不可是 `-`，不可以 `internal-` 開頭。 |
| `internal` | `bool` | `false` | 否 | `true` 時建內部 ALB。 |
| `subnet_ids` | `list(string)` | 無 | 是 | ALB 所在的 subnet，至少兩個、分屬不同 AZ；對外時用 public tier，`internal = true` 時用 app tier。 |
| `security_group_ids` | `list(string)` | 無 | 是 | ALB 的 security group，至少一個，由 network stack 建立。 |
| `certificate_arn` | `string` | `null` | 否 | HTTPS listener 用的 ACM 憑證 ARN。`null` 時只開 HTTP:80，這時 network stack 必須收窄 ALB 的 security group。 |
| `additional_certificate_arns` | `set(string)` | `[]` | 否 | 掛在 HTTPS listener 上做 SNI 的額外 ACM 憑證；非空時必須給 `certificate_arn`。 |
| `idle_timeout` | `number` | `60` | 否 | 閒置逾時秒數，1–4000。 |
| `deletion_protection` | `bool` | `true` | 否 | 是否開啟刪除保護；測試或 PoC 要 destroy 前先設成 `false` 並 apply。 |
| `web_acl` | `object` | `null` | 否 | 要關聯的 regional WAFv2 Web ACL，格式 `{ arn }`，`null` 時不關聯；module 不建 Web ACL。Web ACL 在同一個 configuration 建、plan 時還不知道 ARN 時，一定要用這個變數，不要用 `web_acl_arn`。與 `web_acl_arn` 不能同時給。 |
| `web_acl_arn` | `string` | `null` | 否 | 要關聯的 regional WAFv2 Web ACL ARN，只適合 plan 時已知的值；Web ACL 在同一個 configuration 建時會報 `Invalid count argument`，請改用 `web_acl`。為了既有呼叫端保留，之後會移除。與 `web_acl` 不能同時給。 |
| `vpc_id` | `string` | `null` | 否 | `target_groups` 非空時必填。target group 所在的 VPC。 |
| `target_groups` | `map(object)` | `{}` | 否 | key 對應一個 HTTP target group，名稱 `<name>-<key>`（1–32 字元）。欄位：`port`（必填；改了會重建，規則還在用時會失敗）、`protocol_version`（預設 `HTTP1`）、`deregistration_delay`（預設 300）、`target_type`（`ip` 或 `instance`，預設 `ip`）、`stickiness`（`{ duration }`，1–604800 秒，`lb_cookie`，預設 `null` 不開）、`health_check`（可只覆寫部分欄位），細節見〈target group 與 listener rule〉。 |
| `listener_rules` | `map(object)` | `{}` | 否 | key 對應 HTTPS listener 上的 forward 規則（沒有憑證時掛在 HTTP listener）。欄位：`priority`（不可重複）、`target_group`（`target_groups` 的 key）或 `forward`（加權轉發，1–5 個 target，兩者擇一）、`path_patterns`、`host_headers`（合計至少一個）、`require_origin_verify`（預設 `false`）。欄位見〈target group 與 listener rule〉與〈加權 forward（0.4.0）〉。 |
| `origin_verify_header_name` | `string` | `null` | 否 | CDN 加在回源請求上的 header 名稱，要與 `origin_verify_header_value` 一起給或一起不給。 |
| `origin_verify_header_value` | `string` | `null` | 否 | origin verify header 的值（sensitive）。從 `TF_VAR_origin_verify_header_value` 環境變數傳入，不要寫進 tfvars。 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警 `alarm_actions` 與 `ok_actions` 的 SNS topic ARN，至少一個。 |
| `alarm_config` | `object` | `{}` | 否 | ELB 5xx 告警設定。欄位：`elb_5xx_threshold`（一個 period 內 `HTTPCode_ELB_5XX_Count` 的總和門檻，預設 1）、`period`（秒，預設 60）。 |
| `tags` | `map(string)` | `{}` | 否 | 額外的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `alb_arn` | ALB ARN。 |
| `alb_arn_suffix` | `app/<name>/<id>`，給 CloudWatch dimension 與 `requests_per_target` 的 resource label 用。 |
| `alb_dns_name` | ALB DNS 名稱。 |
| `alb_zone_id` | ALB 的 Route 53 hosted zone ID，給 alias record 用。 |
| `listener_arn` | 有憑證時是 HTTPS listener ARN，否則是 HTTP listener ARN。 |
| `listener_arns` | 依協定分的 listener ARN，`{ http, https }`；`http` 一定有值，沒有憑證時 `https` 是 `null`。 |
| `listener_rule_arns` | key 同 `listener_rules` 的 map，值是 listener rule ARN；沒給時是空 map。 |
| `listener_protocol` | `listener_arn` 的協定，`HTTPS` 或 `HTTP`。 |
| `alarm_arns` | 告警名稱對應告警 ARN 的 map，目前只有 `elb_5xx`。 |
| `target_group_arns` | key 同 `target_groups` 的 map，值是 target group ARN；沒給時是空 map。 |
| `target_group_arn_suffixes` | key 同 `target_groups` 的 map，值是 `targetgroup/<name>/<id>`，給 CloudWatch dimension 用。 |
| `web_acl_association_ids` | Web ACL 關聯 ID 的 list；沒有關聯時是空 list。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/alb
```
