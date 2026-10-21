variable "issuer_url" {
  type        = string
  description = "OIDC issuer URL of an EKS cluster (the oidc_issuer_url output of eks-cluster), in the form https://oidc.eks.<region>.amazonaws.com/id/<id>."
  validation {
    condition     = can(regex("^https://oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Za-z0-9]+$", var.issuer_url))
    error_message = "issuer_url must be https://oidc.eks.<region>.amazonaws.com/id/<id> with no trailing slash."
  }
}

variable "client_ids" {
  type        = set(string)
  default     = ["sts.amazonaws.com"]
  description = "Client IDs (audiences) the provider accepts. IRSA tokens use sts.amazonaws.com."
  validation {
    condition     = length(var.client_ids) >= 1 && alltrue([for c in var.client_ids : can(regex("^\\S{1,255}$", c))])
    error_message = "client_ids needs at least one entry, each 1-255 chars with no whitespace."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the provider."
}
