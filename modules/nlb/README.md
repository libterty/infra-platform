# nlb

建一個 Network Load Balancer、target group、listener，每個 target group 一條 `UnHealthyHostCount` 告警。access log 用 `log-delivery` 開（見〈access log〉）。listener 的 default action 一律是 `forward`，可以把流量按權重分給最多 5 個 target group，用在新舊系統並存的逐步切換。

## 用法

```hcl
module "nlb" {
  source = "git::https://github.com/<org>/<repo>.git//modules/nlb?ref=nlb-v0.1.0"

  name               = "alpha-dev"
  subnet_ids         = local.app_subnet_ids
  security_group_ids = [local.nlb_sg_id]
  vpc_id             = local.vpc_id
  sns_topic_arns     = [module.alarm_topic.topic_arn]

  target_groups = {
    web = { port = 8080 }
  }

  listeners = {
    web = {
      port            = 443
      protocol        = "TLS"
      certificate_arn = local.certificate_arn
      targets         = { web = { target_group = "web", weight = 1 } }
    }
  }
}
```

範例：[`examples/basic/`](./examples/basic/main.tf)，含一個單一 target group 的 TCP listener，和一個兩個 target group 加權的 TLS listener。

## 預設值

- `internal = true`：預設是內部 NLB，要對外要明確設成 `false`。
- `cross_zone = true`、`deletion_protection = true`。測試或 PoC 要 destroy 時，先把 `deletion_protection` 設成 `false` 並 apply。
- TLS listener 的 `ssl_policy` 預設 `ELBSecurityPolicy-TLS13-1-2-2021-06`。
- target group 的 `protocol = "TCP"`、`target_type = "ip"`、`deregistration_delay = 300`。

## 加權分流

listener 的 `targets` 放 1–5 個 target，按 `weight`（0–999，預設 1）分配新連線。每個 target 的 `target_group`（本 module `target_groups` 的 key）與 `target_group_arn`（外部 target group，例如舊系統的）擇一。

```hcl
listeners = {
  app = {
    port            = 443
    protocol        = "TLS"
    certificate_arn = local.certificate_arn
    targets = {
      new = { target_group = "new", weight = 10 }
      old = { target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/legacy/0123456789abcdef", weight = 90 }
    }
  }
}
```

- 只有一個 target 時也用 `forward` block，不用 `target_group_arn`。這樣之後加第二個 target，action 的寫法不用跟著換。
- validation：`targets` 1–5 個；`weight` 0–999，且至少一個大於 0；同一個 listener 的 target group protocol 要一致（只檢查本 module 的 target group，外部 ARN 的 protocol 檢查不到）；外部 ARN 要長得像 ELB target group ARN。
- 權重寫在 tfvars。如果有別的東西（例如 `lb-traffic-breaker` 的 Lambda）直接改了 AWS 上的權重，下次 apply 會改回 tfvars 的值。module 不加 `ignore_changes`，否則 tfvars 改權重就不會生效。

### 改權重只影響新連線（R7）

- 改權重只影響**新連線**，既有的連線照舊留在原來的 target group。
- 權重生效最多約 3 分鐘（AWS 官方 blog 的說法，沒有實測）。
- 所以從新系統切回舊系統時，長連線（資料庫、WebSocket、gRPC streaming）會一直留在新系統，直到連線自己結束。
- 需要即時切斷時，已知的做法是在 NLB 後面接 ALB，用 ALB 做 L7 權重（`target_type = "alb"`）。這是已知限制，這個 module 不處理。

### DNS failover 的坑（D14、R6）

NLB 的 DNS failover 跟 ALB 相反。listener 掛了多個 target group 時，只要其中一個 target group 在某個 AZ 沒有足夠的健康 target，這個 AZ 的 NLB 節點就會被移出 DNS，即使另一個 target group 在這個 AZ 是健康的。結果是新系統在某個 AZ 沒有健康 target 時，連舊系統的流量也受影響。

- 每個 target group 有 `dns_failover`（對應 `target_group_health.dns_failover.minimum_healthy_targets_count`），預設 `"1"`（AWS 預設），可設成 `"off"` 或 1–3000 的數字字串。
- **listener 有多於一個 target 時，它用到的每個本 module target group 都必須 `dns_failover = "off"`**，否則 validation 擋下。權重是 0 的 target 也算。單一 target 時維持預設即可。
- **外部 ARN 的 target group 檢查不到**。接外部 target group 時，請自己確認它的 `dns_failover`，否則 validation 沒辦法擋。
- 就算設成 `"off"`，**每個 AZ 都要有新系統的 target** 比較保險（R6）。
- `"off"` 能不能真的避免整個 zone 被移出 DNS，**沒有用真實環境驗證**。
- `dns_failover` 與 `unhealthy_state_routing` 都只在單一 target group 的單一 AZ 內生效，不能拿來「切回舊系統」。要切回舊系統只能改權重。
- 3000 是 NLB 每個 target group 的 target 數配額，拿來當上限，沒有對照過 provider 或 API 的限制。

## 與 ALB 的差異

- NLB 沒有 HTTP 狀態碼指標，沒有 5xx 錯誤率。依 target group 拆的只有 `HealthyHostCount`、`UnHealthyHostCount`、`NewFlowCount`、`ActiveFlowCount`。`TCP_Target_Reset_Count` 沒有 target group 維度，歸不到新系統。
- 所以 NLB 的斷路器預設看新系統 `HealthyHostCount`，另外可以接應用程式自己發的 CloudWatch 指標。細節見 `lb-traffic-breaker`（D12）。
- 這個 module 只建 `UnHealthyHostCount` 告警，沒有 5xx 告警，也沒有 `alarm_config`。

## 告警

每個 target group 一條，名稱 `<name>-<key>-unhealthy-hosts`：

- 指標 `AWS/NetworkELB` `UnHealthyHostCount`，statistic `Maximum`，大於 0，期間 60 秒、1 個 period，維度是 `TargetGroup` 與 `LoadBalancer` 的 `arn_suffix`。
- `alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`。
- `treat_missing_data = "notBreaching"`：沒有資料代表這個 target group 沒有任何已註冊的 target（例如 TargetGroupBinding 還沒註冊），沒有 target 就沒有「不健康」可說。代價是 target group 一個 target 都沒有時，這條告警不會響；要抓這種情況需要另外看 `HealthyHostCount`。這是依指標行為推論的選擇，沒有實測。
- 外部 ARN 的 target group 沒有告警，因為 module 拿不到它的 arn_suffix。

## access log

0.2.0 起這個 module 不再開 access log（移除了 `access_logs`），改由 `log-delivery` 送，log type 是 `NLB_ACCESS_LOGS`，目的地可以是 CloudWatch Logs、S3 或 Firehose：

```hcl
module "nlb_access_logs" {
  source  = "app.terraform.io/<org>/log-delivery/aws"
  version = "~> 0.2.0"

  name_prefix = "alpha-dev-nlb"

  sources      = { access = { resource_arn = module.nlb.nlb_arn, log_type = "NLB_ACCESS_LOGS" } }
  destinations = { archive = { type = "S3", resource_arn = module.access_log_bucket.arn } }
  deliveries   = { access = { source = "access", destination = "archive" } }
}
```

送 S3 時 bucket 用 `s3-bucket` 建並給 `log_delivery = ["vended_logs"]`。依 AWS 文件，NLB 的 access log 只記 TLS listener 的連線，沒有實測。

## 注意

- **security group 只能在建立 NLB 時加**（未確認）。所以 `security_group_ids` 至少要一個，不給會被擋下。SG 由 `network` stack 建，這個 module 不建 SG，也看不到內容。已經建好、沒有 SG 的 NLB，之後能不能補上 SG 沒有驗證，補不上就要重建。
- NLB 的 SG 預設不會對 target 放行，target 的 SG 要允許來自 NLB SG（或 client IP，視 `preserve_client_ip`）的流量。這部分在 `network` stack。
- TLS listener 必須給 `certificate_arn`，而且不能用開了 `stickiness` 的 target group（TLS listener 不支援 target group stickiness）；沒有 TLS 的 listener 不能給 `certificate_arn` 與 `alpn_policy`。
- `stickiness = true` 是 `source_ip`。provider 在 NLB 的 stickiness 是否需要 `cookie_duration` 沒有驗證，module 沒有送。
- `target_type = "alb"` 的 target group 必須是 `TCP`，健康檢查要用 `HTTP` 或 `HTTPS`（依 AWS 文件，沒有用 apply 驗證）。
- 健康檢查：`protocol` 可為 `TCP`、`HTTP`、`HTTPS`，`interval` 5–300 秒，`healthy_threshold` 與 `unhealthy_threshold` 2–10，預設都是 3。`path` 與 `matcher` 只在 HTTP／HTTPS 時送出。module 不送 `timeout`（NLB 的 TCP 健康檢查逾時由 AWS 決定）。
- `preserve_client_ip` 預設 `null`，交給 AWS 決定。
- listener 的 protocol 與 target group 的 protocol 是否相容（例如 UDP listener 要接 UDP target group）由 AWS 在 apply 時檢查，module 沒有重複檢查。
- 改 target group 的 `port` 或 `protocol` 會讓 target group 重建，listener 還在用時會失敗。要換就新增一個 key、把 listener 改指過去，再移除舊的。**這是讀 provider 行為推論的，沒有 apply 驗證。**
- `<name>-<key>` 要是 1–32 字元，所以 key 不能太長。

## 刻意不做

- 不建 security group、IAM、access log（用 `log-delivery`）、憑證。
- 不建 5xx 告警（NLB 沒有這個指標），不提供 `alarm_config`。
- 不加 `ignore_changes` 保護權重。
- 不支援 listener 的 SNI 多憑證、mutual TLS、`unhealthy_state_routing`、`target_failover`、`proxy_protocol_v2`、`slow_start`、IPv6。
- 不寫 provider 設定。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | NLB 名稱，2–32 字元，不得以 `internal-` 開頭 |
| `internal` | `bool` | `true` | 否 | `true` 建內部 NLB |
| `subnet_ids` | `list(string)` | 無 | 是 | 至少兩個不同的 subnet |
| `security_group_ids` | `list(string)` | 無 | 是 | 至少一個 SG，只能在建立時加（未確認） |
| `cross_zone` | `bool` | `true` | 否 | `enable_cross_zone_load_balancing` |
| `deletion_protection` | `bool` | `true` | 否 | 刪除保護 |
| `vpc_id` | `string` | `null` | 視情況 | target group 的 VPC；`target_groups` 非空時必填 |
| `target_groups` | `map(object)` | `{}` | 否 | 見下表 |
| `listeners` | `map(object)` | `{}` | 否 | 見下表 |
| `sns_topic_arns` | `list(string)` | 無 | 是 | 告警通知的 SNS topic；至少一個 |
| `tags` | `map(string)` | `{}` | 否 | tag；`Name` 由 module 加上 |

`target_groups` 的欄位（名稱是 `<name>-<key>`）：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `port` | `number` | 無（必填） | 1–65535 |
| `protocol` | `string` | `"TCP"` | `TCP`、`TLS`、`UDP`、`TCP_UDP` |
| `target_type` | `string` | `"ip"` | `ip`、`instance`、`alb` |
| `deregistration_delay` | `number` | `300` | 0–3600 秒 |
| `preserve_client_ip` | `bool` | `null` | `null` 交給 AWS 決定 |
| `health_check` | `object` | `{}` | `protocol`（`TCP`）、`port`（`traffic-port`）、`path`（`/`）、`matcher`（`200-399`）、`interval`（30）、`healthy_threshold`（3）、`unhealthy_threshold`（3） |
| `stickiness` | `bool` | `false` | `true` 開 `source_ip` |
| `dns_failover` | `string` | `"1"` | `"off"` 或 1–3000 的數字字串；listener 有多個 target 時必須是 `"off"` |

`listeners` 的欄位：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `port` | `number` | 無（必填） | 1–65535 |
| `protocol` | `string` | `"TCP"` | `TCP`、`TLS`、`UDP`、`TCP_UDP` |
| `certificate_arn` | `string` | `null` | ACM 憑證；TLS 必填，其他 protocol 不可給 |
| `ssl_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | 只對 TLS 生效 |
| `alpn_policy` | `string` | `null` | TLS 才能給：`HTTP1Only`、`HTTP2Only`、`HTTP2Optional`、`HTTP2Preferred`、`None` |
| `targets` | `map(object)` | 無（必填） | 1–5 個；每個有 `target_group` 或 `target_group_arn`（擇一）與 `weight`（0–999，預設 1，至少一個大於 0） |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `nlb_arn` | `string` | NLB ARN |
| `nlb_arn_suffix` | `string` | `net/<name>/<id>`，CloudWatch 的 `LoadBalancer` 維度 |
| `dns_name` | `string` | NLB DNS 名稱 |
| `zone_id` | `string` | alias record 用的 hosted zone ID |
| `listener_arns` | `map(string)` | listener ARN，key 同 `listeners`；沒給時是空 map |
| `target_group_arns` | `map(string)` | target group ARN，key 同 `target_groups` |
| `target_group_arn_suffixes` | `map(string)` | `targetgroup/<name>/<id>`，key 同 `target_groups`，給 CloudWatch dimension 用 |
| `alarm_arns` | `map(string)` | `UnHealthyHostCount` 告警 ARN，key 同 `target_groups` |

## 測試

```bash
scripts/validate.sh modules/nlb
```

測試用 mock provider，不連 AWS。mock 驗不到的部分（SG 能不能事後加、`dns_failover = "off"` 的實際效果、權重生效時間、alb target type 的健康檢查限制）都標在上面各節，需要真實環境才能確認。
