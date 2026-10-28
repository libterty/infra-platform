# apigateway-http

建一個 API Gateway HTTP API：`$default` stage（自動部署）、Lambda proxy integration、JWT authorizer、route，以及選填的 custom domain。每條 route 都要明寫用哪個 authorizer，或明寫 `public = true`，沒有預設公開的 route。stage 的 throttling 與 access log 都是必填。

## 用法

```hcl
module "api" {
  source = "git::https://github.com/<org>/<repo>.git//modules/apigateway-http?ref=apigateway-http-v0.1.0"

  name = "alpha-dev-api"

  jwt_authorizers = {
    cognito = {
      issuer   = module.auth.issuer_url
      audience = [module.auth.client_ids["spa"]]
    }
  }

  integrations = {
    items = { lambda_arn = module.items.function_arn }
  }

  routes = {
    "GET /api/items"  = { integration = "items", authorizer = "cognito", scopes = ["alpha/items.read"] }
    "GET /api/health" = { integration = "items", public = true }
  }

  throttling           = { rate_limit = 50, burst_limit = 100 }
  access_log_group_arn = module.api_logs.log_group_arn

  # CloudFront uses the execute-api URL as its origin.
  disable_execute_api_endpoint = false
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| API 類型 | HTTP API（`protocol_type = "HTTP"`） |
| stage | 只有 `$default`，`auto_deploy = true` |
| integration | `AWS_PROXY`、payload `2.0`、方法 `POST` |
| authorizer | 只有 JWT，token 取自 `Authorization` header |
| route | 有 `authorizer` 的用 `JWT`；`public = true` 的用 `NONE` |
| access log | JSON 格式，欄位固定：requestId、requestTime、ip、userAgent、httpMethod、routeKey、path、protocol、status、responseLength、延遲、integration 狀態與錯誤、authorizer 錯誤、domainName；不記 JWT claim |
| custom domain | `REGIONAL`、`TLS_1_2`，API mapping 指到 `$default` |
| execute-api 網址 | 有 `custom_domain` 時預設關掉，沒有時預設開著；`disable_execute_api_endpoint` 可以覆寫 |

## 注意

- Lambda 的呼叫權限不在這個 module：在 `lambda-function` 的 `permissions` 加一筆，`principal = "apigateway.amazonaws.com"`、`source_arn = "${module.api.execution_arn}/*/*"`。
- execute-api 網址是公開的。API 放在 CloudFront 與 WAF 後面時，直接打這個網址就繞過 WAF；要靠 JWT authorizer、origin verify header 的檢查（應用程式做）與 throttling 擋。AWS WAF 不支援 HTTP API，只支援 REST API。
- HTTP API 寫 access log 不需要 account 層的 CloudWatch Logs role（那是 REST API 的設定），API Gateway 會用 CloudWatch Logs 的 resource policy 寫入；套用的人要有 `logs:CreateLogDelivery`、`logs:PutResourcePolicy` 等權限。
- `cors` 只在前端跟 API 不同源時需要；`allow_credentials = true` 時不能用 `*`。
- `custom_domain` 的憑證要跟 API 在同一個 region。alias record 用 `domain_target`。
- `$default` route 會接住所有沒對到的請求，也一樣要指定 authorizer 或 `public = true`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

WebSocket API、REST API、VPC Link、Lambda authorizer、IAM authorizer、mTLS、多個 stage、route 層級的 throttling、IAM 與 Lambda permission、log group（用 `log-group`）、DNS record（用 `route53-record`）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | HTTP API 的名稱，1–128 字元，限英數字、`_`、`-`、`.`。 |
| `description` | `string` | `null` | 否 | HTTP API 的說明（選填）。 |
| `cors` | `object` | `null` | 否 | CORS 設定（選填，`null` 表示不設定）。欄位：`allow_origins`（必填）、`allow_methods`、`allow_headers`、`allow_credentials`（預設 `false`）、`max_age`（秒，0–86400）。`allow_credentials = true` 時 `allow_origins` 不可有 `*`。API 跟前端同源時不需要設定。 |
| `jwt_authorizers` | `map(object)` | `{}` | 否 | key（1–128 字元，限英數字、`_`、`-`）對應 JWT authorizer。欄位：`issuer`（`https://` 開頭，例如 `cognito-user-pool` 的 `issuer_url`）、`audience`（允許的 client ID，至少一個）。token 從 `Authorization` header 取得。 |
| `integrations` | `map(object)` | 無 | 是 | key（1–128 字元，限英數字、`_`、`-`）對應 Lambda proxy integration，payload 固定 `2.0`。欄位：`lambda_arn`（function ARN，可帶 alias 或版本）、`timeout_ms`（50–30000，預設 30000）。呼叫權限由 `lambda-function` 的 `permissions` 給，`source_arn` 用這個 module 的 `execution_arn`。 |
| `routes` | `map(object)` | 無 | 是 | route key（例如 `"GET /items"`、`"ANY /{proxy+}"`、`"$default"`）對應 route，至少一條。欄位：`integration`（`integrations` 的 key）、`authorizer`（`jwt_authorizers` 的 key）、`scopes`（JWT 必須含有的 scope，只能配 `authorizer`）、`public`（預設 `false`）。每條 route 必須剛好二選一：給 `authorizer`，或明寫 `public = true`。 |
| `throttling` | `object` | 無 | 是 | `$default` stage 的預設 throttling，必填。`rate_limit` 是每秒請求數（大於 0），`burst_limit` 是正整數。被繞過 CDN 直接打時，這是成本的上限之一。 |
| `access_log_group_arn` | `string` | 無 | 是 | access log 寫入的 CloudWatch Logs log group ARN，必填，結尾不帶 `:*`（`log-group` module 的 `log_group_arn`）。log 格式由 module 固定為一組 JSON 欄位。 |
| `custom_domain` | `object` | `null` | 否 | custom domain（選填）。`domain_name` 是完整網域名稱，`certificate_arn` 是同一個 region 的 ACM 憑證（regional）。給了就建 regional domain（TLS 1.2）與 `$default` stage 的 API mapping，alias record 用 `domain_target`。 |
| `disable_execute_api_endpoint` | `bool` | `null` | 否 | 是否關掉預設的 execute-api 網址。預設（`null`）在有 `custom_domain` 時為 `true`，沒有時為 `false`。CloudFront 用 execute-api 網址當 origin 時要明寫 `false`。 |
| `tags` | `map(string)` | `{}` | 否 | API、stage 與 custom domain 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `api_id` | HTTP API 的 ID。 |
| `api_endpoint` | 預設的 execute-api 網址（`https://<api id>.execute-api.<region>.amazonaws.com`），可以當 CloudFront 的 origin。`disable_execute_api_endpoint` 為 `true` 時這個網址不能用。 |
| `execution_arn` | API 的 execution ARN，給 `lambda-function` 的 `permissions` 當 `source_arn`（後面接 `/*/*`）。 |
| `stage_invoke_url` | `$default` stage 的呼叫網址。 |
| `domain_target` | custom domain 的 regional 目標 `{ name, zone_id }`，給 `route53-record` 的 alias record；沒有 `custom_domain` 時為 `null`。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/apigateway-http
```
