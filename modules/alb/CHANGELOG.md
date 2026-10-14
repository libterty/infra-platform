# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 `aws_lb.this`（application、`drop_invalid_header_fields = true`、預設開啟 deletion protection）。
- `aws_lb_listener.http` 一律建立：有憑證時預設 301 轉 HTTPS，沒有憑證時回 404。
- 給 `certificate_arn` 才建 `aws_lb_listener.https`（443、`ELBSecurityPolicy-TLS13-1-2-2021-06`、預設回 404）；`additional_certificate_arns` 掛 SNI 憑證，沒有主憑證時被擋。
- 可選 access log（bucket 由外部傳入）與 WAF 關聯（只做 association）。
- ELB 5xx 告警（`HTTPCode_ELB_5XX_Count`）一個 ALB 一份，`alarm_actions` 與 `ok_actions` 都接 `sns_topic_arns`。
- 輸出 `alb_arn`、`alb_arn_suffix`、`alb_dns_name`、`alb_zone_id`、`listener_arn`、`listener_protocol`、`alarm_arns`。
- 不建 security group、Web ACL、access log bucket、target group、listener rule，不支援 NLB。
