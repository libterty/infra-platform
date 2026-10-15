variable "vpc" {
  description = "Create the VPC (the default). Exactly one of vpc and existing must be set. Tiers public, app and data are part of the SSM contract; the data tier is isolated by default."
  type = object({
    cidr = string
    azs  = list(string)
    subnets = map(object({
      type        = string # public | private | isolated
      newbits     = optional(number)
      netnum_base = optional(number)
      cidrs       = optional(map(string))
    }))
    nat_mode = optional(string, "single")
    flow_log = optional(bool, false) # true sends flow logs to the flow log bucket of the foundation stack
  })
  default = null

  validation {
    condition     = var.vpc == null ? true : alltrue([for t in ["public", "app", "data"] : contains(keys(var.vpc.subnets), t)])
    error_message = "vpc.subnets must contain the tiers public, app and data."
  }
}

variable "existing" {
  description = "Mode A: register a VPC owned by the customer instead of creating one. subnet_ids maps tier to subnet IDs in AZ order and must contain public, app and data."
  type = object({
    vpc_id     = string
    subnet_ids = map(list(string))
  })
  default = null

  validation {
    condition     = (var.vpc == null) != (var.existing == null)
    error_message = "Set exactly one of vpc and existing."
  }

  validation {
    condition     = var.existing == null ? true : alltrue([for t in ["public", "app", "data"] : contains(keys(var.existing.subnet_ids), t)])
    error_message = "existing.subnet_ids must contain the tiers public, app and data."
  }

  validation {
    condition = var.existing == null ? true : (
      alltrue([for t, ids in var.existing.subnet_ids : can(regex("^[a-z][a-z0-9_]*$", t)) && length(ids) >= 2 && length(ids) == length(var.existing.subnet_ids["app"])])
    )
    error_message = "Tier names must be snake_case, and every tier needs the same number of subnets, at least two."
  }
}

variable "interface_endpoints" {
  description = "Interface endpoints, created in both modes. An empty services set creates nothing."
  type = object({
    services    = optional(set(string), []) # for example ecr.api, ecr.dkr, logs, secretsmanager, kms
    subnet_tier = optional(string, "app")
  })
  default = {}

  validation {
    condition = (
      var.vpc != null ? (
        contains(keys(var.vpc.subnets), var.interface_endpoints.subnet_tier) && try(var.vpc.subnets[var.interface_endpoints.subnet_tier].type, "") != "public"
        ) : var.existing != null ? (
        contains(keys(var.existing.subnet_ids), var.interface_endpoints.subnet_tier) && var.interface_endpoints.subnet_tier != "public"
      ) : true
    )
    error_message = "interface_endpoints.subnet_tier must be an existing tier and must not be the public tier."
  }
}

variable "services" {
  description = "Per-service network settings. The keys must equal the services published by containerimage."
  type = map(object({
    port        = number
    from_alb    = optional(bool, false)      # the ALB forwards to this service
    callers     = optional(list(string), []) # services that may call this one
    data_access = optional(list(string), []) # keys of data_stores this service may reach
  }))

  validation {
    condition     = alltrue([for s in values(var.services) : s.port >= 1 && s.port <= 65535])
    error_message = "Service ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue(flatten([for s in values(var.services) : [for c in s.callers : contains(keys(var.services), c)]]))
    error_message = "callers must name services that exist in services."
  }

  validation {
    condition     = alltrue(flatten([for s in values(var.services) : [for d in s.data_access : contains(keys(var.data_stores), d)]]))
    error_message = "data_access must name keys of data_stores."
  }

  validation {
    # A service security group is keyed by its snake_case name, so it must not take a key the stack already uses.
    condition = length(setintersection(
      toset([for s in keys(var.services) : replace(s, "-", "_")]),
      toset(concat(["alb"], keys(var.data_stores), [for k in keys(var.data_stores) : "${k}_proxy"])),
    )) == 0
    error_message = "A service name must not collide with the security group keys alb, <data store> or <data store>_proxy."
  }
}

variable "data_stores" {
  description = "Data stores and their ports. This is the single decision point for the RDS Proxy switch: proxy = true makes services reach the store through the Proxy. The data stack reads the db entry."
  type = map(object({
    port  = number
    proxy = optional(bool, false)
  }))
  default = { db = { port = 5432 } }

  validation {
    condition     = contains(keys(var.data_stores), "db")
    error_message = "data_stores must contain db; the data stack reads sg_db_id, sg_db_proxy_id and db_proxy."
  }

  validation {
    condition     = alltrue([for k, s in var.data_stores : can(regex("^[a-z][a-z0-9]*$", k)) && s.port >= 1 && s.port <= 65535])
    error_message = "Data store keys must be lowercase letters and digits, and ports must be between 1 and 65535."
  }
}

variable "alb_ingress" {
  description = "Who can reach the ALB. https is the single decision point for whether the ALB has a certificate; with https = false the CIDRs must not include 0.0.0.0/0."
  type = object({
    https           = bool
    cidrs           = optional(list(string), [])
    prefix_list_ids = optional(list(string), []) # for example the CloudFront origin-facing prefix list
  })

  validation {
    condition     = length(var.alb_ingress.cidrs) + length(var.alb_ingress.prefix_list_ids) > 0
    error_message = "alb_ingress needs at least one CIDR or prefix list. To open the ALB to everyone write 0.0.0.0/0 explicitly."
  }

  validation {
    condition     = var.alb_ingress.https ? true : !contains(var.alb_ingress.cidrs, "0.0.0.0/0") && !contains(var.alb_ingress.cidrs, "::/0")
    error_message = "Without a certificate (https = false) the ALB must not be open to 0.0.0.0/0 or ::/0. Use a CloudFront prefix list or specific CIDRs."
  }
}
