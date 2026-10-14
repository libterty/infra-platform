# alb

建一個 Application Load Balancer、HTTP／HTTPS listener、ALB 整體的 ELB 5xx 告警，可選 access log 與 WAF 關聯。target group 與 listener rule 由 `ecs-service` 建。

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
  web_acl_arn = aws_wafv2_web_acl.this.arn
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

## 注意

- **沒有憑證時只開 HTTP:80，ALB 的 security group 必須收窄**。SG 由 `network` stack 建，收窄規則也在那裡檢查；這個 module 不建 SG，也看不到 SG 的內容。
- **access log 的 bucket 只能用 SSE-S3 加密**。ALB 的 log delivery 不支援 customer managed KMS，設了 KMS 之後 log 會無聲遺失。bucket 由 `foundation` stack 建，這裡只收名稱（不是 ARN）。
- `additional_certificate_arns` 只掛在 HTTPS listener，所以必須同時給 `certificate_arn`。
- `deletion_protection` 預設 `true`；測試或 PoC 要 destroy 時先設成 `false` 並 apply。
- ELB 5xx 告警只有 `LoadBalancer` 維度，所以放在這裡，一個 ALB 一份；各服務的 target 告警在 `ecs-service-alarms`。

## 刻意不做

- 不建 security group、Web ACL（只做關聯）、access log bucket。
- 不建 target group 與 listener rule。
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
| `web_acl_arn` | `string` | `null` | 否 | regional WAFv2 Web ACL ARN；只做關聯 |
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
| `listener_protocol` | `string` | `"HTTPS"` 或 `"HTTP"` |
| `alarm_arns` | `map(string)` | 告警 ARN，目前只有 `elb_5xx` |

## 測試

```bash
scripts/validate.sh modules/alb
```
