variable "name" {
  type        = string
  description = "Gateway 名稱。英數字與單一 `-`（不可連續 `--`，頭尾不可是 `-`），最多 100 字元。"

  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z-]{0,98}[0-9A-Za-z])?$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be letters, digits and single hyphens, at most 100 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Gateway 的說明。"
}

variable "role_arn" {
  type        = string
  description = "Gateway 的 service role ARN，可以帶 path。Lambda target 用這支 role 呼叫，所以它要有那些 Lambda 的 `lambda:InvokeFunction`。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN; a path is allowed."
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
  description = "入站驗證。欄位：`type`（必填，`AWS_IAM`（SigV4）或 `CUSTOM_JWT`，不收 `NONE`）、`discovery_url`、`allowed_audience`、`allowed_clients`（後兩者預設 `[]`，不可有空字串或只有空白的項目）。`CUSTOM_JWT` 時 `discovery_url` 必填，要 `https://` 開頭、以 `/.well-known/openid-configuration` 結尾，`allowed_audience`、`allowed_clients` 至少一個非空；`AWS_IAM` 時這三個都不可給。"

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

  validation {
    condition     = alltrue([for v in setunion(var.authorizer.allowed_audience, var.authorizer.allowed_clients) : length(trimspace(v)) > 0])
    error_message = "allowed_audience and allowed_clients must not contain empty or whitespace-only entries."
  }
}

variable "mcp" {
  type = object({
    supported_versions = optional(set(string), ["2025-03-26"])
    search_type        = optional(string)
  })
  default     = {}
  nullable    = false
  description = "MCP 協定設定。欄位：`supported_versions`（預設 `[\"2025-03-26\"]`）、`search_type`（給 `SEMANTIC` 開啟工具搜尋；預設 `null`，不送、不開）。"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Gateway 加密用的自管 KMS key ARN（`arn:…:kms:<region>:<帳號>:key/<key id>`，multi-region key 可以，不收 alias 與單獨的 key id）。`null` 時用 AWS 擁有的 key。"

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:...:kms:<region>:<account>:key/<key id>); aliases and bare key ids are not accepted."
  }
}

variable "allowed_account_ids" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "目前帳號以外、Lambda target 可以在的帳號（12 位數字）。空的時候所有 Lambda target 都必須在目前帳號。`tool_schema_s3_uri`（不含帳號）與 MCP server target 不檢查。"

  validation {
    condition     = alltrue([for a in var.allowed_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "allowed_account_ids must contain 12-digit AWS account IDs."
  }
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
  description = "Gateway target，key 是 target 名稱（規則同 `name`），`type` 是 `lambda` 或 `mcp_server`。欄位見〈`targets` 欄位〉。"

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
  description = "套用到 Gateway 的 tag，另外加 `Name`。"
}
