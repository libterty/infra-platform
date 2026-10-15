variable "name" {
  description = "Runtime name. Letters, digits and underscores only; AgentCore rejects hyphens."
  type        = string
  validation {
    # 48 chars follows the AWS documentation; not tested against the API.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores (no hyphens), at most 48 chars."
  }
}

variable "description" {
  description = "Optional runtime description."
  type        = string
  default     = null
}

variable "role_arn" {
  description = "Execution role ARN the runtime assumes. Created outside this module."
  type        = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN without a path."
  }
}

variable "container_uri" {
  description = "ECR image with an explicit tag or digest. Terraform owns the tag: change it here and apply."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+(:[A-Za-z0-9_.-]{1,128}|@sha256:[0-9a-f]{64})$", var.container_uri)) && !endswith(var.container_uri, ":latest")
    error_message = "container_uri must be an ECR image with an explicit tag (not latest) or a sha256 digest."
  }
}

variable "network" {
  description = "VPC by default. PUBLIC must be written out; it bypasses security groups and VPC endpoints."
  type = object({
    mode               = optional(string, "VPC")
    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])
  })
  nullable = false

  validation {
    condition     = contains(["VPC", "PUBLIC"], var.network.mode)
    error_message = "network.mode must be VPC or PUBLIC."
  }

  # Two subnets is this repo's availability convention, not an AWS minimum.
  validation {
    condition     = var.network.mode != "VPC" ? true : length(var.network.subnet_ids) >= 2 && length(distinct(var.network.subnet_ids)) == length(var.network.subnet_ids)
    error_message = "VPC mode needs at least two distinct subnet_ids."
  }

  # The upper limit of 5 follows the AWS documentation; not tested against the API.
  validation {
    condition     = var.network.mode != "VPC" ? true : length(var.network.security_group_ids) >= 1 && length(var.network.security_group_ids) <= 5 && length(distinct(var.network.security_group_ids)) == length(var.network.security_group_ids)
    error_message = "VPC mode needs 1-5 distinct security_group_ids."
  }

  validation {
    condition     = var.network.mode != "PUBLIC" ? true : length(var.network.subnet_ids) == 0 && length(var.network.security_group_ids) == 0
    error_message = "PUBLIC mode does not use subnet_ids or security_group_ids; leave both empty."
  }
}

variable "session_lifecycle" {
  description = "Session lifecycle in seconds. Always sent as a pair: the API replaces the whole lifecycle configuration, so a missing value silently falls back to the AWS default. A longer idle timeout does not reduce cold starts; it holds more sessions against the account quota."
  type = object({
    idle_session_timeout = optional(number, 900)
    max_lifetime         = optional(number, 28800)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for v in [var.session_lifecycle.idle_session_timeout, var.session_lifecycle.max_lifetime] :
      v >= 60 && v <= 1209600
    ])
    error_message = "idle_session_timeout and max_lifetime must both be between 60 and 1209600 seconds."
  }

  # The ordering rule follows the API documentation; not tested against the API.
  validation {
    condition     = var.session_lifecycle.idle_session_timeout <= var.session_lifecycle.max_lifetime
    error_message = "idle_session_timeout must not exceed max_lifetime."
  }
}

variable "protocol" {
  description = "Server protocol of the container: HTTP, MCP or A2A."
  type        = string
  default     = "HTTP"
  nullable    = false
  validation {
    condition     = contains(["HTTP", "MCP", "A2A"], var.protocol)
    error_message = "protocol must be HTTP, MCP or A2A."
  }
}

variable "environment_variables" {
  description = "Plain environment variables. Put secrets in Secrets Manager and pass only the ARN here."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "jwt_authorizer" {
  description = "Inbound JWT authorizer. null keeps the default IAM (SigV4) inbound auth."
  type = object({
    discovery_url    = string
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default = null

  validation {
    condition     = var.jwt_authorizer == null ? true : can(regex("^https://.+/\\.well-known/openid-configuration$", var.jwt_authorizer.discovery_url))
    error_message = "jwt_authorizer.discovery_url must start with https:// and end with /.well-known/openid-configuration."
  }

  validation {
    condition     = var.jwt_authorizer == null ? true : length(var.jwt_authorizer.allowed_audience) + length(var.jwt_authorizer.allowed_clients) > 0
    error_message = "jwt_authorizer needs at least one of allowed_audience or allowed_clients."
  }
}

variable "request_header_allowlist" {
  description = "Request headers passed through to the container. Empty sends no header configuration."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Extra tags; Name is set by the module."
  type        = map(string)
  default     = {}
}
