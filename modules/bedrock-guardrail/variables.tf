variable "name" {
  type        = string
  description = "Guardrail name."
  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,50}$", var.name))
    error_message = "name must be 1-50 characters of letters, digits, hyphens or underscores."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Guardrail description."
}

variable "blocked_input_message" {
  type        = string
  description = "Text returned instead of the prompt when the input is blocked."
}

variable "blocked_output_message" {
  type        = string
  description = "Text returned instead of the model output when the output is blocked."
}

variable "tier" {
  type        = string
  default     = "STANDARD"
  description = "STANDARD or CLASSIC. CLASSIC evaluates English only; non-English text passes unchecked."
  validation {
    condition     = contains(["STANDARD", "CLASSIC"], var.tier)
    error_message = "tier must be STANDARD or CLASSIC."
  }
}

variable "cross_region_profile_id" {
  type        = string
  default     = null
  description = "Guardrail profile id, e.g. apac.guardrail.v1:0. Required for STANDARD. No API validates it; a wrong id only fails on the first real request."
  validation {
    # Format derived from one known id only; other profile id shapes are untested.
    condition = var.tier == "STANDARD" ? (
      can(regex("^[a-z]+(-[a-z]+)?\\.guardrail\\.v[0-9]+:[0-9]+$", var.cross_region_profile_id))
    ) : var.cross_region_profile_id == null
    error_message = "STANDARD needs cross_region_profile_id like apac.guardrail.v1:0; CLASSIC must leave it null."
  }
}

variable "content_filters" {
  type = map(object({
    input_strength  = string
    output_strength = string
    input_action    = optional(string, "BLOCK")
    output_action   = optional(string, "BLOCK")
    input_enabled   = optional(bool, true)
    output_enabled  = optional(bool, true)
  }))
  default     = {}
  description = "Content filters keyed by type: SEXUAL, VIOLENCE, HATE, INSULTS, MISCONDUCT or PROMPT_ATTACK. Strength is NONE, LOW, MEDIUM or HIGH; action is BLOCK or NONE."
  validation {
    condition     = alltrue([for k in keys(var.content_filters) : contains(["SEXUAL", "VIOLENCE", "HATE", "INSULTS", "MISCONDUCT", "PROMPT_ATTACK"], k)])
    error_message = "content_filters keys must be SEXUAL, VIOLENCE, HATE, INSULTS, MISCONDUCT or PROMPT_ATTACK."
  }
  validation {
    condition = alltrue(flatten([for f in values(var.content_filters) : [
      for s in [f.input_strength, f.output_strength] : contains(["NONE", "LOW", "MEDIUM", "HIGH"], s)
    ]]))
    error_message = "content_filters strengths must be NONE, LOW, MEDIUM or HIGH."
  }
  validation {
    condition = alltrue(flatten([for f in values(var.content_filters) : [
      for a in [f.input_action, f.output_action] : contains(["BLOCK", "NONE"], a)
    ]]))
    error_message = "content_filters actions must be BLOCK or NONE."
  }
  validation {
    # The API rejects any other output strength for prompt attacks.
    condition     = try(var.content_filters["PROMPT_ATTACK"].output_strength, "NONE") == "NONE"
    error_message = "PROMPT_ATTACK output_strength must be NONE."
  }
}

variable "denied_topics" {
  type = map(object({
    definition = string
    examples   = optional(list(string), [])
  }))
  default     = {}
  description = "Denied topics keyed by topic name. definition is the only place to state exclusions; examples should be positive only."
  validation {
    condition     = length(var.denied_topics) <= 30
    error_message = "denied_topics must have at most 30 topics."
  }
  validation {
    condition     = alltrue([for t in values(var.denied_topics) : trimspace(t.definition) != ""])
    error_message = "denied_topics definition must not be empty."
  }
}

variable "words" {
  type        = list(string)
  default     = []
  description = "Custom blocked words or phrases."
}

variable "managed_word_lists" {
  type        = set(string)
  default     = []
  description = "AWS managed word lists. Only PROFANITY exists."
  validation {
    condition     = alltrue([for w in var.managed_word_lists : w == "PROFANITY"])
    error_message = "managed_word_lists only accepts PROFANITY."
  }
}

variable "pii_entities" {
  type = map(object({
    action         = string
    input_enabled  = optional(bool, true)
    output_enabled = optional(bool, true)
  }))
  default     = {}
  description = "PII entities keyed by entity type, e.g. EMAIL or PHONE. action is BLOCK or ANONYMIZE; ANONYMIZE still reports an intervention."
  # Same list as the enum the aws provider 6.69.0 validates at plan time; checked here so the error points at this input.
  validation {
    condition = alltrue([for k in keys(var.pii_entities) : contains([
      "ADDRESS", "AGE", "AWS_ACCESS_KEY", "AWS_SECRET_KEY", "CA_HEALTH_NUMBER", "CA_SOCIAL_INSURANCE_NUMBER",
      "CREDIT_DEBIT_CARD_CVV", "CREDIT_DEBIT_CARD_EXPIRY", "CREDIT_DEBIT_CARD_NUMBER", "DRIVER_ID", "EMAIL",
      "INTERNATIONAL_BANK_ACCOUNT_NUMBER", "IP_ADDRESS", "LICENSE_PLATE", "MAC_ADDRESS", "NAME", "PASSWORD", "PHONE",
      "PIN", "SWIFT_CODE", "UK_NATIONAL_HEALTH_SERVICE_NUMBER", "UK_NATIONAL_INSURANCE_NUMBER",
      "UK_UNIQUE_TAXPAYER_REFERENCE_NUMBER", "URL", "USERNAME", "US_BANK_ACCOUNT_NUMBER", "US_BANK_ROUTING_NUMBER",
      "US_INDIVIDUAL_TAX_IDENTIFICATION_NUMBER", "US_PASSPORT_NUMBER", "US_SOCIAL_SECURITY_NUMBER",
      "VEHICLE_IDENTIFICATION_NUMBER",
    ], k)])
    error_message = "pii_entities keys must be Bedrock guardrail PII entity types, e.g. EMAIL, PHONE or CREDIT_DEBIT_CARD_NUMBER (uppercase)."
  }
  validation {
    condition     = alltrue([for p in values(var.pii_entities) : contains(["BLOCK", "ANONYMIZE"], p.action)])
    error_message = "pii_entities action must be BLOCK or ANONYMIZE."
  }
}

variable "regexes" {
  type = map(object({
    pattern     = string
    action      = string
    description = optional(string)
  }))
  default     = {}
  description = "Custom regex filters keyed by name. action is BLOCK or ANONYMIZE."
  validation {
    condition     = alltrue([for r in values(var.regexes) : contains(["BLOCK", "ANONYMIZE"], r.action)])
    error_message = "regexes action must be BLOCK or ANONYMIZE."
  }
}

variable "contextual_grounding" {
  type = object({
    grounding_threshold = optional(number)
    relevance_threshold = optional(number)
  })
  default     = null
  description = "Contextual grounding thresholds, each 0-0.99. At least one must be set."
  validation {
    condition = var.contextual_grounding == null ? true : alltrue([
      for t in [var.contextual_grounding.grounding_threshold, var.contextual_grounding.relevance_threshold] :
      t == null ? true : (t >= 0 && t <= 0.99)
    ])
    error_message = "contextual_grounding thresholds must be between 0 and 0.99."
  }
  validation {
    condition = var.contextual_grounding == null ? true : (
      var.contextual_grounding.grounding_threshold != null || var.contextual_grounding.relevance_threshold != null
    )
    error_message = "contextual_grounding needs grounding_threshold or relevance_threshold."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key ARN (key/<uuid>, not an alias) for the guardrail. null uses an AWS owned key."
  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<uuid>), not an alias or a wildcard."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the guardrail. Name is added by the module."
}
