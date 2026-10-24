# vpn-site-to-site

建一條 Site-to-Site VPN：customer gateway、VPN 連線，終點二選一，module 自己建 virtual private gateway（VGW）掛到 VPC，或接到既有的 transit gateway（TGW）。pre-shared key（PSK）一律交給 Secrets Manager 保管，module 不收、不產生、不輸出 PSK；兩條 tunnel 的活動 log 一律開啟並寫進 KMS 加密的 log group；IKE 參數只收強演算法。

## 用法

```hcl
module "vpn" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpn-site-to-site?ref=vpn-site-to-site-v0.1.0"

  name        = "alpha-dev-onprem"
  kms_key_arn = module.key.key_arn

  vpc_id      = module.vpc.vpc_id
  vpn_gateway = {}

  customer_gateway = { ip_address = "198.51.100.10" }

  routing = {
    static_routes_only = true
    static_routes      = ["192.168.10.0/24"]
  }

  propagate_route_table_ids = module.vpc.route_table_ids_private
}
```

接 transit gateway、用 BGP：

```hcl
module "vpn" {
  source = "git::https://github.com/<org>/<repo>.git//modules/vpn-site-to-site?ref=vpn-site-to-site-v0.1.0"

  name        = "alpha-dev-onprem"
  kms_key_arn = module.key.key_arn

  transit_gateway_id = "tgw-0123456789abcdef0"
  customer_gateway   = { ip_address = "198.51.100.10", bgp_asn = 65010 }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| PSK | `preshared_key_storage = "SecretsManager"`，沒有 `Standard` 的選項，也沒有任何 PSK 輸入；兩條 tunnel 的 key 由服務產生，存在它管理的 secret，ARN 從 `preshared_key_secret_arn` 取得 |
| tunnel log | 兩條 tunnel 的活動 log 一律開（JSON）；動態路由時 BGP log 也開；寫進 module 自己建的 log group `/aws/vendedlogs/vpn/<name>`，用 `kms_key_arn` 加密、保留 `log_retention_days` 天 |
| IKE | 版本固定 `ikev2`；加密、完整性、DH group 只收下面的強參數，兩條 tunnel 用同一組 |
| 路由 | 預設 BGP；`routing.static_routes_only = true` 才是靜態路由 |
| tag | 給定的 `tags` 加上 `Name` |

### 什麼算弱參數

AWS 文件沒有把哪些算弱寫成清單；這個 module 的定義如下，輸入範圍直接排除它們。

| 項目 | 不收 | 理由 |
|---|---|---|
| IKE 版本 | `ikev1` | AWS 產生「建議的安全設定」時會排除 IKEv1 這類舊選項（Site-to-Site VPN 使用者指南〈Enhanced security features using Secrets Manager〉） |
| 完整性演算法 | `SHA1` | SHA-1 已被視為不安全，只收 `SHA2-256`、`SHA2-384`、`SHA2-512` |
| DH group | 2、5 | 分別是 1024 位元與 1536 位元的 MODP group，低於目前建議的 2048 位元；只收 14–24 |
| 加密演算法 | 其他 | AWS 本來就只提供 `AES128`、`AES256`、`AES128-GCM-16`、`AES256-GCM-16`，四個都收 |

「SHA1、DH 2 與 5 算弱」是這個 repo 依通行的密碼學建議做的判斷，不是 AWS 文件的明文。

## 注意

- **PSK 不在 Terraform state 裡**，因為 module 不設 `tunnelN_preshared_key`，且 `preshared_key_storage` 固定 `SecretsManager`；provider 在這個模式下回傳的 `tunnel1_preshared_key`、`tunnel2_preshared_key` 是遮蔽字串（provider 文件）。**`customer_gateway_configuration`（設備設定檔的 XML）在這個模式下會不會含 PSK，provider 與 AWS 文件都沒寫，未確認**；module 不輸出它，但它是 provider 的 computed 屬性，仍會留在 state。state bucket 要照一般機敏資料保護，第一次 apply 後請實際檢查 state。
- 要把 PSK 交給地端設備的人，需要 `secretsmanager:GetSecretValue`，讀 `preshared_key_secret_arn`。這個 secret 是 Site-to-Site VPN 服務透過 service-linked role（`AWSServiceRoleForVPCS2SVPN`）建立與管理的，**用什麼 KMS key 加密、能不能換成客戶管理 key，文件沒寫，未確認**。
- tunnel log 用 CMK 加密：key policy 要讓 CloudWatch Logs 服務（`logs.<region>.amazonaws.com`）能使用這把 key。Site-to-Site VPN 開 log 時會更新 CloudWatch Logs 的 resource policy，所以執行 apply 的身分要有 `logs:CreateLogDelivery`、`logs:GetLogDelivery`、`logs:UpdateLogDelivery`、`logs:DeleteLogDelivery`、`logs:ListLogDeliveries`、`logs:PutResourcePolicy`、`logs:DescribeResourcePolicies`、`logs:DescribeLogGroups`（AWS 文件）。log group 放在 `/aws/vendedlogs/` 底下，避免 resource policy 超過 5120 字元的上限。CMK 加上 vended logs 交付能不能正常運作，這個 repo 還沒有實測。
- 靜態路由只在 VGW 模式支援（`aws_vpn_connection_route` 對應 AWS 的 `CreateVpnConnectionRoute`，只用於 VGW 與 customer gateway 之間）；TGW 模式的靜態路由要加在 TGW 的 route table，那不歸這個 module 管。
- `propagate_route_table_ids` 只用於 VGW 模式；VGW 的 route propagation 開了之後，連線學到或設定的路由會自動進那些 route table。TGW 的 propagation 設在 TGW 那邊。
- customer gateway 的 `ip_address` 要是固定的公網 IPv4；設備在 NAT 後面就填 NAT 的位址，並放行 UDP 500 與 4500。ASN 7224 在所有 region 都被 AWS 保留，module 直接擋；另外 9059（`eu-west-1`）、10124（`ap-northeast-1`）、17943（`ap-southeast-1`）在各自的 region 被保留，module 不擋，使用前自己確認。
- 兩條 tunnel 都要在地端設備上設定，單條 tunnel 沒有備援。
- 費用：每條連線約 0.048 美元／小時（Tokyo，設計文件的估計，以定價頁為準），另加資料傳輸。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

PSK 輸入（`tunnelN_preshared_key`）、`Standard` 的 PSK 儲存、accelerated VPN、Large Bandwidth Tunnel、Cloud WAN、IPv6、憑證型 customer gateway、private IP VPN（Direct Connect）、tunnel 內網段（`inside_cidr`）、DPD 與 startup action 的調整、transit gateway 本身與它的 route table、告警（用 `metric-alarm`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | VPN 連線的名稱，也是各資源的 `Name` tag 與 log group 名稱的一部分。2–63 字元，限小寫英數字與 `-`，以字母開頭。 |
| `kms_key_arn` | `string` | 無 | 是 | module 自己建的 tunnel log group 加密用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 CloudWatch Logs（`logs.<region>.amazonaws.com`）能使用這把 key。pre-shared key 由 Site-to-Site VPN 服務存進它自己管理的 Secrets Manager secret，不經過這把 key，也不經過 Terraform。 |
| `vpn_gateway` | `object` | `null` | 否 | 要 module 自己建 virtual private gateway（VGW）並掛到 `vpc_id` 時給，`{}` 表示用預設 ASN 64512。`amazon_side_asn` 是 AWS 這一側的私有 BGP ASN：16 位元 64512–65534，或 32 位元 4200000000–4294967294。跟 `transit_gateway_id` 恰好擇一。 |
| `transit_gateway_id` | `string` | `null` | 否 | 既有 transit gateway 的 ID（`tgw-0123456789abcdef0`），VPN 連線直接終結在它上面。跟 `vpn_gateway` 恰好擇一；transit gateway 本身與它的 route table 不歸這個 module 管。 |
| `vpc_id` | `string` | `null` | 否 | VGW 要掛上去的 VPC，格式 `vpc-0123456789abcdef0`。給了 `vpn_gateway` 就必填；用 `transit_gateway_id` 時必須是 `null`。 |
| `customer_gateway` | `object` | 無 | 是 | 地端 VPN 設備。`ip_address` 是設備對外介面的固定公網 IPv4（在 NAT 後面就填 NAT 的位址）；`bgp_asn` 是地端的 BGP ASN，1–4294967295（不可用 7224），BGP 路由必填，靜態路由可以是 `null`；`device_name` 是選填的設備名稱。不支援憑證型 customer gateway。 |
| `routing` | `object` | `{}` | 否 | 路由方式。預設 `{}` 是 BGP（動態），這時 `customer_gateway.bgp_asn` 必填。`static_routes_only = true` 用靜態路由：VGW 模式要在 `static_routes` 列出地端網段（網路位址格式，例如 `192.168.10.0/24`，最多 100 條，不可為 `0.0.0.0/0`）；transit gateway 模式的靜態路由放在 transit gateway 的 route table，這裡不能給。 |
| `propagate_route_table_ids` | `list(string)` | `[]` | 否 | 要開啟 VGW route propagation 的 VPC route table，格式 `rtb-0123456789abcdef0`，不可重複。只用在 VGW 模式；transit gateway 的 propagation 設在 transit gateway 那邊。用 list 而不是 set：ID 在 plan 時可能還不知道。 |
| `tunnel_options` | `object` | `{}` | 否 | 兩條 tunnel 共用的 IKE 參數，只收強參數：加密 `AES256-GCM-16`、`AES128-GCM-16`、`AES256`、`AES128`；完整性 `SHA2-256`、`SHA2-384`、`SHA2-512`（不收 `SHA1`）；Diffie-Hellman group 14–24（不收 2、5）；IKE 版本固定 `ikev2`。每個清單至少一個值。`phase1_lifetime_seconds` 900–28800，`phase2_lifetime_seconds` 900–3600 且要小於 phase 1。預設值是這些強參數的完整集合；地端設備只支援其中一部分時再縮小。 |
| `log_retention_days` | `number` | `90` | 否 | module 自己建的 tunnel log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 90）。 |
| `tags` | `map(string)` | `{}` | 否 | 各資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `vpn_connection_id` | VPN 連線的 ID（`vpn-...`）。 |
| `tunnel_addresses` | 兩條 tunnel 的 AWS 側公網 IP，順序是 tunnel 1、tunnel 2；設定地端設備時用。 |
| `preshared_key_secret_arn` | 存放 pre-shared key 的 Secrets Manager secret ARN（由 Site-to-Site VPN 服務建立與管理）。要有 `secretsmanager:GetSecretValue` 的身分才讀得到，module 與 state 都不含 key 本身。 |
| `vpn_gateway_id` | module 建的 virtual private gateway ID；用 `transit_gateway_id` 時是 `null`。 |
| `log_group_name` | tunnel log 的 CloudWatch log group 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/vpn-site-to-site
```
