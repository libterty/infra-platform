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
    chart_version   = optional(string, "3.6.1")
    service_account = optional(string, "aws-load-balancer-controller")
    replica_count   = optional(number, 2)
    values          = optional(any, {})
  })
  default     = null
  description = <<-EOT
    AWS Load Balancer Controller release in kube-system; null installs nothing. The IAM role is not created here:
    the Pod Identity association for the service account lives in eks-cluster. values is merged into the chart
    values; the inputs above win on conflict. With auto_mode set, enableServiceMutatorWebhook and
    createIngressClassResource are forced to false (Auto Mode owns Service and Ingress handling) and cannot be
    turned back on through values.
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

variable "auto_mode" {
  type = object({
    node_role_name = string
    node_classes = map(object({
      subnet_selector_terms             = list(object({ id = optional(string), tags = optional(map(string)) }))
      security_group_selector_terms     = list(object({ id = optional(string), tags = optional(map(string)) }))
      pod_subnet_selector_terms         = optional(list(object({ id = optional(string), tags = optional(map(string)) })), [])
      pod_security_group_selector_terms = optional(list(object({ id = optional(string), tags = optional(map(string)) })), [])
      network_policy                    = optional(string, "DefaultDeny")
      network_policy_event_logs         = optional(string, "Disabled")
    }))
    node_pools = map(object({
      node_class          = string
      taints              = optional(list(object({ key = string, value = optional(string), effect = string })), [])
      labels              = optional(map(string), {})
      capacity_types      = optional(list(string), ["on-demand"])
      instance_categories = optional(list(string), [])
      architectures       = optional(list(string), ["amd64"])
      cpu_limit           = optional(number, 100)
    }))
  })
  default     = null
  description = <<-EOT
    EKS Auto Mode node classes and node pools (local chart auto-mode-nodes: eks.amazonaws.com/v1 NodeClass and
    karpenter.sh/v1 NodePool); null installs nothing. node_role_name is the IAM role name (not ARN) of the node role
    that eks-cluster gave an EC2 access entry. A selector term is { id = "..." } or { tags = { ... } }, exactly one.
    pod_subnet_selector_terms and pod_security_group_selector_terms must be set together: Pod security groups are a
    node class setting and every Pod of the class shares them. network_policy is DefaultDeny (default) or DefaultAllow;
    network_policy_event_logs is Enabled or Disabled (default). A node class must not be named default.
    Setting auto_mode also forces enableServiceMutatorWebhook and createIngressClassResource to false on the
    AWS Load Balancer Controller.
  EOT

  validation {
    condition     = var.auto_mode == null ? true : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.auto_mode.node_role_name))
    error_message = "auto_mode.node_role_name must be an IAM role name (not an ARN)."
  }
  validation {
    condition     = var.auto_mode == null ? true : (length(var.auto_mode.node_classes) > 0 && length(var.auto_mode.node_pools) > 0)
    error_message = "auto_mode needs at least one node class and one node pool."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for name, _ in var.auto_mode.node_classes : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", name)) && name != "default"])
    error_message = "auto_mode.node_classes keys must be RFC 1123 labels and must not be named default (reserved by Auto Mode)."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for name, _ in var.auto_mode.node_pools : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", name))])
    error_message = "auto_mode.node_pools keys must be RFC 1123 labels."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for _, p in var.auto_mode.node_pools : contains(keys(var.auto_mode.node_classes), p.node_class)])
    error_message = "Every auto_mode.node_pools node_class must be a key of auto_mode.node_classes."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for _, c in var.auto_mode.node_classes : length(c.subnet_selector_terms) > 0 && length(c.security_group_selector_terms) > 0
    ])
    error_message = "Every auto_mode node class needs at least one subnet selector term and one security group selector term."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for _, c in var.auto_mode.node_classes : (length(c.pod_subnet_selector_terms) > 0) == (length(c.pod_security_group_selector_terms) > 0)
    ])
    error_message = "pod_subnet_selector_terms and pod_security_group_selector_terms must be set together or both left empty."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for t in flatten([for _, c in var.auto_mode.node_classes : concat(c.subnet_selector_terms, c.security_group_selector_terms, c.pod_subnet_selector_terms, c.pod_security_group_selector_terms)]) :
      (t.id != null) != (t.tags != null && length(coalesce(t.tags, {})) > 0)
    ])
    error_message = "Every selector term must have exactly one of id or a non-empty tags map."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for t in flatten([for _, c in var.auto_mode.node_classes : concat(c.subnet_selector_terms, c.pod_subnet_selector_terms)]) :
      t.id == null ? true : can(regex("^subnet-[0-9a-f]{8,17}$", t.id))
    ])
    error_message = "A subnet selector term id must look like subnet-0123456789abcdef0."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for t in flatten([for _, c in var.auto_mode.node_classes : concat(c.security_group_selector_terms, c.pod_security_group_selector_terms)]) :
      t.id == null ? true : can(regex("^sg-[0-9a-f]{8,17}$", t.id))
    ])
    error_message = "A security group selector term id must look like sg-0123456789abcdef0."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for _, c in var.auto_mode.node_classes : contains(["DefaultDeny", "DefaultAllow"], c.network_policy)])
    error_message = "auto_mode node class network_policy must be DefaultDeny or DefaultAllow."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for _, c in var.auto_mode.node_classes : contains(["Enabled", "Disabled"], c.network_policy_event_logs)])
    error_message = "auto_mode node class network_policy_event_logs must be Enabled or Disabled."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for t in flatten([for _, p in var.auto_mode.node_pools : p.taints]) : length(t.key) > 0 && contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
    ])
    error_message = "auto_mode taints need a non-empty key and an effect of NoSchedule, PreferNoSchedule or NoExecute."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for _, p in var.auto_mode.node_pools : (
        length(p.capacity_types) > 0 &&
        length(distinct(p.capacity_types)) == length(p.capacity_types) &&
        alltrue([for t in p.capacity_types : contains(["on-demand", "spot"], t)])
      )
    ])
    error_message = "auto_mode node pool capacity_types must be a non-empty list without duplicates of on-demand and spot."
  }
  validation {
    condition = var.auto_mode == null ? true : alltrue([
      for _, p in var.auto_mode.node_pools : (
        length(p.architectures) > 0 &&
        length(distinct(p.architectures)) == length(p.architectures) &&
        alltrue([for a in p.architectures : contains(["amd64", "arm64"], a)])
      )
    ])
    error_message = "auto_mode node pool architectures must be a non-empty list without duplicates of amd64 and arm64."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for _, p in var.auto_mode.node_pools : alltrue([for c in p.instance_categories : can(regex("^[a-z]{1,4}$", c))])])
    error_message = "auto_mode node pool instance_categories must be lowercase categories such as c, m, r."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for _, p in var.auto_mode.node_pools : p.cpu_limit > 0])
    error_message = "auto_mode node pool cpu_limit must be greater than 0."
  }
}

variable "network_policy" {
  type = object({
    service_cidr     = string
    api_server_cidrs = list(string)
    aws_api_cidrs    = list(string)
  })
  default     = null
  description = <<-EOT
    Turns the NetworkPolicy controller on (ConfigMap amazon-vpc-cni with enable-network-policy-controller) and installs
    the system NetworkPolicies (local chart system-network-policy) for the components this module installs; null does
    neither. The caller passes the CIDRs: service_cidr is the cluster service CIDR (DNS is its .10 address),
    api_server_cidrs are the subnets of the control plane ENIs and aws_api_cidrs are the subnets of the VPC interface
    endpoints; use ["0.0.0.0/0"] there only when AWS APIs are reached through NAT. Policies cover the AWS Load Balancer
    Controller (only its Pods in kube-system), KEDA and CloudWatch observability, each only when that component is
    installed.
  EOT

  validation {
    condition     = var.network_policy == null ? true : can(cidrhost(var.network_policy.service_cidr, 10))
    error_message = "network_policy.service_cidr must be an IPv4 CIDR with room for the .10 address, such as 172.20.0.0/16."
  }
  validation {
    condition = var.network_policy == null ? true : (
      length(var.network_policy.api_server_cidrs) > 0 &&
      alltrue([for c in var.network_policy.api_server_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    )
    error_message = "network_policy.api_server_cidrs must be a non-empty list of IPv4 CIDRs, and not 0.0.0.0/0 (that would open the API server rule to everything)."
  }
  validation {
    condition = var.network_policy == null ? true : (
      length(var.network_policy.aws_api_cidrs) > 0 &&
      alltrue([for c in var.network_policy.aws_api_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "network_policy.aws_api_cidrs must be a non-empty list of IPv4 CIDRs."
  }
}

variable "system_placement" {
  type = object({
    node_selector = optional(map(string), {})
    tolerations = optional(list(object({
      key      = optional(string)
      operator = optional(string)
      value    = optional(string)
      effect   = optional(string)
    })), [])
  })
  default     = null
  description = <<-EOT
    Node selector and tolerations for the AWS Load Balancer Controller and KEDA (the Deployments that belong on the
    system node pool); null leaves their placement alone. They are written at the top level of the chart values and win
    over the same keys in the component values. CloudWatch observability is not placed: its DaemonSets must cover every
    node, so they keep the chart default of tolerating everything.
  EOT

  validation {
    condition     = var.system_placement == null ? true : alltrue([for k, _ in var.system_placement.node_selector : length(k) > 0])
    error_message = "system_placement.node_selector keys must not be empty."
  }
  validation {
    condition = var.system_placement == null ? true : alltrue([
      for t in var.system_placement.tolerations :
      (t.effect == null ? true : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)) &&
      (t.operator == null ? true : contains(["Equal", "Exists"], t.operator))
    ])
    error_message = "system_placement toleration effect must be NoSchedule, PreferNoSchedule or NoExecute, and operator Equal or Exists."
  }
}

variable "keda" {
  type = object({
    chart_version   = optional(string, "2.21.0")
    namespace       = optional(string, "keda")
    service_account = optional(string, "keda-operator")
    values          = optional(any, {})
  })
  default     = null
  description = <<-EOT
    KEDA release (chart kedacore/keda); null installs nothing. service_account is the operator service account, which
    the Pod Identity association for the CloudWatch scaler lives on (eks-cluster). values is merged into the chart
    values; system_placement and the service account win on conflict.
  EOT

  validation {
    condition     = var.keda == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.keda.chart_version))
    error_message = "keda.chart_version must be an exact version such as 2.21.0."
  }
  validation {
    condition     = var.keda == null ? true : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.keda.namespace))
    error_message = "keda.namespace must be an RFC 1123 label: at most 63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
  validation {
    condition     = var.keda == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.keda.service_account))
    error_message = "keda.service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }
  validation {
    condition     = var.keda == null ? true : try(length(keys(var.keda.values)) >= 0, false)
    error_message = "keda.values must be an object."
  }
}

variable "cloudwatch_observability" {
  type = object({
    chart_version       = optional(string, "6.7.0")
    namespace           = optional(string, "amazon-cloudwatch")
    service_account     = optional(string, "cloudwatch-agent")
    container_logs      = optional(bool, true)
    application_signals = optional(bool, false)
    values              = optional(any, {})
  })
  default     = null
  description = <<-EOT
    Amazon CloudWatch Observability release (chart amazon-cloudwatch-observability); null installs nothing. Container
    Insights with enhanced observability is always on. container_logs turns Fluent Bit on; application_signals is off
    by default. service_account is shared by the CloudWatch agent and Fluent Bit (the chart uses one account for both),
    so one Pod Identity association covers them. The chart default of tolerating every taint is kept on purpose.
    values is merged into the chart values; the inputs above win on conflict.
  EOT

  validation {
    condition     = var.cloudwatch_observability == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.cloudwatch_observability.chart_version))
    error_message = "cloudwatch_observability.chart_version must be an exact version such as 6.7.0."
  }
  validation {
    condition     = var.cloudwatch_observability == null ? true : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.cloudwatch_observability.namespace))
    error_message = "cloudwatch_observability.namespace must be an RFC 1123 label: at most 63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
  validation {
    condition     = var.cloudwatch_observability == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.cloudwatch_observability.service_account))
    error_message = "cloudwatch_observability.service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }
  validation {
    condition     = var.cloudwatch_observability == null ? true : try(length(keys(var.cloudwatch_observability.values)) >= 0, false)
    error_message = "cloudwatch_observability.values must be an object."
  }
}

variable "aggregate_crd_roles" {
  type        = bool
  default     = false
  description = <<-EOT
    Aggregate the custom resources that application charts create into the default view, edit and admin roles, so a
    namespace-scoped edit or admin (for example a CI role with AmazonEKSEditPolicy) can manage them: TargetGroupBinding
    through the local chart crd-role-aggregation when the AWS Load Balancer Controller is installed, and ScaledObject,
    TriggerAuthentication and the other KEDA resources through the KEDA chart's rbac.aggregateToDefaultRoles when KEDA
    is installed.
  EOT
}

variable "chart_repository_overrides" {
  type        = map(string)
  default     = {}
  description = "Chart repository URL per component, for example an ECR mirror of a private cluster. Keys: load_balancer_controller, karpenter, argo_rollouts, keda, cloudwatch_observability."

  validation {
    condition     = alltrue([for k, _ in var.chart_repository_overrides : contains(["load_balancer_controller", "karpenter", "argo_rollouts", "keda", "cloudwatch_observability"], k)])
    error_message = "chart_repository_overrides keys must be load_balancer_controller, karpenter, argo_rollouts, keda or cloudwatch_observability."
  }
  validation {
    condition     = alltrue([for _, v in var.chart_repository_overrides : can(regex("^(https://|oci://)[^\\s]+$", v))])
    error_message = "chart_repository_overrides values must be https:// or oci:// URLs."
  }
}
