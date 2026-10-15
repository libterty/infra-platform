# Changelog

## 0.1.1（未發布）

初版。第一個 tag 由人手動打，release-please 從下一版才接手。

- 建立一個 `aws_bedrockagentcore_gateway`，`protocol_type` 固定 `MCP`；`authorizer` 預設 `AWS_IAM`，這時不送 `authorizer_configuration`；`CUSTOM_JWT` 時送 `discovery_url`、`allowed_audience`、`allowed_clients`。
- `mcp.supported_versions` 預設 `["2025-03-26"]`；`mcp.search_type = null` 時不送。
- 每個 `targets` 建立一個 `aws_bedrockagentcore_gateway_target`，名稱就是 map 的 key。target 只收 `lambda` 與 `mcp_server` 兩種。
- Lambda target 一律帶 `credential_provider_configuration.gateway_iam_role`；工具定義收 `tool_schema_s3_uri`（送 `tool_schema.s3.uri`）或扁平的 `tools`（每個工具一個 `inline_payload`、每個屬性一個 `property`），兩者恰好一個。
- MCP server target 只送 `endpoint`，不帶 credential 區塊、不帶工具定義。
- `targets` 預設 `{}`，沒給就不建任何 target。
- 擋下：`authorizer.type` 不是 `AWS_IAM`／`CUSTOM_JWT`（包括 `NONE`）；`CUSTOM_JWT` 沒有 `https://…/.well-known/openid-configuration` 的 `discovery_url` 或 audience／clients 都空；`AWS_IAM` 帶了 JWT 欄位；gateway 與 target 名稱不是英數加單一 `-`、或超過 100 字；`role_arn` 不是 IAM role ARN（可以帶 path）；target 型別不是 `lambda`／`mcp_server`；Lambda target 沒有 Lambda function ARN、帶了 `endpoint`、`tool_schema_s3_uri` 與 `tools` 不是恰好一個；MCP server target 的 `endpoint` 不是 `https://`、或帶了 Lambda 欄位；`tool_schema_s3_uri` 不是 `s3://bucket/key`；同一個 target 內工具同名、工具描述空白、屬性型別不是 JSON Schema 的 6 種基本型別。
- `role_arn` 可以帶 path（例如 `role/service-role/…`），規則與 `agentcore-runtime` 相同。
- 新增 `allowed_account_ids`（預設 `[]`）：Lambda target 的 `lambda_arn` 必須在目前帳號或這份清單裡，否則 plan 被 precondition 擋下。目前帳號的呼叫端不用改設定。`tool_schema_s3_uri` 不帶帳號，不檢查。
- 擋下 `allowed_audience`／`allowed_clients` 裡的空字串與只有空白的項目。
- 擋下不是 KMS key ARN 的 `kms_key_arn`（alias ARN、單獨的 key id）。
- 輸出 `gateway_id`、`gateway_arn`、`gateway_url`、`target_ids`。
- 不建 IAM、credential provider；不支援 OpenAPI、Smithy、API Gateway 型 target、VPC Lattice、interceptor、policy engine。
