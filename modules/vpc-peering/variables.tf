variable "name" {
  type        = string
  description = "Peering connection name; also its Name tag."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  type        = string
  description = "Requester VPC (the VPC in this account)."
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "Primary CIDR of the requester VPC. Used to reject overlapping peer_cidrs."
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && cidrsubnet(var.vpc_cidr, 0, 0) == var.vpc_cidr
    error_message = "vpc_cidr must be an IPv4 network address such as 10.10.0.0/16."
  }
}

variable "peer_vpc_id" {
  type        = string
  description = "Accepter VPC in the peer account."
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.peer_vpc_id))
    error_message = "peer_vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "peer_owner_id" {
  type        = string
  description = "Account ID of the peer VPC owner (12 digits)."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.peer_owner_id))
    error_message = "peer_owner_id must be a 12-digit AWS account ID."
  }
}

variable "peer_region" {
  type        = string
  default     = null
  description = "Region of the peer VPC. null means the same region as the requester."
  validation {
    condition     = var.peer_region == null ? true : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.peer_region))
    error_message = "peer_region must be a region name such as ap-northeast-1."
  }
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route tables in the requester VPC that get a route to every peer CIDR. A list, not a set: the IDs may be unknown at plan time and routes are keyed by index."
  validation {
    condition     = length(var.route_table_ids) > 0
    error_message = "Give at least one route table ID."
  }
  validation {
    condition     = alltrue([for r in var.route_table_ids : can(regex("^rtb-[0-9a-f]{8,17}$", r))])
    error_message = "route_table_ids must look like rtb-0123456789abcdef0."
  }
  validation {
    condition     = length(distinct(var.route_table_ids)) == length(var.route_table_ids)
    error_message = "route_table_ids must not contain duplicates."
  }
}

variable "peer_cidrs" {
  type        = list(string)
  description = "CIDRs of the peer VPC to route to. Must not be 0.0.0.0/0 and must not overlap vpc_cidr."
  validation {
    condition     = length(var.peer_cidrs) > 0
    error_message = "Give at least one peer CIDR."
  }
  validation {
    condition     = alltrue([for c in var.peer_cidrs : can(cidrnetmask(c)) && cidrsubnet(c, 0, 0) == c])
    error_message = "peer_cidrs must be IPv4 network addresses such as 10.250.0.0/16."
  }
  validation {
    condition     = !contains(var.peer_cidrs, "0.0.0.0/0")
    error_message = "peer_cidrs must not contain 0.0.0.0/0; a default route to the peer would capture all traffic."
  }
  validation {
    condition     = length(distinct(var.peer_cidrs)) == length(var.peer_cidrs)
    error_message = "peer_cidrs must not contain duplicates."
  }
  # Two CIDRs overlap when they share the same network at the shorter of the two prefix lengths (Terraform has no cidroverlap function).
  # try() leaves malformed input to the checks above, so a bad vpc_cidr or peer CIDR does not add a second error here.
  validation {
    condition = alltrue([for c in var.peer_cidrs : try(
      [for m in [min(tonumber(split("/", var.vpc_cidr)[1]), tonumber(split("/", c)[1]))] :
        cidrsubnet("${cidrhost(var.vpc_cidr, 0)}/${m}", 0, 0) != cidrsubnet("${cidrhost(c, 0)}/${m}", 0, 0)
      ][0],
      true
    )])
    error_message = "peer_cidrs must not overlap vpc_cidr; overlapping CIDRs cannot be peered."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the peering connection. Name is added by the module."
}
