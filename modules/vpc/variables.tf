variable "name" {
  description = "VPC 名稱，也是各資源 `Name` tag 的前綴。2–48 字元，限小寫英數字與 `-`，以字母開頭。"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "cidr" {
  description = "VPC 的 IPv4 網路位址，`/16` 到 `/24`，必須是網路位址本身（例如 `10.20.0.0/20`）。"
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
  description = "2–4 個不重複的 AZ。順序決定輸出 list 的順序，`single` NAT 放在第一個 AZ。"
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 to 4 distinct availability zones."
  }
}

variable "subnets" {
  description = "tier 名稱（限 `snake_case`）對應切法。欄位：`type`（`public`、`private`、`isolated`，最多一個 `public` tier）、`newbits` 加 `netnum_base`（自動切）或 `cidrs`（AZ 對應 CIDR，key 要涵蓋每個 AZ），兩者擇一；`tags`（預設 `{}`，只套在這個 tier 的 subnet，不可含 `Name`）。"
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
  description = "要建幾個 NAT：`none` 不建 NAT；`single` 在第一個 AZ 建一個；`per_az` 每個 AZ 各建一個。"
  type        = string
  default     = "single"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single or per_az."
  }
}

variable "gateway_endpoints" {
  description = "要建的 gateway endpoint，限 `s3`、`dynamodb`；關聯到所有 private 與 isolated tier 的 route table。"
  type        = set(string)
  default     = ["s3"]
  validation {
    condition     = alltrue([for e in var.gateway_endpoints : contains(["s3", "dynamodb"], e)])
    error_message = "gateway_endpoints accepts only s3 and dynamodb."
  }
}

variable "flow_log" {
  description = "送到 S3 的 flow log，`null` 時不建。欄位：`destination_arn`（S3 bucket ARN，可帶 `/prefix`，只支援 S3）、`traffic_type`（`ACCEPT`、`REJECT`、`ALL`，預設 `ALL`）。"
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
  description = "額外的 tag；`Name` 由 module 加上。"
  type        = map(string)
  default     = {}
}
