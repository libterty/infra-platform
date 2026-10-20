# Changelog

## 0.1.0（2026-10-15）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 一次呼叫建一組 `aws_security_group`（`for_each = security_groups`）。
- 規則一律用獨立的 `aws_vpc_security_group_ingress_rule`／`egress_rule`，以規則的 key 為 `for_each` key，沒有 inline 規則。
- 規則來源擇一：`peer_group`、`peer_group_id`、`cidr_ipv4`、`prefix_list_id`；`to_port` 預設等於 `from_port`。
- ingress 對 `0.0.0.0/0` 必須明寫 `allow_internet = true`；egress 不需要。
- 輸出 `security_group_ids`、`security_group_arns`。
- 不做 IPv6、預設 egress 放行、NACL；不處理「沒有憑證時 ALB 不開 80」（屬 network stack）。
