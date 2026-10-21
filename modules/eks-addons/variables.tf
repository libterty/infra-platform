variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Passed to the AWS Load Balancer Controller and to Karpenter."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 chars of letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the cluster. The AWS Load Balancer Controller cannot read it from IMDS when the hop limit is 1, so it is passed explicitly."
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like ap-northeast-1."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID of the cluster. The AWS Load Balancer Controller cannot read it from IMDS when the hop limit is 1, so it is passed explicitly."
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "load_balancer_controller" {
  type = object({
    chart_version   = optional(string, "3.6.0")
    service_account = optional(string, "aws-load-balancer-controller")
    replica_count   = optional(number, 2)
    values          = optional(any, {})
  })
  default     = null
  description = <<-EOT
    AWS Load Balancer Controller release in kube-system; null installs nothing. The IAM role is not created here:
    the Pod Identity association for the service account lives in eks-cluster. values is merged into the chart
    values; the inputs above win on conflict.
  EOT

  validation {
    condition     = var.load_balancer_controller == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.load_balancer_controller.chart_version))
    error_message = "load_balancer_controller.chart_version must be an exact version such as 3.6.0."
  }
  validation {
    condition     = var.load_balancer_controller == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.load_balancer_controller.service_account))
    error_message = "load_balancer_controller.service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }
  validation {
    condition     = var.load_balancer_controller == null ? true : (var.load_balancer_controller.replica_count >= 1 && var.load_balancer_controller.replica_count == floor(var.load_balancer_controller.replica_count))
    error_message = "load_balancer_controller.replica_count must be an integer of at least 1."
  }
  validation {
    condition     = var.load_balancer_controller == null ? true : try(length(keys(var.load_balancer_controller.values)) >= 0, false)
    error_message = "load_balancer_controller.values must be an object."
  }
}

variable "karpenter" {
  type = object({
    chart_version           = optional(string, "1.15.0")
    namespace               = optional(string, "kube-system")
    service_account         = optional(string, "karpenter")
    interruption_queue_name = string
    values                  = optional(any, {})
    default_node_class = optional(object({
      node_role_name               = string
      subnet_discovery_tag         = map(string)
      security_group_discovery_tag = map(string)
      ami_alias                    = optional(string, "al2023@latest")
    }))
    default_node_pool = optional(object({
      cpu_limit      = optional(number, 100)
      capacity_types = optional(list(string), ["on-demand"])
    }))
  })
  default     = null
  description = <<-EOT
    Karpenter controller release; null installs nothing. interruption_queue_name is the eks-cluster output
    karpenter_interruption_queue_name. The default NodePool and EC2NodeClass (local chart karpenter-defaults) are
    installed only when both default_node_class and default_node_pool are set; use default_node_pool = {} for the
    default limits. The subnet and security group discovery tags are tag maps, for example
    { "karpenter.sh/discovery" = "alpha-dev" }.
  EOT

  validation {
    condition     = var.karpenter == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.karpenter.chart_version))
    error_message = "karpenter.chart_version must be an exact version such as 1.15.0."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.karpenter.namespace))
    error_message = "karpenter.namespace must be an RFC 1123 label: at most 63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.karpenter.service_account))
    error_message = "karpenter.service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[A-Za-z0-9_-]{1,80}$", var.karpenter.interruption_queue_name))
    error_message = "karpenter.interruption_queue_name must be an SQS queue name (1-80 letters, digits, hyphens or underscores), not a URL or ARN."
  }
  validation {
    condition     = var.karpenter == null ? true : (var.karpenter.default_node_class == null ? true : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.karpenter.default_node_class.node_role_name)))
    error_message = "karpenter.default_node_class.node_role_name must be an IAM role name (not an ARN)."
  }
  validation {
    condition = var.karpenter == null ? true : (var.karpenter.default_node_class == null ? true : (
      length(var.karpenter.default_node_class.subnet_discovery_tag) > 0 &&
      length(var.karpenter.default_node_class.security_group_discovery_tag) > 0 &&
      alltrue([for k in concat(keys(var.karpenter.default_node_class.subnet_discovery_tag), keys(var.karpenter.default_node_class.security_group_discovery_tag)) : length(k) > 0])
    ))
    error_message = "karpenter.default_node_class discovery tags must each have at least one tag with a non-empty key."
  }
  validation {
    # Only AL2023: the EC2NodeClass maps the root volume at /dev/xvda, which Bottlerocket does not use.
    condition     = var.karpenter == null ? true : (var.karpenter.default_node_class == null ? true : can(regex("^al2023@[A-Za-z0-9.]{1,22}$", var.karpenter.default_node_class.ami_alias)))
    error_message = "karpenter.default_node_class.ami_alias must be al2023@latest or al2023@<version> (at most 30 characters)."
  }
  validation {
    condition     = var.karpenter == null ? true : try(length(keys(var.karpenter.values)) >= 0, false)
    error_message = "karpenter.values must be an object."
  }
  validation {
    condition     = var.karpenter == null ? true : (var.karpenter.default_node_pool == null ? true : var.karpenter.default_node_pool.cpu_limit > 0)
    error_message = "karpenter.default_node_pool.cpu_limit must be greater than 0."
  }
  validation {
    condition = var.karpenter == null ? true : (var.karpenter.default_node_pool == null ? true : (
      length(var.karpenter.default_node_pool.capacity_types) > 0 &&
      length(distinct(var.karpenter.default_node_pool.capacity_types)) == length(var.karpenter.default_node_pool.capacity_types) &&
      alltrue([for t in var.karpenter.default_node_pool.capacity_types : contains(["on-demand", "spot"], t)])
    ))
    error_message = "karpenter.default_node_pool.capacity_types must be a non-empty list without duplicates of on-demand and spot."
  }
}

variable "argo_rollouts" {
  type = object({
    chart_version = optional(string, "2.43.8")
    namespace     = optional(string, "argo-rollouts")
    values        = optional(any, {})
  })
  default     = null
  description = "Argo Rollouts release; null installs nothing. values is merged into the chart values. CloudWatch analysis needs a role and a Pod Identity association from eks-cluster."

  validation {
    condition     = var.argo_rollouts == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.argo_rollouts.chart_version))
    error_message = "argo_rollouts.chart_version must be an exact version such as 2.43.8."
  }
  validation {
    condition     = var.argo_rollouts == null ? true : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.argo_rollouts.namespace))
    error_message = "argo_rollouts.namespace must be an RFC 1123 label: at most 63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
  validation {
    condition     = var.argo_rollouts == null ? true : try(length(keys(var.argo_rollouts.values)) >= 0, false)
    error_message = "argo_rollouts.values must be an object."
  }
}

variable "app_namespaces" {
  type = map(object({
    labels = optional(map(string), {})
  }))
  default     = {}
  description = "Application namespaces to create through the local chart app-namespaces. A CI role with the Edit access policy cannot create namespaces, so they are created here. Empty installs nothing."

  validation {
    condition     = alltrue([for name, _ in var.app_namespaces : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", name))])
    error_message = "app_namespaces keys must be RFC 1123 labels: at most 63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
  validation {
    condition     = alltrue([for name, _ in var.app_namespaces : name != "default" && !startswith(name, "kube-")])
    error_message = "app_namespaces must not contain default or a kube- prefixed name: those are reserved and already exist."
  }
}

variable "chart_repository_overrides" {
  type        = map(string)
  default     = {}
  description = "Chart repository URL per component, for example an ECR mirror of a private cluster. Keys: load_balancer_controller, karpenter, argo_rollouts."

  validation {
    condition     = alltrue([for k, _ in var.chart_repository_overrides : contains(["load_balancer_controller", "karpenter", "argo_rollouts"], k)])
    error_message = "chart_repository_overrides keys must be load_balancer_controller, karpenter or argo_rollouts."
  }
  validation {
    condition     = alltrue([for _, v in var.chart_repository_overrides : can(regex("^(https://|oci://)[^\\s]+$", v))])
    error_message = "chart_repository_overrides values must be https:// or oci:// URLs."
  }
}
