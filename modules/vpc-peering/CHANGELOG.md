# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立請求端的 `aws_vpc_peering_connection`，`auto_accept` 固定 `false`；對端必須由對方在自己的帳號接受。
- 每個 route table × 每個 `peer_cidrs` 建一條 `aws_route`。`for_each` 的 key 是 `<route table 的 index>-<CIDR>`，所以 route table ID 在 plan 時還不知道（跟 route table 同一個 stack 建立）也能 plan。
- `peer_cidrs` 拒絕 `0.0.0.0/0`、重複、非 IPv4 網路位址，以及跟 `vpc_cidr` 重疊（含包含與被包含）。重疊檢查用變數 validation，不用 precondition。
- `vpc_id`、`peer_vpc_id`、`route_table_ids` 檢查 ID 格式；`peer_owner_id` 必須是 12 位數；`route_table_ids` 與 `peer_cidrs` 至少一個且不可重複。
- 輸出 `peering_connection_id`。
- 不建 accepter、不處理 DNS resolution 選項、不建 IPv6 route、不設 security group 規則。
