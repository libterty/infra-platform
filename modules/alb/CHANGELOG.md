# Changelog

## 0.2.0（未發布）

新增功能，升 MINOR。tag 在驗收後由人手動打。

- 新變數 `vpc_id`、`target_groups`、`listener_rules`（預設 `null`、`{}`、`{}`）：在 module 內建 IP target group（名稱 `<name>-<key>`）與 forward 規則。規則掛在 HTTPS listener，沒有憑證時掛在 HTTP listener。一個 target group 可以有多條規則，條件可用 path pattern、host header 與 origin verify header。`require_origin_verify` 預設 `false`（要用才開），設成 `true` 的規則才會加 header 條件。
- 新變數 `origin_verify_header_name` 與 `origin_verify_header_value`（`sensitive`）：分成兩個變數，因為包成一個物件時 `var.x == null` 會變成 sensitive，不能當 `for_each` 的條件。要一起給或一起不給。
- validation：規則指到的 target group 要存在、`priority` 不重複、每條規則至少有一個 path pattern 或 host header、條件值合計不超過 5（`require_origin_verify = true` 時算 1 個）、`<name>-<key>` 不超過 32 字元、`target_groups` 非空時必須給 `vpc_id`。
- 新輸出 `target_group_arns`、`target_group_arn_suffixes`（map，key 同 `target_groups`）。
- 三組變數都沒給的既有呼叫端，resource 與輸出都沒有變化，換版應該零差異。**這是測試與讀程式推論的，沒有用 plan 驗證。**
- `require_origin_verify = true` 但沒設定 `origin_verify_header_name` 與 value 會被 validation 擋下，不會有規則靜默失去保護。
- 改 target group 的 `port` 會重建 target group，規則還在用時會失敗；要換 port 就新增 key、改規則、再移除舊的。**這是讀 provider 行為推論的，沒有用 plan 或 apply 驗證。**
- origin verify header 的值會以明文存在 state。

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 `aws_lb.this`（application、`drop_invalid_header_fields = true`、預設開啟 deletion protection）。
- `aws_lb_listener.http` 一律建立：有憑證時預設 301 轉 HTTPS，沒有憑證時回 404。
- 給 `certificate_arn` 才建 `aws_lb_listener.https`（443、`ELBSecurityPolicy-TLS13-1-2-2021-06`、預設回 404）；`additional_certificate_arns` 掛 SNI 憑證，沒有主憑證時被擋。
- 可選 access log（bucket 由外部傳入）與 WAF 關聯（只做 association）。
- ELB 5xx 告警（`HTTPCode_ELB_5XX_Count`）一個 ALB 一份，`alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`。
- 輸出 `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol`、`alarm_arns`。
- 不建 security group、Web ACL、access log bucket、target group、listener rule，不支援 NLB。
