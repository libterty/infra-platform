# vpc-peering

建立 VPC peering 的**請求端**：一個 `aws_vpc_peering_connection`，加上在你的 route table 裡指向對端網段的 route。你的 VPC 要連到另一個帳號（或另一個 region）的 VPC 時，用這個 module。

## 用法

```hcl
module "peering" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpc-peering?ref=vpc-peering-v0.1.0"

  name          = "alpha-dev-to-partner"
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = "10.10.0.0/16"
  peer_vpc_id   = "vpc-0fedcba9876543210"
  peer_owner_id = "444444444444"

  route_table_ids = module.vpc.private_route_table_ids
  peer_cidrs      = ["10.250.0.0/16"]

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 注意

- **對端必須由對方接受。** 這個 module 只建請求端，`auto_accept` 固定 `false`，不會也不能代對方接受。`apply` 之後連線停在 `pending-acceptance`，把輸出的 `peering_connection_id` 交給對方，由對方帳號接受（console、CLI，或對方自己的 Terraform）。接受之前連線不能轉送流量。
- 對方也要在自己的 route table 加回程 route 指向你的網段，並放行 security group，否則只有單向通。這些都在對方帳號，不在這個 module 範圍。
- **`peer_cidrs` 不可為 `0.0.0.0/0`**，也不可跟 `vpc_cidr` 重疊（包含與被包含都算）；重疊的網段 AWS 本來就不能 peer。
- `route_table_ids` 是 list 不是 set：route 的 `for_each` key 是 `<index>-<CIDR>`，所以即使 route table 跟這個 module 在同一個 stack 建立、plan 時還不知道 ID，也能 plan。代價是調整 list 順序會讓 route 重建，新增的請接在最後面。
- 同一個 `vpc_id` 與 `peer_vpc_id` 之間同時只能有一條 active 的 peering，重複建立會被 AWS 拒絕。
- 只處理 IPv4。

## 刻意不做

- 對端的 accepter（`aws_vpc_peering_connection_accepter`）；由對方帳號自己建。
- DNS resolution、IPv6、對端 route table。
- security group 規則；用 `security-group` module 建。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 連線名稱，也是 `Name` tag；小寫英數字與連字號 |
| `vpc_id` | `string` | 無 | 是 | 請求端 VPC（本帳號） |
| `vpc_cidr` | `string` | 無 | 是 | 請求端 VPC 的 CIDR，用來檢查 `peer_cidrs` 是否重疊 |
| `peer_vpc_id` | `string` | 無 | 是 | 對端 VPC |
| `peer_owner_id` | `string` | 無 | 是 | 對端帳號 ID，12 位數 |
| `peer_region` | `string` | `null` | 否 | 對端 region；`null` 表示同 region |
| `route_table_ids` | `list(string)` | 無 | 是 | 要加 route 的 route table，至少一個、不可重複 |
| `peer_cidrs` | `list(string)` | 無 | 是 | 對端網段，至少一個；不可為 `0.0.0.0/0`、不可重複、不可與 `vpc_cidr` 重疊 |
| `tags` | `map(string)` | `{}` | 否 | 連線的 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `peering_connection_id` | `string` | 連線 ID，交給對端帳號接受 |

## 測試

```bash
scripts/validate.sh modules/vpc-peering
```

`tests/fixtures/unknown-ids/` 是測試用的 root module：route table 跟這個 module 在同一個 configuration 建立，用來驗證 ID 未知時也能 plan。
