variable "name" {
  type        = string
  description = "Gateway name."

  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z-]{0,98}[0-9A-Za-z])?$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be letters, digits and single hyphens, at most 100 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Gateway description."
}

variable "role_arn" {
  type        = string
  description = "Gateway service role. Lambda targets are invoked with this role, so it needs lambda:InvokeFunction on them."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN without a path."
  }
}

variable "authorizer" {
  type = object({
    type             = string
    discovery_url    = optional(string)
    allowed_audience = optional(set(string), [])
    allowed_clients  = optional(set(string), [])
  })
  default     = { type = "AWS_IAM" }
  nullable    = false
  description = "Inbound authorization. AWS_IAM (SigV4) or CUSTOM_JWT; NONE is not accepted."

  validation {
    condition     = contains(["AWS_IAM", "CUSTOM_JWT"], var.authorizer.type)
    error_message = "authorizer.type must be AWS_IAM or CUSTOM_JWT; a gateway without inbound auth exposes its tools to anyone with the URL."
  }

  validation {
    condition = var.authorizer.type != "CUSTOM_JWT" ? true : (
      var.authorizer.discovery_url == null ? false : (
        can(regex("^https://\\S+/\\.well-known/openid-configuration$", var.authorizer.discovery_url)) &&
        length(var.authorizer.allowed_audience) + length(var.authorizer.allowed_clients) > 0
      )
    )
    error_message = "CUSTOM_JWT needs an https discovery_url ending in /.well-known/openid-configuration and at least one allowed_audience or allowed_clients entry."
  }

  validation {
    condition = var.authorizer.type != "AWS_IAM" ? true : (
      var.authorizer.discovery_url == null &&
      length(var.authorizer.allowed_audience) == 0 &&
      length(var.authorizer.allowed_clients) == 0
    )
    error_message = "AWS_IAM takes no discovery_url, allowed_audience or allowed_clients."
  }
}

variable "mcp" {
  type = object({
    supported_versions = optional(set(string), ["2025-03-26"])
    search_type        = optional(string)
  })
  default     = {}
  nullable    = false
  description = "MCP protocol settings. search_type = SEMANTIC turns on tool search; null leaves it off."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for the gateway. null uses an AWS owned key."
}

variable "targets" {
  type = map(object({
    type        = string
    description = optional(string)

    lambda_arn         = optional(string)
    tool_schema_s3_uri = optional(string)
    tools = optional(list(object({
      name        = string
      description = string
      properties = optional(map(object({
        type        = string
        description = optional(string)
        required    = optional(bool, false)
      })), {})
    })))

    endpoint = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Targets keyed by target name. type is lambda or mcp_server. A lambda target takes lambda_arn and exactly one of tool_schema_s3_uri and tools (flat properties only; nested schemas go through S3). An mcp_server target takes only an https endpoint."

  validation {
    condition = alltrue([for k, t in var.targets :
      can(regex("^[0-9A-Za-z]([0-9A-Za-z-]{0,98}[0-9A-Za-z])?$", k)) && !strcontains(k, "--")
    ])
    error_message = "Target keys are target names: letters, digits and single hyphens, at most 100 chars."
  }

  validation {
    condition     = alltrue([for t in var.targets : contains(["lambda", "mcp_server"], t.type)])
    error_message = "Target type must be lambda or mcp_server."
  }

  validation {
    condition = alltrue([for t in var.targets : t.type != "lambda" ? true : (
      t.lambda_arn == null ? false : (
        can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}(:[A-Za-z0-9_$-]+)?$", t.lambda_arn)) &&
        t.endpoint == null
      )
    )])
    error_message = "A lambda target needs a Lambda function ARN in lambda_arn and no endpoint."
  }

  validation {
    condition = alltrue([for t in var.targets : t.type != "lambda" ? true : (
      (t.tool_schema_s3_uri != null ? 1 : 0) + (length(coalesce(t.tools, [])) > 0 ? 1 : 0) == 1
    )])
    error_message = "A lambda target needs exactly one of tool_schema_s3_uri and a non-empty tools list."
  }

  validation {
    condition = alltrue([for t in var.targets : t.type != "mcp_server" ? true : (
      t.endpoint == null ? false : (
        can(regex("^https://[^/\\s]+(/\\S*)?$", t.endpoint)) &&
        t.lambda_arn == null && t.tool_schema_s3_uri == null && t.tools == null
      )
    )])
    error_message = "An mcp_server target needs an https endpoint and takes no lambda_arn, tool_schema_s3_uri or tools."
  }

  validation {
    condition = alltrue([for t in var.targets :
      t.tool_schema_s3_uri == null ? true : can(regex("^s3://[^/]+/.+$", t.tool_schema_s3_uri))
    ])
    error_message = "tool_schema_s3_uri must be an s3://bucket/key URI."
  }

  validation {
    condition = alltrue([for t in var.targets : t.tools == null ? true : (
      length(distinct([for tool in t.tools : tool.name])) == length(t.tools) &&
      alltrue([for tool in t.tools :
        length(trimspace(tool.description)) > 0 &&
        alltrue([for p in values(tool.properties) : contains(["string", "number", "integer", "boolean", "object", "array"], p.type)])
      ])
    )])
    error_message = "Tool names must be unique within a target, descriptions must not be empty, and property types must be string, number, integer, boolean, object or array."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the gateway. Name is added."
}
