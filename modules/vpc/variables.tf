variable "name" {
  description = "VPC name; also the Name tag prefix of every resource."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cidr" {
  description = "VPC IPv4 network address, /16 to /24."
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
  description = "2 to 4 AZs. The order sets the order of output lists and the AZ of a single NAT."
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 to 4 distinct availability zones."
  }
}

variable "subnets" {
  description = "Tier name => layout. Give either newbits + netnum_base (auto split) or cidrs (az => cidr), never both. Optional tags are applied to that tier's subnets only."
  type = map(object({
    type        = string # public | private | isolated
    newbits     = optional(number)
    netnum_base = optional(number)
    cidrs       = optional(map(string))     # keys must cover every AZ
    tags        = optional(map(string), {}) # extra tags for this tier's subnets only
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
    condition     = alltrue([for v in values(var.subnets) : !contains(keys(v.tags), "Name")])
    error_message = "Tier tags must not contain the Name key; the module always sets Name on subnets."
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
  description = "none creates no NAT; single puts one in the first AZ; per_az puts one in each AZ."
  type        = string
  default     = "single"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single or per_az."
  }
}

variable "gateway_endpoints" {
  description = "Gateway endpoints, associated with every private and isolated tier route table."
  type        = set(string)
  default     = ["s3"]
  validation {
    condition     = alltrue([for e in var.gateway_endpoints : contains(["s3", "dynamodb"], e)])
    error_message = "gateway_endpoints accepts only s3 and dynamodb."
  }
}

variable "flow_log" {
  description = "Flow log to S3; null creates none."
  type = object({
    destination_arn = string                  # S3 bucket ARN, optionally with /prefix
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
  description = "Extra tags; the module adds Name."
  type        = map(string)
  default     = {}
}
