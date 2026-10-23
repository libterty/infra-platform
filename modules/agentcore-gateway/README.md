# agentcore-gateway

建一個 AgentCore Gateway（MCP）與它的 target。target 只收兩種：Lambda、MCP server。Gateway 一定要有 inbound 認證，預設 `AWS_IAM`（呼叫端用自己的 role 簽 SigV4），也可以用 `CUSTOM_JWT`；不收 `NONE`。

**這個 module 的行為沒有在任何環境部署過。** 下面寫的行為都只根據 provider schema 與 AWS 文件。

## 用法

```hcl
module "gateway" {
  source = "git::https://github.com/<org>/<repo>.git//modules/agentcore-gateway?ref=agentcore-gateway-v0.1.1"

  name     = "alpha-dev-gateway"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"

  targets = {
    catalog = {
      type       = "lambda"
      lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
      tools = [
        {
          name        = "search_items"
          description = "Search items by keyword"
          properties = {
            query = { type = "string", description = "Keyword", required = true }
            limit = { type = "integer" }
          }
        },
      ]
    }
    orders = {
      type               = "lambda"
      lambda_arn         = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-orders"
      tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/orders.json"
    }
    docs = {
      type     = "mcp_server"
      endpoint = "https://mcp.example.com/mcp"
    }
  }
}
```

完整範例見 [`examples/lambda-and-mcp-server/`](./examples/lambda-and-mcp-server/main.tf)。

## 容易出錯的地方

- **Lambda 的工具定義只能是「一層屬性」或「S3 上的完整定義」。** provider 的 inline 工具定義是多層 block（`input_schema` → `property` → `items` → …，第三層之後才是 JSON 字串），Terraform 沒有遞迴，寫不出任意深度。工具輸入只有一層屬性時用 `tools`；需要巢狀型別（例如陣列裡放物件）時，把完整的工具定義放在 S3，給 `tool_schema_s3_uri`。`tools` 裡 `type = "array"` 或 `"object"` 的屬性不會帶 `items`／`properties`，AWS 是否接受這種寫法**未實測**。
- **MCP server target 不帶 outbound 認證。** AWS 是否接受不帶 `credential_provider_configuration` 的 MCP server target **未實測**。如果不接受，MCP server target 在 credential provider module 做出來之前無法使用。
- **Lambda target 一律用 Gateway 自己的 role 呼叫 Lambda**（`gateway_iam_role`）。`role_arn` 那支 role 要有對應 Lambda 的 `lambda:InvokeFunction`，這個 module 不建 IAM，由呼叫端附加。少了這個權限，工具呼叫會失敗，看起來像 Lambda 本身出錯。
- **`tool_schema_s3_uri` 的 S3 物件由 Gateway 的 role 讀取**，role 也要有那個物件的 `s3:GetObject`。
- **名稱規則與 `discovery_url` 的格式檢查是照 API 文件寫的，未實測。** 名稱只收英數與單一 `-`，最多 100 字；target 名稱就是 `targets` 的 key。
- **`CUSTOM_JWT` 要有 IdP。** `discovery_url` 必須是 `https://` 且以 `/.well-known/openid-configuration` 結尾，`allowed_audience` 與 `allowed_clients` 至少一個非空。
- **`AWS_IAM` 時呼叫端要有 `bedrock-agentcore:InvokeGateway`**，resource 是 `gateway_arn`。
- **Lambda target 預設只能在目前的帳號。** `lambda_arn` 的帳號如果不是目前帳號、也不在 `allowed_account_ids` 裡，precondition 會在 plan 時擋下（帳號來自 `aws_caller_identity`，variable validation 讀不到 data source）。要接別的帳號的 Lambda，把那個帳號 ID 明寫進 `allowed_account_ids`。
- **`tool_schema_s3_uri` 沒有帳號檢查。** S3 URI 不帶帳號，module 判斷不了 bucket 屬於誰；要限制能讀哪些 bucket，靠的是 Gateway role 的 `s3:GetObject` 範圍。

## 刻意不做

- credential provider（API key、OAuth）：需要把 secret 交給 AgentCore。之後要做的話另開 module，值不進 state。
- OpenAPI、Smithy、API Gateway、connector 型 target。
- MCP server target 的 inline 工具定義：MCP server 的工具清單由 server 自己回報。
- `private_endpoint`（VPC Lattice）、interceptor、policy engine、`exception_level`。
- IAM：Gateway role 與它的權限由呼叫端（範本的 `iam-base`／`iam-app`）處理。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Gateway 名稱。英數字與單一 `-`（不可連續 `--`，頭尾不可是 `-`），最多 100 字元。 |
| `description` | `string` | `null` | 否 | Gateway 的說明。 |
| `role_arn` | `string` | 無 | 是 | Gateway 的 service role ARN，可以帶 path。Lambda target 用這支 role 呼叫，所以它要有那些 Lambda 的 `lambda:InvokeFunction`。 |
| `authorizer` | `object` | `{ "type": "AWS_IAM" }` | 否 | 入站驗證。欄位：`type`（必填，`AWS_IAM`（SigV4）或 `CUSTOM_JWT`，不收 `NONE`）、`discovery_url`、`allowed_audience`、`allowed_clients`（後兩者預設 `[]`，不可有空字串或只有空白的項目）。`CUSTOM_JWT` 時 `discovery_url` 必填，要 `https://` 開頭、以 `/.well-known/openid-configuration` 結尾，`allowed_audience`、`allowed_clients` 至少一個非空；`AWS_IAM` 時這三個都不可給。 |
| `mcp` | `object` | `{}` | 否 | MCP 協定設定。欄位：`supported_versions`（預設 `["2025-03-26"]`）、`search_type`（給 `SEMANTIC` 開啟工具搜尋；預設 `null`，不送、不開）。 |
| `kms_key_arn` | `string` | `null` | 否 | Gateway 加密用的自管 KMS key ARN（`arn:…:kms:<region>:<帳號>:key/<key id>`，multi-region key 可以，不收 alias 與單獨的 key id）。`null` 時用 AWS 擁有的 key。 |
| `allowed_account_ids` | `set(string)` | `[]` | 否 | 目前帳號以外、Lambda target 可以在的帳號（12 位數字）。空的時候所有 Lambda target 都必須在目前帳號。`tool_schema_s3_uri`（不含帳號）與 MCP server target 不檢查。 |
| `targets` | `map(object)` | `{}` | 否 | Gateway target，key 是 target 名稱（規則同 `name`），`type` 是 `lambda` 或 `mcp_server`。欄位見〈`targets` 欄位〉。 |
| `tags` | `map(string)` | `{}` | 否 | 套用到 Gateway 的 tag，另外加 `Name`。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `gateway_id` | Gateway id。 |
| `gateway_arn` | Gateway ARN，`bedrock-agentcore:InvokeGateway` 的 resource。 |
| `gateway_url` | Gateway 的 MCP 端點 URL。 |
| `target_ids` | key 同 `targets` 的 map，值是 target id。 |
<!-- END_TF_DOCS -->

## `targets` 欄位

`targets` 的每個值：

| 欄位 | 型別 | 預設 | 適用 | 說明 |
|---|---|---|---|---|
| `type` | `string` | 無（必填） | 全部 | `lambda` 或 `mcp_server` |
| `description` | `string` | `null` | 全部 | target 說明 |
| `lambda_arn` | `string` | `null` | `lambda` | Lambda function ARN，`lambda` 時必填 |
| `tool_schema_s3_uri` | `string` | `null` | `lambda` | tool schema 的位置，`s3://bucket/key`。跟 `tools` 恰好給一個；巢狀 schema 走這條 |
| `tools` | `list(object)` | `null` | `lambda` | 直接寫的 tool 清單，跟 `tool_schema_s3_uri` 恰好給一個且不可為空；只支援平面的 `properties` |
| `endpoint` | `string` | `null` | `mcp_server` | MCP server 的 `https://` 端點，`mcp_server` 時必填 |

- `lambda` target 不可給 `endpoint`；`mcp_server` target 不可給 `lambda_arn`、`tool_schema_s3_uri`、`tools`。
- `tools` 每個元素有 `name`（同一個 target 內不重複）、`description`（不可空白）、`properties`（map，key 是屬性名稱，預設 `{}`）。
- `properties` 的每個值：`type`（只收 `string`、`number`、`integer`、`boolean`、`object`、`array`）、`description`（選填）、`required`（預設 `false`）。

## 測試

```bash
scripts/validate.sh modules/agentcore-gateway
```
