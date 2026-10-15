variable "agent_runtimes" {
  description = "AgentCore Runtimes. The keys must equal the agent_runtimes published by containerimage. models, memories, guardrails and knowledge_bases list keys of the variables below; tracing is the single decision point for Runtime tracing. Empty by default, which creates nothing."
  type = map(object({
    image_tag    = string                   # unique per build, never latest; Terraform owns the tag
    network_mode = optional(string, "VPC")  # VPC | PUBLIC; PUBLIC bypasses security groups and VPC endpoints
    subnet_tier  = optional(string, "app")  # a tier published by network, never public
    protocol     = optional(string, "HTTP") # HTTP | MCP | A2A
    session_lifecycle = optional(object({
      idle_session_timeout = optional(number, 900)
      max_lifetime         = optional(number, 28800)
    }), {})
    models             = optional(list(string), [])
    memories           = optional(list(string), [])
    guardrails         = optional(list(string), [])
    knowledge_bases    = optional(list(string), [])
    gateway            = optional(bool, false) # may call agentcore_gateway
    tracing            = optional(bool, false)
    environment        = optional(map(string), {}) # the project's own variables; only ids, ARNs and URLs, never secrets
    log_retention_days = optional(number, 30)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.agent_runtimes) : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", r.image_tag)) && lower(r.image_tag) != "latest"])
    error_message = "image_tag must be an explicit image tag, not latest."
  }

  validation {
    condition     = alltrue([for r in values(var.agent_runtimes) : contains(["VPC", "PUBLIC"], r.network_mode)])
    error_message = "network_mode must be VPC or PUBLIC."
  }

  validation {
    # The tier must also exist in network: reading subnet_ids_<tier> fails the plan when it does not.
    condition     = alltrue([for r in values(var.agent_runtimes) : can(regex("^[a-z][a-z0-9_]*$", r.subnet_tier)) && r.subnet_tier != "public"])
    error_message = "subnet_tier must be a tier published by network and must not be the public tier."
  }

  validation {
    condition = alltrue([for r in values(var.agent_runtimes) :
      alltrue([for m in r.models : contains(keys(var.models), m)]) &&
      alltrue([for m in r.memories : contains(keys(var.memories), m)]) &&
      alltrue([for g in r.guardrails : contains(keys(var.guardrails), g)]) &&
      alltrue([for k in r.knowledge_bases : contains(keys(var.knowledge_bases), k)])
    ])
    error_message = "models, memories, guardrails and knowledge_bases of a Runtime must name keys of the variables with the same name."
  }

  validation {
    condition     = alltrue([for r in values(var.agent_runtimes) : !r.gateway || var.agentcore_gateway != null])
    error_message = "A Runtime with gateway = true needs agentcore_gateway."
  }

  validation {
    # The template sets these; TRACELOOP_TRACE_CONTENT is the only one a project may override.
    condition = alltrue(flatten([for r in values(var.agent_runtimes) : [for name in keys(r.environment) :
      !contains(["AWS_REGION", "GUARDRAIL_VERSION", "AGENTCORE_GATEWAY_URL", "DB_HOST", "DB_READER_HOST", "DB_PORT", "DB_NAME", "DB_SECRET_ARN", "BEDROCK_INVOKE_ROLE_ARN", "BEDROCK_INVOKE_SESSION_SECONDS"], name) &&
      length(regexall("^(MODEL_ID_|MEMORY_ID_|GUARDRAIL_ID_|KNOWLEDGE_BASE_ID_|OTEL_)", name)) == 0
    ]]))
    error_message = "environment must not use a name the template sets (AWS_REGION, MODEL_ID_*, MEMORY_ID_*, GUARDRAIL_ID_*, GUARDRAIL_VERSION, KNOWLEDGE_BASE_ID_*, AGENTCORE_GATEWAY_URL, DB_*, BEDROCK_INVOKE_*, OTEL_*); only TRACELOOP_TRACE_CONTENT may be overridden."
  }
}

variable "models" {
  description = "Models by a project key. This is the single decision point for models: the invoke ARNs that iam-app grants are built here. inference_profile_prefix null calls the foundation model on demand; a prefix such as apac or global calls the system inference profile; tracked creates an application inference profile so cost can be split by tag. Empty by default."
  type = map(object({
    foundation_model_id      = string # for example anthropic.claude-sonnet-4-5-20250929-v1:0
    inference_profile_prefix = optional(string)
    tracked                  = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.models) : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", k))])
    error_message = "Model keys must be kebab-case; they become MODEL_ID_<KEY> environment variables."
  }

  validation {
    condition     = alltrue([for m in values(var.models) : can(regex("^[a-z0-9-]+\\.[A-Za-z0-9._:-]+$", m.foundation_model_id))])
    error_message = "foundation_model_id must be a Bedrock model id such as anthropic.claude-sonnet-4-5-20250929-v1:0, without a region prefix."
  }

  validation {
    condition     = alltrue([for m in values(var.models) : m.inference_profile_prefix == null || can(regex("^[a-z]+$", m.inference_profile_prefix))])
    error_message = "inference_profile_prefix must be null or a system inference profile prefix such as apac or global."
  }
}

variable "guardrails" {
  description = "Guardrails by key, each passed to bedrock-guardrail. tier defaults to STANDARD, which needs cross_region_profile_id (for example apac.guardrail.v1:0). Versions are never published; callers use DRAFT. Empty by default."
  type = map(object({
    blocked_input_message   = string
    blocked_output_message  = string
    description             = optional(string)
    tier                    = optional(string, "STANDARD")
    cross_region_profile_id = optional(string)
    content_filters = optional(map(object({
      input_strength  = string
      output_strength = string
      input_action    = optional(string, "BLOCK")
      output_action   = optional(string, "BLOCK")
      input_enabled   = optional(bool, true)
      output_enabled  = optional(bool, true)
    })), {})
    denied_topics = optional(map(object({
      definition = string
      examples   = optional(list(string), [])
    })), {})
    words              = optional(list(string), [])
    managed_word_lists = optional(set(string), [])
    pii_entities = optional(map(object({
      action         = string
      input_enabled  = optional(bool, true)
      output_enabled = optional(bool, true)
    })), {})
    regexes = optional(map(object({
      pattern     = string
      action      = string
      description = optional(string)
    })), {})
    contextual_grounding = optional(object({
      grounding_threshold = optional(number)
      relevance_threshold = optional(number)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.guardrails) : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", k))])
    error_message = "Guardrail keys must be kebab-case; they become GUARDRAIL_ID_<KEY> environment variables."
  }
}

variable "memories" {
  description = "AgentCore Memories by key, named <project>_<env>_<key>. event_expiry_days is 7-365. strategies are built-in only (SEMANTIC, SUMMARIZATION, USER_PREFERENCE), keyed by strategy name. Empty by default."
  type = map(object({
    event_expiry_days = optional(number, 90)
    strategies = optional(map(object({
      type       = string
      namespaces = list(string)
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.memories) : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", k)) && length(replace("${local.name_prefix}-${k}", "-", "_")) <= 48])
    error_message = "Memory keys must be kebab-case, and <project>_<env>_<key> must be at most 48 characters."
  }

  validation {
    # The aws provider rejects values below 7 at plan time, even though the API documents 3.
    condition     = alltrue([for m in values(var.memories) : m.event_expiry_days >= 7 && m.event_expiry_days <= 365 && floor(m.event_expiry_days) == m.event_expiry_days])
    error_message = "event_expiry_days must be a whole number between 7 and 365."
  }
}

variable "knowledge_bases" {
  description = "Bedrock knowledge bases on the Aurora database of the data stack, by key. Each gets its own corpus bucket <project>-<env>-kb-<key>-<account>, which never expires. credentials_secret_arn is the secret of a dedicated database user the project creates; never the master secret. Needs db.data_api in data and knowledge_base in iam-base agent_service_roles. Empty by default."
  type = map(object({
    embedding_model        = string # a key of models without a prefix and not tracked
    embedding_dimensions   = number
    credentials_secret_arn = string
    table_name             = optional(string, "bedrock_integration.bedrock_kb")
    field_mapping = optional(object({
      primary_key_field     = optional(string, "id")
      vector_field          = optional(string, "embedding")
      text_field            = optional(string, "chunks")
      metadata_field        = optional(string, "metadata")
      custom_metadata_field = optional(string)
    }), {})
    data_sources = map(object({ # all in this knowledge base's corpus bucket, told apart by prefix
      inclusion_prefixes = optional(set(string), [])
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.knowledge_bases) : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", k))])
    error_message = "Knowledge base keys must be kebab-case; they are part of the corpus bucket name."
  }

  validation {
    condition     = alltrue([for k in keys(var.knowledge_bases) : length("${local.name_prefix}-kb-${k}-${var.expected_account_id}") <= 63])
    error_message = "The corpus bucket name <project>-<env>-kb-<key>-<account> must be at most 63 characters; shorten the knowledge base key."
  }

  validation {
    condition = alltrue([for kb in values(var.knowledge_bases) :
      contains(keys(var.models), kb.embedding_model) ? (var.models[kb.embedding_model].inference_profile_prefix == null && !var.models[kb.embedding_model].tracked) : false
    ])
    error_message = "embedding_model must name a key of models that has no inference_profile_prefix and is not tracked."
  }

  validation {
    condition = alltrue([for kb in values(var.knowledge_bases) :
      can(regex("^arn:aws:secretsmanager:${var.aws_region}:${var.expected_account_id}:secret:[A-Za-z0-9/_+=.@!-]+-[A-Za-z0-9]{6}$", kb.credentials_secret_arn))
    ])
    error_message = "credentials_secret_arn must be the full ARN of one Secrets Manager secret in this region and account, ending in the 6-character suffix; wildcards are not allowed because iam-app grants exactly this ARN."
  }
}

variable "agentcore_gateway" {
  description = "AgentCore Gateway with AWS_IAM inbound auth. null creates none. Targets are keyed by target name; type is lambda (lambda_arn and tool_schema_s3_uri) or mcp_server (an https endpoint). Needs gateway in iam-base agent_service_roles."
  type = object({
    targets = map(object({
      type               = string
      lambda_arn         = optional(string)
      tool_schema_s3_uri = optional(string)
      endpoint           = optional(string)
    }))
  })
  default = null
}

variable "bedrock_invoke" {
  description = "Call models in another account (B) by assuming a role there. null calls models in this account. This is the single decision point for cross-account calls: iam-app swaps model permissions for sts:AssumeRole on role_arn. The role, its trust policy and the model access in account B belong to the owner of account B."
  type = object({
    role_arn        = string
    session_seconds = optional(number, 3600)
  })
  default = null

  validation {
    condition     = var.bedrock_invoke == null ? true : can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.bedrock_invoke.role_arn)) && try(split(":", var.bedrock_invoke.role_arn)[4], "") != var.expected_account_id
    error_message = "bedrock_invoke.role_arn must be an IAM role ARN in another account."
  }

  validation {
    # 0 is not "no limit": AssumeRole rejects anything under 900 seconds.
    condition     = var.bedrock_invoke == null ? true : var.bedrock_invoke.session_seconds >= 900
    error_message = "bedrock_invoke.session_seconds must be at least 900."
  }

  validation {
    # An application inference profile lives in this account, so the role in account B cannot use it.
    condition     = var.bedrock_invoke == null ? true : alltrue([for m in values(var.models) : !m.tracked])
    error_message = "Models cannot be tracked when bedrock_invoke is set."
  }
}
