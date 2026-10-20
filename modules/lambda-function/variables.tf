variable "name" {
  type        = string
  description = "Function name. The log group is /aws/lambda/<name>."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,63}$", var.name))
    error_message = "name must be 2-64 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "image_uri" {
  type        = string
  description = "ECR image with an explicit tag or digest. latest is rejected. Terraform owns the tag: change it here and apply."
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+(:[A-Za-z0-9_.-]{1,128}|@sha256:[0-9a-f]{64})$", var.image_uri)) && !endswith(lower(var.image_uri), ":latest")
    error_message = "image_uri must be an ECR image with an explicit tag (not latest) or a sha256 digest."
  }
}

variable "role_arn" {
  type        = string
  description = "Execution role. Build it with iam-role; it needs the logs permissions on the log group and, with vpc, the network interface permissions."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN."
  }
}

variable "architectures" {
  type        = list(string)
  default     = ["arm64"]
  description = "Exactly one of arm64 or x86_64. It must match the architecture the image was built for."
  validation {
    condition     = length(var.architectures) == 1 && contains(["arm64", "x86_64"], var.architectures[0])
    error_message = "architectures must be [\"arm64\"] or [\"x86_64\"]."
  }
}

variable "memory_size" {
  type        = number
  default     = 512
  description = "Memory in MB, 128 to 10240."
  validation {
    condition     = var.memory_size == floor(var.memory_size) && var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be a whole number from 128 to 10240."
  }
}

variable "timeout" {
  type        = number
  default     = 30
  description = "Timeout in seconds, 1 to 900."
  validation {
    condition     = var.timeout == floor(var.timeout) && var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be a whole number from 1 to 900."
  }
}

variable "reserved_concurrent_executions" {
  type        = number
  default     = null
  description = "Reserved concurrency. null leaves it unreserved; 0 stops all invocations."
  validation {
    condition     = var.reserved_concurrent_executions == null ? true : (var.reserved_concurrent_executions == floor(var.reserved_concurrent_executions) && var.reserved_concurrent_executions >= 0)
    error_message = "reserved_concurrent_executions must be null or a whole number of at least 0."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Plain environment variables. Put secrets in Secrets Manager and pass only the ARN here. Names that look like secrets are rejected unless they end in _ARN and the value is an ARN."
  validation {
    condition     = alltrue([for k in keys(var.environment) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", k))])
    error_message = "environment names must start with a letter and contain only letters, digits and underscores."
  }
  # Environment variables are readable through the control plane and stored in state in plain text.
  validation {
    condition = alltrue([for k, v in var.environment :
      !can(regex("(SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL)", upper(k))) ||
      (endswith(upper(k), "_ARN") && startswith(v, "arn:"))
    ])
    error_message = "environment names must not look like secrets (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL). Secrets belong in Secrets Manager; pass only the secret ARN, in a name ending in _ARN."
  }
}

variable "vpc" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default     = null
  description = "Attach the function to a VPC. null runs it outside any VPC. Needs at least one subnet and one security group."
  validation {
    condition     = var.vpc == null ? true : (length(var.vpc.subnet_ids) > 0 && length(var.vpc.security_group_ids) > 0)
    error_message = "vpc needs at least one subnet ID and one security group ID."
  }
  validation {
    condition = var.vpc == null ? true : (
      alltrue([for s in var.vpc.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) &&
      alltrue([for s in var.vpc.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    )
    error_message = "vpc.subnet_ids must look like subnet-0123456789abcdef0 and vpc.security_group_ids like sg-0123456789abcdef0."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the function log group in days. Never-expire (0) is not accepted."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for the log group. Its key policy must allow logs.<region>.amazonaws.com."
  validation {
    condition     = var.log_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (key/<id>), not an alias."
  }
}

variable "log_format" {
  type        = string
  default     = "Text"
  description = "Text or JSON."
  validation {
    condition     = contains(["Text", "JSON"], var.log_format)
    error_message = "log_format must be Text or JSON."
  }
}

variable "permissions" {
  type = map(object({
    principal      = string
    source_arn     = string
    source_account = optional(string)
    action         = optional(string, "lambda:InvokeFunction")
  }))
  default     = {}
  nullable    = false
  description = "Statement id => who may invoke the function. principal is an AWS service (*.amazonaws.com); source_arn is required, so a service is never allowed to invoke from every resource; s3.amazonaws.com also needs source_account because a bucket ARN has no account ID (confused deputy)."
  validation {
    condition     = alltrue([for k in keys(var.permissions) : can(regex("^[A-Za-z0-9_-]{1,100}$", k))])
    error_message = "Keys are statement ids: 1-100 chars of letters, digits, _ or -."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", p.principal))])
    error_message = "principal must be an AWS service principal such as events.amazonaws.com; no wildcards, accounts or other domains."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:[^*\\s]\\S*$", p.source_arn))])
    error_message = "source_arn is required and must be an ARN that does not start its resource part with a wildcard."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : p.source_account == null ? true : can(regex("^[0-9]{12}$", p.source_account))])
    error_message = "source_account must be a 12-digit AWS account ID."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : p.principal != "s3.amazonaws.com" || p.source_account != null])
    error_message = "s3.amazonaws.com needs source_account: a bucket ARN has no account ID, so without it any account's bucket with that name could invoke the function."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^lambda:[A-Za-z]+$", p.action))])
    error_message = "action must be a single lambda: action such as lambda:InvokeFunction; no wildcards."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the function and its log group. Name is added by the module."
}
