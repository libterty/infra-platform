# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 REGIONAL 的 `aws_wafv2_web_acl`，預設動作 allow；什麼都不開時只有 web ACL，沒有任何規則、IP set 或 logging。
- 可選 `kill_switch`：`count` 只計數，`block` 擋所有請求；`block` 搭配 `response_json` 時回 503 與自訂 JSON body。
- 可選 `rate_limit`：每個來源 IP 的請求數上限，最小 10；`allowlist_cidrs` 非空才建 `aws_wafv2_ip_set`，名單內的 IP 只豁免 rate limit，其他規則照常檢查。
- `managed_rule_groups`：依清單順序評估；`count_overrides` 把群組內個別規則改成 count，群組本身永遠保持原本的動作。
- `body_size_exempt_path_prefixes`：這些 path prefix 不受 8 KB body 限制。要求 `AWSManagedRulesCommonRuleSet` 已把 `SizeRestrictions_BODY` 設成 count，否則拒絕；另加一條 `body-size-limit` 規則，擋非例外 path 的超大 body。
- priority 依固定順序產生，不開放呼叫端設定：kill switch 10、rate limit 30、managed 群組 100 起依清單遞增、body size 1000。
- 可選 `logging`：建 `aws-waf-logs-<name>` log group 與 logging configuration；`authorization`、`cookie` 一律遮蔽，`redacted_headers` 可再加其他 header（名稱轉小寫）。
- 輸出 `web_acl_arn`、`web_acl_name`、`ip_set_arn`（沒建時為 null）、`log_group_name`（沒開 logging 時為 null）。
- 不建 association（由 `alb` 的 `web_acl_arn` 負責）、不支援 CLOUDFRONT scope、IPv6 allowlist、自訂規則、geo／bot 規則。
