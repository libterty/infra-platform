variable "name" {
  description = "Prefix for the security group and endpoint Name tags."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,47}$", var.name))
    error_message = "name must be 2-48 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  description = "VPC the endpoints and the security group are created in."
  type        = string
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the endpoints on 443, usually [vpc_cidr]."
  type        = list(string)
  validation {
    condition = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && can(cidrnetmask(c)) && c != "0.0.0.0/0"
    ])
    error_message = "allowed_cidrs needs at least one valid IPv4 CIDR and must not contain 0.0.0.0/0."
  }
}

variable "subnet_ids" {
  description = "One subnet per AZ for the endpoint network interfaces."
  type        = list(string)
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "services" {
  description = "Service names after com.amazonaws.<region>., e.g. ecr.api. Empty creates nothing."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9][a-z0-9.-]*$", s)) && !startswith(s, "com.amazonaws.")])
    error_message = "Service names are the part after com.amazonaws.<region>., e.g. ecr.api."
  }
}

variable "private_dns_enabled" {
  description = "Whether the endpoints override the public service DNS name inside the VPC; the VPC needs DNS support and hostnames enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags; Name is set by the module."
  type        = map(string)
  default     = {}
}
