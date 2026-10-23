variable "name" {
  type        = string
  description = "Web ACL 名稱，也是 CloudWatch metric 名稱與 log group `aws-waf-logs-<name>` 的後綴。1–128 字元，限英數字、`_`、`-`。"
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,128}$", var.name))
    error_message = "name must be 1-128 chars of letters, digits, _ or -."
  }
}

variable "kill_switch" {
  type = object({
    action        = string
    response_json = optional(string)
  })
  default     = null
  description = "比對所有請求的緊急開關，`null` 時關閉。欄位：`action`（`count` 只觀察，`block` 擋下）、`response_json`（只有 `block` 能給，是 503 回應的 body，必須是合法 JSON，最多 10240 字元）。"
  validation {
    condition = var.kill_switch == null ? true : (
      contains(["count", "block"], var.kill_switch.action) &&
      (var.kill_switch.response_json == null ? true : (
        var.kill_switch.action == "block" &&
        can(jsondecode(var.kill_switch.response_json)) &&
        length(var.kill_switch.response_json) <= 10240
      ))
    )
    error_message = "kill_switch.action must be count or block; response_json is only for block, must be valid JSON and at most 10240 chars."
  }
}

variable "rate_limit" {
  type = object({
    limit           = number
    allowlist_cidrs = optional(list(string), [])
  })
  default     = null
  description = "流量限制，`null` 時不限。欄位：`limit`（每個來源 IP 每 5 分鐘的請求數上限，超過就擋，10–2000000000）、`allowlist_cidrs`（IPv4 CIDR，前綴長度 1–32，預設 `[]`；只免除流量限制，其他規則照樣套用）。"
  validation {
    condition = var.rate_limit == null ? true : (
      var.rate_limit.limit >= 10 && var.rate_limit.limit <= 2000000000 &&
      alltrue([
        for c in var.rate_limit.allowlist_cidrs :
        can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([1-9]|[12][0-9]|3[0-2])$", c)) && can(cidrhost(c, 0))
      ])
    )
    error_message = "rate_limit.limit must be between 10 and 2000000000; allowlist_cidrs must be IPv4 CIDRs with a prefix length of 1-32 (0.0.0.0/0 and IPv6 are not accepted)."
  }
}

variable "managed_rule_groups" {
  type = list(object({
    name            = string
    vendor          = optional(string, "AWS")
    count_overrides = optional(list(string), [])
  }))
  default     = []
  description = "依評估順序排列的 managed rule group，`vendor` 加 `name` 不可重複。欄位：`name`、`vendor`（預設 `AWS`），兩者皆 1–100 字元，限英數字、`_`、`-`；`count_overrides`（預設 `[]`，群組內改成只 count 不擋的規則名稱，不可重複）。群組本身一律維持自己的 action。"
  validation {
    condition = alltrue([
      for g in var.managed_rule_groups :
      can(regex("^[A-Za-z0-9_-]{1,100}$", g.name)) &&
      can(regex("^[A-Za-z0-9_-]{1,100}$", g.vendor)) &&
      alltrue([for o in g.count_overrides : can(regex("^[A-Za-z0-9_-]{1,128}$", o))]) &&
      length(distinct(g.count_overrides)) == length(g.count_overrides)
    ])
    error_message = "Each managed rule group needs a name and vendor of 1-100 chars (letters, digits, _ or -); count_overrides must be unique rule names."
  }
  validation {
    condition     = length(distinct([for g in var.managed_rule_groups : "${g.vendor}-${g.name}"])) == length(var.managed_rule_groups)
    error_message = "Each vendor and name pair may appear only once in managed_rule_groups."
  }
}

variable "body_size_exempt_path_prefixes" {
  type        = list(string)
  default     = []
  description = "不受 8 KB body 大小限制的 path prefix，以 `/` 開頭且後面至少一個字元，不可重複。`managed_rule_groups` 必須有 `AWSManagedRulesCommonRuleSet`（vendor `AWS`），且 `SizeRestrictions_BODY` 在它的 `count_overrides` 裡；module 會另外加一條規則，擋下其他 path 的過大 body。"
  validation {
    condition = length(var.body_size_exempt_path_prefixes) == 0 ? true : anytrue([
      for g in var.managed_rule_groups :
      g.vendor == "AWS" && g.name == "AWSManagedRulesCommonRuleSet" && contains(g.count_overrides, "SizeRestrictions_BODY")
    ])
    error_message = "body_size_exempt_path_prefixes requires AWSManagedRulesCommonRuleSet (vendor AWS) in managed_rule_groups with SizeRestrictions_BODY in count_overrides, otherwise the managed rule still blocks the exempt paths."
  }
  validation {
    condition = alltrue([
      for p in var.body_size_exempt_path_prefixes : can(regex("^/[A-Za-z0-9._~/-]+$", p))
    ]) && length(distinct(var.body_size_exempt_path_prefixes)) == length(var.body_size_exempt_path_prefixes)
    error_message = "Each prefix must be unique, start with / and have at least one more character (letters, digits, . _ ~ / -); / alone would exempt every path."
  }
}

variable "logging" {
  type = object({
    retention_days   = optional(number, 14)
    kms_key_arn      = optional(string)
    redacted_headers = optional(list(string), ["authorization", "cookie"])
  })
  default     = null
  description = "寫到 CloudWatch log group `aws-waf-logs-<name>` 的 log，`null` 時不開。欄位：`retention_days`（預設 14，限 CloudWatch Logs 接受的值，不可為 0）、`kms_key_arn`（預設 `null`）、`redacted_headers`（預設 `[\"authorization\", \"cookie\"]`，在這兩個一律遮蔽的 header 之外追加，名稱轉小寫，1–64 字元）。origin verify header 要加在這裡。"
  validation {
    condition = var.logging == null ? true : (
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.logging.retention_days) &&
      alltrue([for h in var.logging.redacted_headers : can(regex("^[A-Za-z0-9_-]{1,64}$", h))])
    )
    error_message = "logging.retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ... 3653, not 0); redacted_headers must be 1-64 chars of letters, digits, _ or -."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "web ACL、IP set 與 log group 的 tag；`Name` 由 module 加上。"
}
