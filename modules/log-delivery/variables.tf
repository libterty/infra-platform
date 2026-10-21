variable "name_prefix" {
  type        = string
  description = "Source and destination names are <name_prefix>-<key>."
}

variable "sources" {
  type = map(object({
    resource_arn = string
    log_type     = string
  }))
  default     = {}
  description = "Delivery sources keyed by a short name. resource_arn is the ARN of any resource that supports vended log delivery (for example an ALB, an EKS cluster, a CloudFront distribution or an AgentCore Runtime). It must carry an account ID that is the current one or listed in allowed_account_ids; an S3 bucket ARN is the only exception because it carries no account. log_type is the value the service defines, such as ALB_ACCESS_LOGS or S3_SERVER_ACCESS_LOGS."
  validation {
    condition     = alltrue([for s in values(var.sources) : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", s.resource_arn)) || can(regex(local.destination_arn_patterns.S3, s.resource_arn))])
    error_message = "Each source resource_arn must be an ARN that includes a 12-digit account ID, or an S3 bucket ARN."
  }
  validation {
    condition     = alltrue([for s in values(var.sources) : can(regex("^[A-Za-z0-9_]{1,255}$", s.log_type))])
    error_message = "log_type must be 1-255 letters, digits or underscores, as defined by the source service (for example ALB_ACCESS_LOGS)."
  }
  validation {
    condition     = alltrue([for k in keys(var.sources) : length("${var.name_prefix}-${k}") <= 60])
    error_message = "Each source name <name_prefix>-<key> must be at most 60 characters."
  }
}

variable "destinations" {
  type = map(object({
    type         = string
    resource_arn = optional(string)
  }))
  default     = {}
  description = "Delivery destinations keyed by a short name. type is CWL, S3, FH or XRAY; resource_arn is the log group ARN for CWL, the bucket ARN for S3, the delivery stream ARN for FH, and must be null for XRAY. CWL and FH destinations must be in the current account or in allowed_account_ids; S3 bucket ARNs carry no account and are not checked."
  validation {
    condition     = alltrue([for d in values(var.destinations) : contains(["CWL", "S3", "FH", "XRAY"], d.type)])
    error_message = "Destination type must be CWL, S3, FH or XRAY."
  }
  validation {
    condition = alltrue([for d in values(var.destinations) : d.type == "XRAY" ? d.resource_arn == null : (
      d.resource_arn == null ? false : can(regex(lookup(local.destination_arn_patterns, d.type, "^$"), d.resource_arn))
    )])
    error_message = "XRAY destinations must not set resource_arn; CWL needs a log group ARN, S3 a bucket ARN and FH a Firehose delivery stream ARN."
  }
  validation {
    condition     = alltrue([for k in keys(var.destinations) : length("${var.name_prefix}-${k}") <= 60])
    error_message = "Each destination name <name_prefix>-<key> must be at most 60 characters."
  }
}

variable "allowed_account_ids" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "Accounts other than the current one that sources and CWL destinations may live in. Empty means both must be in the current account."
  validation {
    condition     = alltrue([for a in var.allowed_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "allowed_account_ids must contain 12-digit AWS account IDs."
  }
}

variable "deliveries" {
  type = map(object({
    source      = string
    destination = string
  }))
  default     = {}
  description = "Deliveries keyed by a short name; source and destination are keys in sources and destinations."
  validation {
    condition     = alltrue([for d in values(var.deliveries) : contains(keys(var.sources), d.source) && contains(keys(var.destinations), d.destination)])
    error_message = "Every delivery must name an existing key in sources and in destinations."
  }
  validation {
    condition     = length(distinct([for d in values(var.deliveries) : "${d.source}/${d.destination}"])) == length(var.deliveries)
    error_message = "A source must not be delivered to the same destination twice."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource. Name is added to sources and destinations by the module."
}
