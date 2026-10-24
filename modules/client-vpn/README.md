# client-vpn

建一個 AWS Client VPN endpoint：支援 mutual TLS（憑證）、SAML（單一登入）、兩者並用，加上 subnet 關聯、授權規則與路由。connection log 一律開啟並寫進 KMS 加密的 log group；傳輸固定 UDP 443；預設 split tunnel；`0.0.0.0/0` 的授權與路由要明確允許才收。

## 用法

```hcl
module "client_vpn" {
  source = "git::https://github.com/<org>/<repo>.git//modules/client-vpn?ref=client-vpn-v0.1.0"

  name        = "alpha-dev-vpn"
  kms_key_arn = module.key.key_arn

  server_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  authentication = {
    mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
  }

  client_cidr_block  = "10.250.0.0/22"
  vpc_id             = module.vpc.vpc_id
  vpc_cidr_blocks    = [module.vpc.vpc_cidr]
  subnet_ids         = [module.vpc.subnet_ids_data[0]]
  security_group_ids = [module.sg_client_vpn.id]

  authorization_rules = [
    { target_cidr = "10.30.8.0/22" },
  ]
}
```

SAML 加群組授權（SAML provider 在 module 外建好）：

```hcl
  authentication = {
    saml_provider_arn = "arn:aws:iam::111111111111:saml-provider/example-idp"
  }

  authorization_rules = [
    { target_cidr = "10.30.8.0/22", access_group_id = "data-engineers" },
  ]
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| connection log | `connection_log_options.enabled = true`，寫進 module 自己建的 log group `/aws/client-vpn/<name>`，用 `kms_key_arn` 加密、保留 `log_retention_days` 天，沒有關閉的選項 |
| 傳輸 | UDP、port 443，建立後不能改 |
| split tunnel | 預設 `true`；`false`（full tunnel）才能搭配 `allow_internet_access` 放行 `0.0.0.0/0` |
| 連線時數 | `session_timeout_hours` 預設 12（只能 8、10、12、24） |
| 自助入口 | 只在給了 `authentication.self_service_saml_provider_arn` 時開啟 |
| 驗證 | 至少一種；兩種都給時，連線要兩個都通過 |
| tag | 給定的 `tags` 加上 `Name` |

## 驗證與授權的規則

| 輸入 | 規則 | 依據 |
|---|---|---|
| `authentication` | 至少給 `mutual_tls_root_certificate_arn` 或 `saml_provider_arn`；兩者並用最多兩個 option | provider 文件（`authentication_options` 1–2 個）與 AWS 文件（mutual 可以加一種 user-based 驗證） |
| `authentication.self_service_saml_provider_arn` | 只能搭配 `saml_provider_arn` | AWS 文件：自助入口使用 SAML 憑證登入 |
| `authorization_rules[].access_group_id` | 只在有 `saml_provider_arn` 時能給；沒給就對所有 client 開放 | AWS 文件：群組來自 AD 或 SAML IdP（module 不支援 AD） |
| `0.0.0.0/0`（授權或路由） | 只在 `split_tunnel = false` 且 `allow_internet_access = true` 時收 | design §5.14；AWS 文件：split tunnel 加 `0.0.0.0/0` 路由可能造成連線中斷 |
| `client_cidr_block` | 網路位址、`/12`–`/22`、不與 `vpc_cidr_blocks` 重疊 | AWS 文件〈Rules and best practices〉 |

## 注意

- **SAML provider 不是這個 module 建的**：module 不建任何 IAM 資源，IAM SAML provider 要在 module 外建好，把 ARN 傳進 `authentication.saml_provider_arn`。IdP 要在 SAML 回應裡帶 `memberOf` 屬性，群組授權才有用（區分大小寫），`NameID` 要是 email 格式（AWS 文件）。
- mutual TLS 的 client 憑證要由 `mutual_tls_root_certificate_arn` 指的 CA 簽發，且 Subject 要有 CN；server 憑證與 CA 憑證都要先匯入 ACM，module 只收 ARN。server 憑證只支援 RSA 1024 與 2048 位元，module 無法在 plan 時檢查，apply 才會失敗。沒做憑證撤銷清單（CRL）。
- `vpc_cidr_blocks` 要把 VPC 的主要與次要網段都列進來，module 才擋得住重疊；日後手動加的 endpoint route 與 `client_cidr_block` 重疊，module 不檢查。`client_cidr_block` 建立後不能改，要改就得重建 endpoint。
- 每個關聯的 subnet 會在該 subnet 建 ENI；同一個可用區不能關聯兩個 subnet（module 無法在 plan 時檢查）。`authorization_rules`、`routes` 與 `subnet_ids` 都用 list 的索引當 key（ID 在 plan 時可能還不知道），改順序或從中間刪除會讓後面的資源重建，新項目請加在最後。
- Client VPN 預設拒絕：沒有 `authorization_rules` 就沒有人連得到任何網路。VPC 本身的路由由 AWS 在關聯 subnet 時自動加進 endpoint route table，不需要在 `routes` 重複寫；authorization rule 要自己寫。
- `security_group_ids` 必填：沒給的話 AWS 會套用 VPC 的 default security group。要放行 client 進來的流量，由呼叫端在目標資源的 security group 加規則，來源是這裡給的 security group。
- 第一次建立 Client VPN endpoint 時，apply 的身分可能需要 `iam:CreateServiceLinkedRole`（建立 `AWSServiceRoleForClientVPN`）；這是設計文件的假設，**這個 repo 尚未在真實帳號驗證**。
- connection log 用 CMK 加密：key policy 要讓 CloudWatch Logs 服務（`logs.<region>.amazonaws.com`）能使用這把 key。module 沒有另外建 log stream，也沒有設 CloudWatch Logs resource policy；Client VPN 是否自己建立 log stream、CMK 搭配 Client VPN 的 log 交付會不會成功，AWS 文件沒寫，**未確認**。
- 費用：每個關聯每小時約 0.15 美元，每個連線每小時約 0.05 美元（Tokyo，設計文件的估計，以定價頁為準）。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

Active Directory 驗證、憑證產生、憑證撤銷清單（CRL）、client connect handler、client login banner、client route enforcement、device posture、Transit Gateway 關聯、IPv6、TCP 與 UDP 以外的 port（`vpn_port` 固定 443）、`disconnect_on_session_timeout`。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Client VPN endpoint 的名稱，也是 `Name` tag 與 log group 名稱的一部分。2–63 字元，限小寫英數字與 `-`，以字母開頭。 |
| `kms_key_arn` | `string` | 無 | 是 | module 自己建的 connection log group 加密用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 CloudWatch Logs（`logs.<region>.amazonaws.com`）能使用這把 key。 |
| `server_certificate_arn` | `string` | 無 | 是 | server 憑證在 ACM 的 ARN，不論用哪種驗證都必填。憑證要是 RSA 1024 或 2048 位元（AWS 文件）；module 只收 ARN，不收憑證或私鑰內容。 |
| `authentication` | `object` | 無 | 是 | 驗證方式，至少要給一種，兩種都給就是兩者並用（連線要兩個都通過）。`mutual_tls_root_certificate_arn` 是簽發 client 憑證的 CA 在 ACM 的 ARN（client 憑證由同一個 CA 簽發時，可以填 server 憑證的 ARN）；`saml_provider_arn` 是 IAM SAML identity provider 的 ARN，要在 module 外建好（module 不建 IAM 資源）；`self_service_saml_provider_arn` 是自助入口用的 SAML provider ARN，給了就開啟自助入口，只能搭配 `saml_provider_arn`。不支援 Active Directory。 |
| `client_cidr_block` | `string` | 無 | 是 | 分配給 client 的 IPv4 網段，必須是網路位址，大小 `/12`–`/22`（AWS 建議 `/22`，要容納同時連線人數的兩倍），不可與 `vpc_cidr_blocks` 重疊；建立後不能改。也不可與日後手動加的 route 重疊，module 不檢查這一項。 |
| `vpc_id` | `string` | 無 | 是 | endpoint 所在的 VPC，格式 `vpc-0123456789abcdef0`；`subnet_ids` 與 `security_group_ids` 都要在這個 VPC 裡。 |
| `vpc_cidr_blocks` | `list(string)` | 無 | 是 | VPC 的所有 IPv4 網段（主要與次要），至少一個、必須是網路位址（例如 `10.30.0.0/20`）；用來擋下與 `client_cidr_block` 重疊的設定，AWS 不允許 client 網段與 VPC 重疊。 |
| `subnet_ids` | `list(string)` | 無 | 是 | 要關聯的 subnet，至少一個、不可重複，格式 `subnet-0123456789abcdef0`，都要在 `vpc_id` 裡、且每個可用區最多一個（AWS 限制，module 無法在 plan 時檢查）。每個關聯另外計費。用 list 而不是 set：ID 在 plan 時可能還不知道。 |
| `security_group_ids` | `list(string)` | 無 | 是 | 套用在 endpoint 的 security group，至少一個、不可重複，格式 `sg-0123456789abcdef0`，由呼叫端建立（module 不建 security group）。必填，避免 AWS 在沒有指定時套用 VPC 的 default security group。 |
| `authorization_rules` | `list(object)` | `[]` | 否 | 授權規則，AWS 預設拒絕，沒有規則就沒有人連得到任何網路。`target_cidr` 是開放的網段（網路位址格式）；`access_group_id` 是 SAML IdP 的群組，只在 `authentication.saml_provider_arn` 有給時能用，沒給就是對所有 client 開放。`0.0.0.0/0` 只在 `split_tunnel = false` 且 `allow_internet_access = true` 時才能用。同一組 `target_cidr` 與 `access_group_id` 不可重複。順序變動會讓規則重建，新規則請加在最後。 |
| `routes` | `list(object)` | `[]` | 否 | endpoint route table 的額外路由（VPC 本身的路由由 AWS 在第一次關聯 subnet 時自動加）。`destination_cidr` 是目的網段（網路位址格式）；`target_subnet_id` 是要送出的已關聯 subnet，必須在 `subnet_ids` 裡。`0.0.0.0/0` 只在 `split_tunnel = false` 且 `allow_internet_access = true` 時才能用。目的網段不可重複。順序變動會讓路由重建，新路由請加在最後。 |
| `split_tunnel` | `bool` | `true` | 否 | 是否啟用 split tunnel（預設 `true`）：只有目的地在 endpoint route table 裡的流量走 VPN，client 其他流量走自己的網路。`false` 是 full tunnel，所有流量都走 VPN，這時要讓 client 上網才需要 `0.0.0.0/0`，並同時設 `allow_internet_access = true`。 |
| `allow_internet_access` | `bool` | `false` | 否 | 明確允許 `0.0.0.0/0` 出現在授權規則與路由（預設 `false`）。只能在 `split_tunnel = false` 時設為 `true`；AWS 文件指出 split tunnel 加 `0.0.0.0/0` 路由可能造成連線中斷，不建議。 |
| `session_timeout_hours` | `number` | `12` | 否 | 最長連線時數，到時 client 要重新驗證，只能是 8、10、12、24（預設 12；provider 與 AWS 的預設是 24）。 |
| `dns_servers` | `list(string)` | `[]` | 否 | client 使用的 DNS server（IPv4），最多兩個；空的就用 client 自己裝置的 DNS。full tunnel 時 Windows 會強制 DNS 走 VPN，要有一個 VPN 內連得到的 DNS server。 |
| `log_retention_days` | `number` | `90` | 否 | module 自己建的 connection log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 90）。 |
| `tags` | `map(string)` | `{}` | 否 | 各資源的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `endpoint_id` | Client VPN endpoint 的 ID（`cvpn-endpoint-...`）。 |
| `dns_name` | client 連線用的 DNS 名稱；client 設定檔請用這個名稱，不要用 IP（IP 會變）。 |
| `log_group_name` | connection log 的 CloudWatch log group 名稱。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/client-vpn
```
