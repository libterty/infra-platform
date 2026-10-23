variable "name" {
  type        = string
  description = "peering 連線名稱，也是它的 `Name` tag。2–63 字元，限小寫英數字與 `-`，以字母開頭。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "vpc_id" {
  type        = string
  description = "請求端 VPC（本帳號的 VPC），格式 `vpc-0123456789abcdef0`。"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "請求端 VPC 的主要 CIDR，必須是網路位址（例如 `10.10.0.0/16`）；用來擋下與它重疊的 `peer_cidrs`。"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && cidrsubnet(var.vpc_cidr, 0, 0) == var.vpc_cidr
    error_message = "vpc_cidr must be an IPv4 network address such as 10.10.0.0/16."
  }
}

variable "peer_vpc_id" {
  type        = string
  description = "對端帳號裡的接受端 VPC，格式 `vpc-0123456789abcdef0`。"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.peer_vpc_id))
    error_message = "peer_vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "peer_owner_id" {
  type        = string
  description = "對端 VPC 擁有者的帳號 ID，12 位數字。"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.peer_owner_id))
    error_message = "peer_owner_id must be a 12-digit AWS account ID."
  }
}

variable "peer_region" {
  type        = string
  default     = null
  description = "對端 VPC 的 region，例如 `ap-northeast-1`；`null` 表示與請求端同 region。"
  validation {
    condition     = var.peer_region == null ? true : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.peer_region))
    error_message = "peer_region must be a region name such as ap-northeast-1."
  }
}

variable "route_table_ids" {
  type        = list(string)
  description = "請求端 VPC 裡要加 route 到每個對端 CIDR 的 route table，至少一個、不可重複，格式 `rtb-0123456789abcdef0`。用 list 而不是 set：ID 在 plan 時可能還不知道，route 以索引為 key。"
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
  description = "要路由過去的對端 VPC 網段，至少一個、不可重複，必須是網路位址（例如 `10.250.0.0/16`）；不可為 `0.0.0.0/0`，也不可與 `vpc_cidr` 重疊。"
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
  description = "peering 連線的 tag；`Name` 由 module 加上。"
}
