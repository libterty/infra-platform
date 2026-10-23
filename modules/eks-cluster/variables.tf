# ---- cluster ----

variable "name" {
  type        = string
  description = "叢集名稱，也是 node group launch template、Karpenter queue 與 EventBridge 規則名稱的前綴，所以上限 40 字元。2–40 字元，小寫字母開頭，限小寫英數字與連字號。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.name))
    error_message = "name must be 2-40 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor 版本，例如 `1.34`。必填、沒有預設，因為版本跟 add-on 版本綁在一起。"
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.34."
  }
}

variable "support_type" {
  type        = string
  default     = "EXTENDED"
  description = "升級政策的 support type：`STANDARD` 或 `EXTENDED`。`EXTENDED`（AWS 預設）在版本過了 standard support 後另外計費；`STANDARD` 會在 standard support 結束時自動升級叢集。"
  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "control plane 網路介面用的 subnet，至少兩個，要在不同 AZ，格式像 `subnet-0123456789abcdef0`。managed node group 沒給 subnet 時也用這些。"
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
  description = "control plane 網路介面額外的 security group，格式像 `sg-0123456789abcdef0`。cluster security group 一律由 EKS 自己建。"
  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "API server endpoint 是否開放從網際網路連線。private endpoint 一律開。"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = []
  description = "可以連 public endpoint 的 CIDR。`endpoint_public_access` 為 `true` 時必填，須是合法 CIDR，不接受 `0.0.0.0/0` 與 `::/0`。public endpoint 關著時忽略。"
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
  description = "Kubernetes secrets envelope encryption 用的客戶自管 KMS key ARN，不接受 alias。必填。加密開了之後不能關，移除會重建叢集。"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (aliases are not accepted)."
  }
}

variable "cluster_role_arn" {
  type        = string
  description = "叢集的 IAM role ARN，由呼叫端用 `iam-role` 建。"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.cluster_role_arn))
    error_message = "cluster_role_arn must be an IAM role ARN."
  }
}

variable "enabled_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
  description = "送到 module 建的 log group 的 control plane log 類型，可選 `api`、`audit`、`authenticator`、`controllerManager`、`scheduler`。"
  validation {
    condition     = alltrue([for t in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "enabled_log_types may only contain api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "control plane log group 的保留天數，須是 CloudWatch Logs 接受的值（1、3、5、7、14、30、60、90 … 3653）。不接受永不過期（`0`）。"
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "control plane log group 用的客戶自管 KMS key ARN，不接受 alias；key policy 要允許 `logs.<region>.amazonaws.com`。`null` 時不指定 KMS key。"
  validation {
    condition     = var.log_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (aliases are not accepted)."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "開著時叢集不能刪除；要刪除或重建，先改成 `false` 並 apply 一次。"
}

variable "zonal_shift" {
  type        = bool
  default     = false
  description = "是否開啟叢集的 ARC zonal shift。"
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
  description = "managed node group，key 是 group 名稱（1–63 字元，小寫英數字與連字號）；空 map 不建。module 替每個 group 建一個 launch template（IMDSv2 必須、hop limit 1、加密的 gp3 root volume）。欄位見〈`managed_node_groups` 欄位〉。"

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
  description = "Fargate profile，key 是 profile 名稱（1–63 字元，小寫英數字與連字號）；空 map 不建。欄位：`pod_execution_role_arn`（IAM role ARN）、`subnet_ids`（至少一個，只能是 private subnet）、`selectors`（至少一個，各有 `namespace` 與 `labels`，`labels` 預設 `{}`）。Fargate pod 不能用 EKS Pod Identity，只能用 IRSA。"

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
  description = "EKS Auto Mode；`null` 不開（三個設定明確送 `false`）。有值時 compute、負載平衡、區塊儲存三個一起開。欄位：`node_pools`（預設 `[\"general-purpose\", \"system\"]`，只能是這兩個）、`node_role_arn`（IAM role ARN，`node_pools` 非空時必填，設定後換 role 會重建叢集；只有 `node_pools = []` 時可以是 `null`，此時 `access_entries` 要有 `EC2` entry 掛 `AmazonEKSAutoNodePolicy`）。"

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
  description = "Karpenter 要的 AWS 資源：interruption SQS queue、5 條 EventBridge 規則、Karpenter node role 的 `EC2_LINUX` access entry、controller 的 Pod Identity association；`null` 不建。需要至少一個 managed node group 跑 controller，不能與 `auto_mode` 並用。欄位：`node_role_arn`（必填，IAM role ARN，不能跟任何 managed node group 的 node role 相同）、`controller_role_arn`（必填，IAM role ARN）、`controller_namespace`（預設 `kube-system`）、`controller_service_account`（預設 `karpenter`）。"

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
  description = "沒有 `auto_mode` 時必填。EKS add-on，key 是 add-on 名稱（例如 `vpc-cni`）；沒有 `auto_mode` 時必須含 `vpc-cni`、`kube-proxy`、`coredns`、`eks-pod-identity-agent`，因為叢集不帶自管 add-on。欄位：`version`（必填，跟 `kubernetes_version` 綁在一起）、`configuration_values`、`pod_identity_role_arn` 與 `service_account`（要一起給，會建 Pod Identity association）、`resolve_conflicts_on_update`（預設 `OVERWRITE`，可為 `NONE`、`PRESERVE`）。建立順序見〈add-on〉。"

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
  description = "EKS access entry，key 是名稱。欄位：`principal_arn`（IAM role 或 user ARN）、`type`（預設 `STANDARD`，可為 `EC2`、`EC2_LINUX`、`EC2_WINDOWS`、`FARGATE_LINUX`）、`policies`（map，每項是 `policy` 名稱與 `namespaces`，`namespaces` 預設 `[]` 代表 cluster scope）。至少要一個 `STANDARD` entry 掛 cluster scope 的 `AmazonEKSClusterAdminPolicy`；只有 `STANDARD`、`EC2` 能掛 policy，`EC2` 只能掛 cluster scope 的 `AmazonEKSAutoNodePolicy`。policy 白名單見〈存取〉。"

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
  description = "EKS Pod Identity association，key 是名稱。欄位：`namespace`、`service_account`、`role_arn`（呼叫端用 `iam-role` 建的 IAM role ARN，trust 要是 `pods.eks.amazonaws.com` 並帶 `sts:TagSession`）。Fargate pod 不能用 Pod Identity。"

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
  description = "module 建的每個資源的 tag；`Name` 由 module 加上。"
}
