variable "name" {
  type        = string
  description = "instance 名稱，也是 `Name` tag，以及告警與資料碟名稱的前綴。2–63 字元，限小寫英數字與連字號，字母開頭。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "subnet_id" {
  type        = string
  description = "放 instance 的 private subnet（`subnet-…` 格式）。instance 不會拿到 public IP。"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    error_message = "subnet_id must look like subnet-0123456789abcdef0."
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
  description = "instance profile 名稱，1–128 字元，要帶 SSM Session Manager 權限；沒有 SSH key。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.instance_profile_name))
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or +=,.@_-."
  }
}

variable "instance_type" {
  type        = string
  description = "instance type，例如 `t4g.small`，必須跟 `architecture` 搭配：Graviton 家族（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like t4g.small."
  }
  # Graviton family names carry a g after the generation digit (t4g, c6gn, is4gen). g4dn and m7i-flex do not match. The legacy a1 family is arm64 but is not recognised.
  validation {
    condition     = !contains(["arm64", "x86_64"], var.architecture) || !can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type)) || (can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.instance_type)) == (var.architecture == "arm64"))
    error_message = "instance_type does not match architecture: Graviton families (t4g, m7g, c6gn, ...) need arm64, all others need x86_64."
  }
}

variable "architecture" {
  type        = string
  default     = "arm64"
  description = "`arm64` 或 `x86_64`。`ami_id` 為 `null` 時依這個值找 Amazon Linux 2023 AMI；給了 `ami_id` 也要一致。"
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "ami_id" {
  type        = string
  default     = null
  description = "要啟動的 AMI（`ami-…` 格式）；`null` 時用 data source 找依 `architecture` 的最新 Amazon Linux 2023。"
  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be null or look like ami-0123456789abcdef0."
  }
}

variable "root_volume" {
  type = object({
    size        = optional(number, 20)
    kms_key_arn = optional(string)
  })
  default     = {}
  description = "root volume，一律是加密的 gp3。欄位：`size`（GiB，8–16384 的整數，預設 `20`）、`kms_key_arn`（KMS key ARN，不收 alias；預設 `null`，用帳號預設的 EBS key）。"
  validation {
    condition     = var.root_volume.size == floor(var.root_volume.size) && var.root_volume.size >= 8 && var.root_volume.size <= 16384
    error_message = "root_volume.size must be a whole number of GiB from 8 to 16384."
  }
  validation {
    condition     = var.root_volume.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.root_volume.kms_key_arn))
    error_message = "root_volume.kms_key_arn must be null or a KMS key ARN (not an alias)."
  }
}

variable "ebs_volumes" {
  type = map(object({
    device_name = string
    size        = number
    type        = optional(string, "gp3")
    kms_key_arn = optional(string)
  }))
  default     = {}
  description = "額外的資料碟，key（小寫英數字與連字號，字母開頭，最多 41 字元）對應一顆 volume，一律加密，建在 instance 所在的 AZ。欄位：`device_name`（必填，`/dev/sdf`–`/dev/sdp` 或 `/dev/xvdf`–`/dev/xvdp`，不可重複）、`size`（必填，GiB，1–16384 的整數）、`type`（預設 `gp3`，可為 `gp3`、`gp2`、`io1`、`io2`、`st1`、`sc1`）、`kms_key_arn`（預設 `null`，用帳號預設的 EBS key；不收 alias）。"
  validation {
    condition     = alltrue([for k, v in var.ebs_volumes : can(regex("^[a-z][a-z0-9-]{0,40}$", k))])
    error_message = "ebs_volumes keys must be lowercase letters, digits or hyphens, starting with a letter."
  }
  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : can(regex("^/dev/(sd[f-p]|xvd[f-p])$", v.device_name))])
    error_message = "device_name must be /dev/sdf to /dev/sdp (or /dev/xvdf to /dev/xvdp); /dev/sda1 is the root device."
  }
  validation {
    condition     = length(distinct([for v in values(var.ebs_volumes) : v.device_name])) == length(var.ebs_volumes)
    error_message = "Each data volume needs its own device_name."
  }
  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.size == floor(v.size) && v.size >= 1 && v.size <= 16384])
    error_message = "Data volume size must be a whole number of GiB from 1 to 16384."
  }
  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], v.type)])
    error_message = "Data volume type must be one of gp3, gp2, io1, io2, st1, sc1."
  }
  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", v.kms_key_arn))])
    error_message = "Data volume kms_key_arn must be null or a KMS key ARN (not an alias)."
  }
}

variable "user_data" {
  type        = string
  default     = null
  description = "第一次開機執行的 cloud-init 或 shell script，上限 16384 bytes。以明文存在 state，也看得到在 EC2 console，不要放 secret：看起來像 secret 的明文值或私鑰會被擋下。"
  validation {
    condition     = var.user_data == null ? true : !can(regex("(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|(SECRET|PASSWORD|PASSWD|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[A-Z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"'$({])", var.user_data))
    error_message = "user_data must not assign a literal value to a secret-like name (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL) or embed a private key. It is stored in plain text; fetch secrets at boot instead, for example PASSWORD=$(aws secretsmanager get-secret-value ...)."
  }
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition     = var.user_data == null || length(base64encode(var.user_data)) <= 21848
    error_message = "user_data must be at most 16384 bytes (the EC2 limit)."
  }
}

variable "disable_api_termination" {
  type        = bool
  default     = true
  description = "終止保護。`terraform destroy` 前要先關掉。"
}

variable "sns_topic_arns" {
  type        = list(string)
  default     = []
  description = "`StatusCheckFailed_System` 告警（alarm 與 OK）的 SNS topic ARN，最多 4 個，因為告警還帶一個 recover action。空 list 時不建告警；這是 repo「告警必須有 SNS topic」慣例的唯一例外（D16）。"
  validation {
    condition     = alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", a))])
    error_message = "sns_topic_arns must be SNS topic ARNs."
  }
  validation {
    condition     = length(var.sns_topic_arns) <= 4
    error_message = "At most 4 SNS topics: a CloudWatch alarm allows 5 actions and one is the EC2 recover action."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "instance、volume 與告警的 tag；`Name` 由 module 加上。"
}
