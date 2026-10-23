# vpc-interface-endpoints

建 interface endpoint（PrivateLink）與它們共用的 security group。

名稱刻意不叫 `vpc-endpoints`，因為這個 module 只負責 interface endpoint。gateway endpoint（S3、DynamoDB）屬於路由，留在 [`vpc`](../vpc/README.md)。

interface endpoint 不碰路由，所以只要給 VPC id、subnet id 與允許的 CIDR，就能放進自己建的 VPC，也能放進客戶已經建好的 VPC。

## 用法

```hcl
module "endpoints" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpc-interface-endpoints?ref=vpc-interface-endpoints-v0.1.0"

  name          = "alpha-prod"
  vpc_id        = module.vpc.vpc_id
  allowed_cidrs = [module.vpc.vpc_cidr]
  subnet_ids    = module.vpc.subnet_ids["app"]
  services      = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

上例會建立 1 個 SG、1 條 443/tcp 的 ingress rule、4 個 interface endpoint。

## 注意

- 服務名稱是 `com.amazonaws.<region>.` 之後的部分，例如 `ecr.api`；帶完整前綴會被擋下。
- `services` 為空時什麼都不建，`security_group_id` 是 `null`。
- SG 沒有任何 egress 規則，因為 interface endpoint 只需要接受連入。規則一律是獨立的 rule 資源。
- `allowed_cidrs` 不接受 `0.0.0.0/0`。通常給 `[vpc_cidr]`；VPC 有 secondary CIDR 或要讓 peering 過來的網段使用時，再加進清單。
- `private_dns_enabled = true` 需要 VPC 開啟 `enableDnsSupport` 與 `enableDnsHostnames`。自建的 VPC 由 `vpc` module 固定開啟；客戶的 VPC 要由呼叫端檢查，因為這個 module 讀不到 VPC 屬性。
- `subnet_ids` 至少兩個，且應分屬不同 AZ；module 拿不到 subnet 的 AZ，所以不檢查。放在哪個 tier 由呼叫端決定。
- 不支援 endpoint policy，也不為每個服務建獨立的 SG。
- 不建 IAM 資源。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | security group 與 endpoint `Name` tag 的前綴。2–48 字元，限小寫英數字與 `-`，以字母開頭。 |
| `vpc_id` | `string` | 無 | 是 | endpoint 與 security group 所在的 VPC，格式 `vpc-0123456789abcdef0`。 |
| `allowed_cidrs` | `list(string)` | 無 | 是 | 允許連 endpoint 443 port 的 IPv4 CIDR，至少一個，不可含 `0.0.0.0/0`；通常給 `[vpc_cidr]`。 |
| `subnet_ids` | `list(string)` | 無 | 是 | endpoint 網路介面所在的 subnet，每個 AZ 一個，至少兩個不重複。 |
| `services` | `set(string)` | `[]` | 否 | 要建的服務名稱，只寫 `com.amazonaws.<region>.` 之後的部分，例如 `ecr.api`；空集合時什麼都不建。 |
| `private_dns_enabled` | `bool` | `true` | 否 | 是否在 VPC 內用 endpoint 蓋過公開服務的 DNS 名稱；VPC 必須開啟 DNS support 與 DNS hostnames。 |
| `tags` | `map(string)` | `{}` | 否 | 額外的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `endpoint_ids` | 服務名稱對應 endpoint ID 的 map。 |
| `security_group_id` | endpoint 的 security group ID；`services` 為空時是 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/vpc-interface-endpoints
```
