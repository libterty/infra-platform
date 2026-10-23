variable "name" {
  description = "Runtime 名稱。字母開頭，只能用字母、數字、`_`（AgentCore 不收 `-`），最多 48 字元。"
  type        = string
  validation {
    # 48 chars follows the AWS documentation; not tested against the API.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores (no hyphens), at most 48 chars."
  }
}

variable "description" {
  description = "Runtime 說明，選填。"
  type        = string
  default     = null
}

variable "role_arn" {
  description = "Runtime assume 的 execution role ARN，可以帶 path；role 在 module 外建立。"
  type        = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN; a path is allowed."
  }
}

variable "container_uri" {
  description = "ECR 映像，要有明確 tag（不能是 `latest`，不分大小寫）或 `sha256` digest。tag 由 Terraform 管：在這裡改 tag 再 apply。registry 帳號必須是目前帳號，或在 `allowed_account_ids` 裡。"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+(:[A-Za-z0-9_.-]{1,128}|@sha256:[0-9a-f]{64})$", var.container_uri)) && !endswith(lower(var.container_uri), ":latest")
    error_message = "container_uri must be an ECR image with an explicit tag (not latest) or a sha256 digest."
  }
}

variable "allowed_account_ids" {
  description = "目前帳號以外、`container_uri` 可以使用的 ECR registry 帳號（12 位數字）。空的時候映像必須在目前帳號。"
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for a in var.allowed_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "allowed_account_ids must contain 12-digit AWS account IDs."
  }
}

variable "network" {
  description = "網路設定，預設 VPC 模式。欄位：`mode`（`VPC` 或 `PUBLIC`，預設 `VPC`；`PUBLIC` 要明寫，會繞過 security group 與 VPC endpoint）、`subnet_ids`（預設 `[]`；`VPC` 時至少 2 個且不重複）、`security_group_ids`（預設 `[]`；`VPC` 時 1–5 個且不重複）。`PUBLIC` 時 `subnet_ids`、`security_group_ids` 都必須是空的。"
  type = object({
    mode               = optional(string, "VPC")
    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])
  })
  nullable = false

  validation {
    condition     = contains(["VPC", "PUBLIC"], var.network.mode)
    error_message = "network.mode must be VPC or PUBLIC."
  }

  # Two subnets is this repo's availability convention, not an AWS minimum.
  validation {
    condition     = var.network.mode != "VPC" ? true : length(var.network.subnet_ids) >= 2 && length(distinct(var.network.subnet_ids)) == length(var.network.subnet_ids)
    error_message = "VPC mode needs at least two distinct subnet_ids."
  }

  # The upper limit of 5 follows the AWS documentation; not tested against the API.
  validation {
    condition     = var.network.mode != "VPC" ? true : length(var.network.security_group_ids) >= 1 && length(var.network.security_group_ids) <= 5 && length(distinct(var.network.security_group_ids)) == length(var.network.security_group_ids)
    error_message = "VPC mode needs 1-5 distinct security_group_ids."
  }

  validation {
    condition     = var.network.mode != "PUBLIC" ? true : length(var.network.subnet_ids) == 0 && length(var.network.security_group_ids) == 0
    error_message = "PUBLIC mode does not use subnet_ids or security_group_ids; leave both empty."
  }
}

variable "session_lifecycle" {
  description = "session 生命週期，單位秒。欄位：`idle_session_timeout`（預設 900）、`max_lifetime`（預設 28800），兩者都在 60–1209600，且 `idle_session_timeout` 不大於 `max_lifetime`。兩個值一律成對送出：API 會整組取代設定，少送一個就會默默回到 AWS 預設。idle timeout 拉長不會減少冷啟動，只會佔用更多帳號的 session 配額。"
  type = object({
    idle_session_timeout = optional(number, 900)
    max_lifetime         = optional(number, 28800)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for v in [var.session_lifecycle.idle_session_timeout, var.session_lifecycle.max_lifetime] :
      v >= 60 && v <= 1209600
    ])
    error_message = "idle_session_timeout and max_lifetime must both be between 60 and 1209600 seconds."
  }

  # The ordering rule follows the API documentation; not tested against the API.
  validation {
    condition     = var.session_lifecycle.idle_session_timeout <= var.session_lifecycle.max_lifetime
    error_message = "idle_session_timeout must not exceed max_lifetime."
  }
}

variable "protocol" {
  description = "容器的 server protocol：`HTTP`、`MCP` 或 `A2A`。"
  type        = string
  default     = "HTTP"
  nullable    = false
  validation {
    condition     = contains(["HTTP", "MCP", "A2A"], var.protocol)
    error_message = "protocol must be HTTP, MCP or A2A."
  }
}

variable "environment_variables" {
  description = "一般環境變數；空的時候不送。secret 放 Secrets Manager，這裡只放 ARN。名稱看起來像 secret 的會被擋下，除非名稱以 `_ARN` 結尾且值是 ARN（規則見〈注意〉）。"
  type        = map(string)
  default     = {}
  nullable    = false
  # Environment variables are readable through the control plane and stored in state in plain text.
  validation {
    condition = alltrue([for k, v in var.environment_variables :
      !can(regex("(SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL)", upper(k))) ||
      (endswith(upper(k), "_ARN") && startswith(v, "arn:"))
    ])
    error_message = "environment_variables names must not look like secrets (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL). Secrets belong in Secrets Manager; pass only the secret ARN, in a name ending in _ARN."
  }
}

variable "jwt_authorizer" {
  description = "入站 JWT 驗證；`null` 時維持預設的 IAM（SigV4）入站驗證。欄位：`discovery_url`（必填，`https://` 開頭、以 `/.well-known/openid-configuration` 結尾）、`allowed_audience`、`allowed_clients`（預設 `[]`，兩者至少一個非空，且不能有空字串或只有空白的項目）。"
  type = object({
    discovery_url    = string
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default = null

  validation {
    condition     = var.jwt_authorizer == null ? true : can(regex("^https://.+/\\.well-known/openid-configuration$", var.jwt_authorizer.discovery_url))
    error_message = "jwt_authorizer.discovery_url must start with https:// and end with /.well-known/openid-configuration."
  }

  validation {
    condition     = var.jwt_authorizer == null ? true : length(var.jwt_authorizer.allowed_audience) + length(var.jwt_authorizer.allowed_clients) > 0
    error_message = "jwt_authorizer needs at least one of allowed_audience or allowed_clients."
  }

  validation {
    condition     = var.jwt_authorizer == null ? true : alltrue([for v in setunion(var.jwt_authorizer.allowed_audience, var.jwt_authorizer.allowed_clients) : length(trimspace(v)) > 0])
    error_message = "jwt_authorizer.allowed_audience and allowed_clients must not contain empty or whitespace-only entries."
  }
}

variable "request_header_allowlist" {
  description = "轉給容器的 request header；空的時候不送 header 設定。不收帶呼叫端憑證或簽章的 header（`Cookie`、`Proxy-Authorization`、`Host`、`X-Amz-Security-Token`、`X-Amz-Date`，不分大小寫）；`Authorization` 只在設了 `jwt_authorizer` 時可以轉，那時 AgentCore 已經驗過 token。"
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition = alltrue([for h in var.request_header_allowlist :
      !contains(["cookie", "proxy-authorization", "host", "x-amz-security-token", "x-amz-date"], lower(h)) &&
      (lower(h) != "authorization" || var.jwt_authorizer != null)
    ])
    error_message = "request_header_allowlist must not include Cookie, Proxy-Authorization, Host, X-Amz-Security-Token or X-Amz-Date, and may include Authorization only with jwt_authorizer; otherwise caller credentials reach the container."
  }
}

variable "tags" {
  description = "額外的 tag；`Name` 由 module 加上。"
  type        = map(string)
  default     = {}
}
