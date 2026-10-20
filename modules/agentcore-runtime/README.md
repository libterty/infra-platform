# agentcore-runtime

建一個 AgentCore Runtime（容器型 artifact）。不建 endpoint，呼叫端用 AWS 自帶的 `DEFAULT` endpoint。

execution role、ECR repository、security group、log 與 trace 的 delivery 都不在這裡建，一律從外部傳入或交給別的 module（`iam-role`、`ecr-repository`、`security-group`、`log-delivery`）。

## 用法

```hcl
module "agent" {
  source = "git::https://github.com/<org>/<repo>.git//modules/agentcore-runtime?ref=agentcore-runtime-v0.1.1"

  name          = "alpha_dev_agent"
  role_arn      = module.agent_role.role_arn
  container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"

  network = {
    subnet_ids         = module.vpc.subnet_ids["app"]
    security_group_ids = [module.agent_sg.security_group_id]
  }
}
```

完整範例見 [`examples/vpc/`](./examples/vpc/main.tf)。

## 容易出錯的地方

- **lifecycle 少送一個值會靜默回到 AWS 預設。** 底層的 `UpdateAgentRuntime` 是 PUT，整個 lifecycle 設定一起換掉；只送 `idle_runtime_session_timeout` 時，`max_lifetime` 會回到 AWS 預設，反之亦然，而且不會報錯。這個 module 一律把兩個值一起送，只覆寫其中一個時另一個仍是 900／28800。
- **映像 tag 只由 Terraform 管。** 換版只要改 `container_uri` 再 apply。module 不忽略映像的變更，所以繞過 Terraform 直接呼叫 API 換的映像，下一次 apply 會被退回去。`:latest`（不分大小寫）與沒有 tag 的 URI 一律擋下。
- **映像預設只能來自目前帳號的 ECR。** URI 開頭的 registry 帳號如果不是目前帳號、也不在 `allowed_account_ids` 裡，precondition 會在 plan 時擋下。要拉別的帳號的映像，把那個帳號 ID 明寫進 `allowed_account_ids`。
- **`PUBLIC` 要明寫。** 預設是 `VPC`。`PUBLIC` 不經過 security group 與 VPC endpoint，流量直接走 AWS 的公開網路，只在確定不需要私有連線時使用。
- **拉長 `idle_session_timeout` 不會改善冷啟動。** 帳號的 session 數量有上限：idle 越長，同時佔用的 session 越多，能撐的流量越少。要降低冷啟動得在應用程式層處理（例如 session 分片），module 不做。
- **名稱只能用底線。** AgentCore 的 Runtime 名稱不收連字號，跟專案其他資源的命名慣例不同，名稱要另外組。

## 注意

- `VPC` 模式要至少 2 個不重複的 subnet（本 repo 的高可用慣例，不是 AWS 的下限）與 1–5 個 security group；`PUBLIC` 時兩者都必須是空的。
- VPC 模式下每個 Runtime 會用掉多少 ENI 與 IP 還沒查證，建議把放 Runtime 的 subnet tier 切大一點。
- 沒有 NAT 時，VPC 裡要有 `bedrock-runtime` 與 `bedrock-agentcore` 的 interface endpoint；這個 module 讀不到 VPC 的狀態，由呼叫端檢查。
- `environment_variables` 不要放 secret。secret 放 Secrets Manager，這裡只放 ARN。名稱含 `SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`／`APIKEY`、`PRIVATE_KEY`／`PRIVATEKEY`、`CREDENTIAL`（不分大小寫）的變數會被擋下；例外是名稱以 `_ARN` 結尾、值以 `arn:` 開頭的（例如 `DB_SECRET_ARN`）。這只是看名稱猜：`AGENT_MAX_TOKENS` 這類名稱也會被擋，要改名；值本身是不是 secret，module 看不出來。
- `request_header_allowlist` 不收 `Cookie`、`Proxy-Authorization`、`Host`、`X-Amz-Security-Token`、`X-Amz-Date`（不分大小寫）：這些 header 帶的是呼叫端的憑證或簽章資料，轉給容器等於把憑證交出去。`Authorization` 只在設了 `jwt_authorizer` 時可以轉：那時 AgentCore 已經驗過 token，容器拿它來辨識使用者；走 IAM（SigV4）時 `Authorization` 是呼叫端的簽章，一律不轉。
- `jwt_authorizer = null` 時維持預設的 IAM（SigV4）入站驗證。
- 名稱 48 字、SG 上限 5、`idle <= max`、`protocol` 允許值、JWT 的格式規則照 AWS 文件寫，尚未實測。
- 不支援 `code_configuration`（S3 程式碼型 artifact）、`filesystem_configuration`、多個 endpoint。
- 不建 IAM 資源。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | 字母開頭、只有字母數字底線，最多 48 字 |
| `description` | `string` | `null` | 否 | Runtime 說明 |
| `role_arn` | `string` | 無 | 是 | execution role ARN，可以帶 path |
| `container_uri` | `string` | 無 | 是 | ECR 映像，明確 tag（不得 `latest`，不分大小寫）或 sha256 digest；registry 帳號必須是目前帳號或在 `allowed_account_ids` 裡 |
| `allowed_account_ids` | `set(string)` | `[]` | 否 | 目前帳號以外、`container_uri` 可以使用的 ECR registry 帳號（12 位數字）。空的時候映像必須在目前帳號 |
| `network` | `object({ mode, subnet_ids, security_group_ids })` | 無 | 是 | `mode` 預設 `VPC`，只收 `VPC`、`PUBLIC` |
| `session_lifecycle` | `object({ idle_session_timeout, max_lifetime })` | `{}`（900／28800） | 否 | 秒；兩個值都在 60–1209600，且 idle 不大於 max |
| `protocol` | `string` | `"HTTP"` | 否 | `HTTP`、`MCP`、`A2A` |
| `environment_variables` | `map(string)` | `{}` | 否 | 一般環境變數；空的時候不送。名稱看起來像 secret 的會被擋下（見〈注意〉），secret 放 Secrets Manager |
| `jwt_authorizer` | `object({ discovery_url, allowed_audience, allowed_clients })` | `null` | 否 | 入站 JWT 驗證；`discovery_url` 要 https 且以 `/.well-known/openid-configuration` 結尾，audience 與 clients 至少一個非空，且不可有空字串或只有空白的項目 |
| `request_header_allowlist` | `set(string)` | `[]` | 否 | 轉給容器的 request header；空的時候不送。不收帶憑證或簽章的 header（見〈注意〉） |
| `tags` | `map(string)` | `{}` | 否 | 額外 tag；`Name` 由 module 加上 |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `runtime_arn` | `string` | Runtime ARN |
| `runtime_id` | `string` | Runtime ID |
| `runtime_name` | `string` | Runtime 名稱 |
| `runtime_version` | `string` | Runtime 版本，每次更新都會變 |
| `workload_identity_arn` | `string` | AWS 為 Runtime 建的 workload identity ARN；沒有回報時為 `null` |

## 測試

```bash
scripts/validate.sh modules/agentcore-runtime
```
