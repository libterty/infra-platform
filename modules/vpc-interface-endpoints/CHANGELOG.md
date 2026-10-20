# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 為 `services` 的每個服務建一個 interface endpoint（`private_dns_enabled` 預設 `true`），共用一個 security group。
- SG 只有 443/tcp 的 ingress，每個 `allowed_cidrs` 一條獨立的 rule 資源，沒有 egress、沒有 inline 規則。
- `services` 為空時什麼都不建，`security_group_id` 為 `null`。
- 輸出 `endpoint_ids`（key 為服務名稱）與 `security_group_id`。
- 從 `vpc` 拆出來：`vpc` 不再有 `interface_endpoints`、endpoint SG 與 `vpce_security_group_id`。拆出來之後，自建與客戶已建好的 VPC 都能呼叫。
- 輸入檢查：`name` 與 `vpc_id` 格式、`allowed_cidrs` 至少一個合法 IPv4 CIDR 且不得含 `0.0.0.0/0`、`subnet_ids` 至少兩個不重複、服務名稱不得帶 `com.amazonaws.` 前綴。
