variable "name" {
  type        = string
  description = "user pool 的名稱，1–128 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,128}$", var.name))
    error_message = "name must be 1-128 chars of letters, digits, '.', '_' or '-'."
  }
}

variable "user_pool_tier" {
  type        = string
  default     = "ESSENTIALS"
  nullable    = false
  description = "user pool 的方案：`LITE`、`ESSENTIALS`、`PLUS`（預設 `ESSENTIALS`）。"

  validation {
    condition     = contains(["LITE", "ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier must be LITE, ESSENTIALS or PLUS."
  }
}

variable "sign_in_attributes" {
  type        = list(string)
  default     = ["email"]
  nullable    = false
  description = "使用者登入用的屬性，`email` 與 `phone_number` 的組合（預設 `[\"email\"]`）。module 不設定 SMS，只自動驗證 email；用 `phone_number` 時電話要由管理者標成已驗證。"

  validation {
    condition     = length(var.sign_in_attributes) > 0 && length(distinct(var.sign_in_attributes)) == length(var.sign_in_attributes) && alltrue([for a in var.sign_in_attributes : contains(["email", "phone_number"], a)])
    error_message = "sign_in_attributes must be a non-empty list of distinct values from email and phone_number."
  }
}

variable "admin_create_user_only" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否只允許管理者建立使用者（預設 `true`，關掉自行註冊）。"
}

variable "mfa" {
  type        = string
  default     = "OPTIONAL"
  nullable    = false
  description = "MFA 設定：`OFF`、`OPTIONAL`、`ON`（預設 `OPTIONAL`）。只用 TOTP（authenticator app），不用 SMS 或 email。"

  validation {
    condition     = contains(["OFF", "OPTIONAL", "ON"], var.mfa)
    error_message = "mfa must be OFF, OPTIONAL or ON."
  }
}

variable "password_policy" {
  type = object({
    minimum_length                   = optional(number, 12)
    require_lowercase                = optional(bool, true)
    require_uppercase                = optional(bool, true)
    require_numbers                  = optional(bool, true)
    require_symbols                  = optional(bool, false)
    temporary_password_validity_days = optional(number, 7)
  })
  default     = {}
  nullable    = false
  description = "密碼規則。`minimum_length` 12–99（預設 12）；預設要求大小寫與數字、不要求符號；`temporary_password_validity_days` 1–365（預設 7），是管理者建立的臨時密碼有效天數。"

  validation {
    condition     = var.password_policy.minimum_length >= 12 && var.password_policy.minimum_length <= 99 && var.password_policy.minimum_length == floor(var.password_policy.minimum_length)
    error_message = "password_policy.minimum_length must be a whole number between 12 and 99."
  }
  validation {
    condition     = var.password_policy.temporary_password_validity_days >= 1 && var.password_policy.temporary_password_validity_days <= 365 && var.password_policy.temporary_password_validity_days == floor(var.password_policy.temporary_password_validity_days)
    error_message = "password_policy.temporary_password_validity_days must be a whole number between 1 and 365."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否開啟刪除保護（預設 `true`）。要 destroy 前先改成 `false` 並 apply 一次。"
}

variable "domain_prefix" {
  type        = string
  description = "hosted UI 的 prefix domain，網址是 `https://<domain_prefix>.auth.<region>.amazoncognito.com`。1–63 字元，限小寫英數字與 `-`，頭尾不能是 `-`，不能含 `aws`、`amazon`、`cognito`。在同一個 region 內必須唯一。"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix))
    error_message = "domain_prefix must be 1-63 chars of lower-case letters, digits or '-', not starting or ending with '-'."
  }
  validation {
    condition     = !can(regex("aws|amazon|cognito", var.domain_prefix))
    error_message = "domain_prefix must not contain the reserved words aws, amazon or cognito."
  }
}

variable "resource_servers" {
  type = map(object({
    name   = string
    scopes = map(string)
  }))
  default     = {}
  nullable    = false
  description = "resource server 的 identifier（1–256 字元，限英數字與 `._:/-`）對應 `{ name, scopes }`。`scopes` 是 scope 名稱（1–256 字元，不含 `/`）對應說明。client 用 `<identifier>/<scope>` 要求這些 scope。"

  validation {
    condition     = alltrue([for k in keys(var.resource_servers) : can(regex("^[A-Za-z0-9._:/-]{1,256}$", k))])
    error_message = "resource_servers keys (identifiers) must be 1-256 chars of letters, digits or ._:/-."
  }
  validation {
    condition     = alltrue([for r in values(var.resource_servers) : can(regex("^[A-Za-z0-9 ._+-]{1,256}$", r.name))])
    error_message = "resource_servers name must be 1-256 chars of letters, digits, spaces or ._+-."
  }
  validation {
    condition     = alltrue(flatten([for r in values(var.resource_servers) : [for s in keys(r.scopes) : can(regex("^[A-Za-z0-9._:-]{1,256}$", s))]]))
    error_message = "resource_servers scope names must be 1-256 chars of letters, digits or ._:- (no '/')."
  }
  validation {
    condition     = alltrue([for r in values(var.resource_servers) : length(r.scopes) > 0 && length(r.scopes) <= 100])
    error_message = "Each resource server needs 1-100 scopes."
  }
}

variable "clients" {
  type = map(object({
    callback_urls        = list(string)
    logout_urls          = optional(list(string), [])
    scopes               = list(string)
    access_token_minutes = optional(number, 60)
    id_token_minutes     = optional(number, 60)
    refresh_token_days   = optional(number, 30)
  }))
  nullable    = false
  description = "client 名稱（1–128 字元，限英數字、`_`、`-`）對應 public app client（沒有 client secret，只用 authorization code flow 加 PKCE）。欄位：`callback_urls`（至少一個）、`logout_urls`，都必須是 `https://`，只有 `http://localhost` 例外；`scopes` 是 `openid`、`email`、`profile` 或 `<resource server>/<scope>`；`access_token_minutes`、`id_token_minutes` 5–1440（預設 60）；`refresh_token_days` 1–3650（預設 30）。"

  validation {
    condition     = alltrue([for k in keys(var.clients) : can(regex("^[A-Za-z0-9_-]{1,128}$", k))])
    error_message = "clients keys must be 1-128 chars of letters, digits, '_' or '-'."
  }
  validation {
    condition = alltrue(flatten([for c in values(var.clients) : [
      for u in concat(c.callback_urls, c.logout_urls) : can(regex("^https://[^\\s/#]+(/[^\\s#]*)?$", u)) || can(regex("^http://localhost(:[0-9]{1,5})?(/[^\\s#]*)?$", u))
    ]]))
    error_message = "callback_urls and logout_urls must be https:// URLs without a fragment; only http://localhost may use http."
  }
  validation {
    condition     = alltrue([for c in values(var.clients) : length(c.callback_urls) > 0])
    error_message = "Each client needs at least one callback_url for the authorization code flow."
  }
  validation {
    condition = alltrue(flatten([for c in values(var.clients) : [
      for s in c.scopes : contains(concat(["openid", "email", "profile"], flatten([for id, r in var.resource_servers : [for n in keys(r.scopes) : "${id}/${n}"]])), s)
    ]]))
    error_message = "Client scopes must be openid, email, profile or <resource server identifier>/<scope> of a scope in resource_servers."
  }
  validation {
    condition     = alltrue([for c in values(var.clients) : length(c.scopes) > 0])
    error_message = "Each client needs at least one scope."
  }
  validation {
    condition     = alltrue([for c in values(var.clients) : c.access_token_minutes >= 5 && c.access_token_minutes <= 1440 && c.access_token_minutes == floor(c.access_token_minutes)])
    error_message = "access_token_minutes must be a whole number between 5 and 1440 (Cognito allows 5 minutes to 1 day)."
  }
  validation {
    condition     = alltrue([for c in values(var.clients) : c.id_token_minutes >= 5 && c.id_token_minutes <= 1440 && c.id_token_minutes == floor(c.id_token_minutes)])
    error_message = "id_token_minutes must be a whole number between 5 and 1440 (Cognito allows 5 minutes to 1 day)."
  }
  validation {
    condition     = alltrue([for c in values(var.clients) : c.refresh_token_days >= 1 && c.refresh_token_days <= 3650 && c.refresh_token_days == floor(c.refresh_token_days)])
    error_message = "refresh_token_days must be a whole number between 1 and 3650 (Cognito allows up to 10 years)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "user pool 的 tag；`Name` 由 module 加上。"
}
