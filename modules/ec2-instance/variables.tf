# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "name" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Instance name; also its Name tag and the prefix of the alarm and data volume names."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "subnet_id" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Private subnet for the instance. The instance never gets a public IP."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "subnet_id must look like subnet-0123456789abcdef0."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "security_group_ids" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = list(string)
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Security groups for the instance, at least one."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = length(var.security_group_ids) > 0
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "Give at least one security group ID."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "instance_profile_name" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Instance profile for the instance. It should carry the SSM Session Manager permissions; there is no SSH key."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.instance_profile_name))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or +=,.@_-."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "instance_type" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Instance type. Must match architecture: Graviton families (t4g, m7g, c6gn, ...) are arm64, the rest x86_64."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "instance_type must look like t4g.small."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  # Graviton family names carry a g after the generation digit (t4g, c6gn, is4gen). g4dn and m7i-flex do not match. The legacy a1 family is arm64 but is not recognised.
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = !contains(["arm64", "x86_64"], var.architecture) || !can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type)) || (can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.instance_type)) == (var.architecture == "arm64"))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "instance_type does not match architecture: Graviton families (t4g, m7g, c6gn, ...) need arm64, all others need x86_64."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "architecture" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = "arm64"
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "arm64 or x86_64. Selects the Amazon Linux 2023 AMI when ami_id is null."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = contains(["arm64", "x86_64"], var.architecture)
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "architecture must be arm64 or x86_64."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "ami_id" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = null
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "AMI to launch. When null, the latest Amazon Linux 2023 for architecture is looked up with a data source."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "ami_id must be null or look like ami-0123456789abcdef0."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "root_volume" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = object({
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    size = optional(number, 20)
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    kms_key_arn = optional(string)
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  })
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = {}
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Root volume (always encrypted gp3). size is in GiB; kms_key_arn null uses the account default EBS key."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = var.root_volume.size == floor(var.root_volume.size) && var.root_volume.size >= 8 && var.root_volume.size <= 16384
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "root_volume.size must be a whole number of GiB from 8 to 16384."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = var.root_volume.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.root_volume.kms_key_arn))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "root_volume.kms_key_arn must be null or a KMS key ARN (not an alias)."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "ebs_volumes" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = map(object({
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    device_name = string
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    size = number
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    type = optional(string, "gp3")
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    kms_key_arn = optional(string)
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }))
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = {}
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Extra data volumes by key, always encrypted, created in the instance's AZ and attached at device_name. kms_key_arn null uses the account default EBS key."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for k, v in var.ebs_volumes : can(regex("^[a-z][a-z0-9-]{0,40}$", k))])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "ebs_volumes keys must be lowercase letters, digits or hyphens, starting with a letter."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for v in values(var.ebs_volumes) : can(regex("^/dev/(sd[f-p]|xvd[f-p])$", v.device_name))])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "device_name must be /dev/sdf to /dev/sdp (or /dev/xvdf to /dev/xvdp); /dev/sda1 is the root device."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = length(distinct([for v in values(var.ebs_volumes) : v.device_name])) == length(var.ebs_volumes)
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "Each data volume needs its own device_name."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for v in values(var.ebs_volumes) : v.size == floor(v.size) && v.size >= 1 && v.size <= 16384])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "Data volume size must be a whole number of GiB from 1 to 16384."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for v in values(var.ebs_volumes) : contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], v.type)])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "Data volume type must be one of gp3, gp2, io1, io2, st1, sc1."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for v in values(var.ebs_volumes) : v.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", v.kms_key_arn))])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "Data volume kms_key_arn must be null or a KMS key ARN (not an alias)."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "user_data" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = string
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = null
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Cloud-init or shell script run at first boot. Stored as plain text in the state file and visible in the EC2 console: never put secrets in it. Text that looks like a secret is rejected."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = var.user_data == null ? true : !can(regex("(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|(SECRET|PASSWORD|PASSWD|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[A-Z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^[:space:]\"'$({])", var.user_data))
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "user_data must not assign a literal value to a secret-like name (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL) or embed a private key. It is stored in plain text; fetch secrets at boot instead, for example PASSWORD=$(aws secretsmanager get-secret-value ...)."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = var.user_data == null || length(base64encode(var.user_data)) <= 21848
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "user_data must be at most 16384 bytes (the EC2 limit)."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "disable_api_termination" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = bool
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = true
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Termination protection. Turn it off before terraform destroy."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "sns_topic_arns" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = list(string)
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = []
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "SNS topics for the StatusCheckFailed_System alarm (alarm and OK). Empty creates no alarm; this is the one exception to the repo rule that alarms need an SNS topic (D16). At most 4, since the alarm also carries the recover action."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", a))])
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "sns_topic_arns must be SNS topic ARNs."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  validation {
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    condition = length(var.sns_topic_arns) <= 4
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
    error_message = "At most 4 SNS topics: a CloudWatch alarm allows 5 actions and one is the EC2 recover action."
    # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  }
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.

# 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
variable "tags" {
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  type = map(string)
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  default = {}
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
  description = "Tags for the instance, its volumes and the alarm. Name is added by the module."
  # 21848 is the base64 length of 16384 bytes, so the limit counts bytes, not characters.
}
