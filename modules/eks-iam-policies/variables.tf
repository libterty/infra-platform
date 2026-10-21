variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Used in ARNs and in the cluster tag conditions of the Karpenter policy."
  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 chars of letters, digits, hyphen or underscore, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the cluster, for example ap-northeast-1."
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like ap-northeast-1."
  }
}

variable "account_id" {
  type        = string
  description = "12-digit AWS account ID of the cluster."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit account ID."
  }
}

variable "partition" {
  type        = string
  default     = "aws"
  description = "AWS partition used in the ARNs this module builds. The LB Controller policy is the official file and is not affected."
  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}

variable "load_balancer_controller_version" {
  type        = string
  default     = "3.6.0"
  description = "AWS Load Balancer Controller version whose official IAM policy is returned. Only the versions vendored in policies/aws-load-balancer-controller/ are accepted."
  validation {
    condition     = contains(keys(local.load_balancer_controller_policies), var.load_balancer_controller_version)
    error_message = "load_balancer_controller_version must be one of the vendored versions (see policies/aws-load-balancer-controller/)."
  }
}

variable "karpenter" {
  type = object({
    version                 = optional(string, "1.15.0")
    node_role_arn           = string
    interruption_queue_name = string
  })
  default     = null
  description = "Karpenter controller policy settings; null returns no Karpenter policy. node_role_arn is the only role the controller may pass to EC2; interruption_queue_name is the SQS queue it may read. Only the versions in local.karpenter_supported_versions are accepted."
  validation {
    condition     = var.karpenter == null ? true : contains(local.karpenter_supported_versions, var.karpenter.version)
    error_message = "karpenter.version must be one of the supported versions (see locals.tf and policies/karpenter/)."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^arn:(aws|aws-cn|aws-us-gov):iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.karpenter.node_role_arn))
    error_message = "karpenter.node_role_arn must be an IAM role ARN with no wildcard."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[A-Za-z0-9_-]{1,80}$", var.karpenter.interruption_queue_name))
    error_message = "karpenter.interruption_queue_name must be 1-80 chars of letters, digits, hyphen or underscore."
  }
}
