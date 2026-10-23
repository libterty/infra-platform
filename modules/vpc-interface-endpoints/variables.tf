variable "name" {
  description = "security group 與 endpoint `Name` tag 的前綴。2–48 字元，限小寫英數字與 `-`，以字母開頭。"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  description = "endpoint 與 security group 所在的 VPC，格式 `vpc-0123456789abcdef0`。"
  type        = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "allowed_cidrs" {
  description = "允許連 endpoint 443 port 的 IPv4 CIDR，至少一個，不可含 `0.0.0.0/0`；通常給 `[vpc_cidr]`。"
  type        = list(string)
  validation {
    condition = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && can(cidrnetmask(c)) && c != "0.0.0.0/0"
    ])
    error_message = "allowed_cidrs needs at least one valid IPv4 CIDR and must not contain 0.0.0.0/0."
  }
}

variable "subnet_ids" {
  description = "endpoint 網路介面所在的 subnet，每個 AZ 一個，至少兩個不重複。"
  type        = list(string)
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "services" {
  description = "要建的服務名稱，只寫 `com.amazonaws.<region>.` 之後的部分，例如 `ecr.api`；空集合時什麼都不建。"
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9][a-z0-9.-]*$", s)) && !startswith(s, "com.amazonaws.")])
    error_message = "Service names are the part after com.amazonaws.<region>., e.g. ecr.api."
  }
}

variable "private_dns_enabled" {
  description = "是否在 VPC 內用 endpoint 蓋過公開服務的 DNS 名稱；VPC 必須開啟 DNS support 與 DNS hostnames。"
  type        = bool
  default     = true
}

variable "tags" {
  description = "額外的 tag；`Name` 由 module 加上。"
  type        = map(string)
  default     = {}
}
