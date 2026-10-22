variable "vpc_cidr" {
  description = "VPC CIDR. The subnet layout in vpc.tf is computed from it and needs a /16."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr)) && cidrsubnet(var.vpc_cidr, 0, 0) == var.vpc_cidr
    error_message = "vpc_cidr must be an IPv4 /16 network address such as 10.10.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones, in a stable order; every tier gets one subnet per zone."
  type        = list(string)

  validation {
    # The layout reserves three slots per tier.
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 2 or 3 distinct availability zones."
  }
}

variable "nat_mode" {
  description = "per_az puts a NAT gateway in each AZ; none creates no NAT, and then services reach AWS only through the interface endpoints and the S3 gateway endpoint."
  type        = string
  default     = "per_az"

  validation {
    condition     = contains(["per_az", "none"], var.nat_mode)
    error_message = "nat_mode must be per_az or none."
  }
}

variable "bedrock_endpoints_enabled" {
  description = "Create the interface endpoints for the three Bedrock services in the app subnets."
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Port the api container listens on. The ALB may reach the app group on this port only; the application stack's container port must match."
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "alb_ingress" {
  description = "Who can reach the ALB on 443 and 80: CIDRs and managed prefix lists (for example the CloudFront origin-facing list, which uses many rules of the security group quota). Writing 0.0.0.0/0 opens the ALB to everyone and must be explicit."
  type = object({
    cidrs           = optional(list(string), [])
    prefix_list_ids = optional(list(string), [])
  })

  validation {
    condition     = length(var.alb_ingress.cidrs) + length(var.alb_ingress.prefix_list_ids) > 0
    error_message = "alb_ingress needs at least one CIDR or prefix list."
  }

  validation {
    condition     = alltrue([for c in var.alb_ingress.cidrs : can(cidrnetmask(c))])
    error_message = "alb_ingress.cidrs must be valid IPv4 CIDRs."
  }
}

variable "bastion_enabled" {
  description = "Open the paths a bastion needs (to the Proxy and the caches). The security group always exists so its ID can be published; the instance belongs to the operation stack, and the two must agree."
  type        = bool
  default     = false
}

variable "peering" {
  description = "Request a VPC peering connection and route the app and agent tiers to the peer CIDRs. null creates none. The peer account must accept the request on its side."
  type = object({
    peer_vpc_id   = string
    peer_owner_id = string
    peer_cidrs    = list(string)
    peer_region   = optional(string)
  })
  default = null

  validation {
    condition     = var.peering == null ? true : can(regex("^[0-9]{12}$", var.peering.peer_owner_id))
    error_message = "peering.peer_owner_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.peering == null ? true : can(regex("^vpc-[0-9a-f]{8,17}$", var.peering.peer_vpc_id))
    error_message = "peering.peer_vpc_id must look like vpc-0123456789abcdef0."
  }

  validation {
    condition     = var.peering == null ? true : length(var.peering.peer_cidrs) > 0
    error_message = "peering.peer_cidrs needs at least one CIDR."
  }
}

variable "k8s_api_sources" {
  description = "Networks and security groups of the runners that run Helm against the private Kubernetes API (eks-addons stack, CI). Empty means nobody outside the cluster can reach the API."
  type = object({
    cidrs              = optional(list(string), [])
    security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.k8s_api_sources.cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "k8s_api_sources.cidrs must be IPv4 CIDRs and must not be 0.0.0.0/0; the API endpoint is private."
  }

  validation {
    condition     = alltrue([for g in var.k8s_api_sources.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", g))])
    error_message = "k8s_api_sources.security_group_ids must look like sg-0123456789abcdef0."
  }
}
