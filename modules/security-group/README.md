# security-group

一次呼叫建一組**互相引用**的 security group 與它們的規則。ALB、服務、DB、Proxy 的規則鏈（ALB → app → proxy → db）在同一次呼叫裡寫完，規則用 SG 的 key 互相引用。

沒有做成「一次一個 SG」，因為規則鏈是雙向引用，而 module 的引數不能引用自己；一次建一個的話，stack 會出現自我引用。

## 用法

```hcl
module "sg" {
  source = "git::https://github.com/<org>/<repo>.git//modules/security-group?ref=security-group-v0.1.0"

  vpc_id = module.vpc.vpc_id

  security_groups = {
    alb = { name = "alpha-dev-alb", description = "ALB" }
    api = { name = "alpha-dev-api", description = "api service" }
  }

  rules = {
    alb_in_https  = { security_group = "alb", type = "ingress", description = "clients", from_port = 443, cidr_ipv4 = "0.0.0.0/0", allow_internet = true }
    alb_out_api   = { security_group = "alb", type = "egress", description = "to api", from_port = 8080, peer_group = "api" }
    api_in_alb    = { security_group = "api", type = "ingress", description = "from alb", from_port = 8080, peer_group = "alb" }
    api_out_https = { security_group = "api", type = "egress", description = "AWS APIs", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }

  tags = {
    Project = "alpha"
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。其他 module 取 SG 用 `module.sg.security_group_ids["api"]`。

## 規則怎麼寫

- 每條規則的來源／目的地從四種擇一：`peer_group`（同一次呼叫裡的 SG key）、`peer_group_id`（這次呼叫以外的 SG）、`cidr_ipv4`、`prefix_list_id`。給零個或兩個以上會被擋。
- `ip_protocol` 只收 `tcp`、`udp`、`-1`。tcp／udp 必須給 `from_port`，`to_port` 不給就等於 `from_port`；`-1` 兩個 port 都要留空。
- **ingress 對 `0.0.0.0/0` 開放，必須明寫 `allow_internet = true`**，避免 DB 或服務的 SG 被一行寫錯的 CIDR 打開。egress 對 `0.0.0.0/0` 不需要。
- 規則的 key 就是 `for_each` 的 key，請用「這條規則允許什麼」命名（例如 `api_in_alb`）。規則增減不會讓其他規則重建；改 key 等於刪掉再建。

## 注意

- 規則一律是獨立的 `aws_vpc_security_group_ingress_rule`／`egress_rule`，**沒有 inline `ingress {}`／`egress {}`**。inline 寫法會接管整個 SG 的規則，客戶在 console 加的規則會在下一次 apply 時被默默刪掉。
- Terraform 建立 SG 時會移除 AWS 預設的「全部對外放行」egress，所以沒有寫 egress 規則的 SG 對外是不通的。
- SG 的 `name` 與 `description` 改了會讓 SG 被替換（ForceNew），而 SG 掛著 ENI 時替換會卡住。名稱與說明請一開始就定好。

## 刻意不做

- 不做 IPv6 規則、預設的 egress 放行、NACL。
- 不管「沒有憑證時 ALB SG 不准對 `0.0.0.0/0` 開 80」：這需要知道哪個 SG 是 ALB、有沒有憑證，屬於 network stack 的檢查。這裡只提供通用的底線 `allow_internet`。
- 不收 icmp 等其他協定。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `vpc_id` | `string` | 無 | 是 | 這一組 SG 所在的 VPC |
| `security_groups` | `map(object({ name, description }))` | 無 | 是 | key => SG；至少一個，key 為 snake_case |
| `rules` | `map(object)` | `{}` | 否 | key => 規則；欄位見上方「規則怎麼寫」，`security_group`、`type`、`description` 必填 |
| `tags` | `map(string)` | `{}` | 否 | SG 與規則的 tag；SG 另加 `Name`，值是 SG 名稱；規則的 `Name` 是規則 key |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `security_group_ids` | `map(string)` | SG ID，key 同 `security_groups` |
| `security_group_arns` | `map(string)` | SG ARN，key 同 `security_groups` |

## 測試

```bash
scripts/validate.sh modules/security-group
```
