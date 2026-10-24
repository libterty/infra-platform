variable "cluster_name" {
  type        = string
  description = "EKS cluster 名稱，傳給 AWS Load Balancer Controller 與 Karpenter。1–100 字元，限英數字、`-`、`_`，首字元須為英數字。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 chars of letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "cluster 所在 region，例如 `ap-northeast-1`。傳給 AWS Load Balancer Controller：hop limit 為 1 時它讀不到 IMDS，所以明確傳入。"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like ap-northeast-1."
  }
}

variable "vpc_id" {
  type        = string
  description = "cluster 的 VPC ID，格式像 `vpc-0123456789abcdef0`。傳給 AWS Load Balancer Controller：hop limit 為 1 時它讀不到 IMDS，所以明確傳入。"
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
    AWS Load Balancer Controller 的 release，namespace 固定 `kube-system`；`null` 不裝。欄位：`chart_version`（預設 `3.6.1`，精確版本）、`service_account`（預設 `aws-load-balancer-controller`）、`replica_count`（預設 `2`，至少 1 的整數）、`values`（預設 `{}`，併進 chart values，衝突時以前面的欄位為準）。IAM role 不在這裡建，service account 的 Pod Identity association 在 `eks-cluster`。設了 `auto_mode` 時 `enableServiceMutatorWebhook` 與 `createIngressClassResource` 固定為 `false`，`values` 改不回來。
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
    Karpenter controller 的 release；`null` 不裝。欄位：`chart_version`（預設 `1.15.0`，精確版本）、`namespace`（預設 `kube-system`）、`service_account`（預設 `karpenter`）、`interruption_queue_name`（必填，SQS queue 名稱，不是 URL 或 ARN，即 `eks-cluster` 的輸出 `karpenter_interruption_queue_name`）、`values`（預設 `{}`）、`default_node_class` 與 `default_node_pool`（預設 `null`，兩個都有值才裝本地 chart `karpenter-defaults`；`default_node_pool = {}` 表示用預設限制）。這兩個的欄位見〈Karpenter 的預設 NodePool 與 EC2NodeClass〉。
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
  description = "Argo Rollouts 的 release；`null` 不裝。欄位：`chart_version`（預設 `2.43.8`，精確版本）、`namespace`（預設 `argo-rollouts`）、`values`（預設 `{}`，併進 chart values）。CloudWatch 指標分析要的 role 與 Pod Identity association 在 `eks-cluster` 建。"

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
  description = "用本地 chart `app-namespaces` 建的應用程式 namespace，key 是 namespace 名稱（RFC 1123 label，不能是 `default` 或 `kube-` 開頭），欄位 `labels` 預設 `{}`；空 map 不裝。掛 Edit access policy 的 CI role 建不了 namespace，所以在這裡建。"

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
    EKS Auto Mode 的 NodeClass 與 NodePool（本地 chart `auto-mode-nodes`，`eks.amazonaws.com/v1` NodeClass 與 `karpenter.sh/v1` NodePool）；`null` 不裝。有值時也會把 AWS Load Balancer Controller 的 `enableServiceMutatorWebhook` 與 `createIngressClassResource` 固定為 `false`。欄位見〈`auto_mode` 欄位〉。
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
    啟用 NetworkPolicy controller（`kube-system` 的 ConfigMap `amazon-vpc-cni` 設 `enable-network-policy-controller`），並替這個 module 有裝的元件建 system NetworkPolicy（本地 chart `system-network-policy`）；`null` 兩者都不做。欄位都必填，CIDR 由呼叫端給：`service_cidr`（cluster 的 IPv4 service CIDR，DNS 是它的 `.10`）、`api_server_cidrs`（control plane ENI 所在 subnet，不可為空，不接受 `0.0.0.0/0`）、`aws_api_cidrs`（VPC interface endpoint 所在 subnet，不可為空；只有經 NAT 連 AWS API 時才用 `["0.0.0.0/0"]`）。規則見〈NetworkPolicy 與 system 的放行規則〉。
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
    AWS Load Balancer Controller 與 KEDA（該跑在 system node pool 的 Deployment）的 node selector 與 toleration；`null` 不改它們的排程。寫在 chart values 最上層，跟元件 `values` 同名的 key 衝突時以這裡為準。欄位：`node_selector`（預設 `{}`，key 不可為空）、`tolerations`（預設 `[]`，每項的 `key`、`operator`、`value`、`effect` 都選填；`operator` 為 `Equal` 或 `Exists`，`effect` 為 `NoSchedule`、`PreferNoSchedule` 或 `NoExecute`）。CloudWatch 採集不套用，它的 DaemonSet 要涵蓋每個 node。
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
    KEDA 的 release（chart `kedacore/keda`）；`null` 不裝。欄位：`chart_version`（預設 `2.21.0`，精確版本）、`namespace`（預設 `keda`）、`service_account`（預設 `keda-operator`，operator 的 service account，CloudWatch scaler 的 Pod Identity association 建在它上面，在 `eks-cluster`）、`values`（預設 `{}`，併進 chart values，衝突時以 `system_placement` 與 service account 為準）。
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
    Amazon CloudWatch Observability 的 release（chart `amazon-cloudwatch-observability`）；`null` 不裝。Container Insights（enhanced observability）固定開。欄位：`chart_version`（預設 `6.7.0`，精確版本）、`namespace`（預設 `amazon-cloudwatch`）、`service_account`（預設 `cloudwatch-agent`，CloudWatch agent 與 Fluent Bit 共用，一個 Pod Identity association 涵蓋兩者）、`container_logs`（預設 `true`，開 Fluent Bit）、`application_signals`（預設 `false`）、`values`（預設 `{}`，併進 chart values，衝突時以前面的欄位為準）。chart 預設容忍所有 taint，刻意保留。
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
    把應用程式 chart 會建的自訂資源權限併進內建的 `view`、`edit`、`admin` role，讓 namespace scope 的 Edit 或 Admin（例如掛 `AmazonEKSEditPolicy` 的 CI role）能管理：有裝 AWS Load Balancer Controller 時用本地 chart `crd-role-aggregation` 加 TargetGroupBinding；有裝 KEDA 時用 KEDA chart 的 `rbac.aggregateToDefaultRoles` 加 ScaledObject、TriggerAuthentication 等 KEDA 資源。見〈CI 用 Helm 部署應用程式的權限〉。
  EOT
}

variable "chart_repository_overrides" {
  type        = map(string)
  default     = {}
  description = "各元件的 chart repository URL，例如 private cluster 的 ECR mirror。key 只能是 `load_balancer_controller`、`karpenter`、`argo_rollouts`、`keda`、`cloudwatch_observability`；值要是 `https://` 或 `oci://` URL。預設 repository 見〈預設 chart repository〉。"

  validation {
    condition     = alltrue([for k, _ in var.chart_repository_overrides : contains(["load_balancer_controller", "karpenter", "argo_rollouts", "keda", "cloudwatch_observability"], k)])
    error_message = "chart_repository_overrides keys must be load_balancer_controller, karpenter, argo_rollouts, keda or cloudwatch_observability."
  }
  validation {
    condition     = alltrue([for _, v in var.chart_repository_overrides : can(regex("^(https://|oci://)[^\\s]+$", v))])
    error_message = "chart_repository_overrides values must be https:// or oci:// URLs."
  }
}
