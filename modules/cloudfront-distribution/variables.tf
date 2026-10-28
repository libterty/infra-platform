variable "name" {
  type        = string
  description = "distribution 的識別名稱：`Name` tag、`comment` 的預設值，也是 OAC 名稱 `<name>-<origin key>` 的前綴。1–64 字元，限英數字、`_`、`-`。"
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars of letters, digits, _ or -."
  }
}

variable "comment" {
  type        = string
  default     = null
  description = "distribution 的說明，最多 128 字元，`null` 時用 `name`。"
  validation {
    condition     = var.comment == null ? true : length(var.comment) <= 128
    error_message = "comment must be at most 128 chars."
  }
}

variable "aliases" {
  type        = list(string)
  default     = []
  description = "distribution 的自訂網域（CNAME），例如 `app.dev.example.com`，不可重複。非空時必須給 `certificate_arn`，憑證要涵蓋每個名稱。"
  validation {
    condition = alltrue([
      for a in var.aliases : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", a))
    ]) && length(distinct(var.aliases)) == length(var.aliases)
    error_message = "aliases must be unique lower-case domain names (a leading *. is allowed)."
  }
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = "viewer 憑證，必須是 us-east-1 的 ACM 憑證 ARN（CloudFront 只讀 us-east-1 的憑證）。`null` 時用 CloudFront 預設憑證，此時 `aliases` 必須是空的。"
  validation {
    condition     = var.certificate_arn == null ? true : can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[A-Za-z0-9-]+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN in us-east-1 (arn:aws:acm:us-east-1:<account>:certificate/<id>)."
  }
  validation {
    condition     = length(var.aliases) == 0 || var.certificate_arn != null
    error_message = "aliases need a certificate_arn that covers them."
  }
}

variable "web_acl_arn" {
  type        = string
  default     = null
  description = "掛在 distribution 上的 WAF web ACL，必須是 CLOUDFRONT scope 的 ARN（`arn:aws:wafv2:us-east-1:<帳號>:global/webacl/...`）。`null` 時不掛。"
  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:aws:wafv2:us-east-1:[0-9]{12}:global/webacl/[A-Za-z0-9_-]+/[A-Za-z0-9-]+$", var.web_acl_arn))
    error_message = "web_acl_arn must be a CLOUDFRONT scope web ACL ARN (arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>)."
  }
}

variable "price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "edge location 範圍：`PriceClass_100`、`PriceClass_200`（預設，含亞洲）或 `PriceClass_All`。"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "origins" {
  type = map(object({
    type        = string
    domain_name = string
    origin_path = optional(string)
    custom = optional(object({
      https_port        = optional(number, 443)
      read_timeout      = optional(number, 30)
      keepalive_timeout = optional(number, 5)
    }))
  }))
  description = "key 是 origin ID（behavior 用它指定 origin），至少一個。欄位：`type`（`s3` 時 module 建一個 OAC；`custom` 時固定 `https-only` 與 TLSv1.2）、`domain_name`（`s3` 要給 bucket 的 regional domain name，不能是 website endpoint；`custom` 只給主機名稱，不含 `https://` 與路徑）、`origin_path`（以 `/` 開頭、不以 `/` 結尾）、`custom`（只有 `custom` 能給：`https_port` 預設 443、`read_timeout` 預設 30 秒（1–180）、`keepalive_timeout` 預設 5 秒（1–180））。"
  validation {
    condition = length(var.origins) > 0 && alltrue([
      for k, o in var.origins : can(regex("^[A-Za-z0-9_-]{1,63}$", k)) && contains(["s3", "custom"], o.type)
    ])
    error_message = "origins needs at least one entry; keys must be 1-63 chars of letters, digits, _ or -, and type must be s3 or custom."
  }
  validation {
    condition = alltrue([
      for o in values(var.origins) : o.type != "s3" || (
        o.custom == null && can(regex("^[a-z0-9][a-z0-9.-]*\\.s3(\\.[a-z0-9-]+)?\\.amazonaws\\.com$", o.domain_name))
      )
    ])
    error_message = "An s3 origin needs a bucket regional domain name (<bucket>.s3.<region>.amazonaws.com, not a website endpoint) and no custom block."
  }
  validation {
    condition = alltrue([
      for o in values(var.origins) : o.type != "custom" || can(regex("^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$", o.domain_name))
    ])
    error_message = "A custom origin domain_name must be a host name only, without https:// or a path."
  }
  validation {
    condition = alltrue([
      for o in values(var.origins) : o.custom == null ? true : (
        o.custom.https_port >= 1 && o.custom.https_port <= 65535 &&
        o.custom.read_timeout >= 1 && o.custom.read_timeout <= 180 &&
        o.custom.keepalive_timeout >= 1 && o.custom.keepalive_timeout <= 180
      )
    ])
    error_message = "custom.https_port must be 1-65535; read_timeout and keepalive_timeout must be 1-180 seconds."
  }
  validation {
    condition = alltrue([
      for o in values(var.origins) : o.origin_path == null ? true : can(regex("^/[A-Za-z0-9._~/-]*[A-Za-z0-9._~-]$", o.origin_path))
    ])
    error_message = "origin_path must start with / and must not end with /."
  }
  validation {
    condition     = alltrue([for k, o in var.origins : o.type != "s3" || length("${var.name}-${k}") <= 64])
    error_message = "The OAC name <name>-<origin key> of every s3 origin must be at most 64 chars."
  }
}

variable "origin_verify" {
  type = object({
    origin      = string
    header_name = string
  })
  default     = null
  description = "在一個 `custom` origin 的回源請求加上 origin verify header，`null` 時不加。欄位：`origin`（`origins` 裡 `type = \"custom\"` 的 key）、`header_name`（例如 `X-Origin-Verify`）。值由 `origin_verify_header_value` 給，兩者要一起給或一起不給。"
  validation {
    condition = var.origin_verify == null ? true : (
      try(var.origins[var.origin_verify.origin].type, "") == "custom" &&
      can(regex("^[A-Za-z0-9-]{1,64}$", var.origin_verify.header_name))
    )
    error_message = "origin_verify.origin must be a custom origin in origins, and header_name must be 1-64 chars of letters, digits or -."
  }
  validation {
    condition     = (var.origin_verify == null) == nonsensitive(var.origin_verify_header_value == null)
    error_message = "origin_verify and origin_verify_header_value must be given together or not at all."
  }
}

variable "origin_verify_header_value" {
  type        = string
  default     = null
  sensitive   = true
  description = "origin verify header 的值（sensitive）。從 `TF_VAR_origin_verify_header_value` 環境變數傳入，不要寫進 tfvars；plan 會遮住，state 仍是明文。"
}

variable "default_behavior" {
  type = object({
    origin                  = string
    allowed_methods         = optional(string, "read")
    cache_policy            = optional(string, "Managed-CachingOptimized")
    origin_request_policy   = optional(string)
    response_headers_policy = optional(string, "Managed-SecurityHeadersPolicy")
  })
  description = "預設 behavior。欄位：`origin`（`origins` 的 key）、`allowed_methods`（`read` 是 GET、HEAD，`read_options` 再加 OPTIONS，`all` 是全部 7 種；一律只快取 GET、HEAD）、`cache_policy`（預設 `Managed-CachingOptimized`）、`origin_request_policy`（預設 `null`）、`response_headers_policy`（預設 `Managed-SecurityHeadersPolicy`）。三個 policy 都收 managed policy 名稱，module 查出 ID。"
  validation {
    condition     = contains(keys(var.origins), var.default_behavior.origin)
    error_message = "default_behavior.origin must be a key of origins."
  }
  validation {
    condition     = contains(["read", "read_options", "all"], var.default_behavior.allowed_methods)
    error_message = "default_behavior.allowed_methods must be read, read_options or all."
  }
  validation {
    condition = alltrue([
      for p in [var.default_behavior.cache_policy, var.default_behavior.origin_request_policy, var.default_behavior.response_headers_policy] :
      p == null ? true : can(regex("^[A-Za-z0-9_-]{1,128}$", p))
    ])
    error_message = "Policy names must be 1-128 chars of letters, digits, _ or -."
  }
}

variable "ordered_behaviors" {
  type = list(object({
    path_pattern            = string
    origin                  = string
    allowed_methods         = optional(string, "read")
    cache_policy            = optional(string, "Managed-CachingOptimized")
    origin_request_policy   = optional(string)
    response_headers_policy = optional(string, "Managed-SecurityHeadersPolicy")
  }))
  default     = []
  description = "依比對順序排列的其他 behavior，`path_pattern` 不可重複（例如 `/api/*`）。其他欄位與預設值同 `default_behavior`。"
  validation {
    condition     = alltrue([for b in var.ordered_behaviors : contains(keys(var.origins), b.origin)])
    error_message = "Every ordered behavior origin must be a key of origins."
  }
  validation {
    condition     = alltrue([for b in var.ordered_behaviors : contains(["read", "read_options", "all"], b.allowed_methods)])
    error_message = "Every ordered behavior allowed_methods must be read, read_options or all."
  }
  validation {
    condition = alltrue([
      for b in var.ordered_behaviors : length(b.path_pattern) >= 1 && length(b.path_pattern) <= 255 && alltrue([
        for p in [b.cache_policy, b.origin_request_policy, b.response_headers_policy] :
        p == null ? true : can(regex("^[A-Za-z0-9_-]{1,128}$", p))
      ])
    ])
    error_message = "path_pattern must be 1-255 chars; policy names must be 1-128 chars of letters, digits, _ or -."
  }
  validation {
    condition     = length(distinct([for b in var.ordered_behaviors : b.path_pattern])) == length(var.ordered_behaviors)
    error_message = "Each path_pattern may appear only once in ordered_behaviors."
  }
}

variable "spa_fallback" {
  type        = bool
  default     = false
  description = "`true` 時建一個 CloudFront Function `<name>-spa-fallback`，掛在預設 behavior 的 viewer-request：最後一段路徑沒有副檔名的請求改成讀 `/index.html`，給 SPA 的前端路由用。`ordered_behaviors`（例如 `/api/*`）不受影響。"
  validation {
    condition     = !var.spa_fallback || length("${var.name}-spa-fallback") <= 64
    error_message = "With spa_fallback the function name <name>-spa-fallback must be at most 64 chars, so name can have at most 51 chars."
  }
}

variable "default_root_object" {
  type        = string
  default     = null
  description = "請求根路徑時回的物件，例如 `index.html`（不含開頭的 `/`）。"
  validation {
    condition     = var.default_root_object == null ? true : can(regex("^[A-Za-z0-9._~-][A-Za-z0-9._~/-]{0,254}$", var.default_root_object))
    error_message = "default_root_object must be an object name without a leading /, at most 255 chars."
  }
}

variable "geo_restriction" {
  type = object({
    type      = string
    locations = list(string)
  })
  default     = null
  description = "地理限制，`null` 時不限。欄位：`type`（`whitelist` 只允許、`blacklist` 擋下）、`locations`（ISO 3166-1 alpha-2 大寫國碼，至少一個）。"
  validation {
    condition = var.geo_restriction == null ? true : (
      contains(["whitelist", "blacklist"], var.geo_restriction.type) &&
      length(var.geo_restriction.locations) > 0 &&
      alltrue([for l in var.geo_restriction.locations : can(regex("^[A-Z]{2}$", l))])
    )
    error_message = "geo_restriction.type must be whitelist or blacklist, and locations must be at least one upper-case two-letter country code."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "distribution 的 tag；`Name` 由 module 加上。"
}
