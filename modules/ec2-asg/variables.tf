variable "name" {
  type        = string
  description = "Auto Scaling group and launch template name; also the Name tag of every instance."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the group launches into, at least one. Instances never get a public IP."
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Give at least one subnet ID."
  }
  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "subnet_ids must look like subnet-0123456789abcdef0."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups for the instances, at least one."
  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Give at least one security group ID."
  }
  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
  }
}

variable "instance_profile_name" {
  type        = string
  description = "Instance profile for the instances (for example SSM Session Manager permissions). There is no SSH key."
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.instance_profile_name))
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or +=,.@_-."
  }
}

variable "instance_types" {
  type        = list(string)
  description = "Instance types; the first is the primary type. The others are only used as spot overrides, so they matter only when spot is set. All must match architecture: Graviton families (t4g, m7g, c6gn, ...) are arm64, the rest x86_64."
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "Give at least one instance type."
  }
  validation {
    condition     = alltrue([for t in var.instance_types : can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", t))])
    error_message = "instance_types must look like t4g.small."
  }
  # Graviton family names carry a g after the generation digit (t4g, c6gn, is4gen). g4dn and m7i-flex do not match. The legacy a1 family is arm64 but is not recognised.
  validation {
    condition = !contains(["arm64", "x86_64"], var.architecture) || alltrue([
      for t in var.instance_types :
      !can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", t)) || (can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", t)) == (var.architecture == "arm64"))
    ])
    error_message = "Every instance type must match architecture: Graviton families (t4g, m7g, c6gn, ...) need arm64, all others need x86_64."
  }
}

variable "architecture" {
  type        = string
  default     = "arm64"
  description = "arm64 or x86_64. Selects the Amazon Linux 2023 AMI."
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "ami_id" {
  type        = string
  default     = null
  description = "AMI for the instances. null looks up the latest Amazon Linux 2023 for architecture; a new AMI then reaches the group through instance refresh."
  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must look like ami-0123456789abcdef0."
  }
}

variable "root_volume" {
  type = object({
    size        = optional(number, 20)
    kms_key_arn = optional(string)
  })
  default     = {}
  nullable    = false
  description = "Root volume, always an encrypted gp3. size is GiB (the Amazon Linux 2023 snapshot is 8 GiB, so that is the minimum). kms_key_arn null uses the account default EBS key."
  validation {
    condition     = var.root_volume.size == floor(var.root_volume.size) && var.root_volume.size >= 8 && var.root_volume.size <= 16384
    error_message = "root_volume.size must be a whole number of GiB from 8 to 16384."
  }
  validation {
    condition     = var.root_volume.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.root_volume.kms_key_arn))
    error_message = "root_volume.kms_key_arn must be a KMS key ARN (not an alias)."
  }
}

variable "user_data" {
  type        = string
  default     = null
  description = "Shell script run at first boot. It is stored in state and in the launch template in plain text and anyone who can read the launch template can read it, so never put secrets here; fetch them from Secrets Manager at boot. Text that looks like a secret is rejected."
  # Same word list as lambda-function environment names, plus a hyphen form for flags such as x-api-key; matching is case-insensitive.
  validation {
    condition     = var.user_data == null ? true : !can(regex("(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|(SECRET|PASSWORD|PASSWD|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[A-Z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"'$({])", var.user_data))
    error_message = "user_data must not assign a literal value to a secret-like name (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL) or embed a private key. It is stored in plain text; fetch secrets at boot instead, for example PASSWORD=$(aws secretsmanager get-secret-value ...)."
  }
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances."
  validation {
    condition     = var.min_size == floor(var.min_size) && var.min_size >= 0
    error_message = "min_size must be a whole number, 0 or more."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances."
  validation {
    condition     = var.max_size == floor(var.max_size) && var.max_size >= 0
    error_message = "max_size must be a whole number, 0 or more."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Initial number of instances. Only used when the group is created; later changes are ignored so scaling policies own the count."
  validation {
    condition     = var.desired_capacity == floor(var.desired_capacity) && var.min_size <= var.desired_capacity && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be a whole number with min_size <= desired_capacity <= max_size."
  }
}

variable "spot" {
  type = object({
    on_demand_base_capacity         = optional(number, 1)
    on_demand_percentage_above_base = optional(number, 0)
    allocation_strategy             = optional(string, "price-capacity-optimized")
  })
  default     = null
  description = "Mixed instances policy with spot. null keeps the group all on-demand and creates no mixed_instances_policy. With the defaults one on-demand instance is the base and every instance above it is spot."
  validation {
    condition = var.spot == null ? true : (
      var.spot.on_demand_base_capacity == floor(var.spot.on_demand_base_capacity) &&
      var.spot.on_demand_base_capacity >= 0
    )
    error_message = "spot.on_demand_base_capacity must be a whole number, 0 or more."
  }
  validation {
    condition = var.spot == null ? true : (
      var.spot.on_demand_percentage_above_base >= 0 && var.spot.on_demand_percentage_above_base <= 100
    )
    error_message = "spot.on_demand_percentage_above_base must be between 0 and 100."
  }
  validation {
    condition = var.spot == null ? true : contains(
      ["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"],
      var.spot.allocation_strategy
    )
    error_message = "spot.allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }
}

variable "target_group_arns" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Target groups to register instances in (alb target_type = instance). Non-empty switches the health check type to ELB."
  validation {
    condition     = alltrue([for a in var.target_group_arns : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/", a))])
    error_message = "target_group_arns must be target group ARNs."
  }
}

variable "health_check_grace_period" {
  type        = number
  default     = 300
  description = "Seconds after launch before health checks count. Set it longer than the boot and user_data time."
  validation {
    condition     = var.health_check_grace_period == floor(var.health_check_grace_period) && var.health_check_grace_period >= 0
    error_message = "health_check_grace_period must be a whole number of seconds, 0 or more."
  }
}

variable "instance_refresh" {
  type = object({
    min_healthy_percentage = optional(number, 90)
  })
  default     = {}
  nullable    = false
  description = "Rolling instance refresh started when the launch template changes (for example a new AMI or user_data)."
  validation {
    condition     = var.instance_refresh.min_healthy_percentage >= 0 && var.instance_refresh.min_healthy_percentage <= 100
    error_message = "instance_refresh.min_healthy_percentage must be between 0 and 100."
  }
}

variable "cpu_target" {
  type        = number
  default     = null
  description = "Target average CPU percent for a target tracking policy (ASGAverageCPUUtilization). null creates no scaling policy."
  validation {
    condition     = var.cpu_target == null ? true : (var.cpu_target > 0 && var.cpu_target <= 100)
    error_message = "cpu_target must be above 0 and at most 100."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the launch template and for every instance (propagate_at_launch). Name is added by the module."
}
