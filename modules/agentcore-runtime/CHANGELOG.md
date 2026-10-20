# Changelog

## 0.1.1（2026-10-16）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_bedrockagentcore_agent_runtime`（容器型 artifact），不建 endpoint，用 AWS 自帶的 `DEFAULT`。
- 網路模式預設 `VPC`，`PUBLIC` 要明寫；`VPC` 時送 `network_mode_config`，`PUBLIC` 時不送。
- `lifecycle_configuration` 的 `idle_runtime_session_timeout` 與 `max_lifetime` 一律一起送，預設 900／28800。
- `container_uri` 由 Terraform 擁有，不忽略映像的變更。
- `jwt_authorizer = null` 時不送 `authorizer_configuration`；`request_header_allowlist` 為空時不送 `request_header_configuration`；`environment_variables` 為空時送 `null`。
- 擋下：名稱含連字號、超過 48 字或數字開頭；`role_arn` 不是 role（可以帶 path）；`container_uri` 不是 ECR、沒有 tag 或用 `:latest`（不分大小寫）；網路模式不是 `VPC`／`PUBLIC`、`VPC` 少於 2 個不重複的 subnet 或 SG 不在 1–5 個、`PUBLIC` 卻給了 subnet 或 SG；lifecycle 任一值不在 60–1209600 或 idle 大於 max；`protocol` 不是 `HTTP`／`MCP`／`A2A`；JWT 的 `discovery_url` 不是 https 或不以 well-known 結尾、audience 與 clients 都是空的。
- `role_arn` 可以帶 path（例如 `role/service-role/…`），規則與 `agentcore-gateway` 相同。
- 新增 `allowed_account_ids`（預設 `[]`）：`container_uri` 的 ECR registry 帳號必須是目前帳號或在這份清單裡，否則 plan 被 precondition 擋下。目前帳號的呼叫端不用改設定。
- 擋下 `jwt_authorizer` 的 `allowed_audience`／`allowed_clients` 裡的空字串與只有空白的項目。
- 擋下 `request_header_allowlist` 裡的 `Cookie`、`Proxy-Authorization`、`Host`、`X-Amz-Security-Token`、`X-Amz-Date`（不分大小寫）；`Authorization` 只在設了 `jwt_authorizer` 時可以轉。
- 擋下名稱看起來像 secret 的 `environment_variables`（`SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`、`PRIVATE_KEY`、`CREDENTIAL`，不分大小寫）；名稱以 `_ARN` 結尾且值是 ARN 的放行。
- 輸出 `runtime_arn`、`runtime_id`、`runtime_name`、`runtime_version`、`workload_identity_arn`。
- 不建 IAM、ECR、SG、log／trace delivery，不支援 `code_configuration` 與 `filesystem_configuration`。
- aws provider 是 `>= 6.69, < 7.0`：6.0 沒有 `aws_bedrockagentcore_*`。
