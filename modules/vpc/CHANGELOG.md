# Changelog

## 0.1.0（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立 VPC（DNS support 與 hostnames 都開），並清空 default security group 的規則。
- subnet 依 tier 切，`for_each` key 為 `"<tier>/<az>"`；支援自動切（`newbits` + `netnum_base`）與明確指定（`cidrs`）。
- 一個 subnet 一張 route table；public 走 IGW，private 依 `nat_mode`（`none`／`single`／`per_az`）走 NAT，isolated 只有 local 路由。
- S3、DynamoDB gateway endpoint 關聯所有 private 與 isolated 的路由表；可選 interface endpoint（附只對 VPC CIDR 開 443 的 SG）。
- 可選 flow log，只支援 S3。
- 所有 subnet CIDR 換成整數區間兩兩比對，重疊、超出 VPC、槽位不夠、`cidrs` 與 `azs` 不符都在 plan 階段由 `aws_vpc.this` 的 precondition 擋下。
- SG 規則與路由一律用獨立資源，沒有 inline 規則。
- 不支援 IPv6、private NAT、Transit Gateway、VPC peering、NACL、送 CloudWatch Logs 的 flow log。
