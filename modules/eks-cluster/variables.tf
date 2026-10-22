# ---- cluster ----

variable "name" {
  type        = string
  description = "Cluster name. Also the prefix of the node group launch templates, the Karpenter queue name and the EventBridge rule names, so it is capped at 40 chars."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.name))
    error_message = "name must be 2-40 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version, for example 1.34. Required: the version is tied to the add-on versions, so there is no default."
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.34."
  }
}

variable "support_type" {
  type        = string
  default     = "EXTENDED"
  description = "Upgrade policy support type, STANDARD or EXTENDED. EXTENDED (the AWS default) is billed extra once the version leaves standard support; STANDARD upgrades the cluster automatically at the end of standard support."
  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the control plane network interfaces, in at least two AZs. Also the default subnets of managed node groups."
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Give at least two subnet IDs (EKS needs two AZs)."
  }
  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "subnet_ids must look like subnet-0123456789abcdef0."
  }
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Extra security groups for the control plane network interfaces. EKS always creates the cluster security group itself."
  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Whether the API server endpoint is reachable from the internet. The private endpoint is always on."
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public endpoint. Required when endpoint_public_access is true; 0.0.0.0/0 and ::/0 are rejected. Ignored while the public endpoint is off."
  validation {
    condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
    error_message = "endpoint_public_access = true needs at least one entry in public_access_cidrs."
  }
  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "public_access_cidrs entries must be valid CIDR blocks such as 203.0.113.0/24."
  }
  validation {
    condition     = alltrue([for c in var.public_access_cidrs : !endswith(c, "/0")])
    error_message = "public_access_cidrs must not open the endpoint to the whole internet (0.0.0.0/0 or ::/0)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key for Kubernetes secrets envelope encryption. Required. Encryption cannot be turned off later, and removing it forces a new cluster."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (aliases are not accepted)."
  }
}

variable "cluster_role_arn" {
  type        = string
  description = "IAM role of the cluster, created by the caller with iam-role."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.cluster_role_arn))
    error_message = "cluster_role_arn must be an IAM role ARN."
  }
}

variable "enabled_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
  description = "Control plane log types sent to the module's log group."
  validation {
    condition     = alltrue([for t in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "enabled_log_types may only contain api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the control plane log group in days. Never-expire (0) is not accepted."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for the control plane log group. Its key policy must allow logs.<region>.amazonaws.com."
  validation {
    condition     = var.log_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (aliases are not accepted)."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Block deletion of the cluster until this is set to false and applied."
}

variable "zonal_shift" {
  type        = bool
  default     = false
  description = "Enable ARC zonal shift for the cluster."
}

# ---- nodes ----

variable "managed_node_groups" {
  type = map(object({
    node_role_arn              = string
    subnet_ids                 = optional(list(string))
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    instance_types             = list(string)
    capacity_type              = optional(string, "ON_DEMAND")
    min_size                   = number
    max_size                   = number
    desired_size               = number
    disk_size                  = optional(number, 50)
    disk_kms_key_arn           = optional(string)
    labels                     = optional(map(string), {})
    taints                     = optional(list(object({ key = string, value = optional(string), effect = string })), [])
    max_unavailable_percentage = optional(number, 33)
  }))
  default     = {}
  description = "Managed node groups by name. The module builds one launch template per group (IMDSv2 required, hop limit 1, encrypted gp3 root volume). subnet_ids defaults to the cluster subnets. desired_size only applies at creation. Empty creates none."

  validation {
    condition     = alltrue([for k, g in var.managed_node_groups : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", k))])
    error_message = "Node group names must be 1-63 chars of lowercase letters, digits or hyphens."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", g.node_role_arn))])
    error_message = "node_role_arn must be an IAM role ARN."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : g.subnet_ids == null ? true : (length(g.subnet_ids) > 0 && alltrue([for s in g.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]))])
    error_message = "A node group subnet_ids, when given, must be a non-empty list of subnet IDs."
  }
  # AL2 is no longer published. Bottlerocket is left out because its data volume is /dev/xvdb, not the /dev/xvda this module's launch template encrypts.
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : contains(["AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "AL2023_x86_64_NEURON", "AL2023_x86_64_NVIDIA"], g.ami_type)])
    error_message = "ami_type must be AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, AL2023_x86_64_NEURON or AL2023_x86_64_NVIDIA."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : length(g.instance_types) > 0])
    error_message = "Every node group needs at least one instance type."
  }
  validation {
    condition = alltrue([
      for g in values(var.managed_node_groups) :
      g.min_size >= 0 && g.max_size >= 1 && g.min_size <= g.desired_size && g.desired_size <= g.max_size
    ])
    error_message = "Sizes must satisfy 0 <= min_size <= desired_size <= max_size and max_size >= 1."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : g.disk_size >= 20 && g.disk_size <= 16384])
    error_message = "disk_size must be between 20 and 16384 GiB."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : g.disk_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", g.disk_kms_key_arn))])
    error_message = "disk_kms_key_arn must be a KMS key ARN (aliases are not accepted)."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : alltrue([for t in g.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)])])
    error_message = "Taint effect must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
  validation {
    condition     = alltrue([for g in values(var.managed_node_groups) : g.max_unavailable_percentage >= 1 && g.max_unavailable_percentage <= 100])
    error_message = "max_unavailable_percentage must be between 1 and 100."
  }
}

variable "fargate_profiles" {
  type = map(object({
    pod_execution_role_arn = string
    subnet_ids             = list(string)
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default     = {}
  description = "Fargate profiles by name. Subnets must be private. Fargate pods cannot use EKS Pod Identity, only IRSA. Empty creates none."

  validation {
    condition     = alltrue([for k, p in var.fargate_profiles : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", k))])
    error_message = "Fargate profile names must be 1-63 chars of lowercase letters, digits or hyphens."
  }
  validation {
    condition     = alltrue([for p in values(var.fargate_profiles) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", p.pod_execution_role_arn))])
    error_message = "pod_execution_role_arn must be an IAM role ARN."
  }
  validation {
    condition     = alltrue([for p in values(var.fargate_profiles) : length(p.subnet_ids) > 0 && alltrue([for s in p.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])])
    error_message = "Every Fargate profile needs at least one private subnet ID."
  }
  validation {
    condition     = alltrue([for p in values(var.fargate_profiles) : length(p.selectors) > 0 && alltrue([for s in p.selectors : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", s.namespace))])])
    error_message = "Every Fargate profile needs at least one selector, and each namespace must be a valid Kubernetes namespace name."
  }
}

variable "auto_mode" {
  type = object({
    node_role_arn = optional(string)
    node_pools    = optional(list(string), ["general-purpose", "system"])
  })
  default     = null
  description = "EKS Auto Mode. When set, compute, elastic load balancing and block storage are all enabled together. node_role_arn is required while node_pools is non-empty, and cannot be changed afterwards without recreating the cluster. With node_pools = [] it may be null: the cluster is created without a node role and the node role comes from an EC2 access entry holding AmazonEKSAutoNodePolicy (access_entries). null leaves Auto Mode off (all three explicitly false)."

  validation {
    condition     = var.auto_mode == null ? true : var.auto_mode.node_role_arn == null ? length(var.auto_mode.node_pools) == 0 : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.auto_mode.node_role_arn))
    error_message = "auto_mode.node_role_arn must be an IAM role ARN; it may be null only when node_pools is empty."
  }
  validation {
    condition     = var.auto_mode == null ? true : alltrue([for p in var.auto_mode.node_pools : contains(["general-purpose", "system"], p)])
    error_message = "auto_mode.node_pools may only contain general-purpose and system."
  }
}

variable "karpenter" {
  type = object({
    node_role_arn              = string
    controller_namespace       = optional(string, "kube-system")
    controller_service_account = optional(string, "karpenter")
    controller_role_arn        = string
  })
  default     = null
  description = "Karpenter AWS resources: interruption queue, five EventBridge rules, an EC2_LINUX access entry for the Karpenter node role and a Pod Identity association for the controller. Needs a managed node group to run the controller, cannot be combined with auto_mode, and node_role_arn must differ from the node roles of the managed node groups (EKS already creates an access entry for those). null creates nothing."

  validation {
    condition     = var.karpenter == null ? true : var.auto_mode == null
    error_message = "karpenter and auto_mode cannot be used together (both manage nodepools.karpenter.sh and nodeclaims.karpenter.sh)."
  }
  validation {
    condition     = var.karpenter == null ? true : length(var.managed_node_groups) > 0
    error_message = "karpenter needs at least one managed node group to run the controller."
  }
  validation {
    condition     = var.karpenter == null ? true : !contains([for g in values(var.managed_node_groups) : g.node_role_arn], var.karpenter.node_role_arn)
    error_message = "karpenter.node_role_arn must differ from the node roles of the managed node groups, because EKS already creates an access entry for those."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.karpenter.node_role_arn))
    error_message = "karpenter.node_role_arn must be an IAM role ARN."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.karpenter.controller_role_arn))
    error_message = "karpenter.controller_role_arn must be an IAM role ARN."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.karpenter.controller_namespace))
    error_message = "karpenter.controller_namespace must be a valid Kubernetes namespace name."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.karpenter.controller_service_account))
    error_message = "karpenter.controller_service_account must be a valid Kubernetes service account name."
  }
}

# ---- add-ons ----

variable "addons" {
  type = map(object({
    version                     = string
    configuration_values        = optional(string)
    pod_identity_role_arn       = optional(string)
    service_account             = optional(string)
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
  }))
  default     = {}
  description = "EKS add-ons by add-on name. version is required (it is tied to kubernetes_version). Without auto_mode, vpc-cni, kube-proxy, coredns and eks-pod-identity-agent must be present because the cluster is created without self-managed add-ons. vpc-cni, kube-proxy and eks-pod-identity-agent are created before the nodes; every other add-on waits for them."

  validation {
    condition     = var.auto_mode != null || alltrue([for a in ["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent"] : contains(keys(var.addons), a)])
    error_message = "Without auto_mode, addons must include vpc-cni, kube-proxy, coredns and eks-pod-identity-agent (the cluster has no self-managed add-ons)."
  }
  validation {
    condition     = alltrue([for k in keys(var.addons) : can(regex("^[a-z][a-z0-9-]{1,63}$", k))])
    error_message = "Add-on names must be lowercase letters, digits or hyphens, such as vpc-cni."
  }
  validation {
    condition     = alltrue([for a in values(var.addons) : length(a.version) > 0])
    error_message = "Every add-on needs a version."
  }
  validation {
    condition     = alltrue([for a in values(var.addons) : contains(["NONE", "OVERWRITE", "PRESERVE"], a.resolve_conflicts_on_update)])
    error_message = "resolve_conflicts_on_update must be NONE, OVERWRITE or PRESERVE."
  }
  validation {
    condition     = alltrue([for a in values(var.addons) : (a.pod_identity_role_arn == null) == (a.service_account == null)])
    error_message = "pod_identity_role_arn and service_account go together: give both or neither."
  }
  validation {
    condition     = alltrue([for a in values(var.addons) : a.pod_identity_role_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a.pod_identity_role_arn))])
    error_message = "pod_identity_role_arn must be an IAM role ARN."
  }
}

# ---- access ----

variable "access_entries" {
  type = map(object({
    principal_arn = string
    type          = optional(string, "STANDARD")
    policies = optional(map(object({
      policy     = string
      namespaces = optional(list(string), [])
    })), {})
  }))
  description = "EKS access entries by name. policies maps a name to an access policy and its namespaces (empty means cluster scope). The cluster is created without creator admin permissions, so at least one STANDARD entry must hold AmazonEKSClusterAdminPolicy at cluster scope, normally the role that runs terraform apply. type EC2 is the Auto Mode node role entry: it may only hold AmazonEKSAutoNodePolicy at cluster scope, and that policy is allowed on no other type. With auto_mode and node_pools = [], one such entry is required."

  validation {
    condition = anytrue([
      for e in values(var.access_entries) :
      e.type == "STANDARD" && anytrue([for p in values(e.policies) : p.policy == "AmazonEKSClusterAdminPolicy" && length(p.namespaces) == 0])
    ])
    error_message = "access_entries needs at least one STANDARD entry with AmazonEKSClusterAdminPolicy at cluster scope (empty namespaces); without it nobody can operate the cluster."
  }
  validation {
    condition     = alltrue([for e in values(var.access_entries) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", e.principal_arn))])
    error_message = "principal_arn must be an IAM role or user ARN."
  }
  validation {
    condition     = alltrue([for e in values(var.access_entries) : contains(["STANDARD", "EC2", "EC2_LINUX", "EC2_WINDOWS", "FARGATE_LINUX"], e.type)])
    error_message = "type must be STANDARD, EC2, EC2_LINUX, EC2_WINDOWS or FARGATE_LINUX."
  }
  validation {
    condition     = alltrue([for e in values(var.access_entries) : e.type == "STANDARD" || e.type == "EC2" || length(e.policies) == 0])
    error_message = "Only STANDARD and EC2 access entries can have access policies."
  }
  validation {
    condition = alltrue([
      for e in values(var.access_entries) : alltrue([
        for p in values(e.policies) :
        e.type == "EC2" ? p.policy == "AmazonEKSAutoNodePolicy" && length(p.namespaces) == 0 :
        contains(["AmazonEKSClusterAdminPolicy", "AmazonEKSAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy", "AmazonEKSAdminViewPolicy"], p.policy)
      ])
    ])
    error_message = "STANDARD entries accept AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy or AmazonEKSAdminViewPolicy (a name, not an ARN). EC2 entries accept only AmazonEKSAutoNodePolicy at cluster scope (empty namespaces)."
  }
  validation {
    condition = alltrue([
      for e in values(var.access_entries) : alltrue([
        for p in values(e.policies) : alltrue([for n in p.namespaces : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", n))])
      ])
    ])
    error_message = "Namespaces must be valid Kubernetes namespace names."
  }
}

variable "pod_identity_associations" {
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
  default     = {}
  description = "EKS Pod Identity associations by name. Roles are created by the caller with iam-role and must trust pods.eks.amazonaws.com. Fargate pods cannot use Pod Identity."

  validation {
    condition     = alltrue([for a in values(var.pod_identity_associations) : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a.role_arn))])
    error_message = "role_arn must be an IAM role ARN."
  }
  validation {
    condition     = alltrue([for a in values(var.pod_identity_associations) : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", a.namespace))])
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
  validation {
    condition     = alltrue([for a in values(var.pod_identity_associations) : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", a.service_account))])
    error_message = "service_account must be a valid Kubernetes service account name."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource the module creates. Name is added by the module."
}
