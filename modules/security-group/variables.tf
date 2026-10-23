variable "vpc_id" {
  type        = string
  description = "這次呼叫的所有 SG 所在的 VPC。"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "security_groups" {
  type = map(object({
    name        = string
    description = string
  }))
  description = "key 對應一個 SG，規則用這個 key 指稱 SG。至少一個，key 為 snake_case。欄位：`name`、`description`。"
  validation {
    condition     = length(var.security_groups) > 0 && alltrue([for k in keys(var.security_groups) : can(regex("^[a-z][a-z0-9_]*$", k))])
    error_message = "Give at least one security group; keys must be snake_case."
  }
}

variable "rules" {
  type = map(object({
    security_group = string
    type           = string
    description    = string
    ip_protocol    = optional(string, "tcp")
    from_port      = optional(number)
    to_port        = optional(number)
    peer_group     = optional(string)
    peer_group_id  = optional(string)
    cidr_ipv4      = optional(string)
    prefix_list_id = optional(string)
    allow_internet = optional(bool, false)
  }))
  default     = {}
  description = "規則 key 對應一條規則。key 是穩定的 `for_each` key，照規則允許的內容命名。`security_group`、`type`、`description` 必填；`peer_group`、`peer_group_id`、`cidr_ipv4`、`prefix_list_id` 每條規則剛好給一個。欄位見〈規則怎麼寫〉。"

  validation {
    condition     = alltrue([for r in values(var.rules) : contains(keys(var.security_groups), r.security_group)])
    error_message = "Every rule security_group must be a key in security_groups."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : r.peer_group == null ? true : contains(keys(var.security_groups), r.peer_group)])
    error_message = "Every rule peer_group must be a key in security_groups."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : length([for p in [r.peer_group, r.peer_group_id, r.cidr_ipv4, r.prefix_list_id] : p if p != null]) == 1])
    error_message = "Each rule must set exactly one of peer_group, peer_group_id, cidr_ipv4, prefix_list_id."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : contains(["ingress", "egress"], r.type)])
    error_message = "Rule type must be ingress or egress."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : contains(["tcp", "udp", "-1"], r.ip_protocol)])
    error_message = "ip_protocol must be tcp, udp or -1."
  }

  validation {
    condition = alltrue([for r in values(var.rules) :
      r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : (
        r.from_port != null ? (
          r.from_port >= 0 && r.from_port <= 65535 && (r.to_port == null ? true : (r.to_port >= r.from_port && r.to_port <= 65535))
        ) : false
      )
    ])
    error_message = "tcp and udp rules need from_port in 0..65535 and an optional to_port between from_port and 65535; ip_protocol -1 must leave both ports null."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : r.cidr_ipv4 == null ? true : (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", r.cidr_ipv4)) && can(cidrnetmask(r.cidr_ipv4)))])
    error_message = "cidr_ipv4 must be a valid IPv4 CIDR such as 10.0.0.0/16."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : !(r.type == "ingress" && r.cidr_ipv4 == "0.0.0.0/0") || r.allow_internet])
    error_message = "An ingress rule open to 0.0.0.0/0 must set allow_internet = true."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "SG 與規則的 tag。SG 另加 `Name`，值是 SG 名稱；規則的 `Name` 是規則 key。"
}
