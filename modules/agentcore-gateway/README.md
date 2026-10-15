# agentcore-gateway

建一個 AgentCore Gateway（MCP）與它的 target。target 只收兩種：Lambda、MCP server。Gateway 一定要有 inbound 認證，預設 `AWS_IAM`（呼叫端用自己的 role 簽 SigV4），也可以用 `CUSTOM_JWT`；不收 `NONE`。

**這個 module 的行為沒有在任何環境部署過。** 唯一的參考實作裡，Lambda target 標註為沒在使用、OpenAPI target 已停用，所以每一條行為都只有 provider schema 與 AWS 文件當依據。

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

## 要修掉的坑

- **Lambda 的工具定義只能是「一層屬性」或「S3 上的完整定義」。** provider 的 inline 工具定義是多層 block（`input_schema` → `property` → `items` → …，第三層之後才是 JSON 字串），Terraform 沒有遞迴，寫不出任意深度。工具輸入只有一層屬性時用 `tools`；需要巢狀型別（例如陣列裡放物件）時，把完整的工具定義放在 S3，給 `tool_schema_s3_uri`。`tools` 裡 `type = "array"` 或 `"object"` 的屬性不會帶 `items`／`properties`，AWS 是否接受這種寫法**未實測**。
- **MCP server target 不帶 outbound 認證。** AWS 是否接受不帶 `credential_provider_configuration` 的 MCP server target **未實測**。如果不接受，MCP server target 在 credential provider module 做出來之前無法使用。
- **Lambda target 一律用 Gateway 自己的 role 呼叫 Lambda**（`gateway_iam_role`）。`role_arn` 那支 role 要有對應 Lambda 的 `lambda:InvokeFunction`，這個 module 不建 IAM，由呼叫端附加。少了權限的症狀是工具呼叫失敗，看起來像 Lambda 本身出錯。
- **`tool_schema_s3_uri` 的 S3 物件由 Gateway 的 role 讀取**，role 也要有那個物件的 `s3:GetObject`。
- **名稱規則與 `discovery_url` 的格式檢查是照 API 文件寫的，未實測。** 名稱只收英數與單一 `-`，最多 100 字；target 名稱就是 `targets` 的 key。
- **`CUSTOM_JWT` 要有 IdP。** `discovery_url` 必須是 `https://` 且以 `/.well-known/openid-configuration` 結尾，`allowed_audience` 與 `allowed_clients` 至少一個非空。
- **`AWS_IAM` 時呼叫端要有 `bedrock-agentcore:InvokeGateway`**，resource 是 `gateway_arn`。

## 刻意不做

- credential provider（API key、OAuth）：要把 secret 交給 AgentCore。之後若做，另開 module，值不進 state。
- OpenAPI、Smithy、API Gateway、connector 型 target。
- MCP server target 的 inline 工具定義：MCP server 的工具清單由 server 自己回報。
- `private_endpoint`（VPC Lattice）、interceptor、policy engine、`exception_level`。
- IAM：Gateway role 與它的權限由呼叫端（範本的 `iam-base`／`iam-app`）處理。

## 輸入

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | Gateway 名稱。英數與單一 `-`，最多 100 字 |
| `description` | `string` | `null` | 否 | Gateway 說明 |
| `role_arn` | `string` | 無 | 是 | Gateway 的 service role ARN（不帶 path）。Lambda target 用這支 role 呼叫 |
| `authorizer` | `object` | `{ type = "AWS_IAM" }` | 否 | `type`：`AWS_IAM` 或 `CUSTOM_JWT`。`CUSTOM_JWT` 時 `discovery_url` 必填、`allowed_audience`／`allowed_clients` 至少一個非空；`AWS_IAM` 時這三個不可給 |
| `mcp` | `object` | `{}` | 否 | `supported_versions`（預設 `["2025-03-26"]`）、`search_type`（`SEMANTIC` 開啟工具搜尋；預設 `null`，不送） |
| `kms_key_arn` | `string` | `null` | 否 | 加密用的 customer managed key；`null` 用 AWS 管的 key |
| `targets` | `map(object)` | `{}` | 否 | key 是 target 名稱（規則同 `name`）。`type`：`lambda` 或 `mcp_server`；`description` 選填。`lambda`：`lambda_arn` 必填，`tool_schema_s3_uri`（`s3://bucket/key`）與 `tools` 恰好一個，不可給 `endpoint`。`tools` 每個元素有 `name`（同 target 內不重複）、`description`（不可空白）、`properties`（map，key 是屬性名稱；`type` 只收 `string`、`number`、`integer`、`boolean`、`object`、`array`，`description` 選填，`required` 預設 `false`）。`mcp_server`：`endpoint` 必填且是 `https://`，不可給 Lambda 的欄位 |
| `tags` | `map(string)` | `{}` | 否 | 套用到 Gateway 的 tag，另外加 `Name` |

## 輸出

> 之後改由 terraform-docs 產生。

| 名稱 | 型別 | 說明 |
|---|---|---|
| `gateway_id` | `string` | Gateway id |
| `gateway_arn` | `string` | Gateway ARN，`bedrock-agentcore:InvokeGateway` 的 resource |
| `gateway_url` | `string` | Gateway 的 MCP 端點 URL |
| `target_ids` | `map(string)` | target id，key 為 `targets` 的 key |

## 測試

```bash
scripts/validate.sh modules/agentcore-gateway
```
