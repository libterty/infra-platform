variable "name" {
  type        = string
  description = "ALB 名稱。2–32 字元，限英數字與 `-`，頭尾不可是 `-`，不可以 `internal-` 開頭。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 letters, digits or hyphens, not starting or ending with a hyphen nor starting with internal-."
  }
}

variable "internal" {
  type        = bool
  default     = false
  description = "`true` 時建內部 ALB。"
}

variable "subnet_ids" {
  type        = list(string)
  description = "ALB 所在的 subnet，至少兩個、分屬不同 AZ；對外時用 public tier，`internal = true` 時用 app tier。"
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "ALB 的 security group，至少一個，由 network stack 建立。"
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Give at least one security group (created by the network stack)."
  }
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = "HTTPS listener 用的 ACM 憑證 ARN。`null` 時只開 HTTP:80，這時 network stack 必須收窄 ALB 的 security group。"
  validation {
    condition     = var.certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "additional_certificate_arns" {
  type        = set(string)
  default     = []
  description = "掛在 HTTPS listener 上做 SNI 的額外 ACM 憑證；非空時必須給 `certificate_arn`。"
  validation {
    condition     = length(var.additional_certificate_arns) == 0 || var.certificate_arn != null
    error_message = "additional_certificate_arns needs certificate_arn: without a certificate there is no HTTPS listener."
  }
}

variable "idle_timeout" {
  type        = number
  default     = 60
  description = "閒置逾時秒數，1–4000。"
  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be 1-4000 seconds."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "是否開啟刪除保護；測試或 PoC 要 destroy 前先設成 `false` 並 apply。"
}

variable "web_acl" {
  type = object({
    arn = string
  })
  default     = null
  description = "要關聯的 regional WAFv2 Web ACL，格式 `{ arn }`，`null` 時不關聯；module 不建 Web ACL。Web ACL 在同一個 configuration 建、plan 時還不知道 ARN 時，一定要用這個變數，不要用 `web_acl_arn`。與 `web_acl_arn` 不能同時給。"
  validation {
    condition     = var.web_acl == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl.arn))
    error_message = "web_acl.arn must be a regional WAFv2 Web ACL ARN."
  }
  validation {
    condition     = var.web_acl == null || var.web_acl_arn == null
    error_message = "Set either web_acl or web_acl_arn, not both."
  }
}

variable "web_acl_arn" {
  type        = string
  default     = null
  description = "要關聯的 regional WAFv2 Web ACL ARN，只適合 plan 時已知的值；Web ACL 在同一個 configuration 建時會報 `Invalid count argument`，請改用 `web_acl`。為了既有呼叫端保留，之後會移除。與 `web_acl` 不能同時給。"
  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl_arn))
    error_message = "web_acl_arn must be a regional WAFv2 Web ACL ARN."
  }
}

variable "vpc_id" {
  type        = string
  default     = null
  description = "`target_groups` 非空時必填。target group 所在的 VPC。"
  validation {
    condition     = length(var.target_groups) == 0 || var.vpc_id != null
    error_message = "vpc_id is required when target_groups is non-empty."
  }
}

variable "target_groups" {
  type = map(object({
    port                 = number
    protocol_version     = optional(string, "HTTP1")
    deregistration_delay = optional(number, 300)
    target_type          = optional(string, "ip") # ip or instance
    stickiness = optional(object({                # null disables; lb_cookie
      duration = number                           # seconds, 1-604800
    }))
    health_check = optional(object({
      path                = optional(string, "/health")
      matcher             = optional(string, "200")
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))
  default     = {}
  description = "key 對應一個 HTTP target group，名稱 `<name>-<key>`（1–32 字元）。欄位：`port`（必填；改了會重建，規則還在用時會失敗）、`protocol_version`（預設 `HTTP1`）、`deregistration_delay`（預設 300）、`target_type`（`ip` 或 `instance`，預設 `ip`）、`stickiness`（`{ duration }`，1–604800 秒，`lb_cookie`，預設 `null` 不開）、`health_check`（可只覆寫部分欄位），細節見〈target group 與 listener rule〉。"
  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", "${var.name}-${k}"))])
    error_message = "<name>-<key> must be 1-32 letters, digits or hyphens, not starting or ending with a hyphen."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["ip", "instance"], t.target_type)])
    error_message = "target_type must be ip or instance."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.stickiness == null ? true : t.stickiness.duration >= 1 && t.stickiness.duration <= 604800])
    error_message = "stickiness.duration must be 1-604800 seconds."
  }
}

variable "listener_rules" {
  type = map(object({
    priority     = number
    target_group = optional(string) # key of target_groups; exactly one of target_group and forward
    forward = optional(object({
      targets = map(object({
        target_group     = optional(string) # key of target_groups
        target_group_arn = optional(string) # external target group; exactly one of the two
        weight           = number
      }))
      stickiness_duration = optional(number) # seconds; required when a target_groups entry used here has stickiness
    }))
    path_patterns         = optional(list(string), [])
    host_headers          = optional(list(string), [])
    require_origin_verify = optional(bool, false)
  }))
  default     = {}
  description = "key 對應 HTTPS listener 上的 forward 規則（沒有憑證時掛在 HTTP listener）。欄位：`priority`（不可重複）、`target_group`（`target_groups` 的 key）或 `forward`（加權轉發，1–5 個 target，兩者擇一）、`path_patterns`、`host_headers`（合計至少一個）、`require_origin_verify`（預設 `false`）。欄位見〈target group 與 listener rule〉與〈加權 forward（0.4.0）〉。"
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : (r.target_group != null) != (r.forward != null)])
    error_message = "Every rule needs exactly one of target_group and forward."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      r.target_group == null ? true : contains(keys(var.target_groups), r.target_group)
    ])
    error_message = "Every rule target_group must be a key of target_groups."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : alltrue([
        for t in values(r.forward.targets) : (t.target_group != null) != (t.target_group_arn != null)
      ])
    ])
    error_message = "Every forward target needs exactly one of target_group and target_group_arn."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : alltrue([
        for t in values(r.forward.targets) : t.target_group == null ? true : contains(keys(var.target_groups), t.target_group)
      ])
    ])
    error_message = "Every forward target target_group must be a key of target_groups."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : alltrue([
        for t in values(r.forward.targets) :
        t.target_group_arn == null ? true : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]+/[a-f0-9]+$", t.target_group_arn))
      ])
    ])
    error_message = "target_group_arn must be an ELB target group ARN (arn:aws:elasticloadbalancing:<region>:<account>:targetgroup/<name>/<id>)."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : length(r.forward.targets) >= 1 && length(r.forward.targets) <= 5
    ])
    error_message = "A forward rule needs 1-5 targets (ALB limit)."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : alltrue([
        for t in values(r.forward.targets) : t.weight >= 0 && t.weight <= 999
      ])
    ])
    error_message = "Forward target weight must be 0-999."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : anytrue([
        for t in values(r.forward.targets) : t.weight > 0
      ])
    ])
    error_message = "At least one forward target must have a weight above 0."
  }
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      r.forward == null ? true : r.forward.stickiness_duration == null ? true : r.forward.stickiness_duration >= 1 && r.forward.stickiness_duration <= 604800
    ])
    error_message = "forward.stickiness_duration must be 1-604800 seconds."
  }
  # Group-level stickiness only makes sense with a duration; ask for it when a local target group is sticky.
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) : r.forward == null ? true : (
        r.forward.stickiness_duration != null ||
        !anytrue([for t in values(r.forward.targets) : try(var.target_groups[t.target_group].stickiness != null, false)])
      )
    ])
    error_message = "forward.stickiness_duration is required when a target group used in the rule has stickiness."
  }
  validation {
    condition     = length(distinct([for r in values(var.listener_rules) : r.priority])) == length(var.listener_rules)
    error_message = "Rule priorities must be unique."
  }
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : length(r.path_patterns) + length(r.host_headers) > 0])
    error_message = "Every rule needs at least one path pattern or host header."
  }
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : !r.require_origin_verify || var.origin_verify_header_name != null])
    error_message = "A rule with require_origin_verify = true needs origin_verify_header_name and origin_verify_header_value."
  }
  # ALB allows five condition values per rule; the origin verify header takes one of them.
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      length(r.path_patterns) + length(r.host_headers) + (r.require_origin_verify ? 1 : 0) <= 5
    ])
    error_message = "A rule can have at most 5 condition values in total (path patterns, host headers and the origin verify header)."
  }
}

variable "origin_verify_header_name" {
  type        = string
  default     = null
  description = "CDN 加在回源請求上的 header 名稱，要與 `origin_verify_header_value` 一起給或一起不給。"
  validation {
    condition     = (var.origin_verify_header_name == null) == nonsensitive(var.origin_verify_header_value == null)
    error_message = "origin_verify_header_name and origin_verify_header_value must be given together or not at all."
  }
}

variable "origin_verify_header_value" {
  type        = string
  default     = null
  sensitive   = true
  description = "origin verify header 的值（sensitive）。從 `TF_VAR_origin_verify_header_value` 環境變數傳入，不要寫進 tfvars。"
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "告警 `alarm_actions` 與 `ok_actions` 的 SNS topic ARN，至少一個。"
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "alarm_config" {
  type = object({
    elb_5xx_threshold = optional(number, 1) # sum of HTTPCode_ELB_5XX_Count within one period
    period            = optional(number, 60)
  })
  default     = {}
  description = "ELB 5xx 告警設定。欄位：`elb_5xx_threshold`（一個 period 內 `HTTPCode_ELB_5XX_Count` 的總和門檻，預設 1）、`period`（秒，預設 60）。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "額外的 tag；`Name` 由 module 加上。"
}
