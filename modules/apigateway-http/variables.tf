variable "name" {
  type        = string
  description = "HTTP API 的名稱，1–128 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,128}$", var.name))
    error_message = "name must be 1-128 chars of letters, digits, '.', '_' or '-'."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "HTTP API 的說明（選填）。"
}

variable "cors" {
  type = object({
    allow_origins     = list(string)
    allow_methods     = optional(list(string), ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    allow_headers     = optional(list(string), ["authorization", "content-type"])
    allow_credentials = optional(bool, false)
    max_age           = optional(number, 0)
  })
  default     = null
  description = "CORS 設定（選填，`null` 表示不設定）。欄位：`allow_origins`（必填）、`allow_methods`、`allow_headers`、`allow_credentials`（預設 `false`）、`max_age`（秒，0–86400）。`allow_credentials = true` 時 `allow_origins` 不可有 `*`。API 跟前端同源時不需要設定。"

  validation {
    condition     = var.cors == null || length(var.cors.allow_origins) > 0
    error_message = "cors.allow_origins must list at least one origin."
  }
  validation {
    condition     = var.cors == null || !var.cors.allow_credentials || !contains(var.cors.allow_origins, "*")
    error_message = "cors.allow_origins must not contain * when allow_credentials is true; list the exact origins."
  }
  validation {
    condition     = var.cors == null || (var.cors.max_age >= 0 && var.cors.max_age <= 86400 && var.cors.max_age == floor(var.cors.max_age))
    error_message = "cors.max_age must be a whole number of seconds between 0 and 86400."
  }
}

variable "jwt_authorizers" {
  type = map(object({
    issuer   = string
    audience = list(string)
  }))
  default     = {}
  nullable    = false
  description = "key（1–128 字元，限英數字、`_`、`-`）對應 JWT authorizer。欄位：`issuer`（`https://` 開頭，例如 `cognito-user-pool` 的 `issuer_url`）、`audience`（允許的 client ID，至少一個）。token 從 `Authorization` header 取得。"

  validation {
    condition     = alltrue([for k in keys(var.jwt_authorizers) : can(regex("^[A-Za-z0-9_-]{1,128}$", k))])
    error_message = "jwt_authorizers keys must be 1-128 chars of letters, digits, '_' or '-'."
  }
  validation {
    condition     = alltrue([for a in values(var.jwt_authorizers) : can(regex("^https://[^\\s/]+(/\\S*)?$", a.issuer))])
    error_message = "jwt_authorizers issuer must be an https:// URL."
  }
  validation {
    condition     = alltrue([for a in values(var.jwt_authorizers) : length(a.audience) > 0])
    error_message = "jwt_authorizers audience must list at least one client id."
  }
}

variable "integrations" {
  type = map(object({
    lambda_arn = string
    timeout_ms = optional(number, 30000)
  }))
  nullable    = false
  description = "key（1–128 字元，限英數字、`_`、`-`）對應 Lambda proxy integration，payload 固定 `2.0`。欄位：`lambda_arn`（function ARN，可帶 alias 或版本）、`timeout_ms`（50–30000，預設 30000）。呼叫權限由 `lambda-function` 的 `permissions` 給，`source_arn` 用這個 module 的 `execution_arn`。"

  validation {
    condition     = alltrue([for k in keys(var.integrations) : can(regex("^[A-Za-z0-9_-]{1,128}$", k))])
    error_message = "integrations keys must be 1-128 chars of letters, digits, '_' or '-'."
  }
  validation {
    condition     = alltrue([for i in values(var.integrations) : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}(:[A-Za-z0-9_$-]+)?$", i.lambda_arn))])
    error_message = "integrations lambda_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }
  validation {
    condition     = alltrue([for i in values(var.integrations) : i.timeout_ms >= 50 && i.timeout_ms <= 30000 && i.timeout_ms == floor(i.timeout_ms)])
    error_message = "integrations timeout_ms must be a whole number between 50 and 30000."
  }
}

variable "routes" {
  type = map(object({
    integration = string
    authorizer  = optional(string)
    scopes      = optional(list(string), [])
    public      = optional(bool, false)
  }))
  nullable    = false
  description = "route key（例如 `\"GET /items\"`、`\"ANY /{proxy+}\"`、`\"$default\"`）對應 route，至少一條。欄位：`integration`（`integrations` 的 key）、`authorizer`（`jwt_authorizers` 的 key）、`scopes`（JWT 必須含有的 scope，只能配 `authorizer`）、`public`（預設 `false`）。每條 route 必須剛好二選一：給 `authorizer`，或明寫 `public = true`。"

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must define at least one route."
  }
  validation {
    condition     = alltrue([for k in keys(var.routes) : can(regex("^(\\$default|(ANY|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /\\S*)$", k))])
    error_message = "routes keys must be \"$default\" or \"<METHOD> /<path>\" with METHOD one of ANY, GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : (r.authorizer != null) != r.public])
    error_message = "Each route needs exactly one of authorizer or public = true; routes are never public by default."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : r.public == false || length(r.scopes) == 0])
    error_message = "scopes only apply to routes with an authorizer; remove them from public routes."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : contains(keys(var.integrations), r.integration)])
    error_message = "Each route integration must be a key of integrations."
  }
  validation {
    condition     = alltrue([for r in values(var.routes) : r.authorizer == null || contains(keys(var.jwt_authorizers), coalesce(r.authorizer, "-"))])
    error_message = "Each route authorizer must be a key of jwt_authorizers."
  }
}

variable "throttling" {
  type = object({
    rate_limit  = number
    burst_limit = number
  })
  description = "`$default` stage 的預設 throttling，必填。`rate_limit` 是每秒請求數（大於 0），`burst_limit` 是正整數。被繞過 CDN 直接打時，這是成本的上限之一。"

  validation {
    condition     = var.throttling != null
    error_message = "throttling is required."
  }
  validation {
    condition     = var.throttling == null || try(var.throttling.rate_limit > 0, false)
    error_message = "throttling.rate_limit must be greater than 0."
  }
  validation {
    condition     = var.throttling == null || try(var.throttling.burst_limit > 0 && var.throttling.burst_limit == floor(var.throttling.burst_limit), false)
    error_message = "throttling.burst_limit must be a positive whole number."
  }
}

variable "access_log_group_arn" {
  type        = string
  description = "access log 寫入的 CloudWatch Logs log group ARN，必填，結尾不帶 `:*`（`log-group` module 的 `log_group_arn`）。log 格式由 module 固定為一組 JSON 欄位。"

  validation {
    condition     = var.access_log_group_arn != null && can(regex("^arn:aws[a-z-]*:logs:[a-z0-9-]+:[0-9]{12}:log-group:[A-Za-z0-9_./#-]+$", var.access_log_group_arn))
    error_message = "access_log_group_arn must be a CloudWatch Logs log group ARN without the trailing :*."
  }
}

variable "custom_domain" {
  type = object({
    domain_name     = string
    certificate_arn = string
  })
  default     = null
  description = "custom domain（選填）。`domain_name` 是完整網域名稱，`certificate_arn` 是同一個 region 的 ACM 憑證（regional）。給了就建 regional domain（TLS 1.2）與 `$default` stage 的 API mapping，alias record 用 `domain_target`。"

  validation {
    condition     = var.custom_domain == null || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.custom_domain.domain_name))
    error_message = "custom_domain.domain_name must be a lower-case fully qualified domain name without a trailing dot."
  }
  validation {
    condition     = var.custom_domain == null || can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", var.custom_domain.certificate_arn))
    error_message = "custom_domain.certificate_arn must be an ACM certificate ARN."
  }
}

variable "disable_execute_api_endpoint" {
  type        = bool
  default     = null
  description = "是否關掉預設的 execute-api 網址。預設（`null`）在有 `custom_domain` 時為 `true`，沒有時為 `false`。CloudFront 用 execute-api 網址當 origin 時要明寫 `false`。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "API、stage 與 custom domain 的 tag；`Name` 由 module 加上。"
}
