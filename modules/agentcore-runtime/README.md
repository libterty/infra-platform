# agentcore-runtime

建一個 AgentCore Runtime（容器型 artifact）。不建 endpoint，呼叫端用 AWS 自帶的 `DEFAULT` endpoint。

execution role、ECR repository、security group、log 與 trace 的 delivery 都不在這裡建，一律從外部傳入或交給別的 module（`iam-role`、`ecr-repository`、`security-group`、`log-delivery`）。

## 用法

```hcl
module "agent" {
  source = "git::https://github.com/<org>/<repo>.git//modules/agentcore-runtime?ref=agentcore-runtime-v0.1.0"

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
- **映像 tag 由 Terraform 擁有。** 換版只改 `container_uri` 再 apply。module 不忽略映像的變更，繞過 Terraform 直接呼叫 API 換映像，下一次 apply 會退版。`:latest` 與沒有 tag 的 URI 一律擋下。
- **`PUBLIC` 要明寫。** 預設是 `VPC`。`PUBLIC` 不經過 security group 與 VPC endpoint，流量直接走 AWS 的公開網路，只在確定不需要私有連線時使用。
- **拉長 `idle_session_timeout` 不會改善冷啟動。** 帳號的 session 存量有上限：idle 越長，同時佔用的 session 越多，能撐的流量越少。要降冷啟動是應用程式層的事（例如 session 分片），module 不做。
- **名稱只能用底線。** AgentCore 的 Runtime 名稱不收連字號，跟專案其他資源的命名慣例不同，要另外組。

## 注意

- `VPC` 模式要至少 2 個不重複的 subnet（本 repo 的高可用慣例，不是 AWS 的下限）與 1–5 個 security group；`PUBLIC` 時兩者都必須是空的。
- VPC 模式每個 Runtime 用掉多少 ENI 與 IP 還沒查證，放 Runtime 的 subnet tier 建議切大一點。
- 沒有 NAT 時，VPC 裡要有 `bedrock-runtime` 與 `bedrock-agentcore` 的 interface endpoint；這個 module 讀不到 VPC 的狀態，由呼叫端檢查。
- `environment_variables` 不要放 secret。secret 放 Secrets Manager，這裡只放 ARN；module 不做「看起來像 secret」的檢查。
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
| `role_arn` | `string` | 無 | 是 | execution role ARN，不得帶 path |
| `container_uri` | `string` | 無 | 是 | ECR 映像，明確 tag（不得 `latest`）或 sha256 digest |
| `network` | `object({ mode, subnet_ids, security_group_ids })` | 無 | 是 | `mode` 預設 `VPC`，只收 `VPC`、`PUBLIC` |
| `session_lifecycle` | `object({ idle_session_timeout, max_lifetime })` | `{}`（900／28800） | 否 | 秒；兩個值都在 60–1209600，且 idle 不大於 max |
| `protocol` | `string` | `"HTTP"` | 否 | `HTTP`、`MCP`、`A2A` |
| `environment_variables` | `map(string)` | `{}` | 否 | 一般環境變數；空的時候不送 |
| `jwt_authorizer` | `object({ discovery_url, allowed_audience, allowed_clients })` | `null` | 否 | 入站 JWT 驗證；`discovery_url` 要 https 且以 `/.well-known/openid-configuration` 結尾，audience 與 clients 至少一個非空 |
| `request_header_allowlist` | `set(string)` | `[]` | 否 | 轉給容器的 request header；空的時候不送 |
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
