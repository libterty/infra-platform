variable "name" {
  type        = string
  description = "Web ACL name. Also the CloudWatch metric name and the suffix of the log group aws-waf-logs-<name>."
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
  description = "Optional kill switch that matches every request. action is count (observe only) or block. With block, response_json is returned as the body of a 503 response. Set to null to turn the kill switch off."
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
  description = "Optional rate limit: requests per source IP in 5 minutes, above which requests are blocked. allowlist_cidrs (IPv4) are exempt from the rate limit only; they stay subject to every other rule."
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
  description = "Managed rule groups in evaluation order. count_overrides lists rules inside the group that only count instead of block. The group itself always keeps its own actions."
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
  description = "Path prefixes exempt from the 8 KB body size limit. Needs AWSManagedRulesCommonRuleSet with SizeRestrictions_BODY in count_overrides; the module then adds its own rule that blocks oversized bodies on every other path."
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
  description = "Optional logging to the CloudWatch log group aws-waf-logs-<name>. redacted_headers are added to authorization and cookie, which are always redacted; names are lowercased. Add the origin verify header here."
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
  description = "Tags for the web ACL, the IP set and the log group. Name is added by the module."
}
