variable "name" {
  type        = string
  description = "Auto Scaling group 與 launch template 名稱，也是每台 instance 的 `Name` tag。2–63 字元，限小寫英數字與連字號，字母開頭。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "ASG 啟動 instance 的 private subnet（`subnet-…` 格式），至少一個。instance 不會拿到 public IP。"
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
  description = "instance 的 security group（`sg-…` 格式），至少一個。"
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
  description = "instance 的 instance profile 名稱，1–128 字元（例如帶 SSM Session Manager 權限）。沒有 SSH key。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.instance_profile_name))
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or +=,.@_-."
  }
}

variable "instance_types" {
  type        = list(string)
  description = "instance type 清單，至少一個（例如 `t4g.small`），第一個是主要型號；其餘只當 spot override，所以只有設了 `spot` 才用得到。全部都要跟 `architecture` 搭配：Graviton 家族（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。"
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
  description = "`arm64` 或 `x86_64`，決定用哪個 Amazon Linux 2023 AMI。"
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "ami_id" {
  type        = string
  default     = null
  description = "instance 的 AMI（`ami-…` 格式）；`null` 時找依 `architecture` 的最新 Amazon Linux 2023，出了新 AMI 會透過 instance refresh 換上。"
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
  description = "root volume，一律是加密的 gp3。欄位：`size`（GiB，8–16384 的整數，預設 `20`；Amazon Linux 2023 快照是 8 GiB，所以最小 `8`）、`kms_key_arn`（KMS key ARN，不收 alias；預設 `null`，用帳號預設的 EBS key）。"
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
  description = "第一次開機執行的 shell script。以明文存在 state 與 launch template，能讀 launch template 的人都看得到，不要放 secret，改在開機時從 Secrets Manager 讀。看起來像 secret 的明文值或私鑰會被擋下。"
  # Same word list as lambda-function environment names, plus a hyphen form for flags such as x-api-key; matching is case-insensitive.
  validation {
    condition     = var.user_data == null ? true : !can(regex("(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|(SECRET|PASSWORD|PASSWD|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[A-Z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"'$({])", var.user_data))
    error_message = "user_data must not assign a literal value to a secret-like name (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL) or embed a private key. It is stored in plain text; fetch secrets at boot instead, for example PASSWORD=$(aws secretsmanager get-secret-value ...)."
  }
}

variable "min_size" {
  type        = number
  description = "最少台數，不小於 0 的整數。"
  validation {
    condition     = var.min_size == floor(var.min_size) && var.min_size >= 0
    error_message = "min_size must be a whole number, 0 or more."
  }
}

variable "max_size" {
  type        = number
  description = "最多台數，不小於 0 的整數。"
  validation {
    condition     = var.max_size == floor(var.max_size) && var.max_size >= 0
    error_message = "max_size must be a whole number, 0 or more."
  }
}

variable "desired_capacity" {
  type        = number
  description = "建立時的台數，整數，`min_size <= desired_capacity <= max_size`。只在建立 ASG 時使用，之後的變更會被忽略，數量交給 scaling policy。"
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
  description = "搭配 spot 的 mixed instances policy；`null` 時全部 on-demand，不建 `mixed_instances_policy`。欄位：`on_demand_base_capacity`（不小於 0 的整數，預設 `1`）、`on_demand_percentage_above_base`（0–100，預設 `0`）、`allocation_strategy`（`price-capacity-optimized`（預設）、`capacity-optimized`、`capacity-optimized-prioritized`、`lowest-price`）。用預設值時保留 1 台 on-demand，其餘都是 spot。"
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
  description = "要把 instance 註冊進去的 target group ARN（ALB `target_type = instance`）。非空時 health check 類型改成 `ELB`。"
  validation {
    condition     = alltrue([for a in var.target_group_arns : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/", a))])
    error_message = "target_group_arns must be target group ARNs."
  }
}

variable "health_check_grace_period" {
  type        = number
  default     = 300
  description = "instance 啟動後幾秒才開始算 health check，不小於 0 的整數。要比開機加 `user_data` 跑完的時間長。"
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
  description = "launch template 變更（例如新 AMI 或 `user_data`）時啟動的 rolling instance refresh。欄位：`min_healthy_percentage`（0–100，預設 `90`）。"
  validation {
    condition     = var.instance_refresh.min_healthy_percentage >= 0 && var.instance_refresh.min_healthy_percentage <= 100
    error_message = "instance_refresh.min_healthy_percentage must be between 0 and 100."
  }
}

variable "cpu_target" {
  type        = number
  default     = null
  description = "target tracking policy（`ASGAverageCPUUtilization`）的平均 CPU 目標百分比，大於 0、最多 100；`null` 時不建 scaling policy。"
  validation {
    condition     = var.cpu_target == null ? true : (var.cpu_target > 0 && var.cpu_target <= 100)
    error_message = "cpu_target must be above 0 and at most 100."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "launch template 與每台 instance 的 tag（`propagate_at_launch`）；`Name` 由 module 加上。"
}
