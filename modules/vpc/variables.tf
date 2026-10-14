variable "name" {
  description = "VPC 名稱，同時是各資源 Name tag 的前綴。"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cidr" {
  description = "VPC 的 IPv4 網路位址，/16 到 /24。"
  type        = string
  validation {
    condition = (
      can(cidrnetmask(var.cidr)) &&
      cidrsubnet(var.cidr, 0, 0) == var.cidr &&
      tonumber(split("/", var.cidr)[1]) >= 16 &&
      tonumber(split("/", var.cidr)[1]) <= 24
    )
    error_message = "cidr must be an IPv4 network address from /16 to /24 (e.g. 10.20.0.0/20)."
  }
}

variable "azs" {
  description = "使用的 AZ，2 到 4 個；順序決定各輸出 list 的順序與 single NAT 的位置。"
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 to 4 distinct availability zones."
  }
}

variable "subnets" {
  description = "Tier name => layout. Give either newbits + netnum_base (auto split) or cidrs (az => cidr), never both."
  type = map(object({
    type        = string # public | private | isolated
    newbits     = optional(number)
    netnum_base = optional(number)
    cidrs       = optional(map(string)) # key 必須涵蓋每一個 AZ
  }))
  validation {
    condition     = alltrue([for k, v in var.subnets : can(regex("^[a-z][a-z0-9_]*$", k)) && contains(["public", "private", "isolated"], v.type)])
    error_message = "Tier names must be snake_case and type must be public, private or isolated."
  }
  validation {
    condition = alltrue([for v in values(var.subnets) :
      v.cidrs != null ? (v.newbits == null && v.netnum_base == null) : (v.newbits != null && v.netnum_base != null)
    ])
    error_message = "Each tier needs exactly one of: newbits + netnum_base, or cidrs."
  }
  validation {
    condition     = length([for v in values(var.subnets) : v if v.type == "public"]) <= 1
    error_message = "At most one public tier."
  }
  validation {
    condition = alltrue([for v in values(var.subnets) :
      v.cidrs == null ? true : alltrue([for c in values(v.cidrs) : can(cidrnetmask(c))])
    ])
    error_message = "Every entry in cidrs must be a valid IPv4 CIDR."
  }
}

variable "nat_mode" {
  description = "none 不建 NAT；single 一顆放在第一個 AZ；per_az 每個 AZ 一顆。"
  type        = string
  default     = "single"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single or per_az."
  }
}

variable "gateway_endpoints" {
  description = "Gateway endpoint，關聯所有 private 與 isolated tier 的路由表。"
  type        = set(string)
  default     = ["s3"]
  validation {
    condition     = alltrue([for e in var.gateway_endpoints : contains(["s3", "dynamodb"], e)])
    error_message = "gateway_endpoints accepts only s3 and dynamodb."
  }
}

variable "interface_endpoints" {
  description = "Interface endpoint 的服務清單與放置的 tier；null 表示不建。"
  type = object({
    services    = set(string) # 例：["ecr.api", "ecr.dkr", "logs", "secretsmanager", "kms"]
    subnet_tier = string
  })
  default = null
  validation {
    condition     = var.interface_endpoints == null ? true : alltrue([for s in var.interface_endpoints.services : can(regex("^[a-z0-9][a-z0-9.-]*$", s)) && !startswith(s, "com.amazonaws.")])
    error_message = "Service names are the part after com.amazonaws.<region>., e.g. ecr.api."
  }
}

variable "flow_log" {
  description = "Flow log 送 S3；null 表示不建。"
  type = object({
    destination_arn = string                  # S3 bucket ARN（可帶 /prefix）
    traffic_type    = optional(string, "ALL") # ACCEPT | REJECT | ALL
  })
  default = null
  validation {
    condition = var.flow_log == null ? true : (
      can(regex("^arn:aws[a-z-]*:s3:::", var.flow_log.destination_arn)) &&
      contains(["ACCEPT", "REJECT", "ALL"], var.flow_log.traffic_type)
    )
    error_message = "flow_log supports S3 destinations only; traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "tags" {
  description = "額外的 tag；Name 由 module 加上。"
  type        = map(string)
  default     = {}
}
