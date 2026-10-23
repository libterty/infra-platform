variable "issuer_url" {
  type        = string
  description = "EKS 叢集的 OIDC issuer URL（`eks-cluster` 的 `oidc_issuer_url` 輸出），格式 `https://oidc.eks.<region>.amazonaws.com/id/<id>`，結尾不可有 `/`。"
  validation {
    condition     = can(regex("^https://oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Za-z0-9]+$", var.issuer_url))
    error_message = "issuer_url must be https://oidc.eks.<region>.amazonaws.com/id/<id> with no trailing slash."
  }
}

variable "client_ids" {
  type        = set(string)
  default     = ["sts.amazonaws.com"]
  description = "provider 接受的 client ID（audience），至少一個，每個 1–255 字元、不含空白。IRSA 的 token 用 `sts.amazonaws.com`。"
  validation {
    condition     = length(var.client_ids) >= 1 && alltrue([for c in var.client_ids : can(regex("^\\S{1,255}$", c))])
    error_message = "client_ids needs at least one entry, each 1-255 chars with no whitespace."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "provider 的 tag，原樣傳入（provider 沒有名稱，module 不加 `Name`）。"
}
