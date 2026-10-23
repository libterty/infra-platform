# vpc

建一個 VPC 與它的 subnet、IGW、NAT、route table、gateway endpoint、flow log。interface endpoint 不在這裡，由 [`vpc-interface-endpoints`](../vpc-interface-endpoints/README.md) 負責。tier 的數量與切法由呼叫端決定，module 不寫死「三層」。

## 用法

```hcl
module "vpc" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpc?ref=vpc-v0.1.0"

  name = "alpha-dev"
  cidr = "10.20.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  subnets = {
    public = { type = "public", newbits = 4, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 4 }
    data   = { type = "isolated", newbits = 4, netnum_base = 8 }
  }

  nat_mode = "single"
}
```

範例：[`examples/basic/`](./examples/basic/main.tf)（自動切）、[`examples/explicit-cidrs/`](./examples/explicit-cidrs/main.tf)（明確指定 CIDR、`per_az` NAT、gateway endpoint、flow log）。

## subnet tag

每個 tier 可以用 `tags` 加自己的 tag，只套在那個 tier 的 subnet。合併順序是 `var.tags`、tier 的 `tags`、`Name`：同名的 key 以後面為準，`Name` 一律由 module 最後蓋上。

為了避免 `Name` 被悄悄蓋掉而不自知，tier 的 `tags` 不可以有 `Name` key，給了會在 plan 階段被 validation 擋下。沒給 `tags` 時，subnet 的 tag 與 0.1.0 完全相同。

EKS 用的例子：AWS Load Balancer Controller 與 Karpenter 都靠 subnet tag 找 subnet，不看 route table。

```hcl
subnets = {
  public = {
    type        = "public"
    newbits     = 4
    netnum_base = 0
    tags        = { "kubernetes.io/role/elb" = "1" }
  }
  app = {
    type        = "private"
    newbits     = 4
    netnum_base = 4
    tags = {
      "kubernetes.io/role/internal-elb" = "1"
      "karpenter.sh/discovery"          = "<cluster 名稱>"
    }
  }
  data = { type = "isolated", newbits = 4, netnum_base = 8 }
}
```

- `public` tier 加 `kubernetes.io/role/elb = "1"`：internet-facing 的 LB 會選這些 subnet。
- `private` tier 加 `kubernetes.io/role/internal-elb = "1"`：internal 的 LB 會選這些 subnet。
- `karpenter.sh/discovery = <cluster 名稱>`：Karpenter 的 EC2NodeClass 用它挑節點要放的 subnet，放在放節點的 tier。

## tier 命名合約

範本固定三個 tier 名稱，並寫進 SSM 合約，不可更改：

| tier | type | 路由 |
|---|---|---|
| `public` | `public` | 預設路由走 IGW |
| `app` | `private` | 預設路由走 NAT（`nat_mode != "none"` 時） |
| `data` | `isolated` | 只有 local；DB 需要對外連線時改 `private` |

要加 tier 可以，但名稱不能跟這三個衝突。tier 名稱限 snake_case，最多一個 `public` tier。

## IP 規劃

- 自動切：`cidr_block = cidrsubnet(cidr, newbits, netnum_base + AZ 在 azs 裡的位置)`。
- 每個 tier 預留 4 個 AZ 的槽位，`netnum_base` 以 4 為間隔（0、4、8…）。之後從 2 個 AZ 加到 3、4 個，既有 subnet 不用動。
- 槽位數是 `2^newbits`。`/20` 搭配 `newbits = 4` 得到 16 個 `/24`，三個 tier 各佔 4 個槽位，共用掉 12 個。
- 不同 tier 想要不同大小，就用不同的 `newbits`；module 會檢查結果不重疊，不用自己算。
- 槽位由 AZ 的位置決定：**只從尾端移除 AZ 時**，其餘 subnet 的 CIDR 不變；移除中間的 AZ 時，後面 AZ 的 subnet 會換到新位置對應的槽位，也就是重建。要避免這種情況，就改用 `cidrs` 明確指定。

## 檢查

所有檢查都在 `aws_vpc.this` 的 `lifecycle.precondition`，plan 階段就失敗：

- 用 `cidrs` 的 tier，key 必須恰好等於 `azs`。
- 自動切時 `netnum_base + length(azs) <= 2^newbits`，且 subnet 不小於 `/28`。
- `nat_mode != "none"` 時要有 public tier。
- 所有 subnet 都在 VPC CIDR 內。
- 所有 subnet CIDR 兩兩不重疊：每個 CIDR 換成 `[起始整數, 結束整數]` 再比對，不管怎麼切都擋得住。例如用兩種 `newbits` 切同一個 `/16`、兩個 AZ 剛好填滿時，第三個 AZ 會悄悄撞進別的 subnet，這個檢查會把它擋下來。

## 注意

- 不建任何新的 security group。唯一碰到 SG 的是 `aws_default_security_group`：它接管 VPC 原有的 default SG 並清空規則，任何資源都不得使用這個 SG。服務用的 SG 由 `security-group` module 建，interface endpoint 與它的 SG 由 `vpc-interface-endpoints` 建。
- SG 規則與路由一律用獨立資源，所以客戶在 console 加的規則與路由不會在下一次 apply 被刪掉。
- `single` 的 NAT 放在 `azs` 的第一個 AZ，其他 AZ 跨 AZ 出去；`per_az` 每個 AZ 走自己的 NAT。
- gateway endpoint 只關聯 private 與 isolated 的路由表；public 的表不需要。
- flow log 只支援 S3，不需要 IAM role；bucket 與 bucket policy 由 `foundation` stack 管。

## 刻意不做

IPv6、private NAT、Transit Gateway 與 VPC peering 的路由、NACL、送 CloudWatch Logs 的 flow log（要多一個 IAM role）、流量規格 preset。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | VPC 名稱，也是各資源 `Name` tag 的前綴。2–48 字元，限小寫英數字與 `-`，以字母開頭。 |
| `cidr` | `string` | 無 | 是 | VPC 的 IPv4 網路位址，`/16` 到 `/24`，必須是網路位址本身（例如 `10.20.0.0/20`）。 |
| `azs` | `list(string)` | 無 | 是 | 2–4 個不重複的 AZ。順序決定輸出 list 的順序，`single` NAT 放在第一個 AZ。 |
| `subnets` | `map(object)` | 無 | 是 | tier 名稱（限 `snake_case`）對應切法。欄位：`type`（`public`、`private`、`isolated`，最多一個 `public` tier）、`newbits` 加 `netnum_base`（自動切）或 `cidrs`（AZ 對應 CIDR，key 要涵蓋每個 AZ），兩者擇一；`tags`（預設 `{}`，只套在這個 tier 的 subnet，不可含 `Name`）。 |
| `nat_mode` | `string` | `"single"` | 否 | 要建幾個 NAT：`none` 不建 NAT；`single` 在第一個 AZ 建一個；`per_az` 每個 AZ 各建一個。 |
| `gateway_endpoints` | `set(string)` | `[ "s3" ]` | 否 | 要建的 gateway endpoint，限 `s3`、`dynamodb`；關聯到所有 private 與 isolated tier 的 route table。 |
| `flow_log` | `object` | `null` | 否 | 送到 S3 的 flow log，`null` 時不建。欄位：`destination_arn`（S3 bucket ARN，可帶 `/prefix`，只支援 S3）、`traffic_type`（`ACCEPT`、`REJECT`、`ALL`，預設 `ALL`）。 |
| `tags` | `map(string)` | `{}` | 否 | 額外的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `vpc_id` | VPC ID。 |
| `vpc_cidr` | VPC CIDR。 |
| `azs` | 原樣回傳 `azs`；其他輸出的 list 都照這個順序。 |
| `subnet_ids` | tier 對應 subnet ID 的 map，值是依 `azs` 順序的 list。 |
| `subnet_cidrs` | tier 對應 subnet CIDR 的 map，值是依 `azs` 順序的 list。 |
| `route_table_ids` | tier 對應 route table ID 的 map，值是依 `azs` 順序的 list。 |
| `nat_gateway_ids` | 依 `azs` 順序的 NAT gateway ID list；`none` 時是 `[]`，`single` 時只有 1 個。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/vpc
```
