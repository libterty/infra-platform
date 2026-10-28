# cognito-user-pool

建一個 Cognito user pool、它的 prefix domain（hosted UI）、選填的 resource server，以及多個 public app client。client 沒有 client secret，只用 authorization code flow（搭配 PKCE），適合 SPA 與行動 app。`issuer_url` 與 `client_ids` 直接接到 `apigateway-http` 的 JWT authorizer。

## 用法

```hcl
module "auth" {
  source = "git::https://github.com/<org>/<repo>.git//modules/cognito-user-pool?ref=cognito-user-pool-v0.1.0"

  name          = "alpha-dev-users"
  domain_prefix = "alpha-dev-login"

  resource_servers = {
    alpha = {
      name   = "alpha-api"
      scopes = { "items.read" = "Read items" }
    }
  }

  clients = {
    spa = {
      callback_urls = ["https://app.dev.example.com/callback"]
      logout_urls   = ["https://app.dev.example.com/"]
      scopes        = ["openid", "email", "alpha/items.read"]
    }
  }
}
```

完整範例見 [`examples/basic/`](./examples/basic/main.tf)。

## 固定行為

| 項目 | 值 |
|---|---|
| client secret | 不產生（`generate_secret = false`），state 裡沒有 secret |
| OAuth flow | 只有 `code`，不准 implicit 與 client credentials；identity provider 只有 `COGNITO` |
| auth flow | `ALLOW_USER_SRP_AUTH`、`ALLOW_REFRESH_TOKEN_AUTH`，不准明文密碼的 `USER_PASSWORD_AUTH` |
| 帳號列舉 | `prevent_user_existence_errors = "ENABLED"` |
| token | 開 token revocation；access 與 ID token 以分鐘計、refresh token 以天計 |
| MFA | 只用 TOTP，`mfa = "OFF"` 時不設定 |
| 帳號復原 | 只用已驗證的 email |
| 寄信 | `COGNITO_DEFAULT` |
| 使用者名稱 | 不分大小寫 |
| tag | 給定的 `tags` 加上 `Name` |

## 注意

- `COGNITO_DEFAULT` 每個帳號每天最多寄 50 封信（每天 UTC 09:00 重算），邀請信、驗證碼、忘記密碼都算在內。sit 做大量註冊測試會撞到；正式上線要換 SES，這個 module 目前不支援。
- `deletion_protection` 預設開啟。destroy 前先改成 `false` 並 apply 一次。
- `domain_prefix` 在同一個 region 內要唯一，已經被別的帳號用掉時 apply 會失敗。
- `admin_create_user_only = true`（預設）時使用者只能由管理者建立，Cognito 會寄含臨時密碼的邀請信。
- `sign_in_attributes` 有 `phone_number` 時，module 不設定 SMS，電話要由管理者標成已驗證；只用 `email` 最單純。
- 前端用 hosted UI 登入時要帶 PKCE（`code_challenge`）；Cognito 不會強制，這是前端的責任。
- JWT authorizer 的 `audience` 要填 `client_ids` 裡的 ID。Cognito 的 access token 沒有 `aud` claim，API Gateway 改比對 `client_id`。
- 這個 module 只做過離線的靜態驗證，還沒在真實帳號 apply 過。

## 刻意不做

confidential client（有 client secret）、identity pool、社群登入與 SAML／OIDC IdP、Lambda trigger、custom domain（用 prefix domain）、SES、managed login branding、SMS MFA 與 email MFA、advanced security（threat protection）。

<!-- BEGIN_TF_DOCS -->
## 輸入

| 名稱 | 型別 | 預設 | 必填 | 說明 |
|---|---|---|---|---|
| `name` | `string` | 無 | 是 | user pool 的名稱，1–128 字元，限英數字、`_`、`-`、`.`。 |
| `user_pool_tier` | `string` | `"ESSENTIALS"` | 否 | user pool 的方案：`LITE`、`ESSENTIALS`、`PLUS`（預設 `ESSENTIALS`）。 |
| `sign_in_attributes` | `list(string)` | `[ "email" ]` | 否 | 使用者登入用的屬性，`email` 與 `phone_number` 的組合（預設 `["email"]`）。module 不設定 SMS，只自動驗證 email；用 `phone_number` 時電話要由管理者標成已驗證。 |
| `admin_create_user_only` | `bool` | `true` | 否 | 是否只允許管理者建立使用者（預設 `true`，關掉自行註冊）。 |
| `mfa` | `string` | `"OPTIONAL"` | 否 | MFA 設定：`OFF`、`OPTIONAL`、`ON`（預設 `OPTIONAL`）。只用 TOTP（authenticator app），不用 SMS 或 email。 |
| `password_policy` | `object` | `{}` | 否 | 密碼規則。`minimum_length` 12–99（預設 12）；預設要求大小寫與數字、不要求符號；`temporary_password_validity_days` 1–365（預設 7），是管理者建立的臨時密碼有效天數。 |
| `deletion_protection` | `bool` | `true` | 否 | 是否開啟刪除保護（預設 `true`）。要 destroy 前先改成 `false` 並 apply 一次。 |
| `domain_prefix` | `string` | 無 | 是 | hosted UI 的 prefix domain，網址是 `https://<domain_prefix>.auth.<region>.amazoncognito.com`。1–63 字元，限小寫英數字與 `-`，頭尾不能是 `-`，不能含 `aws`、`amazon`、`cognito`。在同一個 region 內必須唯一。 |
| `resource_servers` | `map(object)` | `{}` | 否 | resource server 的 identifier（1–256 字元，限英數字與 `._:/-`）對應 `{ name, scopes }`。`scopes` 是 scope 名稱（1–256 字元，不含 `/`）對應說明。client 用 `<identifier>/<scope>` 要求這些 scope。 |
| `clients` | `map(object)` | 無 | 是 | client 名稱（1–128 字元，限英數字、`_`、`-`）對應 public app client（沒有 client secret，只用 authorization code flow 加 PKCE）。欄位：`callback_urls`（至少一個）、`logout_urls`，都必須是 `https://`，只有 `http://localhost` 例外；`scopes` 是 `openid`、`email`、`profile` 或 `<resource server>/<scope>`；`access_token_minutes`、`id_token_minutes` 5–1440（預設 60）；`refresh_token_days` 1–3650（預設 30）。 |
| `tags` | `map(string)` | `{}` | 否 | user pool 的 tag；`Name` 由 module 加上。 |

## 輸出

| 名稱 | 說明 |
|---|---|
| `user_pool_id` | user pool 的 ID。 |
| `user_pool_arn` | user pool 的 ARN。 |
| `issuer_url` | token 的 issuer（`https://cognito-idp.<region>.amazonaws.com/<pool id>`），給 `apigateway-http` 的 JWT authorizer。 |
| `client_ids` | client 名稱對應 client ID，給 JWT authorizer 的 `audience` 與前端設定。 |
| `hosted_ui_url` | hosted UI 的網址（`https://<domain_prefix>.auth.<region>.amazoncognito.com`）。 |
<!-- END_TF_DOCS -->

## 測試

```bash
scripts/validate.sh modules/cognito-user-pool
```
