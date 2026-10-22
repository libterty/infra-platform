variable "kubernetes_version" {
  description = "Kubernetes minor version of the cluster, for example 1.36. No default: pick one that is still in EKS standard support."
  type        = string
}

# Access entries (design v4 §7). The principals come from tfvars; deploy_role_arn is not reused because it may be empty.
variable "cluster_admin_principal_arns" {
  description = "IAM roles or users that get cluster admin (AmazonEKSClusterAdminPolicy at cluster scope)."
  type        = list(string)

  validation {
    condition     = length(var.cluster_admin_principal_arns) > 0
    error_message = "Give at least one cluster admin; the cluster is created without creator admin permissions."
  }

  validation {
    condition     = alltrue([for a in var.cluster_admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", a))])
    error_message = "cluster_admin_principal_arns must be IAM role or user ARNs."
  }
}

variable "addons_apply_principal_arn" {
  description = "Role that applies the eks-addons stack. It installs cluster-scoped objects (NodeClass, NodePool, CRDs), so it gets cluster admin."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.addons_apply_principal_arn))
    error_message = "addons_apply_principal_arn must be an IAM role ARN."
  }
}

variable "ci_deploy_principal_arn" {
  description = "Role CI deploys the api and worker charts with. It gets AmazonEKSEditPolicy in app_namespace only."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.ci_deploy_principal_arn))
    error_message = "ci_deploy_principal_arn must be an IAM role ARN."
  }

  # EKS allows one access entry per principal, so one principal cannot hold two of these roles.
  validation {
    condition     = length(distinct(concat(var.cluster_admin_principal_arns, [var.addons_apply_principal_arn, var.ci_deploy_principal_arn]))) == length(var.cluster_admin_principal_arns) + 2
    error_message = "cluster_admin_principal_arns, addons_apply_principal_arn and ci_deploy_principal_arn must all be different principals."
  }
}

# Where api and worker run. The chart reads these names from SSM, so the Pod Identity associations match.
variable "app_namespace" {
  description = "Namespace of the api and worker. eks-addons creates it; CI may deploy only here."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.app_namespace)) && var.app_namespace != "default" && !startswith(var.app_namespace, "kube-")
    error_message = "app_namespace must be an RFC 1123 label other than default and kube-*."
  }
}

variable "api_service_account" {
  description = "ServiceAccount of the api pods."
  type        = string
  default     = "api"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.api_service_account))
    error_message = "api_service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }
}

variable "worker_service_account" {
  description = "ServiceAccount of the worker pods. Must differ from api_service_account: each has its own role."
  type        = string
  default     = "worker"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.worker_service_account))
    error_message = "worker_service_account must be a Kubernetes name: lowercase letters, digits, hyphens or dots."
  }

  validation {
    condition     = var.worker_service_account != var.api_service_account
    error_message = "worker_service_account must differ from api_service_account."
  }
}
